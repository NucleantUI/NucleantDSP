//
//  Presets.swift
//  Synth
//

import NucleantDSP

/// Starting points, each a whole set of settings.
enum Preset: CaseIterable, Identifiable, Sendable {
    case classic, bass, lead, pad, pluck, bells, crushed, trance, acid, vowels

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
        case .trance: "Trance"
        case .acid: "Acid"
        case .vowels: "Vowels"
        }
    }

    var settings: SynthSettings {
        var s = SynthSettings()
        switch self {
        case .classic:
            break
        case .bass:
            s.filterEnvelope = EnvelopeSettings(attack: 0.002, decay: 0.18, sustain: 0.1, release: 0.15)
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
            s.amplitude.attack = 0.003
            s.amplitude.decay = 0.25
            s.amplitude.sustain = 0.4
            s.amplitude.release = 0.15
            s.drive = .clipper
            s.driveAmount = 0.4
            s.delayMix = 0
            s.reverbMix = 0.08
        case .lead:
            s.filterEnvelope = EnvelopeSettings(attack: 0.02, decay: 0.5, sustain: 0.5, release: 0.3)
            s.oscillators = [
                OscillatorSettings(waveform: .sawtooth, level: 0.8),
                OscillatorSettings(waveform: .sawtooth, cents: 9, level: 0.7),
                OscillatorSettings(waveform: .square, semitones: 12, level: 0.25),
            ]
            s.filter = .lowPass
            s.cutoff = 1_800
            s.resonance = 0.45
            s.envelopeAmount = 0.3
            s.amplitude.attack = 0.02
            s.amplitude.decay = 0.4
            s.amplitude.sustain = 0.75
            s.amplitude.release = 0.3
            s.drive = .saturation
            s.driveAmount = 0.5
            s.delayTime = 0.375
            s.delayFeedback = 0.45
            s.delayMix = 0.3
            s.reverbMix = 0.2
        case .pad:
            s.filterEnvelope = EnvelopeSettings(attack: 1.2, decay: 2, sustain: 0.6, release: 2.5)
            s.oscillators = [
                OscillatorSettings(waveform: .triangle, level: 0.7),
                OscillatorSettings(waveform: .sawtooth, cents: -12, level: 0.35),
                OscillatorSettings(waveform: .sawtooth, cents: 12, level: 0.35),
            ]
            s.filter = .ladder
            s.cutoff = 700
            s.resonance = 0.2
            s.envelopeAmount = 0.35
            s.amplitude.attack = 0.9
            s.amplitude.decay = 1.2
            s.amplitude.sustain = 0.8
            s.amplitude.release = 2.2
            s.drive = .off
            s.delayMix = 0.15
            s.reverbSize = 0.9
            s.reverbDamping = 0.3
            s.reverbMix = 0.5
        case .pluck:
            s.filterEnvelope = EnvelopeSettings(attack: 0.001, decay: 0.25, sustain: 0, release: 0.3)
            s.oscillators = [
                OscillatorSettings(waveform: .sawtooth, level: 0.8),
                OscillatorSettings(waveform: .square, cents: 5, level: 0.4),
                OscillatorSettings(waveform: .sine, semitones: -12, level: 0),
            ]
            s.filter = .lowPass
            s.cutoff = 300
            s.resonance = 0.3
            s.envelopeAmount = 0.8
            s.amplitude.attack = 0.002
            s.amplitude.decay = 0.3
            s.amplitude.sustain = 0
            s.amplitude.release = 0.3
            s.drive = .saturation
            s.driveAmount = 0.2
            s.delayTime = 0.25
            s.delayFeedback = 0.4
            s.delayMix = 0.25
            s.reverbMix = 0.25
        case .bells:
            s.filterEnvelope = EnvelopeSettings(attack: 0.002, decay: 1, sustain: 0, release: 1.5)
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
            s.amplitude.attack = 0.002
            s.amplitude.decay = 1.5
            s.amplitude.sustain = 0
            s.amplitude.release = 1.5
            s.drive = .folder
            s.driveAmount = 0.35
            s.delayTime = 0.5
            s.delayFeedback = 0.3
            s.delayMix = 0.2
            s.reverbSize = 0.8
            s.reverbMix = 0.4
        case .crushed:
            s.filterEnvelope = EnvelopeSettings(attack: 0.005, decay: 0.2, sustain: 0.4, release: 0.2)
            s.oscillators = [
                OscillatorSettings(waveform: .square, level: 0.8),
                OscillatorSettings(waveform: .square, semitones: 7, level: 0.5),
                OscillatorSettings(waveform: .sawtooth, semitones: -12, level: 0.3),
            ]
            s.filter = .highPass
            s.cutoff = 150
            s.resonance = 0.2
            s.envelopeAmount = 0
            s.amplitude.attack = 0.005
            s.amplitude.decay = 0.2
            s.amplitude.sustain = 0.7
            s.amplitude.release = 0.2
            s.drive = .crusher
            s.driveAmount = 0.55
            s.delayMix = 0.1
            s.reverbMix = 0.1
        case .trance:
            // Two supersaws an octave apart, through the Moog ladder.
            s.filterEnvelope = EnvelopeSettings(attack: 0.01, decay: 0.6, sustain: 0.6, release: 0.5)
            s.oscillators = [
                OscillatorSettings(waveform: .supersaw, level: 0.8, shape: 0.8),
                OscillatorSettings(waveform: .supersaw, semitones: 12, level: 0.35, shape: 0.7),
                OscillatorSettings(waveform: .sine, semitones: -12, level: 0.3),
            ]
            s.filter = .moog
            s.cutoff = 2_200
            s.resonance = 0.25
            s.envelopeAmount = 0.25
            s.amplitude = EnvelopeSettings(attack: 0.01, decay: 0.4, sustain: 0.8, release: 0.45)
            s.drive = .saturation
            s.driveAmount = 0.2
            s.eqLow = 2
            s.eqHigh = 3
            s.delayTime = 0.375
            s.delayFeedback = 0.4
            s.delayMix = 0.25
            s.reverbSize = 0.85
            s.reverbMix = 0.35
        case .acid:
            // A narrow pulse through the squelching three-pole filter.
            s.filterEnvelope = EnvelopeSettings(attack: 0.002, decay: 0.22, sustain: 0, release: 0.15)
            s.oscillators = [
                OscillatorSettings(waveform: .pulse, level: 0.9, shape: 0.3),
                OscillatorSettings(waveform: .sawtooth, level: 0),
                OscillatorSettings(waveform: .sine, semitones: -12, level: 0),
            ]
            s.octave = -1
            s.filter = .threePole
            s.cutoff = 350
            s.resonance = 0.8
            s.envelopeAmount = 0.7
            s.amplitude = EnvelopeSettings(attack: 0.002, decay: 0.3, sustain: 0.7, release: 0.12)
            s.drive = .clipper
            s.driveAmount = 0.35
            s.delayTime = 0.25
            s.delayFeedback = 0.3
            s.delayMix = 0.15
            s.reverbMix = 0.08
            s.lowCut = 40
        case .vowels:
            // The formant filter, its envelope sweeping it from E toward U.
            s.filterEnvelope = EnvelopeSettings(attack: 0.6, decay: 1.5, sustain: 0.4, release: 1.2)
            s.oscillators = [
                OscillatorSettings(waveform: .sawtooth, level: 0.5),
                OscillatorSettings(waveform: .sawtooth, cents: -9, level: 0.4),
                OscillatorSettings(waveform: .pulse, semitones: -12, level: 0.2, shape: 0.4),
            ]
            s.filter = .formant
            s.cutoff = 300
            s.envelopeAmount = 0.4
            s.amplitude = EnvelopeSettings(attack: 0.25, decay: 1, sustain: 0.85, release: 1.2)
            s.drive = .off
            s.tilt = 1
            s.delayMix = 0.15
            s.reverbSize = 0.8
            s.reverbMix = 0.4
            s.volume = 0.5
        }
        return s
    }
}
