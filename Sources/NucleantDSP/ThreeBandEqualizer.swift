//
//  ThreeBandEqualizer.swift
//  NucleantDSP
//
//  Neil C's three-band equaliser (musicdsp.org, "3 Band Equaliser"; placed
//  in the public domain by Neil C / Etanza Systems), on Paul Kellet's
//  one-pole filters.
//

import AudioProtocols
import Foundation

/// The lows, the mids and the highs, each raised or cut on its own: a
/// mixer channel's EQ.
///
///     var eq = ThreeBandEqualizer(low: 3, mid: -2, high: 1.5)
///
/// Two four-pole low-passes, at `lowFrequency` and `highFrequency`, split
/// the signal: the lows are the first's output, the highs what the second
/// leaves out, and the mids whatever is left between. At 0 dB on all three
/// the sound comes out as it went in, three samples later.
public struct ThreeBandEqualizer: AudioProcessor {
    /// In decibels: what the band below `lowFrequency` is raised by.
    public var low: Float
    /// In decibels: the band between the two frequencies.
    public var mid: Float
    /// In decibels: the band above `highFrequency`.
    public var high: Float
    /// In hertz: where the lows end and the mids begin.
    public var lowFrequency: Float
    /// In hertz: where the mids end and the highs begin.
    public var highFrequency: Float

    /// Per channel: both filters' four poles, and the last three inputs.
    private struct Bands: Sendable {
        var lowPoles = SIMD4<Double>.zero
        var highPoles = SIMD4<Double>.zero
        var history = SIMD3<Double>.zero
    }

    private var bands = ContiguousArray<Bands>()

    /// A very small amount added at each filter's input, so its poles never
    /// decay into denormals.
    private static let tiny = 1.0 / 4_294_967_295

    public init(low: Float = 0, mid: Float = 0, high: Float = 0, lowFrequency: Float = 880, highFrequency: Float = 5_000) {
        self.low = low
        self.mid = mid
        self.high = high
        self.lowFrequency = lowFrequency
        self.highFrequency = highFrequency
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if bands.count != channels { bands = ContiguousArray(repeating: Bands(), count: channels) }
        func coefficient(_ frequency: Float) -> Double {
            2 * sin(Double.pi * min(max(Double(frequency), 10), sampleRate / 4) / sampleRate)
        }
        func level(_ decibels: Float) -> Double { pow(10, Double(decibels) / 20) }
        let lf = coefficient(lowFrequency), hf = coefficient(highFrequency)
        let lg = level(low), mg = level(mid), hg = level(high)
        let tiny = ThreeBandEqualizer.tiny

        buffer.withFrames(channels: channels) { samples, frames in
            bands.withUnsafeMutableBufferPointer { bands in
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        let index = frame * channels + channel
                        let x = Double(samples[index])
                        var b = bands[channel]
                        b.lowPoles[0] += lf * (x - b.lowPoles[0]) + tiny
                        b.lowPoles[1] += lf * (b.lowPoles[0] - b.lowPoles[1])
                        b.lowPoles[2] += lf * (b.lowPoles[1] - b.lowPoles[2])
                        b.lowPoles[3] += lf * (b.lowPoles[2] - b.lowPoles[3])
                        let l = b.lowPoles[3]

                        b.highPoles[0] += hf * (x - b.highPoles[0]) + tiny
                        b.highPoles[1] += hf * (b.highPoles[0] - b.highPoles[1])
                        b.highPoles[2] += hf * (b.highPoles[1] - b.highPoles[2])
                        b.highPoles[3] += hf * (b.highPoles[2] - b.highPoles[3])
                        let delayed = b.history[2]
                        let h = delayed - b.highPoles[3]
                        let m = delayed - (h + l)

                        b.history = SIMD3(x, b.history[0], b.history[1])
                        bands[channel] = b
                        samples[index] = Float(l * lg + m * mg + h * hg)
                    }
                }
            }
        }
    }
}
