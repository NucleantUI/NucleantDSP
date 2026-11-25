//
//  Oscillator.swift
//  NucleantDSP
//

import AudioProtocols
import Foundation

/// A tone: fills every channel with the same waveform. The sawtooth's and
/// square's jumps are smoothed with PolyBLEP, so high notes do not alias
/// into tones of their own.
public struct Oscillator: AudioProcessor {
    public enum Waveform: Sendable {
        case sine
        case sawtooth
        case square
        case triangle
    }

    public var waveform: Waveform
    /// In hertz.
    public var frequency: Float
    /// The peak level: 1 spans −1…1.
    public var amplitude: Float

    /// Where in the cycle the next sample is, 0..<1.
    private var phase: Double = 0

    public init(_ waveform: Waveform = .sine, frequency: Float, amplitude: Float = 1) {
        self.waveform = waveform
        self.frequency = frequency
        self.amplitude = amplitude
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let increment = Double(frequency) / sampleRate
        let frames = buffer.count / channels
        for frame in 0..<frames {
            let value = amplitude * Float(sample(at: phase, increment: increment))
            for channel in 0..<channels {
                buffer[frame * channels + channel] = value
            }
            phase += increment
            phase -= phase.rounded(.down)
        }
    }

    private func sample(at phase: Double, increment: Double) -> Double {
        switch waveform {
        case .sine:
            return sin(2 * .pi * phase)
        case .sawtooth:
            return 2 * phase - 1 - Oscillator.blep(phase, increment)
        case .square:
            let half = (phase + 0.5).truncatingRemainder(dividingBy: 1)
            return (phase < 0.5 ? 1 : -1) + Oscillator.blep(phase, increment) - Oscillator.blep(half, increment)
        case .triangle:
            return 1 - 4 * abs(phase - 0.5)
        }
    }

    /// The polynomial that rounds off a jump of 2 at phase 0, within one
    /// sample of it on either side.
    private static func blep(_ phase: Double, _ increment: Double) -> Double {
        guard increment > 0 else { return 0 }
        if phase < increment {
            let t = phase / increment
            return t + t - t * t - 1
        }
        if phase > 1 - increment {
            let t = (phase - 1) / increment
            return t * t + t + t + 1
        }
        return 0
    }
}
