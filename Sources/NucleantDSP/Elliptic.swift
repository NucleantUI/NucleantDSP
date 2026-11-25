//
//  Elliptic.swift
//  NucleantDSP
//
//  Rewritten in Swift from Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import AudioProtocols
import Foundation

/// An elliptic (Cauer) filter of any order from 1 to 16: the steepest fall
/// from pass band to stop band for its order, for a ripple in both.
///
///     var filter = Elliptic(.lowPass, order: 4, frequency: 3_000, ripple: 0.5, rolloff: 0)
///
/// `ripple` is how far the level wanders where the filter passes; at
/// `frequency` a low- or high-pass is down by it. Past the cutoff, zeros
/// hold the stop band down; `rolloff` trades how steep the fall is against
/// how far down the stop band is held. It runs as second-order sections in
/// Double, four channels per vector.
public struct Elliptic: AudioProcessor {
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
    /// In decibels, 0.001…12: how far the level wanders where the filter
    /// passes.
    public var ripple: Float
    /// −16…4: lower is a steeper fall to a stop band held less far down;
    /// higher, a gentler fall to a deeper one.
    public var rolloff: Float

    private static let maximumOrder = 16
    private var prototype = Prototype()
    private var analog = PoleZeroLayout(maximumPoles: Elliptic.maximumOrder)
    private var digital = PoleZeroLayout(maximumPoles: 2 * Elliptic.maximumOrder)
    private var cascade = BiquadCascade(maximumPoles: 2 * Elliptic.maximumOrder)
    /// What `cascade` was designed for.
    private var designed: (response: Response, order: Int, frequency: Float, ripple: Float, rolloff: Float,
                           sampleRate: Double)?
    /// What `analog` was designed for.
    private var prototypeKey: (order: Int, ripple: Float, rolloff: Float)?

    public init(_ response: Response, order: Int = 4, frequency: Float, ripple: Float = 1, rolloff: Float = 0) {
        self.response = response
        self.order = order
        self.frequency = frequency
        self.ripple = ripple
        self.rolloff = rolloff
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        design(sampleRate: sampleRate)
        buffer.withFrames(channels: channels) { samples, frames in
            cascade.process(samples, frames: frames, channels: channels)
        }
    }

    private mutating func design(sampleRate: Double) {
        let order = min(max(order, 1), Elliptic.maximumOrder)
        let ripple = min(max(ripple, 0.001), 12)
        let rolloff = min(max(rolloff, -16), 4)
        if let designed, designed.response == response, designed.order == order, designed.frequency == frequency,
           designed.ripple == ripple, designed.rolloff == rolloff, designed.sampleRate == sampleRate {
            return
        }
        designed = (response, order, frequency, ripple, rolloff, sampleRate)
        let center = min(max(Double(frequency), 1), sampleRate * 0.4995) / sampleRate
        func share(_ width: Float) -> Double { max(Double(width), 1) / sampleRate }

        // The prototype is the costly part: made again only when its own
        // settings change, not for a new cutoff.
        let same = prototypeKey.map { $0.order == order && $0.ripple == ripple && $0.rolloff == rolloff } ?? false
        if !same {
            prototypeKey = (order, ripple, rolloff)
            prototype.design(order, ripple: Double(ripple), rolloff: Double(rolloff), into: &analog)
        }
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
}

extension Elliptic {
    /// DSPFilters' elliptic analog low-pass: its zeros from the Jacobi
    /// elliptic function sn, and its poles from factoring the polynomial
    /// those make into quadratics (Bairstow's method). Its working arrays
    /// are made once, so designing again never allocates.
    fileprivate struct Prototype: Sendable {
        private var zeros = Self.array(), c1 = Self.array(), b1 = Self.array(), a1 = Self.array()
        private var d1 = Self.array(), q1 = Self.array(), z1 = Self.array(), s1 = Self.array()
        private var p = Self.array(), zw1 = Self.array(), zf1 = Self.array(), zq1 = Self.array()
        private var f = Self.array()
        private var k = 0.0, kPrime = 0.0, e = 0.0
        private var nin = 0, m = 0, n2 = 0, em = 0

        private static func array() -> ContiguousArray<Double> { ContiguousArray(repeating: 0, count: 100) }

        mutating func design(_ n: Int, ripple: Double, rolloff: Double, into layout: inout PoleZeroLayout) {
            layout.reset()
            let e2 = pow(10, ripple / 10) - 1
            let xi = 5 * exp(rolloff - 1) + 1
            k = Prototype.ellipticK(1 / xi)
            kPrime = Prototype.ellipticK(sqrt(1 - 1 / (xi * xi)))
            let ni = n & 1 == 1 ? 0 : 1
            if n >= 2 {
                for i in 1...(n / 2) {
                    let u = Double(2 * i - ni) * k / Double(n)
                    let sn = sine(u) * 2 * Double.pi / k
                    f[i] = 1 / sn
                    zeros[i - 1] = 1 / sn
                }
            }
            zeros[n / 2] = .infinity
            let fb = 1 / (2 * Double.pi)
            nin = n % 2
            n2 = n / 2
            if n2 >= 1 {
                for i in 1...n2 {
                    let x = f[n2 + 1 - i]
                    z1[i] = sqrt(1 - 1 / (x * x))
                }
            }
            e = sqrt(e2)
            let fbb = fb * fb
            m = nin + 2 * n2
            em = 2 * (m / 2)
            let tp = 2 * Double.pi
            calculateFz()
            calculateQz()
            if m > em { c1[2 * m] = 0 }
            for i in stride(from: 0, through: 2 * m, by: 2) {
                a1[m - i / 2] = c1[i] + d1[i]
            }
            let a0 = factor(m)
            var r = 0
            while r < em / 2 {
                r += 1
                p[r] /= 10
                q1[r] /= 100
                let d = 1 + p[r] + q1[r]
                b1[r] = (1 + p[r] / 2) * fbb / d
                zf1[r] = fb / pow(d, 0.25)
                zq1[r] = 1 / sqrt(abs(2 * (1 - b1[r] / (zf1[r] * zf1[r]))))
                zw1[r] = tp * zf1[r]
                let pole = Complex(
                    -0.5 * zw1[r] / zq1[r],
                    0.5 * sqrt(abs(zw1[r] * zw1[r] / (zq1[r] * zq1[r]) - 4 * zw1[r] * zw1[r])))
                layout.addConjugatePairs(pole: pole, zero: Complex(0, zeros[r - 1]))
            }
            if a0 != 0 {
                layout.add(pole: Complex(-sqrt(fbb / (0.1 * a0 - 1)) * tp), zero: .infinity)
            }
            layout.setNormal(w: 0, gain: n & 1 == 1 ? 1 : pow(10, -ripple / 20))
        }

        /// The complete elliptic integral of the first kind, by the
        /// arithmetic-geometric mean.
        private static func ellipticK(_ k: Double) -> Double {
            var a = 1.0
            var b = sqrt(1 - k * k)
            var c = a - b
            var previous: Double
            repeat {
                previous = c
                c = (a - b) / 2
                let mean = (a + b) / 2
                b = sqrt(a * b)
                a = mean
            } while c < previous
            return Double.pi / (a + a)
        }

        /// The product of (z + s1[i]) for i = 1…degree, into b1: b1[0] +
        /// b1[1]·z + … + b1[degree]·z^degree.
        private mutating func multiply(_ degree: Int) {
            b1[0] = s1[1]
            b1[1] = 1
            guard degree >= 2 else { return }
            for j in 2...degree {
                a1[0] = s1[j] * b1[0]
                for i in 1...(j - 1) { a1[i] = b1[i - 1] + s1[j] * b1[i] }
                for i in 0..<j { b1[i] = a1[i] }
                b1[j] = 1
            }
        }

        /// One coefficient of f(z)².
        private mutating func calculateFz2(_ i: Int) {
            var ji = 0, jf = 0
            if i < em + 2 {
                ji = 0
                jf = i
            }
            if i > em {
                ji = i - em
                jf = em
            }
            c1[i] = 0
            for j in stride(from: ji, through: jf, by: 2) {
                c1[i] += a1[j] * (a1[i - j] * pow(10, Double(m - i / 2)))
            }
        }

        private mutating func calculateFz() {
            var i = 1
            if nin == 1 {
                s1[i] = 1
                i += 1
            }
            while i <= nin + n2 {
                s1[i] = z1[i - nin]
                s1[i + n2] = z1[i - nin]
                i += 1
            }
            multiply(nin + 2 * n2)
            for i in stride(from: 0, through: em, by: 2) { a1[i] = e * b1[i] }
            for i in stride(from: 0, through: 2 * em, by: 2) { calculateFz2(i) }
        }

        private mutating func calculateQz() {
            var i = 1
            while i <= nin {
                s1[i] = -10
                i += 1
            }
            while i <= nin + n2 {
                s1[i] = -10 * z1[i - nin] * z1[i - nin]
                i += 1
            }
            while i <= nin + 2 * n2 {
                s1[i] = s1[i - n2]
                i += 1
            }
            multiply(m)
            let sign: Double = nin & 1 == 1 ? -1 : 1
            for i in stride(from: 0, through: 2 * m, by: 2) { d1[i] = sign * b1[i / 2] }
        }

        /// Factors the polynomial in a1, of degree `t`, into quadratics
        /// z² + p·z + q (p and q1, from index 1), by Bairstow's method;
        /// returns the root of the linear factor left over, or 0.
        private mutating func factor(_ degree: Int) -> Double {
            var t = degree
            var root = 0.0
            if t >= 1 {
                for i in 1...t { a1[i] /= a1[0] }
            }
            a1[0] = 1
            b1[0] = 1
            c1[0] = 1
            var found = 0
            while t > 2 {
                var p0 = 0.0, q0 = 0.0
                found += 1
                // Bounded, so a polynomial it cannot factor never hangs the
                // audio thread.
                for _ in 0..<1_000 {
                    b1[1] = a1[1] - p0
                    c1[1] = b1[1] - p0
                    for i in 2...t { b1[i] = a1[i] - p0 * b1[i - 1] - q0 * b1[i - 2] }
                    for i in 2..<t { c1[i] = b1[i] - p0 * c1[i - 1] - q0 * c1[i - 2] }
                    let x1 = t - 1, x2 = t - 2, x3 = t - 3
                    var x4 = c1[x2] * c1[x2] + c1[x3] * (b1[x1] - c1[x1])
                    if x4 == 0 { x4 = 1e-3 }
                    let dp = (b1[x1] * c1[x2] - b1[t] * c1[x3]) / x4
                    p0 += dp
                    let dq = (b1[t] * c1[x2] - b1[x1] * (c1[x1] - b1[x1])) / x4
                    q0 += dq
                    if abs(dp + dq) < 1e-6 { break }
                }
                p[found] = p0
                q1[found] = q0
                a1[1] -= p0
                t -= 2
                if t >= 2 {
                    for i in 2...t { a1[i] -= p0 * a1[i - 1] + q0 * a1[i - 2] }
                }
            }
            if t == 2 {
                found += 1
                p[found] = a1[1]
                q1[found] = a1[2]
            }
            if t == 1 { root = -a1[1] }
            return root
        }

        /// The Jacobi elliptic function sn(u), from its q-series.
        private func sine(_ u: Double) -> Double {
            var sn = 0.0
            let q = exp(-Double.pi * kPrime / k)
            let v = Double.pi * 0.5 * u / k
            for j in 0..<10_000 {
                let w = pow(q, Double(j) + 0.5)
                sn += w * sin(Double(2 * j + 1) * v) / (1 - w * w)
                if w < 1e-7 { break }
            }
            return sn
        }
    }
}
