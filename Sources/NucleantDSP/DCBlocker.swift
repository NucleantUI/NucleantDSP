//
//  DCBlocker.swift
//  NucleantDSP
//
//  The one-pole, one-zero DC filter from Julius O. Smith's "Introduction to
//  Digital Filters", as given at musicdsp.org ("DC filter").
//

import AudioProtocols
import Foundation

/// Takes away a signal's offset from zero, and whatever moves slower than
/// `cutoff`: what an asymmetric shaper, a wave folder or a sum of
/// processors leaves behind, which only takes up headroom.
///
///     var chain = Oscillator(.sawtooth, frequency: 110)
///         .then(Wavefolder(level: 0.6))
///         .then(DCBlocker())
///
/// y[n] = x[n] − x[n − 1] + R·y[n − 1], with R = 1 − 2π·`cutoff`/rate:
/// −3 dB at `cutoff`, and flat a few octaves above it.
public struct DCBlocker: AudioProcessor {
    /// In hertz: where it is 3 dB down.
    public var cutoff: Float

    /// Per channel: the last input and output.
    private var state = ContiguousArray<SIMD2<Double>>()

    public init(cutoff: Float = 20) {
        self.cutoff = cutoff
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if state.count != channels { state = ContiguousArray(repeating: .zero, count: channels) }
        let r = 1 - 2 * Double.pi * min(max(Double(cutoff), 0), sampleRate / 8) / sampleRate
        buffer.withFrames(channels: channels) { samples, frames in
            state.withUnsafeMutableBufferPointer { state in
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        let index = frame * channels + channel
                        let x = Double(samples[index])
                        let y = x - state[channel].x + r * state[channel].y
                        state[channel] = SIMD2(x, y)
                        samples[index] = Float(y)
                    }
                }
            }
        }
    }
}
