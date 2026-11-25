//
//  Mixer.swift
//  NucleantDSP
//

import AudioProtocols

/// Several processors side by side on the same sound: each is handed the
/// buffer as it came, and what they leave is added together, each at its
/// own level.
///
/// Inputs that make sound (oscillators) are mixed; inputs that change it
/// (filters, effects) run in parallel on the same signal.
///
///     var oscillators = Mixer([
///         Oscillator(.sawtooth, frequency: 110),
///         Oscillator(.sawtooth, frequency: 110.64),  // 10 cents up
///         Oscillator(.square, frequency: 55),        // an octave down
///     ], levels: [0.4, 0.4, 0.3])
///
///     oscillators.inputs[2].level = 0.5
///     oscillators.inputs[1].source.frequency = 111
///
/// A change of level is spread over the next buffer, so it does not click.
public struct Mixer<Source: AudioProcessor>: AudioProcessor {
    /// One processor in the mix, and how loud it is in it.
    public struct Input: Sendable {
        public var source: Source
        /// The factor what it leaves is added at: 1 as it is, 0 not at all.
        public var level: Float
        /// The level the last buffer ended at.
        fileprivate var reached: Float

        public init(_ source: Source, level: Float = 1) {
            self.source = source
            self.level = level
            self.reached = level
        }
    }

    public var inputs: [Input]

    /// Two halves: the sum of the inputs so far, and the input being
    /// rendered. A buffer longer than a half is mixed a half at a time, so
    /// nothing is allocated on the audio thread.
    private var scratch = ContiguousArray<Float>(repeating: 0, count: 2 * Mixer.chunk)

    /// Samples mixed at a time: 2048 frames of stereo.
    static var chunk: Int { 4_096 }

    public init(_ inputs: [Input]) {
        self.inputs = inputs
    }

    /// `sources`, each at the level at its place in `levels`, or 1 past its
    /// end.
    public init(_ sources: [Source], levels: [Float] = []) {
        self.inputs = sources.indices.map { Input(sources[$0], level: $0 < levels.count ? levels[$0] : 1) }
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let frames = buffer.count / channels
        let chunkFrames = Mixer.chunk / channels
        guard frames > 0, chunkFrames > 0 else { return }
        var start = 0
        while start < frames {
            let count = min(chunkFrames, frames - start)
            mix(into: &buffer, from: start * channels, frames: count, channels: channels, sampleRate: sampleRate)
            start += count
        }
        for index in inputs.indices { inputs[index].reached = inputs[index].level }
    }

    /// The inputs over `frames` frames of `buffer` from sample `offset`.
    private mutating func mix(
        into buffer: inout MutableSpan<Float>, from offset: Int, frames: Int, channels: Int, sampleRate: Double
    ) {
        let samples = frames * channels
        let chunk = Mixer.chunk
        scratch.withUnsafeMutableBufferPointer { scratch in
            for index in 0..<samples { scratch[index] = 0 }
            for input in inputs.indices {
                for index in 0..<samples { scratch[chunk + index] = buffer[offset + index] }
                var part = UnsafeMutableBufferPointer(rebasing: scratch[chunk..<(chunk + samples)]).mutableSpan
                inputs[input].source.process(into: &part, channels: channels, sampleRate: sampleRate)

                // The level goes from where the last buffer left it to its
                // own over the whole buffer, this part of it included.
                let from = inputs[input].reached
                let to = inputs[input].level
                let total = Float(buffer.count / channels)
                let first = Float(offset / channels)
                for frame in 0..<frames {
                    let level = from == to ? to : from + (to - from) * (first + Float(frame + 1)) / total
                    for channel in 0..<channels {
                        let index = frame * channels + channel
                        scratch[index] += level * scratch[chunk + index]
                    }
                }
            }
            for index in 0..<samples { buffer[offset + index] = scratch[index] }
        }
    }
}
