//
//  Legendre.swift
//  NucleantDSP
//
//  Rewritten in Swift from Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt). Its
//  polynomial follows C. Bond's "Optimum 'L'" algorithm (2004), after
//  A. Papoulis, "On Monotonic Response Filters" (1959).
//

import AudioProtocols
import Foundation

/// A Legendre ("Optimum L") filter of any order from 1 to 16: the steepest
/// fall at the cutoff for a level that only ever falls, with no ripple
/// anywhere. Between a Butterworth and a Chebyshev: steeper than the one,
/// smoother than the other.
///
///     var filter = Legendre(.lowPass, order: 5, frequency: 2_500)
///
/// At `frequency` a low- or high-pass is −3 dB. Its poles are found
/// numerically from Papoulis' polynomial, then moved to the z plane by the
/// bilinear transform; it runs as second-order sections in Double, four
/// channels per vector.
public struct Legendre: AudioProcessor {
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
        /// Passes `width` hertz around `frequency`: twice the order's poles.
        case bandPass(width: Float)
        /// Cuts `width` hertz around `frequency`.
        case bandStop(width: Float)
    }

    public var response: Response
    /// 1…16: how many poles the prototype has.
    public var order: Int
    /// In hertz: the cutoff, or the middle of a band. Kept below the
    /// output's Nyquist frequency.
    public var frequency: Float

    private static let maximumOrder = 16
    private var polynomial = Polynomial(maximumOrder: Legendre.maximumOrder)
    private var roots = RootFinder(maximumDegree: 2 * Legendre.maximumOrder)
    private var analog = PoleZeroLayout(maximumPoles: Legendre.maximumOrder)
    private var digital = PoleZeroLayout(maximumPoles: 2 * Legendre.maximumOrder)
    private var cascade = BiquadCascade(maximumPoles: 2 * Legendre.maximumOrder)
    /// What `cascade` was designed for, and the order `analog` was: its
    /// roots are found again only when the order changes.
    private var designed: (response: Response, order: Int, frequency: Float, sampleRate: Double)?
    private var prototypeOrder: Int?

    public init(_ response: Response, order: Int = 4, frequency: Float) {
        self.response = response
        self.order = order
        self.frequency = frequency
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        design(sampleRate: sampleRate)
        buffer.withFrames(channels: channels) { samples, frames in
            cascade.process(samples, frames: frames, channels: channels)
        }
    }

    private mutating func design(sampleRate: Double) {
        let order = min(max(order, 1), Legendre.maximumOrder)
        if let designed, designed.response == response, designed.order == order,
           designed.frequency == frequency, designed.sampleRate == sampleRate {
            return
        }
        designed = (response, order, frequency, sampleRate)
        let center = min(max(Double(frequency), 1), sampleRate * 0.4995) / sampleRate
        func share(_ width: Float) -> Double { max(Double(width), 1) / sampleRate }

        designLowPass(order)
        switch response {
        case .lowPass:
            digital.makeLowPass(from: analog, frequency: center)
        case .highPass:
            digital.makeHighPass(from: analog, frequency: center)
        case .bandPass(let width):
            digital.makeBandPass(from: analog, center: center, width: share(width))
        case .bandStop(let width):
            digital.makeBandStop(from: analog, center: center, width: share(width))
        }
        cascade.setLayout(digital)
    }

    /// The poles are the left half of the roots of 1 + L(−s²), L being
    /// Papoulis' polynomial of the order; the zeros are at infinity.
    private mutating func designLowPass(_ order: Int) {
        if prototypeOrder == order { return }
        prototypeOrder = order
        analog.reset()
        polynomial.solve(order)
        let degree = order * 2
        roots.coefficients[0] = Complex(1 + polynomial.coefficients[0])
        roots.coefficients[1] = .zero
        for index in 1...order {
            roots.coefficients[2 * index] = Complex(polynomial.coefficients[index] * (index & 1 == 1 ? -1 : 1))
            if 2 * index + 1 <= degree { roots.coefficients[2 * index + 1] = .zero }
        }
        roots.solve(degree: degree)
        roots.keepLeftHalfPlane(of: degree)
        roots.sort(degree: order)
        let pairCount = order / 2
        for index in 0..<pairCount { analog.addConjugatePairs(pole: roots.roots[index], zero: .infinity) }
        if order & 1 == 1 { analog.add(pole: Complex(roots.roots[pairCount].real), zero: .infinity) }
        analog.setNormal(w: 0, gain: 1)
    }
}

extension Legendre {
    /// Papoulis' "Optimum L" polynomial of an order, built from Legendre
    /// polynomials of the first kind: DSPFilters' PolynomialFinder. Its
    /// working arrays are made once.
    fileprivate struct Polynomial: Sendable {
        /// The polynomial's coefficients after `solve`, from the constant up.
        private(set) var coefficients: ContiguousArray<Double>
        private var a: ContiguousArray<Double>
        private var p: ContiguousArray<Double>
        private var s: ContiguousArray<Double>
        private var v: ContiguousArray<Double>
        private var aa: ContiguousArray<Double>
        private var bb: ContiguousArray<Double>

        init(maximumOrder n: Int) {
            coefficients = ContiguousArray(repeating: 0, count: 2 * n + 1)
            a = ContiguousArray(repeating: 0, count: n + 1)
            p = ContiguousArray(repeating: 0, count: 2 * n + 1)
            s = ContiguousArray(repeating: 0, count: 2 * n + 1)
            v = ContiguousArray(repeating: 0, count: 2 * n + 4)
            aa = ContiguousArray(repeating: 0, count: n + 1)
            bb = ContiguousArray(repeating: 0, count: n + 1)
        }

        /// The Legendre polynomial of the first kind of degree `n`, into p,
        /// by (n + 1)·P(n+1) = (2n + 1)·x·P(n) − n·P(n−1).
        private mutating func legendre(_ n: Int) {
            if n == 0 {
                p[0] = 1
                return
            }
            if n == 1 {
                p[0] = 0
                p[1] = 1
                return
            }
            p[0] = -0.5
            p[1] = 0
            p[2] = 1.5
            if n == 2 { return }
            for i in 0...n {
                aa[i] = 0
                bb[i] = 0
            }
            bb[1] = 1
            for i in 3...n {
                for j in 0...i {
                    aa[j] = bb[j]
                    bb[j] = p[j]
                    p[j] = 0
                }
                for j in stride(from: i - 2, through: 0, by: -2) {
                    p[j] -= Double(i - 1) * aa[j] / Double(i)
                }
                for j in stride(from: i - 1, through: 0, by: -2) {
                    p[j + 1] += Double(2 * i - 1) * bb[j] / Double(i)
                }
            }
        }

        /// The polynomial for order `n` (n = 2k + 1 when odd, 2k + 2 when
        /// even), into `coefficients`.
        mutating func solve(_ n: Int) {
            let k = (n - 1) / 2
            if n & 1 == 1 {
                for i in 0...k { a[i] = (2 * Double(i) + 1) / (2.0.squareRoot() * (Double(k) + 1)) }
            } else {
                for i in 0..<(k + 1) { a[i] = 0 }
                let scale = Double((k + 1) * (k + 2)).squareRoot()
                for i in stride(from: k & 1 == 1 ? 1 : 0, through: k, by: 2) {
                    a[i] = Double(2 * i + 1) / scale
                }
            }
            for i in 0...n {
                s[i] = 0
                coefficients[i] = 0
            }
            // s = the sum of a[i]·P[i].
            s[0] = a[0]
            s[1] = k >= 1 ? a[1] : 0
            if k >= 2 {
                for i in 2...k {
                    legendre(i)
                    for j in 0...i { s[j] += a[i] * p[j] }
                }
            }
            // v = s².
            for i in 0...(2 * k + 2) { v[i] = 0 }
            for i in 0...k {
                for j in 0...k { v[i + j] += s[i] * s[j] }
            }
            // For an even order, the integrand times (x + 1).
            v[2 * k + 1] = 0
            if n & 1 == 0 {
                for i in stride(from: n, through: 0, by: -1) { v[i + 1] += v[i] }
            }
            // Its integral.
            for i in stride(from: n + 1, through: 0, by: -1) { v[i + 1] = v[i] / Double(i + 1) }
            v[0] = 0
            // The definite integral from −1 to 2x² − 1.
            for i in 0..<(n + 2) { s[i] = 0 }
            s[0] = -1
            s[1] = 2
            for i in 1...n {
                if i > 1 {
                    var c0 = -s[0]
                    for j in 1..<(i + 1) {
                        let c1 = -s[j] + 2 * s[j - 1]
                        s[j - 1] = c0
                        c0 = c1
                    }
                    let c1 = 2 * s[i]
                    s[i] = c0
                    s[i + 1] = c1
                }
                for j in stride(from: i, to: 0, by: -1) { coefficients[j] += v[i] * s[j] }
            }
            if n & 1 == 0 { coefficients[1] = 0 }
        }
    }
}
