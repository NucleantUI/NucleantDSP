//
//  Butterworth.swift
//  NucleantDSP
//
//  Rewritten in Swift from Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import AudioProtocols
import Foundation

/// A Butterworth filter of any order from 1 to 16: as flat as a filter can
/// be where it passes, and −3 dB at `frequency`, falling 6 dB per octave
/// for each order beyond it.
///
///     var filter = Butterworth(.lowPass, order: 8, frequency: 2_000)
///     var band = Butterworth(.bandPass(width: 400), order: 4, frequency: 1_000)
///
/// Designed from its poles in the s plane, moved to the z plane by the
/// bilinear transform, and run as second-order sections in Double, four
/// channels per vector.
public struct Butterworth: AudioProcessor {
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
        /// Passes `width` hertz around `frequency`: twice the order's poles.
        case bandPass(width: Float)
        /// Cuts `width` hertz around `frequency`.
        case bandStop(width: Float)
        /// Below `frequency` raised or cut by `decibels`, above it as it is.
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

    private static let maximumOrder = 16
    private var analog = PoleZeroLayout(maximumPoles: Butterworth.maximumOrder)
    private var digital = PoleZeroLayout(maximumPoles: 2 * Butterworth.maximumOrder)
    private var cascade = BiquadCascade(maximumPoles: 2 * Butterworth.maximumOrder)
    /// What `cascade` was designed for.
    private var designed: (response: Response, order: Int, frequency: Float, sampleRate: Double)?

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
        let order = min(max(order, 1), Butterworth.maximumOrder)
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
            designLowShelf(order, decibels: Double(decibels))
            digital.makeLowPass(from: analog, frequency: center)
        case .highShelf(let decibels):
            designLowShelf(order, decibels: Double(decibels))
            digital.makeHighPass(from: analog, frequency: center)
        case .bandShelf(let width, let decibels):
            designLowShelf(order, decibels: Double(decibels))
            digital.makeBandPass(from: analog, center: center, width: share(width))
            // Unity far from the band, on the side further from it.
            digital.setNormal(w: center < 0.25 ? Double.pi : 0, gain: 1)
        }
        cascade.setLayout(digital)
    }

    /// The poles evenly around the left half of the unit circle, the
    /// zeros at infinity.
    private mutating func designLowPass(_ order: Int) {
        analog.reset()
        let n2 = 2 * Double(order)
        for index in 0..<(order / 2) {
            let pole = Complex(radius: 1, angle: Double.pi / 2 + Double(2 * index + 1) * Double.pi / n2)
            analog.addConjugatePairs(pole: pole, zero: .infinity)
        }
        if order & 1 == 1 { analog.add(pole: Complex(-1), zero: .infinity) }
        analog.setNormal(w: 0, gain: 1)
    }

    /// Poles and zeros on two circles, their radii set by the gain.
    private mutating func designLowShelf(_ order: Int, decibels: Double) {
        analog.reset()
        let n2 = Double(order) * 2
        let g = pow(pow(10, decibels / 20), 1 / n2)
        let gp = -1 / g
        let gz = -g
        if order >= 2 {
            for index in 1...(order / 2) {
                let theta = Double.pi * (0.5 - Double(2 * index - 1) / n2)
                analog.addConjugatePairs(pole: Complex(radius: gp, angle: theta), zero: Complex(radius: gz, angle: theta))
            }
        }
        if order & 1 == 1 { analog.add(pole: Complex(gp), zero: Complex(gz)) }
        analog.setNormal(w: Double.pi, gain: 1)
    }
}
