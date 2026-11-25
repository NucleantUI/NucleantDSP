//
//  Bessel.swift
//  NucleantDSP
//
//  Rewritten in Swift from Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import AudioProtocols
import Foundation

/// A Bessel filter of any order from 1 to 16: the gentlest fall of the
/// designs here, for the flattest delay. Every frequency it passes comes
/// out about as late as every other, so a pulse keeps its shape: a step
/// overshoots by about 1%, where a Butterworth of the same order rings.
///
///     var filter = Bessel(.lowPass, order: 4, frequency: 1_000)
///
/// Its poles are the roots of the reverse Bessel polynomial, found
/// numerically, scaled by `frequency`: the prototype's delay is one radian
/// of `frequency`. So the level is still near full there, and falls past
/// it, the further the higher the order (−3 dB at about 1.36 times
/// `frequency` at order 2, twice it at order 4). It runs as second-order
/// sections in Double, four channels per vector.
public struct Bessel: AudioProcessor {
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
        /// Passes `width` hertz around `frequency`: twice the order's poles.
        case bandPass(width: Float)
        /// Cuts `width` hertz around `frequency`.
        case bandStop(width: Float)
        /// Below `frequency` raised or cut by `decibels`, above it as it is.
        case lowShelf(decibels: Float)
    }

    public var response: Response
    /// 1…16: how many poles the prototype has.
    public var order: Int
    /// In hertz: what scales the prototype (see above), or the middle of a
    /// band. Kept below the output's Nyquist frequency.
    public var frequency: Float

    private static let maximumOrder = 16
    private var poles = RootFinder(maximumDegree: Bessel.maximumOrder)
    private var zeros = RootFinder(maximumDegree: Bessel.maximumOrder)
    private var analog = PoleZeroLayout(maximumPoles: Bessel.maximumOrder)
    private var digital = PoleZeroLayout(maximumPoles: 2 * Bessel.maximumOrder)
    private var cascade = BiquadCascade(maximumPoles: 2 * Bessel.maximumOrder)
    /// What `cascade` was designed for, and what `analog` was: its roots
    /// are found again only when the order or the shelf's gain changes.
    private var designed: (response: Response, order: Int, frequency: Float, sampleRate: Double)?
    private var prototype: (order: Int, shelf: Float?)?

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
        let order = min(max(order, 1), Bessel.maximumOrder)
        if let designed, designed.response == response, designed.order == order,
           designed.frequency == frequency, designed.sampleRate == sampleRate {
            return
        }
        designed = (response, order, frequency, sampleRate)
        let center = min(max(Double(frequency), 1), sampleRate * 0.4995) / sampleRate
        func share(_ width: Float) -> Double { max(Double(width), 1) / sampleRate }

        switch response {
        case .lowPass:
            designLowPass(order)
            digital.makeLowPass(from: analog, frequency: center)
        case .highPass:
            designLowPass(order)
            digital.makeHighPass(from: analog, frequency: center)
        case .bandPass(let width):
            designLowPass(order)
            digital.makeBandPass(from: analog, center: center, width: share(width))
        case .bandStop(let width):
            designLowPass(order)
            digital.makeBandStop(from: analog, center: center, width: share(width))
        case .lowShelf(let decibels):
            designLowShelf(order, decibels: decibels)
            digital.makeLowPass(from: analog, frequency: center)
        }
        cascade.setLayout(digital)
    }

    /// The k-th coefficient of the reverse Bessel polynomial of degree n:
    /// (2n − k)! / ((n − k)!·k!·2^(n − k)).
    private static func reverseBessel(_ k: Int, _ n: Int) -> Double {
        func factorial(_ n: Int) -> Double {
            var y = 1.0
            if n > 1 { for m in 2...n { y *= Double(m) } }
            return y
        }
        return factorial(2 * n - k) / ((factorial(n - k) * factorial(k)) * pow(2, Double(n - k)))
    }

    /// The poles are the polynomial's roots; the zeros are at infinity.
    private mutating func designLowPass(_ order: Int) {
        if let prototype, prototype.order == order, prototype.shelf == nil { return }
        prototype = (order, nil)
        analog.reset()
        for index in 0...order { poles.coefficients[index] = Complex(Bessel.reverseBessel(index, order)) }
        poles.solve(degree: order)
        let pairCount = order / 2
        for index in 0..<pairCount { analog.addConjugatePairs(pole: poles.roots[index], zero: .infinity) }
        if order & 1 == 1 { analog.add(pole: Complex(poles.roots[pairCount].real), zero: .infinity) }
        analog.setNormal(w: 0, gain: 1)
    }

    /// The zeros are the roots of the same polynomial with its constant
    /// raised by the gain.
    private mutating func designLowShelf(_ order: Int, decibels: Float) {
        if let prototype, prototype.order == order, prototype.shelf == decibels { return }
        prototype = (order, decibels)
        analog.reset()
        let g = pow(10, Double(decibels) / 20) - 1
        for index in 0...order {
            poles.coefficients[index] = Complex(Bessel.reverseBessel(index, order))
            zeros.coefficients[index] = Complex(Bessel.reverseBessel(index, order))
        }
        zeros.coefficients[0] += g * Bessel.reverseBessel(0, order)
        poles.solve(degree: order)
        zeros.solve(degree: order)
        let pairCount = order / 2
        for index in 0..<pairCount {
            analog.addConjugatePairs(pole: poles.roots[index], zero: zeros.roots[index])
        }
        if order & 1 == 1 {
            analog.add(pole: Complex(poles.roots[pairCount].real), zero: Complex(zeros.roots[pairCount].real))
        }
        analog.setNormal(w: Double.pi, gain: 1)
    }
}
