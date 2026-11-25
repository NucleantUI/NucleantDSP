//
//  TiltEqualizer.swift
//  NucleantDSP
//
//  Lubomir I. Ivanov's tilt equalizer (musicdsp.org, "Simple Tilt
//  equalizer"), after the "Niveau" filter of Elysia's mPressor.
//

import AudioProtocols
import Foundation

/// One knob for the whole tone: the sound tilted about `frequency`, its
/// highs raised as its lows are lowered, or the other way round.
///
///     var tone = TiltEqualizer(frequency: 800, decibels: 2)
///
/// A one-pole low-pass splits the signal in two around `frequency` (its own
/// cutoff is at two thirds of it). Tilted up (`decibels` above 0), the
/// highs rise by `decibels` and the lows fall by five times as much;
/// tilted down, the lows rise by the size of `decibels` and the highs fall
/// five times as far. The change is gradual: each end comes within a
/// fraction of a decibel of that only a few octaves from `frequency`. Near
/// ±6 dB the far side is all but gone: a first-order high- or low-pass with
/// 6 dB of gain.
public struct TiltEqualizer: AudioProcessor {
    /// In hertz: the pivot, 20 Hz to 20 kHz.
    public var frequency: Float
    /// −6…6: how far the side being raised rises.
    public var decibels: Float

    /// Per channel: the low-pass's output.
    private var lows = ContiguousArray<Double>()

    public init(frequency: Float = 1_000, decibels: Float = 0) {
        self.frequency = frequency
        self.decibels = decibels
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if lows.count != channels { lows = ContiguousArray(repeating: 0, count: channels) }
        let gain = Double(min(max(decibels, -6), 6))
        // Decibels to a factor, by e^(gain / (6/ln 2)): 6 dB doubles.
        let amp = 6 / log(2.0)
        let proportion = 5.0
        let (lowGain, highGain) = gain > 0 ? (-proportion * gain, gain) : (-gain, proportion * gain)
        let lowFactor = exp(lowGain / amp) - 1
        let highFactor = exp(highGain / amp) - 1
        let omega = 2 * Double.pi * min(max(Double(frequency), 20), 20_000)
        let sr3 = 3 * sampleRate
        let n = 1 / (sr3 + omega)
        let a0 = 2 * omega * n
        let b1 = (sr3 - omega) * n

        buffer.withFrames(channels: channels) { samples, frames in
            lows.withUnsafeMutableBufferPointer { lows in
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        let index = frame * channels + channel
                        let x = Double(samples[index])
                        let low = a0 * x + b1 * lows[channel]
                        lows[channel] = low
                        samples[index] = Float(x + lowFactor * low + highFactor * (x - low))
                    }
                }
            }
        }
    }
}
