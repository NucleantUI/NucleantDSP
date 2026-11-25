//
//  Reverb.swift
//  NucleantDSP
//

import AudioProtocols
import CNucleantDSP

/// Freeverb (reverb.c): a room's reverberation, from eight comb filters and
/// four allpasses for each of a left and a right side. Even channels hear
/// the left side, odd ones the right.
public struct Reverb: AudioProcessor {
    /// 0…1: how long the reverb rings.
    public var roomSize: Float
    /// 0…1: how quickly its high frequencies die away.
    public var damping: Float
    /// 0 the same in every channel … 1 the two sides apart.
    public var width: Float
    /// 0 the input alone … 1 the reverb alone.
    public var mix: Float

    private var state = NativeState(copy: ndsp_reverb_copy, destroy: ndsp_reverb_destroy)

    public init(roomSize: Float = 0.5, damping: Float = 0.5, width: Float = 1, mix: Float = 0.3) {
        self.roomSize = roomSize
        self.damping = damping
        self.width = width
        self.mix = mix
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard let reverb = state.pointer(channels: channels, sampleRate: sampleRate, make: {
            ndsp_reverb_create(Int32(channels), sampleRate)
        }) else { return }
        let roomSize = min(max(roomSize, 0), 1)
        let damping = min(max(damping, 0), 1)
        let width = min(max(width, 0), 1)
        let mix = min(max(mix, 0), 1)
        buffer.withFrames(channels: channels) { samples, frames in
            ndsp_reverb_process(reverb, samples, frames, roomSize, damping, width, mix)
        }
    }
}
