//
//  PulseOscillator.swift
//  NucleantDSP
//
//  Pulse-width modulation as Steffan Diedrichsen gives it at musicdsp.org
//  ("Pulsewidth modulation"): a rising sawtooth and a falling one, the
//  second shifted by part of a period, added together.
//

import AudioProtocols
import Foundation

/// A pulse wave whose width can move while it plays: fills every channel
/// with it. Swept slowly, the width gives the chorusing, hollow sound of
/// pulse-width modulation.
///
///     var pulse = PulseOscillator(frequency: 110, width: 0.25)
///     pulse.width = 0.4  // while it plays
///
/// The pulse is a sawtooth minus the same sawtooth `width` of a period
/// ahead. Each is smoothed with PolyBLEP, so the pulse's edges do not alias.
/// Its two levels are always 2·`amplitude` apart and its average is 0, so
/// a width of 0.5 is a square from −`amplitude` to `amplitude`, and a
/// narrower pulse sits lower: from −2·width to 2 − 2·width times
/// `amplitude`. At a width of 0 or 1 the two sawtooths cancel, and it is
/// silent.
public struct PulseOscillator: AudioProcessor {
    /// In hertz.
    public var frequency: Float
    /// 0…1: the share of each period spent high, from its start.
    public var width: Float
    /// Half the distance between the pulse's two levels.
    public var amplitude: Float

    /// Where in the cycle the next sample is, 0..<1.
    private var phase: Double = 0

    public init(frequency: Float, width: Float = 0.5, amplitude: Float = 1) {
        self.frequency = frequency
        self.width = width
        self.amplitude = amplitude
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        let increment = Double(frequency) / sampleRate
        let width = Double(min(max(width, 0), 1))
        let frames = buffer.count / channels
        for frame in 0..<frames {
            // The sawtooth shifted so it falls at `width`, minus the one
            // that falls at 0: up by 2 at 0, down by 2 at `width`.
            var shifted = phase + 1 - width
            shifted -= shifted.rounded(.down)
            let pulse = PulseOscillator.sawtooth(shifted, increment) - PulseOscillator.sawtooth(phase, increment)
            let value = amplitude * Float(pulse)
            for channel in 0..<channels {
                buffer[frame * channels + channel] = value
            }
            phase += increment
            phase -= phase.rounded(.down)
        }
    }

    /// A sawtooth rising from −1 to 1 over the cycle, its jump back at 0
    /// rounded off with PolyBLEP.
    private static func sawtooth(_ phase: Double, _ increment: Double) -> Double {
        var value = 2 * phase - 1
        guard increment > 0 else { return value }
        if phase < increment {
            let t = phase / increment
            value -= t + t - t * t - 1
        } else if phase > 1 - increment {
            let t = (phase - 1) / increment
            value -= t * t + t + t + 1
        }
        return value
    }
}
