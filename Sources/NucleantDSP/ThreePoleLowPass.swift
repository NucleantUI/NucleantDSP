//
//  ThreePoleLowPass.swift
//  NucleantDSP
//
//  Josep M. Comajuncosas' 18 dB/octave resonant low-pass with tanh
//  distortion (musicdsp.org, "18dB/oct resonant 3 pole LPF with tanh()
//  dist", his lpf18 for Csound and Sync Modular).
//

import AudioProtocols
import Foundation

/// A three-pole resonant low-pass, 18 dB an octave, with its feedback
/// through tanh and a tanh distortion on its way out: the rubbery,
/// squelching sound of a single-oscillator bass synth.
///
///     var filter = ThreePoleLowPass(cutoff: 600, resonance: 0.8, distortion: 0.5)
///
/// `cutoff` is where it resonates: a polynomial tunes its three one-pole
/// stages so that together they turn the phase half a cycle there, and
/// another scales the resonance so it rings on its own from about 0.85,
/// whatever the cutoff. Without resonance it is already about 17 dB down at
/// the cutoff, each stage 3 dB down at about 0.6 of it. The output always
/// passes through tanh: at `distortion` 0 that only rounds off a signal
/// past about ±0.5.
public struct ThreePoleLowPass: AudioProcessor {
    /// In hertz, up to 0.49 of the output's rate.
    public var cutoff: Float
    /// 0…1: the feedback. Below about 0.85 a peak just under the cutoff;
    /// from there, the filter oscillates on its own, at the cutoff.
    public var resonance: Float
    /// 0 and up: how hard the output is driven into tanh, more so as the
    /// resonance rises and the cutoff falls.
    public var distortion: Float

    /// Per channel: each stage's output, and the input each stage had one
    /// sample before.
    private struct Stages: Sendable {
        var input = 0.0, y1 = 0.0, y2 = 0.0, output = 0.0
    }

    private var stages = ContiguousArray<Stages>()

    public init(cutoff: Float, resonance: Float = 0, distortion: Float = 0) {
        self.cutoff = cutoff
        self.resonance = resonance
        self.distortion = distortion
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if stages.count != channels { stages = ContiguousArray(repeating: Stages(), count: channels) }
        // The cutoff as a share of the Nyquist frequency.
        let fcn = min(max(Double(cutoff), 10), 0.49 * sampleRate) / (sampleRate / 2)
        let p = ((-2.7528 * fcn + 3.0429) * fcn + 1.718) * fcn - 0.9984
        let p1 = p + 1
        let scale = ((-2.7079 * p1 + 10.963) * p1 - 14.934) * p1 + 8.4974
        let k = Double(min(max(resonance, 0), 1)) * scale
        let half = p1 / 2
        let drive = 1 + Double(max(distortion, 0)) * (1.5 + 2 * k * (1 - fcn))

        buffer.withFrames(channels: channels) { samples, frames in
            stages.withUnsafeMutableBufferPointer { stages in
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        let index = frame * channels + channel
                        var s = stages[channel]
                        let x = Double(samples[index]) - k * tanh(s.output)
                        let y1 = (x + s.input) * half - p * s.y1
                        let y2 = (y1 + s.y1) * half - p * s.y2
                        let output = (y2 + s.y2) * half - p * s.output
                        s = Stages(input: x, y1: y1, y2: y2, output: output)
                        stages[channel] = s
                        samples[index] = Float(tanh(output * drive))
                    }
                }
            }
        }
    }
}
