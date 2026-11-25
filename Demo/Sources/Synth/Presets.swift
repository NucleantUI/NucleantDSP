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
            s.waveform = .square
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
            s.waveform = .sawtooth
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
            s.waveform = .triangle
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
            s.waveform = .sawtooth
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
            s.waveform = .sine
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
            s.waveform = .square
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
