//
//  Supersaw.swift
//  NucleantDSP
//
//  Roland's supersaw, the JP-8000's: seven sawtooths, six detuned around
//  the seventh by a fixed table, summed and high-passed, run at twice the
//  output's rate. The table, the detune and the mix follow the JP-8000's
//  own DSP code as read and checked against its emulator at atosynth
//  ("The Super Saw code" and "JP80x0 MIDI to coefficient mapping",
//  February 2026), turned from 24-bit fixed point into floating point; the high-pass at the pitch is Adam Szabo's ("How to
//  Emulate the Super Saw", 2010).
//

import AudioProtocols
import Foundation

/// Seven sawtooths at once, six of them tuned a little off the middle one:
/// the thick, shimmering lead and pad of trance. Fills every channel with
/// them.
///
///     var lead = Supersaw(frequency: 220, detune: 0.5, mix: 0.7)
///
/// Each side sawtooth is off the pitch by its entry in the JP-8000's table,
/// 0, +128, −128, +408, −412, +704, −720, times a base `detune` sets. `detune`
/// is the JP-8000's detune knob, along its own curve: most of its travel is
/// fine detune, the base climbing slowly, and the last few steps reach far.
/// The outer two are 0.3% off the pitch at 13%, 1.1% at half way, 3.2% at
/// 80%, and 11% (two semitones) at full detune, where the next two are
/// about 6% off and the inner two 2%. Even at 0 the outer two are 0.6 cents
/// off, as the knob's lowest step is. The middle sawtooth is always at its own
/// level; `mix` raises the six others from 1/25 of it to 1.32 times it, in
/// a straight line, as the JP-8000's mix control does. Their sum is
/// high-passed at the pitch, which takes away what would rumble beneath
/// the note. All seven start together halfway up their ramp, as the
/// JP-8000's counters start from 0, and drift apart as they play.
///
/// The JP-8000 runs its supersaw at 88.2 kHz and plays at 44.1 kHz, so
/// what its sawtooths alias lands above what is heard and is filtered away.
/// This one does the same at twice the output's rate: its sawtooths are
/// smoothed with PolyBLEP there, and a half-band filter brings it down.
public struct Supersaw: AudioProcessor {
    /// In hertz: the middle sawtooth's pitch.
    public var frequency: Float
    /// 0…1: how far the side sawtooths are tuned off the pitch: the
    /// JP-8000's detune knob, from its first step to its last.
    public var detune: Float
    /// 0…1: how loud the six side sawtooths are against the middle one.
    public var mix: Float
    /// The level: the sum is scaled to sound about as loud as one sawtooth
    /// at this amplitude, whatever `mix` is. The JP-8000's own mix leaves
    /// the middle sawtooth alone, and what evens out its level comes later
    /// in its path.
    public var amplitude: Float

    /// Each sawtooth's offset at full detune, in 128ths of the detune's
    /// base.
    private static let offsets: [Double] = [0, 128, -128, 408, -412, 704, -720]
    /// The detune knob's 128 steps: the base each sets, in 1/16384ths of
    /// the pitch (the JP-8000's 15-bit value, times 512, over 2²³). Up by 1
    /// every second step to 63, every step to 80, by 2 to 120, then in
    /// bigger jumps to 321.
    private static let detuneSteps: [Double] = [
        1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
        9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16,
        17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24,
        25, 25, 26, 26, 27, 27, 28, 28, 29, 29, 30, 30, 31, 31, 32, 32,
        33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
        49, 51, 53, 55, 57, 59, 61, 63, 65, 67, 69, 71, 73, 75, 77, 79,
        81, 83, 85, 87, 89, 91, 93, 95, 97, 99, 101, 103, 105, 107, 109, 111,
        113, 115, 117, 119, 121, 123, 125, 127, 129, 137, 145, 153, 169, 193, 225, 321,
    ]

    /// The detune's base for `detune`, a share of the pitch: the knob's
    /// step there, and between two steps a straight line from one to the
    /// next.
    private static func base(_ detune: Float) -> Double {
        let position = Double(min(max(detune, 0), 1)) * 127
        let step = min(Int(position), 126)
        let between = position - Double(step)
        let value = detuneSteps[step] + (detuneSteps[step + 1] - detuneSteps[step]) * between
        return value / 16_384
    }
    /// The middle sawtooth's level, and the side ones' at no mix and at
    /// full mix: 25, 1 and 33 128ths, the JP-8000's.
    private static let middleLevel = 25.0 / 128
    private static let sideLevels = (1.0 / 128, 33.0 / 128)
    private static let voices = 7

    /// Where in its cycle each sawtooth is, 0..<1: all at 0.5, the value 0,
    /// to begin with.
    private var phases = ContiguousArray<Double>(repeating: 0.5, count: Supersaw.voices)
    /// The high-pass's two delayed values.
    private var z1 = 0.0, z2 = 0.0
    private var down = Halfband(channels: 1)
    /// A chunk at the doubled rate.
    private var doubled = ContiguousArray<Float>(repeating: 0, count: 2 * Supersaw.chunk)

    /// Frames of the output's rate worked through at a time.
    private static let chunk = 256

    public init(frequency: Float, detune: Float = 0.5, mix: Float = 0.7, amplitude: Float = 1) {
        self.frequency = frequency
        self.detune = detune
        self.mix = mix
        self.amplitude = amplitude
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        let rate = 2 * sampleRate
        let pitch = max(Double(frequency), 0)
        let base = Supersaw.base(detune) / 128
        let mix = Double(min(max(mix, 0), 1))
        let middle = Supersaw.middleLevel
        let side = Supersaw.sideLevels.0 + (Supersaw.sideLevels.1 - Supersaw.sideLevels.0) * mix
        // Seven sawtooths that have drifted apart add up in power: scaled
        // back to one sawtooth's.
        let level = Double(amplitude) / (middle * middle + 6 * side * side).squareRoot()

        // A second-order Butterworth high-pass at the pitch, at the doubled
        // rate (Bristow-Johnson's cookbook).
        let w0 = 2 * Double.pi * min(max(pitch, 10), 0.45 * rate) / rate
        let alpha = sin(w0) / (2 * 0.7071)
        let cosW0 = cos(w0)
        let a0 = 1 + alpha
        let b0 = (1 + cosW0) / 2 / a0, b1 = -(1 + cosW0) / a0, b2 = b0
        let a1 = -2 * cosW0 / a0, a2 = (1 - alpha) / a0

        let frames = buffer.count / channels
        var start = 0
        while start < frames {
            let count = min(Supersaw.chunk, frames - start)
            phases.withUnsafeMutableBufferPointer { phases in
                Supersaw.offsets.withUnsafeBufferPointer { offsets in
                    doubled.withUnsafeMutableBufferPointer { doubled in
                        for index in 0..<(2 * count) {
                            var sum = 0.0
                            for voice in 0..<Supersaw.voices {
                                let increment = pitch * (1 + base * offsets[voice]) / rate
                                let saw = Supersaw.sawtooth(phases[voice], increment)
                                sum += (voice == 0 ? middle : side) * saw
                                var phase = phases[voice] + increment
                                phase -= phase.rounded(.down)
                                phases[voice] = phase
                            }
                            // Direct form II, transposed.
                            let y = b0 * sum + z1
                            z1 = b1 * sum - a1 * y + z2
                            z2 = b2 * sum - a2 * y
                            doubled[index] = Float(level * y)
                        }
                        guard let samples = doubled.baseAddress else { return }
                        // Halved in place: the chunk's frames at the output's
                        // rate are the first `count`.
                        down.downsample(samples, into: samples, frames: count)
                    }
                }
            }
            for frame in 0..<count {
                let value = doubled[frame]
                for channel in 0..<channels { buffer[(start + frame) * channels + channel] = value }
            }
            start += count
        }
    }

    /// A sawtooth rising from −1 to 1 over the cycle, its jump back at 0
    /// rounded off with PolyBLEP. The JP-8000's are counters left to wrap
    /// around, from 0 at the start: here phase 0.5 is that 0.
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
