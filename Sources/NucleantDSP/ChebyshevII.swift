//
//  ChebyshevII.swift
//  NucleantDSP
//
//  Rewritten in Swift from Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import AudioProtocols
import Foundation

/// A Chebyshev type II (inverse Chebyshev) filter of any order from 1 to
/// 16: flat where it passes, like a Butterworth, but steeper, with zeros in
/// its stop band that keep everything past the cutoff at least `stopBand`
/// decibels down.
///
///     var filter = ChebyshevII(.lowPass, order: 6, frequency: 4_000, stopBand: 60)
///
/// `frequency` is where the stop band begins: a low-pass is `stopBand`
/// down there, and passes what is well below it. The poles and zeros are
/// moved from the s plane by the bilinear transform; it runs as
/// second-order sections in Double, four channels per vector.
public struct ChebyshevII: AudioProcessor {
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
        /// Passes `width` hertz around `frequency`: twice the order's poles.
        case bandPass(width: Float)
        /// Cuts `width` hertz around `frequency`.
        case bandStop(width: Float)
        /// Below `frequency` raised or cut by `decibels`. DSPFilters designs
        /// this shelf as its Chebyshev type I one, with `stopBand` as the
        /// ripple: how far the shelf's level wanders, at most `decibels`.
        case lowShelf(decibels: Float)
        /// Above `frequency` raised or cut by `decibels`, as `lowShelf`.
        case highShelf(decibels: Float)
        /// `width` hertz around `frequency` raised or cut by `decibels`, as
        /// `lowShelf`.
        case bandShelf(width: Float, decibels: Float)
    }

    public var response: Response
    /// 1…16: how many poles the prototype has.
    public var order: Int
    /// In hertz: where the stop band begins, or the middle of a band. Kept
    /// below the output's Nyquist frequency.
    public var frequency: Float
    /// In decibels, 3…60: how far down the stop band is held.
    public var stopBand: Float

    private static let maximumOrder = 16
    private var analog = PoleZeroLayout(maximumPoles: ChebyshevII.maximumOrder)
    private var digital = PoleZeroLayout(maximumPoles: 2 * ChebyshevII.maximumOrder)
    private var cascade = BiquadCascade(maximumPoles: 2 * ChebyshevII.maximumOrder)
    /// What `cascade` was designed for.
    private var designed: (response: Response, order: Int, frequency: Float, stopBand: Float, sampleRate: Double)?

    public init(_ response: Response, order: Int = 4, frequency: Float, stopBand: Float = 48) {
        self.response = response
        self.order = order
        self.frequency = frequency
        self.stopBand = stopBand
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        design(sampleRate: sampleRate)
        buffer.withFrames(channels: channels) { samples, frames in
            cascade.process(samples, frames: frames, channels: channels)
        }
    }

    private mutating func design(sampleRate: Double) {
        let order = min(max(order, 1), ChebyshevII.maximumOrder)
        let stopBand = min(max(stopBand, 3), 60)
        if let designed, designed.response == response, designed.order == order, designed.frequency == frequency,
           designed.stopBand == stopBand, designed.sampleRate == sampleRate {
            return
        }
        designed = (response, order, frequency, stopBand, sampleRate)
        let center = min(max(Double(frequency), 1), sampleRate * 0.4995) / sampleRate
        func share(_ width: Float) -> Double { max(Double(width), 1) / sampleRate }
        let stopDecibels = Double(stopBand)

        switch response {
        case .lowPass:
            designLowPass(order, stopBand: stopDecibels)
            digital.makeLowPass(from: analog, frequency: center)
        case .highPass:
            designLowPass(order, stopBand: stopDecibels)
            digital.makeHighPass(from: analog, frequency: center)
        case .bandPass(let width):
            designLowPass(order, stopBand: stopDecibels)
            digital.makeBandPass(from: analog, center: center, width: share(width))
        case .bandStop(let width):
            designLowPass(order, stopBand: stopDecibels)
            digital.makeBandStop(from: analog, center: center, width: share(width))
        case .lowShelf(let decibels):
            designLowShelf(order, decibels: Double(decibels), stopBand: stopDecibels)
            digital.makeLowPass(from: analog, frequency: center)
        case .highShelf(let decibels):
            designLowShelf(order, decibels: Double(decibels), stopBand: stopDecibels)
            digital.makeHighPass(from: analog, frequency: center)
        case .bandShelf(let width, let decibels):
            designLowShelf(order, decibels: Double(decibels), stopBand: stopDecibels)
            digital.makeBandPass(from: analog, center: center, width: share(width))
            digital.setNormal(w: center < 0.25 ? Double.pi : 0, gain: 1)
        }
        cascade.setLayout(digital)
    }

    /// The type I poles inverted, and zeros on the imaginary axis past the
    /// cutoff.
    private mutating func designLowPass(_ order: Int, stopBand: Double) {
        analog.reset()
        let epsilon = sqrt(1 / (exp(stopBand * 0.1 * log(10.0)) - 1))
        let v0 = asinh(1 / epsilon) / Double(order)
        let sinhV0 = -sinh(v0)
        let coshV0 = cosh(v0)
        let fn = Double.pi / (2 * Double(order))
        var k = 1
        for _ in 0..<(order / 2) {
            let a = sinhV0 * cos(Double(k - order) * fn)
            let b = coshV0 * sin(Double(k - order) * fn)
            let d2 = a * a + b * b
            let im = 1 / cos(Double(k) * fn)
            analog.addConjugatePairs(pole: Complex(a / d2, b / d2), zero: Complex(0, im))
            k += 2
        }
        if order & 1 == 1 { analog.add(pole: Complex(1 / sinhV0), zero: .infinity) }
        analog.setNormal(w: 0, gain: 1)
    }

    /// DSPFilters' Chebyshev II shelf: the same as its type I one.
    private mutating func designLowShelf(_ order: Int, decibels: Double, stopBand: Double) {
        analog.reset()
        analog.setNormal(w: Double.pi, gain: 1)
        guard abs(decibels) > 1e-6 else { return }
        let gainDecibels = -decibels
        var stopBand = min(stopBand, abs(gainDecibels))
        if gainDecibels < 0 { stopBand = -stopBand }
        let g = pow(10, gainDecibels / 20)
        let gb = pow(10, (gainDecibels - stopBand) / 20)
        let g0 = 1.0
        let root0 = pow(g0, 1 / Double(order))
        let epsilon = gb != g0 ? sqrt((g * g - gb * gb) / (gb * gb - g0 * g0)) : g - 1
        let b = pow(g / epsilon + gb * sqrt(1 + 1 / (epsilon * epsilon)), 1 / Double(order))
        let u = log(b / root0)
        let v = log(pow(1 / epsilon + sqrt(1 + 1 / (epsilon * epsilon)), 1 / Double(order)))
        let sinhU = sinh(u), sinhV = sinh(v)
        let coshU = cosh(u), coshV = cosh(v)
        let n2 = 2 * Double(order)
        if order >= 2 {
            for index in 1...(order / 2) {
                let a = Double.pi * Double(2 * index - 1) / n2
                let sn = sin(a), cs = cos(a)
                analog.addConjugatePairs(pole: Complex(-sn * sinhU, cs * coshU), zero: Complex(-sn * sinhV, cs * coshV))
            }
        }
        if order & 1 == 1 { analog.add(pole: Complex(-sinhU), zero: Complex(-sinhV)) }
    }
}
