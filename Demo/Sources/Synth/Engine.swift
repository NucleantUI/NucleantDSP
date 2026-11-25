//
//  Engine.swift
//  Synth
//
//  The sound: eight voices, each three oscillators mixed, through a filter
//  and an envelope; the voices summed, then through a drive, a delay and a
//  reverb. Every part is one of NucleantDSP's processors; this file only
//  wires them together.
//  It runs on the audio thread, inside NucleantAudio's `AudioPlayer`.
//

import Foundation
import NucleantDSP

/// One of a voice's oscillators: its waveform, how far it is tuned from the
/// note, and how loud it is in the voice's mix.
struct OscillatorSettings: Sendable, Equatable {
    var waveform: Oscillator.Waveform = .sawtooth
    /// Semitones up or down from the note, −24…24.
    var semitones = 0
    /// Cents up or down from that, −50…50: a fine tune.
    var cents: Float = 0
    /// 0…1.
    var level: Float = 0
}

/// What the synth sounds like: everything the panels change.
struct SynthSettings: Sendable, Equatable {
    /// Every voice's three oscillators. The second, a few cents off the
    /// first, beats against it; the third is an octave down.
    var oscillators = [
        OscillatorSettings(waveform: .sawtooth, level: 0.8),
        OscillatorSettings(waveform: .sawtooth, cents: 7, level: 0.6),
        OscillatorSettings(waveform: .square, semitones: -12, level: 0.3),
    ]
    /// Octaves up or down from the keyboard's own.
    var octave = 0

    var filter: FilterKind = .ladder
    /// In hertz, before the envelope opens it further.
    var cutoff: Float = 900
    /// 0…1, mapped onto each filter's own range.
    var resonance: Float = 0.35
    /// 0…1: how far the envelope opens the filter, up to five octaves.
    var envelopeAmount: Float = 0.5

    var attack = 0.01
    var decay = 0.35
    var sustain: Float = 0.6
    var release = 0.4

    var drive: DriveKind = .saturation
    /// 0…1.
    var driveAmount: Float = 0.3

    var delayTime = 0.3
    var delayFeedback: Float = 0.35
    var delayMix: Float = 0.2

    var reverbSize: Float = 0.6
    var reverbDamping: Float = 0.5
    var reverbMix: Float = 0.25

    var volume: Float = 0.7
}

/// The filter every voice goes through: one of the state variable filter's
/// outputs, or the ladder.
enum FilterKind: CaseIterable, Identifiable, Sendable {
    case lowPass, highPass, bandPass, notch, ladder

    var id: Self { self }

    var name: String {
        switch self {
        case .lowPass: "Low"
        case .highPass: "High"
        case .bandPass: "Band"
        case .notch: "Notch"
        case .ladder: "Ladder"
        }
    }

    var mode: StateVariableFilter.Mode? {
        switch self {
        case .lowPass: .lowPass
        case .highPass: .highPass
        case .bandPass: .bandPass
        case .notch: .notch
        case .ladder: nil
        }
    }
}

/// The waveshaper after the voices.
enum DriveKind: CaseIterable, Identifiable, Sendable {
    case off, saturation, clipper, folder, crusher

    var id: Self { self }

    var name: String {
        switch self {
        case .off: "Off"
        case .saturation: "Soft"
        case .clipper: "Clip"
        case .folder: "Fold"
        case .crusher: "Crush"
        }
    }
}

/// One note: three oscillators mixed, a filter and an envelope, rendered in
/// mono.
struct Voice: Sendable {
    /// The MIDI note it plays, or nil while free.
    var note: Int?
    /// When it was started, to steal the oldest when every voice is busy.
    var startedAt = 0

    var oscillators = Mixer([Oscillator](repeating: Oscillator(.sawtooth, frequency: 440, amplitude: 0.2), count: 3))
    var stateVariable = StateVariableFilter(cutoff: 1_000)
    var ladder = LadderFilter(cutoff: 1_000)
    var envelope = Envelope()

    /// Samples rendered between two updates of the filter's cutoff from the
    /// envelope: short enough that a fast attack still sweeps.
    static let block = 64

    mutating func render(into samples: UnsafeMutableBufferPointer<Float>, settings: SynthSettings, sampleRate: Double) {
        guard let note else { return }
        // Each oscillator at the note, moved by its own tuning.
        let pitch = Double(note + 12 * settings.octave - 69)
        for index in oscillators.inputs.indices where index < settings.oscillators.count {
            let tuning = settings.oscillators[index]
            let semitones = pitch + Double(tuning.semitones) + Double(tuning.cents) / 100
            oscillators.inputs[index].source.waveform = tuning.waveform
            oscillators.inputs[index].source.frequency = Float(440 * pow(2, semitones / 12))
            oscillators.inputs[index].level = tuning.level
        }
        envelope.attack = settings.attack
        envelope.decay = settings.decay
        envelope.sustain = settings.sustain
        envelope.release = settings.release

        var start = 0
        while start < samples.count {
            let end = min(start + Voice.block, samples.count)
            let pointer = UnsafeMutableBufferPointer(rebasing: samples[start..<end])
            var block = pointer.mutableSpan
            // The envelope opens the filter by up to five octaves.
            let opening = pow(2, 5 * Double(settings.envelopeAmount) * Double(envelope.level))
            let cutoff = Float(min(Double(settings.cutoff) * opening, 18_000))

            oscillators.process(into: &block, channels: 1, sampleRate: sampleRate)
            if let mode = settings.filter.mode {
                stateVariable.mode = mode
                stateVariable.cutoff = cutoff
                stateVariable.resonance = settings.resonance * 4
                stateVariable.process(into: &block, channels: 1, sampleRate: sampleRate)
            } else {
                ladder.cutoff = cutoff
                ladder.resonance = settings.resonance * 0.95
                ladder.process(into: &block, channels: 1, sampleRate: sampleRate)
            }
            envelope.process(into: &block, channels: 1, sampleRate: sampleRate)
            start = end
        }
        if !envelope.isActive { self.note = nil }
    }
}

/// The whole synth, as one `AudioProcessor`.
struct SynthEngine: AudioProcessor {
    var settings = SynthSettings()

    /// Each made on its own, not copied from one: copies would share their
    /// mixers' buffers until the audio thread wrote to them, and copied
    /// them there.
    private var voices = ContiguousArray((0..<8).map { _ in Voice() })
    private var started = 0
    /// One voice's samples, before they are added into the buffer.
    private var mono: ContiguousArray<Float> = []

    private var saturation = SoftSaturation()
    private var clipper = CubicClipper()
    private var folder = Wavefolder(level: 0)
    private var crusher = Bitcrusher(amount: 0)
    private var delay = Delay(time: 0.3, maximumTime: 1.5)
    private var reverb = Reverb()
    private var output = Gain()

    /// The latest frames of the first channel, oldest first, for the scope:
    /// twice what it shows, so it can start where the wave rises.
    private(set) var scope = [Float](repeating: 0, count: 2_048)

    init(settings: SynthSettings = SynthSettings()) {
        self.settings = settings
    }

    /// How many voices are sounding.
    var activeVoices: Int { voices.reduce(0) { $0 + ($1.note == nil ? 0 : 1) } }

    mutating func noteOn(_ note: Int) {
        started += 1
        // The voice already on this note, else a free one, else the oldest.
        let index = voices.firstIndex { $0.note == note }
            ?? voices.firstIndex { $0.note == nil }
            ?? voices.indices.min { voices[$0].startedAt < voices[$1].startedAt }!
        if voices[index].note != note {
            voices[index].envelope.reset()
        }
        voices[index].note = note
        voices[index].startedAt = started
        voices[index].envelope.open()
    }

    mutating func noteOff(_ note: Int) {
        for index in voices.indices where voices[index].note == note {
            voices[index].envelope.close()
        }
    }

    mutating func allNotesOff() {
        for index in voices.indices { voices[index].envelope.close() }
    }

    mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let frames = buffer.count / channels
        if mono.count < frames { mono = ContiguousArray(repeating: 0, count: frames) }
        for index in 0..<buffer.count { buffer[index] = 0 }

        // Each sounding voice, rendered alone, then added into every channel.
        mono.withUnsafeMutableBufferPointer { mono in
            let samples = UnsafeMutableBufferPointer(rebasing: mono[0..<frames])
            for index in voices.indices where voices[index].note != nil {
                for frame in 0..<frames { samples[frame] = 0 }
                voices[index].render(into: samples, settings: settings, sampleRate: sampleRate)
                for frame in 0..<frames {
                    let sample = samples[frame]
                    for channel in 0..<channels { buffer[frame * channels + channel] += sample }
                }
            }
        }

        let amount = settings.driveAmount
        switch settings.drive {
        case .off:
            break
        case .saturation:
            saturation.drive = 1 + amount * 15
            saturation.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .clipper:
            clipper.drive = 1 + amount * 7
            clipper.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .folder:
            folder.level = amount
            folder.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .crusher:
            crusher.amount = amount
            crusher.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        }

        delay.time = settings.delayTime
        delay.feedback = settings.delayFeedback
        delay.mix = settings.delayMix
        delay.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        reverb.roomSize = settings.reverbSize
        reverb.damping = settings.reverbDamping
        reverb.mix = settings.reverbMix
        reverb.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        output.level = settings.volume
        output.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        // The scope keeps the newest frames: shift the old ones down, and
        // the new ones in behind them.
        let kept = min(frames, scope.count)
        scope.withUnsafeMutableBufferPointer { scope in
            let count = scope.count
            for index in 0..<(count - kept) { scope[index] = scope[index + kept] }
            for index in 0..<kept {
                scope[count - kept + index] = buffer[(frames - kept + index) * channels]
            }
        }
    }
}
