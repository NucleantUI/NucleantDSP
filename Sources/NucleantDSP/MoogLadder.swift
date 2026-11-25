//
//  MoogLadder.swift
//  NucleantDSP
//
//  Antti Huovilainen's non-linear model of the Moog ladder filter
//  ("Non-linear digital implementation of the Moog ladder filter",
//  DAFx 2004), with the tuning and resonance corrections of Victor
//  Lazzarini's Csound version of it (musicdsp.org, "Moog Filter").
//

import AudioProtocols
import Foundation

/// Moog's transistor ladder: four one-pole stages, each saturating as its
/// transistors do, with feedback from the last to the first. A four-pole
/// low-pass, 24 dB an octave, that self-oscillates as `resonance` reaches 1.
///
///     var filter = MoogLadder(cutoff: 800, resonance: 0.6)
///     var bass = Oscillator(.sawtooth, frequency: 55)
///         .then(MoogLadder(cutoff: 400, resonance: 0.8, drive: 3))
///
/// Each stage runs its input through tanh: a signal within about ±0.5
/// passes almost clean, and a louder one, or one pushed by `drive`, rounds
/// off and thickens. Half a sample of delay in the feedback, and
/// polynomials in the cutoff, keep the tuning and the resonance where they
/// are asked for. The model needs twice the output's rate: it runs there,
/// the signal doubled and halved again by a half-band filter.
///
/// At `cutoff` it is about 12 dB down, each of the four stages 3 dB. As on
/// the Moog, resonance thins what passes below the cutoff.
public struct MoogLadder: AudioProcessor {
    /// In hertz, 20 Hz up to 0.45 of the output's rate.
    public var cutoff: Float
    /// 0…1: the feedback around the stages; at 1 the filter rings on its
    /// own.
    public var resonance: Float
    /// What the signal is multiplied by on its way in: above 1, it
    /// saturates the stages more.
    public var drive: Float

    /// Twice the transistors' thermal voltage, for a signal whose full
    /// scale is ±1: the Csound version's 40000 for its ±32768.
    private static let thermal = 40_000.0 / 32_768

    /// Per channel: the four stages' outputs, the last one's before, the
    /// feedback, and each stage's output through tanh.
    private struct Stages: Sendable {
        var z1 = 0.0, z2 = 0.0, z3 = 0.0, z4 = 0.0, z5 = 0.0
        var feedback = 0.0
        var t1 = 0.0, t2 = 0.0, t3 = 0.0, t4 = 0.0
    }

    private var stages = ContiguousArray<Stages>()
    private var up = Halfband(channels: 0)
    private var down = Halfband(channels: 0)
    /// A chunk of the buffer at the doubled rate.
    private var scratch = ContiguousArray<Float>()

    /// Frames of the output's rate worked through at a time.
    private static let chunk = 256

    public init(cutoff: Float, resonance: Float = 0, drive: Float = 1) {
        self.cutoff = cutoff
        self.resonance = resonance
        self.drive = drive
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if stages.count != channels {
            stages = ContiguousArray(repeating: Stages(), count: channels)
            up = Halfband(channels: channels)
            down = Halfband(channels: channels)
            scratch = ContiguousArray(repeating: 0, count: 2 * MoogLadder.chunk * channels)
        }

        // The tuning, from the cutoff as a share of the output's rate (kfc)
        // and of the doubled rate the stages run at (kf).
        let frequency = min(max(Double(cutoff), 20), 0.45 * sampleRate)
        let kfc = frequency / sampleRate
        let kf = frequency / (2 * sampleRate)
        let tuning = 1.8730 * kfc * kfc * kfc + 0.4955 * kfc * kfc - 0.6490 * kfc + 0.9988
        let correction = -3.9364 * kfc * kfc + 1.8409 * kfc + 0.9968
        let thermal = MoogLadder.thermal
        let g = thermal * (1 - exp(-2 * Double.pi * tuning * kf))
        let feedback = 4 * Double(min(max(resonance, 0), 1)) * correction
        let drive = Double(drive)

        buffer.withFrames(channels: channels) { samples, frames in
            scratch.withUnsafeMutableBufferPointer { scratch in
                guard let doubled = scratch.baseAddress else { return }
                stages.withUnsafeMutableBufferPointer { stages in
                    var start = 0
                    while start < frames {
                        let count = min(MoogLadder.chunk, frames - start)
                        let chunk = samples + start * channels
                        up.upsample(chunk, into: doubled, frames: count)
                        for frame in 0..<(2 * count) {
                            for channel in 0..<channels {
                                let index = frame * channels + channel
                                var s = stages[channel]
                                let input = drive * Double(doubled[index])
                                // Each stage: y = z + g·(tanh(in/2Vt) − tanh(z/2Vt)).
                                s.z1 += g * (tanh((input - feedback * s.feedback) / thermal) - s.t1)
                                s.t1 = tanh(s.z1 / thermal)
                                s.z2 += g * (s.t1 - s.t2)
                                s.t2 = tanh(s.z2 / thermal)
                                s.z3 += g * (s.t2 - s.t3)
                                s.t3 = tanh(s.z3 / thermal)
                                s.z4 += g * (s.t3 - s.t4)
                                s.t4 = tanh(s.z4 / thermal)
                                // Half a sample's delay, by the mean with the last.
                                s.feedback = (s.z4 + s.z5) * 0.5
                                s.z5 = s.z4
                                stages[channel] = s
                                doubled[index] = Float(s.feedback)
                            }
                        }
                        down.downsample(doubled, into: chunk, frames: count)
                        start += count
                    }
                }
            }
        }
    }
}
