//
//  LadderFilter.swift
//  NucleantDSP
//

import AudioProtocols
import CNucleantDSP

/// Vult's ladder filter (Vult/filters/ladder.vult): four one-pole stages
/// with a saturating stage in each and feedback around them, solved with
/// Heun's method. A four-pole low-pass that self-oscillates as `resonance`
/// nears 1.
///
/// Each stage clips at ±2/3, so it colours a loud input: keep the input
/// within about ±0.5 for it to stay clean.
public struct LadderFilter: AudioProcessor {
    /// In hertz, about 33 Hz to 20 kHz: the range ladder.vult tunes over.
    public var cutoff: Float
    /// 0…1: the feedback around the stages.
    public var resonance: Float

    private var state = NativeState(copy: ndsp_ladder_copy, destroy: ndsp_ladder_destroy)

    public init(cutoff: Float, resonance: Float = 0) {
        self.cutoff = cutoff
        self.resonance = resonance
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard let filter = state.pointer(channels: channels, make: { ndsp_ladder_create(Int32(channels)) }) else { return }
        let cut = min(max(vultCV(frequency: cutoff, sampleRate: sampleRate), 0), 1)
        let resonance = min(max(resonance, 0), 1)
        buffer.withFrames(channels: channels) { samples, frames in
            ndsp_ladder_process(filter, samples, frames, cut, resonance)
        }
    }
}
