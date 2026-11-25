//
//  Gain.swift
//  NucleantDSP
//

import AudioProtocols
import Foundation

/// Scales every sample by `level`. A change of level is reached over a few
/// milliseconds rather than at once, so it does not click.
public struct Gain: AudioProcessor {
    /// The factor samples are multiplied by: 1 leaves them as they are.
    public var level: Float

    /// The level in decibels: 0 dB is a level of 1, −6 dB about half.
    public var decibels: Float {
        get { Float(20 * log10(Double(level))) }
        set { level = Gain.level(decibels: newValue) }
    }

    /// In Double, where every platform has its math functions (Android's
    /// Foundation has no Float overloads).
    private static func level(decibels: Float) -> Float {
        Float(pow(10, Double(decibels) / 20))
    }

    /// Where the level is on its way to `level`; nil until the first buffer,
    /// which starts at `level`.
    private var current: Float?

    /// How long a change of level takes to come most of the way (1 − 1/e).
    static let smoothing = 0.005

    public init(level: Float = 1) {
        self.level = level
    }

    public init(decibels: Float) {
        self.level = Gain.level(decibels: decibels)
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let target = level
        var current = self.current ?? target
        defer { self.current = current }
        buffer.withFrames(channels: channels) { samples, frames in
            if current == target {
                scale(samples, count: frames * channels, by: target)
                return
            }
            // Toward the target a little every frame; the same for every
            // channel in it.
            let keep = Float(exp(-1 / (Gain.smoothing * sampleRate)))
            for frame in 0..<frames {
                current = target + (current - target) * keep
                if abs(current - target) < 1e-6 { current = target }
                let sample = samples + frame * channels
                for channel in 0..<channels { sample[channel] *= current }
            }
        }
    }

    /// Four samples at a time, as one vector.
    private func scale(_ samples: UnsafeMutablePointer<Float>, count: Int, by factor: Float) {
        let raw = UnsafeMutableRawPointer(samples)
        let vector = SIMD4<Float>(repeating: factor)
        var index = 0
        while index + 4 <= count {
            let offset = index * MemoryLayout<Float>.stride
            let scaled = raw.loadUnaligned(fromByteOffset: offset, as: SIMD4<Float>.self) * vector
            raw.storeBytes(of: scaled, toByteOffset: offset, as: SIMD4<Float>.self)
            index += 4
        }
        while index < count {
            samples[index] *= factor
            index += 1
        }
    }
}
