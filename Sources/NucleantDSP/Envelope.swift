//
//  Envelope.swift
//  NucleantDSP
//

import AudioProtocols
import Foundation

/// An ADSR envelope, applied to the buffer: every sample is multiplied by
/// the envelope's level. `open()` starts a note: the level rises to 1 over
/// `attack`, falls toward `sustain` over `decay`, and holds there. `close()`
/// ends it: the level falls to 0 over `release`.
///
///     var voice = Oscillator(.sawtooth, frequency: 220)
///         .then(Envelope(attack: 0.01, decay: 0.2, sustain: 0.6, release: 0.4))
///     voice.second.open()
///
/// Opened again before the release has finished, it rises from the level it
/// is at, so a note played again does not click.
public struct Envelope: AudioProcessor {
    /// Seconds from 0 to 1, in a straight line.
    public var attack: Double
    /// Seconds from 1 to `sustain`: an exponential fall, within 1% of it by
    /// then.
    public var decay: Double
    /// 0…1: the level held while the note is open.
    public var sustain: Float
    /// Seconds from wherever the level is to 0, like `decay`.
    public var release: Double

    /// Where the envelope is, from one buffer to the next.
    public enum Stage: Sendable {
        case idle, attack, decay, sustain, release
    }

    public private(set) var stage: Stage = .idle
    /// The level the last sample was multiplied by.
    public private(set) var level: Float = 0

    /// Whether the envelope still makes sound: not idle. A note's voice is
    /// free again once this is false.
    public var isActive: Bool { stage != .idle }

    public init(attack: Double = 0.01, decay: Double = 0.1, sustain: Float = 0.8, release: Double = 0.3) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }

    /// Starts the attack, from the level the envelope is at.
    public mutating func open() {
        stage = .attack
    }

    /// Starts the release, unless the envelope is already silent.
    public mutating func close() {
        if stage != .idle { stage = .release }
    }

    /// Silent at once, the note cut off.
    public mutating func reset() {
        stage = .idle
        level = 0
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let frames = buffer.count / channels
        // Per sample: the attack's step, and what the decay and release keep
        // of the distance to their target (within 1% after their time).
        let attackStep = Float(1 / max(attack * sampleRate, 1))
        let decayKeep = Envelope.keep(decay, sampleRate)
        let releaseKeep = Envelope.keep(release, sampleRate)
        let sustain = min(max(self.sustain, 0), 1)

        for frame in 0..<frames {
            switch stage {
            case .idle:
                level = 0
            case .attack:
                level += attackStep
                if level >= 1 {
                    level = 1
                    stage = .decay
                }
            case .decay:
                level = sustain + (level - sustain) * decayKeep
                if abs(level - sustain) < 1e-4 {
                    level = sustain
                    stage = .sustain
                }
            case .sustain:
                level = sustain
            case .release:
                level *= releaseKeep
                if level < 1e-4 {
                    level = 0
                    stage = .idle
                }
            }
            for channel in 0..<channels {
                buffer[frame * channels + channel] *= level
            }
        }
    }

    /// The factor that leaves 1% of a distance after `seconds`. In Double,
    /// where every platform has its math functions.
    private static func keep(_ seconds: Double, _ sampleRate: Double) -> Float {
        Float(exp(log(0.01) / max(seconds * sampleRate, 1)))
    }
}
