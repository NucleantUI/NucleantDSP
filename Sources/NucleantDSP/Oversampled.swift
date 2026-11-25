//
//  Oversampled.swift
//  NucleantDSP
//

import AudioProtocols

/// A processor run at a multiple of the output's rate: the buffer is
/// upsampled, handed to `processor` at the higher rate, and brought back
/// down. What the processor makes above the output's Nyquist frequency —
/// the harmonics a waveshaper or a saturating filter adds — is filtered out
/// before the rate comes down, instead of folding back as tones of its own.
///
///     var drive = Wavefolder(level: 0.8).oversampled(4)
///     var voice = Oscillator(.sawtooth, frequency: 110)
///         .then(SoftSaturation(drive: 8).oversampled())
///
/// Each doubling is a half-band low-pass of two allpass chains (Halfband):
/// flat to 0.48 of the lower rate and 104 dB down from 0.52 of it. It
/// delays the signal by a few samples, and works a buffer through in parts,
/// so nothing is allocated on the audio thread once the channel count is
/// known.
public struct Oversampled<Processor: AudioProcessor>: AudioProcessor {
    /// Run at `factor` times the output's rate: stays reachable to change
    /// while it plays.
    public var processor: Processor
    /// 2, 4, 8 or 16: how many times the output's rate `processor` runs at.
    public let factor: Int

    private let doublings: Int
    private var up: [Halfband] = []
    private var down: [Halfband] = []
    /// Two buffers of `Oversampled.chunk` frames at the highest rate, the
    /// rate doubled from one into the other.
    private var scratch = ContiguousArray<Float>()
    private var channels = 0

    /// Frames of the output's rate worked through at a time.
    static var chunk: Int { 256 }

    /// `factor` is taken to 2, 4, 8 or 16: the nearest at or above it.
    public init(_ processor: Processor, factor: Int = 2) {
        self.processor = processor
        var doublings = 1
        while doublings < 4, 1 << doublings < factor { doublings += 1 }
        self.doublings = doublings
        self.factor = 1 << doublings
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if self.channels != channels {
            self.channels = channels
            up = (0..<doublings).map { _ in Halfband(channels: channels) }
            down = (0..<doublings).map { _ in Halfband(channels: channels) }
            scratch = ContiguousArray(repeating: 0, count: 2 * Oversampled.chunk * factor * channels)
        }
        let frames = buffer.count / channels
        var start = 0
        while start < frames {
            let count = min(Oversampled.chunk, frames - start)
            processChunk(&buffer, from: start, frames: count, channels: channels, sampleRate: sampleRate)
            start += count
        }
    }

    private mutating func processChunk(
        _ buffer: inout MutableSpan<Float>, from start: Int, frames: Int, channels: Int, sampleRate: Double
    ) {
        let half = Oversampled.chunk * factor * channels
        let doublings = doublings
        let factor = factor
        scratch.withUnsafeMutableBufferPointer { scratch in
            guard let base = scratch.baseAddress else { return }
            // The two halves, by index: no array of them, made on the audio
            // thread.
            func halves(_ index: Int) -> UnsafeMutablePointer<Float> { index == 0 ? base : base + half }
            for index in 0..<(frames * channels) { base[index] = buffer[start * channels + index] }

            // Up, one doubling at a time, from one half into the other.
            var current = 0
            var length = frames
            for stage in 0..<doublings {
                up[stage].upsample(halves(current), into: halves(1 - current), frames: length)
                current = 1 - current
                length *= 2
            }

            let samples = UnsafeMutableBufferPointer(start: halves(current), count: length * channels)
            var span = samples.mutableSpan
            processor.process(into: &span, channels: channels, sampleRate: sampleRate * Double(factor))

            // And down again, each halving in place.
            for stage in stride(from: doublings - 1, through: 0, by: -1) {
                length /= 2
                down[stage].downsample(halves(current), into: halves(current), frames: length)
            }
            for index in 0..<(frames * channels) { buffer[start * channels + index] = halves(current)[index] }
        }
    }
}

extension AudioProcessor {
    /// This processor run at `factor` times the output's rate, and brought
    /// back down: 2, 4, 8 or 16.
    public func oversampled(_ factor: Int = 2) -> Oversampled<Self> {
        Oversampled(self, factor: factor)
    }
}
