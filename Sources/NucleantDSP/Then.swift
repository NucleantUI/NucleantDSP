//
//  Then.swift
//  NucleantDSP
//

import AudioProtocols

/// Two processors one after the other on the same buffer: `first` fills or
/// changes it, then `second` changes what `first` left.
///
///     let voice = Oscillator(.sawtooth, frequency: 110)
///         .then(LadderFilter(cutoff: 800, resonance: 0.4))
///         .then(Gain(decibels: -6))
///
/// Both are stored as they are, so each stays reachable to change while it
/// plays: `voice.first.second.cutoff = 1200`.
public struct Then<First: AudioProcessor, Second: AudioProcessor>: AudioProcessor {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        first.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        second.process(into: &buffer, channels: channels, sampleRate: sampleRate)
    }
}

extension AudioProcessor {
    /// This processor, then `next` on what it leaves in the buffer.
    public func then<Next: AudioProcessor>(_ next: Next) -> Then<Self, Next> {
        Then(self, next)
    }
}
