//
//  Delay.swift
//  NucleantDSP
//

import AudioProtocols
import CNucleantDSP

/// An echo: each channel heard again `time` seconds later, and again from
/// there by `feedback` (delay.c).
public struct Delay: AudioProcessor {
    /// In seconds, up to `maximumTime`; between two samples, the delayed
    /// signal is read between them.
    public var time: Double
    /// 0…<1: how much of the echo is fed back to echo again.
    public var feedback: Float
    /// 0 the input alone … 1 the echo alone.
    public var mix: Float
    /// The longest `time` this delay keeps room for.
    public let maximumTime: Double

    private var state = NativeState(copy: ndsp_delay_copy, destroy: ndsp_delay_destroy)

    public init(time: Double, feedback: Float = 0.3, mix: Float = 0.5, maximumTime: Double = 2) {
        self.time = time
        self.feedback = feedback
        self.mix = mix
        self.maximumTime = max(maximumTime, time)
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let maximumFrames = Int((maximumTime * sampleRate).rounded(.up))
        guard let delay = state.pointer(channels: channels, sampleRate: sampleRate, make: {
            ndsp_delay_create(Int32(channels), max(maximumFrames, 1))
        }) else { return }
        let delayFrames = Float(time * sampleRate)
        let feedback = min(max(feedback, 0), 0.999)
        let mix = min(max(mix, 0), 1)
        buffer.withFrames(channels: channels) { samples, frames in
            ndsp_delay_process(delay, samples, frames, delayFrames, feedback, mix)
        }
    }
}
