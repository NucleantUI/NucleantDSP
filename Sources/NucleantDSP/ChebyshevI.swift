//
//  ChebyshevI.swift
//  NucleantDSP
//
//  Rewritten in Swift from Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt). The shelves
//  follow Sophocles J. Orfanidis, "High-Order Digital Parametric Equalizer
//  Design".
//

import AudioProtocols
import Foundation

/// A Chebyshev type I filter of any order from 1 to 16: steeper than a
/// Butterworth of the same order, for a ripple of `ripple` decibels where
/// it passes. The more ripple, the steeper, and the more it rings at the
/// cutoff.
///
///     var filter = ChebyshevI(.lowPass, order: 6, frequency: 1_200, ripple: 1)
///
/// At `frequency` a low- or high-pass is down by `ripple`, and falls away
/// from there. Its poles lie on an ellipse in the s plane, moved to the z
/// plane by the bilinear transform; it runs as second-order sections in
/// Double, four channels per vector.
public struct ChebyshevI: AudioProcessor {
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
        /// Passes `width` hertz around `frequency`: twice the order's poles.
        case bandPass(width: Float)
        /// Cuts `width` hertz around `frequency`.
        case bandStop(width: Float)
        /// Below `frequency` raised or cut by `decibels`; `ripple` is then
        /// how far the shelf's level wanders, at most `decibels`.
        case lowShelf(decibels: Float)
        /// Above `frequency` raised or cut by `decibels`.
        case highShelf(decibels: Float)
        /// `width` hertz around `frequency` raised or cut by `decibels`.
        case bandShelf(width: Float, decibels: Float)
    }

    public var response: Response
    /// 1…16: how many poles the prototype has.
    public var order: Int
    /// In hertz: the cutoff, or the middle of a band. Kept below the
    /// output's Nyquist frequency.
    public var frequency: Float
    /// In decibels, 0.001…12: how far the level dips and rises where the
    /// filter passes.
    public var ripple: Float

    private static let maximumOrder = 16
    private var analog = PoleZeroLayout(maximumPoles: ChebyshevI.maximumOrder)
    private var digital = PoleZeroLayout(maximumPoles: 2 * ChebyshevI.maximumOrder)
    private var cascade = BiquadCascade(maximumPoles: 2 * ChebyshevI.maximumOrder)
    /// What `cascade` was designed for.
    private var designed: (response: Response, order: Int, frequency: Float, ripple: Float, sampleRate: Double)?

    public init(_ response: Response, order: Int = 4, frequency: Float, ripple: Float = 1) {
        self.response = response
        self.order = order
        self.frequency = frequency
        self.ripple = ripple
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        design(sampleRate: sampleRate)
        buffer.withFrames(channels: channels) { samples, frames in
            cascade.process(samples, frames: frames, channels: channels)
        }
    }

    private mutating func design(sampleRate: Double) {
        let order = min(max(order, 1), ChebyshevI.maximumOrder)
        let ripple = min(max(ripple, 0.001), 12)
        if let designed, designed.response == response, designed.order == order, designed.frequency == frequency,
           designed.ripple == ripple, designed.sampleRate == sampleRate {
            return
        }
        designed = (response, order, frequency, ripple, sampleRate)
        let center = min(max(Double(frequency), 1), sampleRate * 0.4995) / sampleRate
        func share(_ width: Float) -> Double { max(Double(width), 1) / sampleRate }
        let rippleDecibels = Double(ripple)

        switch response {
        case .lowPass:
            designLowPass(order, ripple: rippleDecibels)
            digital.makeLowPass(from: analog, frequency: center)
        case .highPass:
            designLowPass(order, ripple: rippleDecibels)
            digital.makeHighPass(from: analog, frequency: center)
        case .bandPass(let width):
            designLowPass(order, ripple: rippleDecibels)
            digital.makeBandPass(from: analog, center: center, width: share(width))
        case .bandStop(let width):
            designLowPass(order, ripple: rippleDecibels)
            digital.makeBandStop(from: analog, center: center, width: share(width))
        case .lowShelf(let decibels):
            designLowShelf(order, decibels: Double(decibels), ripple: rippleDecibels)
            digital.makeLowPass(from: analog, frequency: center)
        case .highShelf(let decibels):
            designLowShelf(order, decibels: Double(decibels), ripple: rippleDecibels)
            digital.makeHighPass(from: analog, frequency: center)
        case .bandShelf(let width, let decibels):
            designLowShelf(order, decibels: Double(decibels), ripple: rippleDecibels)
            digital.makeBandPass(from: analog, center: center, width: share(width))
            digital.setNormal(w: center < 0.25 ? Double.pi : 0, gain: 1)
        }
        cascade.setLayout(digital)
    }

    /// The poles on an ellipse, the zeros at infinity. An even order peaks
    /// at 0 dB, so at 0 Hz it is down by the ripple.
    private mutating func designLowPass(_ order: Int, ripple: Double) {
        analog.reset()
        let epsilon = sqrt(1 / exp(-ripple * 0.1 * log(10.0)) - 1)
        let v0 = asinh(1 / epsilon) / Double(order)
        let sinhV0 = -sinh(v0)
        let coshV0 = cosh(v0)
        let n2 = 2 * Double(order)
        for index in 0..<(order / 2) {
            let k = Double(2 * index + 1 - order)
            let a = sinhV0 * cos(k * Double.pi / n2)
            let b = coshV0 * sin(k * Double.pi / n2)
            analog.addConjugatePairs(pole: Complex(a, b), zero: .infinity)
        }
        if order & 1 == 1 {
            analog.add(pole: Complex(sinhV0), zero: .infinity)
            analog.setNormal(w: 0, gain: 1)
        } else {
            analog.setNormal(w: 0, gain: pow(10, -ripple / 20))
        }
    }

    /// Orfanidis' Chebyshev type I shelf: poles and zeros on two ellipses.
    private mutating func designLowShelf(_ order: Int, decibels: Double, ripple: Double) {
        analog.reset()
        analog.setNormal(w: Double.pi, gain: 1)
        // No gain, no shelf: no poles, and the signal as it is.
        guard abs(decibels) > 1e-6 else { return }
        let gainDecibels = -decibels
        var ripple = min(ripple, abs(gainDecibels))
        if gainDecibels < 0 { ripple = -ripple }
        let g = pow(10, gainDecibels / 20)
        let gb = pow(10, (gainDecibels - ripple) / 20)
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
