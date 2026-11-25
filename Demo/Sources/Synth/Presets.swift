//
//  Presets.swift
//  Synth
//

import NucleantDSP

/// Starting points, each a whole set of settings.
enum Preset: CaseIterable, Identifiable, Sendable {
    case classic, bass, lead, pad, pluck, bells, crushed

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .bass: "Bass"
        case .lead: "Lead"
        case .pad: "Pad"
        case .pluck: "Pluck"
        case .bells: "Bells"
        case .crushed: "Crushed"
        }
    }

    var settings: SynthSettings {
        var s = SynthSettings()
        switch self {
        case .classic:
            break
        case .bass:
            s.oscillators = [
                OscillatorSettings(waveform: .square, level: 0.8),
                OscillatorSettings(waveform: .sawtooth, cents: -6, level: 0.5),
                OscillatorSettings(waveform: .sine, semitones: -12, level: 0.6),
            ]
            s.octave = -1
            s.filter = .ladder
            s.cutoff = 260
            s.resonance = 0.55
            s.envelopeAmount = 0.6
            s.attack = 0.003
            s.decay = 0.25
            s.sustain = 0.4
            s.release = 0.15
            s.drive = .clipper
            s.driveAmount = 0.4
            s.delayMix = 0
            s.reverbMix = 0.08
        case .lead:
            s.oscillators = [
                OscillatorSettings(waveform: .sawtooth, level: 0.8),
                OscillatorSettings(waveform: .sawtooth, cents: 9, level: 0.7),
                OscillatorSettings(waveform: .square, semitones: 12, level: 0.25),
            ]
            s.filter = .lowPass
            s.cutoff = 1_800
            s.resonance = 0.45
            s.envelopeAmount = 0.3
            s.attack = 0.02
            s.decay = 0.4
            s.sustain = 0.75
            s.release = 0.3
            s.drive = .saturation
            s.driveAmount = 0.5
            s.delayTime = 0.375
            s.delayFeedback = 0.45
            s.delayMix = 0.3
            s.reverbMix = 0.2
        case .pad:
            s.oscillators = [
                OscillatorSettings(waveform: .triangle, level: 0.7),
                OscillatorSettings(waveform: .sawtooth, cents: -12, level: 0.35),
                OscillatorSettings(waveform: .sawtooth, cents: 12, level: 0.35),
            ]
            s.filter = .ladder
            s.cutoff = 700
            s.resonance = 0.2
            s.envelopeAmount = 0.35
            s.attack = 0.9
            s.decay = 1.2
            s.sustain = 0.8
            s.release = 2.2
            s.drive = .off
            s.delayMix = 0.15
            s.reverbSize = 0.9
            s.reverbDamping = 0.3
            s.reverbMix = 0.5
        case .pluck:
            s.oscillators = [
                OscillatorSettings(waveform: .sawtooth, level: 0.8),
                OscillatorSettings(waveform: .square, cents: 5, level: 0.4),
                OscillatorSettings(waveform: .sine, semitones: -12, level: 0),
            ]
            s.filter = .lowPass
            s.cutoff = 300
            s.resonance = 0.3
            s.envelopeAmount = 0.8
            s.attack = 0.002
            s.decay = 0.3
            s.sustain = 0
            s.release = 0.3
            s.drive = .saturation
            s.driveAmount = 0.2
            s.delayTime = 0.25
            s.delayFeedback = 0.4
            s.delayMix = 0.25
            s.reverbMix = 0.25
        case .bells:
            // The second at 2.76 times the first's frequency (17.59
            // semitones up), as a bell's partials are.
            s.oscillators = [
                OscillatorSettings(waveform: .sine, level: 0.8),
                OscillatorSettings(waveform: .sine, semitones: 18, cents: -41, level: 0.35),
                OscillatorSettings(waveform: .triangle, semitones: 24, level: 0.15),
            ]
            s.octave = 1
            s.filter = .bandPass
            s.cutoff = 2_400
            s.resonance = 0.6
            s.envelopeAmount = 0
            s.attack = 0.002
            s.decay = 1.5
            s.sustain = 0
            s.release = 1.5
            s.drive = .folder
            s.driveAmount = 0.35
            s.delayTime = 0.5
            s.delayFeedback = 0.3
            s.delayMix = 0.2
            s.reverbSize = 0.8
            s.reverbMix = 0.4
        case .crushed:
            s.oscillators = [
                OscillatorSettings(waveform: .square, level: 0.8),
                OscillatorSettings(waveform: .square, semitones: 7, level: 0.5),
                OscillatorSettings(waveform: .sawtooth, semitones: -12, level: 0.3),
            ]
            s.filter = .highPass
            s.cutoff = 150
            s.resonance = 0.2
            s.envelopeAmount = 0
            s.attack = 0.005
            s.decay = 0.2
            s.sustain = 0.7
            s.release = 0.2
            s.drive = .crusher
            s.driveAmount = 0.55
            s.delayMix = 0.1
            s.reverbMix = 0.1
        }
        return s
    }
}
