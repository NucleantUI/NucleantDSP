//
//  Biquad.swift
//  NucleantDSP
//

import AudioProtocols
import Foundation

/// A second-order filter, its coefficients from Robert Bristow-Johnson's
/// Audio EQ Cookbook. Channels are filtered four at a time, one in each lane
/// of a vector.
public struct Biquad: AudioProcessor {
    /// What the filter does around `frequency`.
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
        /// Passes `frequency` at 0 dB, narrower as `q` grows.
        case bandPass
        case notch
        /// Every frequency at 0 dB, its phase turned around `frequency`.
        case allPass
        /// A bell at `frequency`, raised or cut by `decibels`.
        case peak(decibels: Float)
        case lowShelf(decibels: Float)
        case highShelf(decibels: Float)
    }

    public var response: Response
    /// In hertz. Kept below the output's Nyquist frequency.
    public var frequency: Float
    /// How sharp the filter is around `frequency`: 0.7071 for a Butterworth
    /// low- or high-pass; a shelf's slope at 0.7071 is the steepest without
    /// a bump.
    public var q: Float

    private struct Coefficients {
        var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    }

    private var coefficients = Coefficients()
    /// What `coefficients` were worked out for.
    private var designed: (response: Response, frequency: Float, q: Float, sampleRate: Double)?
    /// Two delayed values per channel, four channels per vector: for channel
    /// group `g`, `state[2g]` and `state[2g + 1]`.
    private var state: ContiguousArray<SIMD4<Float>> = []

    public init(_ response: Response, frequency: Float, q: Float = 0.7071) {
        self.response = response
        self.frequency = frequency
        self.q = q
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        design(sampleRate: sampleRate)
        let groups = (channels + 3) / 4
        if state.count != groups * 2 {
            state = ContiguousArray(repeating: .zero, count: groups * 2)
        }
        let b0 = SIMD4<Float>(repeating: coefficients.b0), b1 = SIMD4<Float>(repeating: coefficients.b1)
        let b2 = SIMD4<Float>(repeating: coefficients.b2), a1 = SIMD4<Float>(repeating: coefficients.a1)
        let a2 = SIMD4<Float>(repeating: coefficients.a2)
        buffer.withFrames(channels: channels) { samples, frames in
            state.withUnsafeMutableBufferPointer { state in
                for group in 0..<groups {
                    let first = group * 4
                    let lanes = min(4, channels - first)
                    var z1 = state[group * 2], z2 = state[group * 2 + 1]
                    for frame in 0..<frames {
                        let sample = samples + frame * channels + first
                        var x = SIMD4<Float>.zero
                        for lane in 0..<lanes { x[lane] = sample[lane] }
                        // Direct form II, transposed.
                        let y = b0 * x + z1
                        z1 = b1 * x - a1 * y + z2
                        z2 = b2 * x - a2 * y
                        for lane in 0..<lanes { sample[lane] = y[lane] }
                    }
                    state[group * 2] = z1
                    state[group * 2 + 1] = z2
                }
            }
        }
    }

    private mutating func design(sampleRate: Double) {
        if let designed, designed.response == response, designed.frequency == frequency,
           designed.q == q, designed.sampleRate == sampleRate {
            return
        }
        designed = (response, frequency, q, sampleRate)
        // Worked out in Double, which is also where every platform has its
        // math functions (Android's Foundation has no Float overloads).
        let nyquist = sampleRate / 2
        let f0 = min(max(Double(frequency), 1), nyquist * 0.999)
        let w0 = 2 * Double.pi * f0 / sampleRate
        let cosW0 = cos(w0)
        let alpha = sin(w0) / (2 * max(Double(q), 0.0001))

        var b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double
        switch response {
        case .lowPass:
            b0 = (1 - cosW0) / 2; b1 = 1 - cosW0; b2 = b0
            a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cosW0) / 2; b1 = -(1 + cosW0); b2 = b0
            a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
        case .bandPass:
            b0 = alpha; b1 = 0; b2 = -alpha
            a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
        case .notch:
            b0 = 1; b1 = -2 * cosW0; b2 = 1
            a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
        case .allPass:
            b0 = 1 - alpha; b1 = -2 * cosW0; b2 = 1 + alpha
            a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
        case .peak(let decibels):
            let a = pow(10, Double(decibels) / 40)
            b0 = 1 + alpha * a; b1 = -2 * cosW0; b2 = 1 - alpha * a
            a0 = 1 + alpha / a; a1 = -2 * cosW0; a2 = 1 - alpha / a
        case .lowShelf(let decibels):
            let a = pow(10, Double(decibels) / 40)
            let root = 2 * sqrt(a) * alpha
            b0 = a * ((a + 1) - (a - 1) * cosW0 + root)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosW0)
            b2 = a * ((a + 1) - (a - 1) * cosW0 - root)
            a0 = (a + 1) + (a - 1) * cosW0 + root
            a1 = -2 * ((a - 1) + (a + 1) * cosW0)
            a2 = (a + 1) + (a - 1) * cosW0 - root
        case .highShelf(let decibels):
            let a = pow(10, Double(decibels) / 40)
            let root = 2 * sqrt(a) * alpha
            b0 = a * ((a + 1) + (a - 1) * cosW0 + root)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosW0)
            b2 = a * ((a + 1) + (a - 1) * cosW0 - root)
            a0 = (a + 1) - (a - 1) * cosW0 + root
            a1 = 2 * ((a - 1) - (a + 1) * cosW0)
            a2 = (a + 1) - (a - 1) * cosW0 - root
        }
        coefficients = Coefficients(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0), a1: Float(a1 / a0), a2: Float(a2 / a0))
    }
}
