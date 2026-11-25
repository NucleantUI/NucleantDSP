//
//  StateVariableFilter.swift
//  NucleantDSP
//

import AudioProtocols
import CNucleantDSP

/// Vult's state variable filter (Vult/filters/svf.vult): a two-pole filter
/// whose output is its low-, high- or band-pass, or a notch, softly
/// saturated.
public struct StateVariableFilter: AudioProcessor {
    /// Which of the filter's outputs is heard: svf.vult's `sel`.
    public enum Mode: Int32, Sendable {
        case lowPass = 0
        case highPass = 1
        case bandPass = 2
        case notch = 3
    }

    public var mode: Mode
    /// In hertz, about 33 Hz to 16.7 kHz: the range svf.vult tunes over.
    public var cutoff: Float
    /// 0 and up: the filter's Q is 0.5 + `resonance`, so 0.2071 is a
    /// Butterworth response and larger values ring at the cutoff.
    public var resonance: Float

    private var state = NativeState(copy: ndsp_svf_copy, destroy: ndsp_svf_destroy)

    public init(_ mode: Mode = .lowPass, cutoff: Float, resonance: Float = 0.2071) {
        self.mode = mode
        self.cutoff = cutoff
        self.resonance = resonance
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard let filter = state.pointer(channels: channels, make: { ndsp_svf_create(Int32(channels)) }) else { return }
        let cv = min(max(vultCV(frequency: cutoff, sampleRate: sampleRate), 0), 0.9)
        let q = max(resonance, 0)
        let mode = mode.rawValue
        buffer.withFrames(channels: channels) { samples, frames in
            ndsp_svf_process(filter, samples, frames, cv, q, mode)
        }
    }
}
