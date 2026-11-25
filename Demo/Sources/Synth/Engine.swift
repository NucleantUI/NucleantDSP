//
//  Engine.swift
//  Synth
//
//  The sound: eight voices, each three oscillators mixed, through a filter
//  and an envelope; the voices summed, then through a drive, an EQ, a delay
//  and a reverb, and a low cut. Every part is one of NucleantDSP's
//  processors; this file only wires them together.
//  It runs on the audio thread, inside NucleantAudio's `AudioPlayer`.
//

import Foundation
import NucleantDSP

/// What one of a voice's oscillators plays: NucleantDSP's `Oscillator`
/// waveforms, a `PulseOscillator` or a `Supersaw`.
enum Wave: CaseIterable, Sendable {
    case sine, sawtooth, square, triangle, pulse, supersaw

    var name: String {
        switch self {
        case .sine: "Sin"
        case .sawtooth: "Saw"
        case .square: "Sqr"
        case .triangle: "Tri"
        case .pulse: "Pls"
        case .supersaw: "Sup"
        }
    }

    /// Whether the oscillator's Shape knob does anything for it.
    var isShaped: Bool { self == .pulse || self == .supersaw }
}

/// One of a voice's oscillators: its wave, how far it is tuned from the
/// note, how loud it is in the voice's mix, and its shape.
struct OscillatorSettings: Sendable, Equatable {
    var waveform: Wave = .sawtooth
    /// Semitones up or down from the note, −24…24.
    var semitones = 0
    /// Cents up or down from that, −50…50: a fine tune.
    var cents: Float = 0
    /// 0…1.
    var level: Float = 0
    /// 0…1. The pulse: from a square at 0 to a 5% pulse at 1. The
    /// supersaw: its detune, and with it its mix.
    var shape: Float = 0.5
}

/// An envelope's four stages: times in seconds, the sustain 0…1.
struct EnvelopeSettings: Sendable, Equatable {
    var attack: Double
    var decay: Double
    var sustain: Float
    var release: Double
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
    /// 0…1, mapped onto each filter's own range, or its order or ripple.
    var resonance: Float = 0.35
    /// 0…1: how far the filter envelope opens the filter, up to five
    /// octaves.
    var envelopeAmount: Float = 0.5

    /// How the filter opens and closes over a note.
    var filterEnvelope = EnvelopeSettings(attack: 0.005, decay: 0.4, sustain: 0.3, release: 0.4)
    /// How loud a note is over its life.
    var amplitude = EnvelopeSettings(attack: 0.01, decay: 0.35, sustain: 0.6, release: 0.4)

    var drive: DriveKind = .saturation
    /// 0…1.
    var driveAmount: Float = 0.3

    /// The three bands, in decibels, −12…12.
    var eqLow: Float = 0
    var eqMid: Float = 0
    var eqHigh: Float = 0
    /// The tilt, in decibels, −6…6.
    var tilt: Float = 0

    var delayTime = 0.3
    var delayFeedback: Float = 0.35
    var delayMix: Float = 0.2

    var reverbSize: Float = 0.6
    var reverbDamping: Float = 0.5
    var reverbMix: Float = 0.25

    /// In hertz: everything below is cut, at the very end.
    var lowCut: Float = 20
    var volume: Float = 0.7
}

/// The filter every voice goes through.
enum FilterKind: CaseIterable, Identifiable, Sendable {
    case lowPass, highPass, bandPass, notch, ladder
    case moog, threePole, formant
    case butterworth, chebyshevI, chebyshevII, elliptic, bessel, legendre

    var id: Self { self }

    var name: String {
        switch self {
        case .lowPass: "SVF Low-pass"
        case .highPass: "SVF High-pass"
        case .bandPass: "SVF Band-pass"
        case .notch: "SVF Notch"
        case .ladder: "Vult Ladder"
        case .moog: "Moog Ladder"
        case .threePole: "3-Pole 18 dB"
        case .formant: "Formant"
        case .butterworth: "Butterworth"
        case .chebyshevI: "Chebyshev I"
        case .chebyshevII: "Chebyshev II"
        case .elliptic: "Elliptic"
        case .bessel: "Bessel"
        case .legendre: "Legendre"
        }
    }

    var mode: StateVariableFilter.Mode? {
        switch self {
        case .lowPass: .lowPass
        case .highPass: .highPass
        case .bandPass: .bandPass
        case .notch: .notch
        default: nil
        }
    }

    /// What the Res knob sets for this filter.
    var resonanceName: String {
        switch self {
        case .butterworth, .bessel, .legendre: "Order"
        case .chebyshevI, .elliptic: "Ripple"
        case .chebyshevII: "Stop"
        default: "Res"
        }
    }

    /// Whether the Res knob does anything for it: the formant filter has
    /// nothing to set.
    var hasResonance: Bool { self != .formant }

    /// The designed filters' order from the Res knob: 2 to 8 poles.
    static func order(_ resonance: Float) -> Int { 2 + Int((resonance * 6).rounded()) }
    /// Chebyshev I's and the elliptic's ripple: 0.1 to 6 dB.
    static func ripple(_ resonance: Float) -> Float { 0.1 + resonance * 5.9 }
    /// Chebyshev II's stop band: 60 dB down to 15 dB down.
    static func stopBand(_ resonance: Float) -> Float { 60 - resonance * 45 }

    /// The Res knob's value, as this filter reads it.
    func resonanceText(_ resonance: Float) -> String {
        switch self {
        case .butterworth, .bessel, .legendre: "\(FilterKind.order(resonance)) poles"
        case .chebyshevI, .elliptic: String(format: "%.1f dB", FilterKind.ripple(resonance))
        case .chebyshevII: String(format: "-%.0f dB", FilterKind.stopBand(resonance))
        case .formant: "–"
        default: String(format: "%.0f%%", resonance * 100)
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

/// One oscillator of a voice: whichever of NucleantDSP's generators its
/// wave calls for, so three of them can share a `Mixer`.
struct VoiceOscillator: AudioProcessor {
    var wave: Wave = .sawtooth
    var frequency: Float = 440
    var shape: Float = 0.5

    private var basic = Oscillator(.sawtooth, frequency: 440, amplitude: 0.2)
    private var pulse = PulseOscillator(frequency: 440, amplitude: 0.2)
    private var supersaw = Supersaw(frequency: 440, amplitude: 0.2)

    mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        switch wave {
        case .sine, .sawtooth, .square, .triangle:
            basic.waveform = switch wave {
            case .sine: .sine
            case .square: .square
            case .triangle: .triangle
            default: .sawtooth
            }
            basic.frequency = frequency
            basic.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .pulse:
            pulse.frequency = frequency
            pulse.width = 0.5 - 0.45 * shape
            pulse.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .supersaw:
            supersaw.frequency = frequency
            supersaw.detune = shape
            supersaw.mix = 0.4 + 0.6 * shape
            supersaw.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        }
    }
}

/// One note: three oscillators mixed, a filter its own envelope opens, and an
/// envelope for its level, rendered in mono.
struct Voice: Sendable {
    /// The MIDI note it plays, or nil while free.
    var note: Int?
    /// When it was started, to steal the oldest when every voice is busy.
    var startedAt = 0

    /// Each made on its own, so none shares another's buffers.
    var oscillators = Mixer((0..<3).map { _ in VoiceOscillator() })
    var stateVariable = StateVariableFilter(cutoff: 1_000)
    var ladder = LadderFilter(cutoff: 1_000)
    var moog = MoogLadder(cutoff: 1_000, drive: 1.5)
    var threePole = ThreePoleLowPass(cutoff: 1_000, distortion: 0.3)
    var formant = FormantFilter(.a)
    var butterworth = Butterworth(.lowPass, frequency: 1_000)
    var chebyshevI = ChebyshevI(.lowPass, frequency: 1_000)
    var chebyshevII = ChebyshevII(.lowPass, order: 6, frequency: 1_000)
    var elliptic = Elliptic(.lowPass, frequency: 1_000)
    var bessel = Bessel(.lowPass, frequency: 1_000)
    var legendre = Legendre(.lowPass, frequency: 1_000)
    /// Its level over the note: applied to the sound.
    var amplitude = Envelope()
    /// How far the filter is open over the note: run over a block of ones,
    /// so what it leaves is its own curve, and its level is read from it.
    var filterEnvelope = Envelope()
    private var contour = ContiguousArray<Float>(repeating: 0, count: Voice.block)

    /// Samples rendered between two updates of the filter's cutoff from its
    /// envelope: short enough that a fast attack still sweeps.
    static let block = 64

    mutating func open() {
        amplitude.open()
        filterEnvelope.open()
    }

    mutating func close() {
        amplitude.close()
        filterEnvelope.close()
    }

    mutating func reset() {
        amplitude.reset()
        filterEnvelope.reset()
    }

    mutating func render(into samples: UnsafeMutableBufferPointer<Float>, settings: SynthSettings, sampleRate: Double) {
        guard let note else { return }
        // Each oscillator at the note, moved by its own tuning.
        let pitch = Double(note + 12 * settings.octave - 69)
        for index in oscillators.inputs.indices where index < settings.oscillators.count {
            let tuning = settings.oscillators[index]
            let semitones = pitch + Double(tuning.semitones) + Double(tuning.cents) / 100
            oscillators.inputs[index].source.wave = tuning.waveform
            oscillators.inputs[index].source.frequency = Float(440 * pow(2, semitones / 12))
            oscillators.inputs[index].source.shape = tuning.shape
            oscillators.inputs[index].level = tuning.level
        }
        Voice.set(&amplitude, to: settings.amplitude)
        Voice.set(&filterEnvelope, to: settings.filterEnvelope)

        var start = 0
        while start < samples.count {
            let end = min(start + Voice.block, samples.count)
            let pointer = UnsafeMutableBufferPointer(rebasing: samples[start..<end])
            var block = pointer.mutableSpan
            // The filter envelope opens the filter by up to five octaves.
            let frames = end - start
            contour.withUnsafeMutableBufferPointer { contour in
                for index in 0..<frames { contour[index] = 1 }
                var ones = UnsafeMutableBufferPointer(rebasing: contour[0..<frames]).mutableSpan
                filterEnvelope.process(into: &ones, channels: 1, sampleRate: sampleRate)
            }
            let opening = pow(2, 5 * Double(settings.envelopeAmount) * Double(filterEnvelope.level))
            let cutoff = Float(min(Double(settings.cutoff) * opening, 18_000))

            oscillators.process(into: &block, channels: 1, sampleRate: sampleRate)
            filter(&block, cutoff: cutoff, settings: settings, sampleRate: sampleRate)
            amplitude.process(into: &block, channels: 1, sampleRate: sampleRate)
            start = end
        }
        if !amplitude.isActive { self.note = nil }
    }

    /// The block through the chosen filter, at `cutoff`.
    private mutating func filter(_ block: inout MutableSpan<Float>, cutoff: Float, settings: SynthSettings, sampleRate: Double) {
        let resonance = settings.resonance
        switch settings.filter {
        case .lowPass, .highPass, .bandPass, .notch:
            stateVariable.mode = settings.filter.mode ?? .lowPass
            stateVariable.cutoff = cutoff
            stateVariable.resonance = resonance * 4
            stateVariable.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .ladder:
            ladder.cutoff = cutoff
            ladder.resonance = resonance * 0.95
            ladder.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .moog:
            moog.cutoff = cutoff
            moog.resonance = resonance
            moog.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .threePole:
            threePole.cutoff = cutoff
            threePole.resonance = resonance * 0.9
            threePole.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .formant:
            // The cutoff's place on its knob, 40 Hz to 16 kHz, moves the
            // vowel from A to U: the envelope sweeps through them.
            let position = log(Double(max(cutoff, 40)) / 40) / log(16_000.0 / 40)
            formant.vowel = Float(min(max(position, 0), 1) * 4)
            formant.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .butterworth:
            butterworth.frequency = cutoff
            butterworth.order = FilterKind.order(resonance)
            butterworth.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .chebyshevI:
            chebyshevI.frequency = cutoff
            chebyshevI.ripple = FilterKind.ripple(resonance)
            chebyshevI.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .chebyshevII:
            chebyshevII.frequency = cutoff
            chebyshevII.stopBand = FilterKind.stopBand(resonance)
            chebyshevII.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .elliptic:
            elliptic.frequency = cutoff
            elliptic.ripple = FilterKind.ripple(resonance)
            elliptic.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .bessel:
            bessel.frequency = cutoff
            bessel.order = FilterKind.order(resonance)
            bessel.process(into: &block, channels: 1, sampleRate: sampleRate)
        case .legendre:
            legendre.frequency = cutoff
            legendre.order = FilterKind.order(resonance)
            legendre.process(into: &block, channels: 1, sampleRate: sampleRate)
        }
    }

    private static func set(_ envelope: inout Envelope, to settings: EnvelopeSettings) {
        envelope.attack = settings.attack
        envelope.decay = settings.decay
        envelope.sustain = settings.sustain
        envelope.release = settings.release
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

    /// The shapers at four times the rate, so the harmonics they add above
    /// what is heard are filtered out instead of folding back.
    private var saturation = SoftSaturation().oversampled(4)
    private var clipper = CubicClipper().oversampled(4)
    private var folder = Wavefolder(level: 0).oversampled(4)
    private var crusher = Bitcrusher(amount: 0).oversampled(4)
    /// What a shaper leaves off-centre, taken away.
    private var dcBlocker = DCBlocker()
    private var equalizer = ThreeBandEqualizer()
    private var tilt = TiltEqualizer(frequency: 800)
    private var delay = Delay(time: 0.3, maximumTime: 1.5)
    private var reverb = Reverb()
    private var lowCut = LinkwitzRiley(.highPass, frequency: 20)
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
            voices[index].reset()
        }
        voices[index].note = note
        voices[index].startedAt = started
        voices[index].open()
    }

    mutating func noteOff(_ note: Int) {
        for index in voices.indices where voices[index].note == note {
            voices[index].close()
        }
    }

    mutating func allNotesOff() {
        for index in voices.indices { voices[index].close() }
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
            saturation.processor.drive = 1 + amount * 15
            saturation.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .clipper:
            clipper.processor.drive = 1 + amount * 7
            clipper.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .folder:
            folder.processor.level = amount
            folder.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        case .crusher:
            crusher.processor.amount = amount
            crusher.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        }
        dcBlocker.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        equalizer.low = settings.eqLow
        equalizer.mid = settings.eqMid
        equalizer.high = settings.eqHigh
        equalizer.process(into: &buffer, channels: channels, sampleRate: sampleRate)
        tilt.decibels = settings.tilt
        tilt.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        delay.time = settings.delayTime
        delay.feedback = settings.delayFeedback
        delay.mix = settings.delayMix
        delay.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        reverb.roomSize = settings.reverbSize
        reverb.damping = settings.reverbDamping
        reverb.mix = settings.reverbMix
        reverb.process(into: &buffer, channels: channels, sampleRate: sampleRate)

        lowCut.frequency = settings.lowCut
        lowCut.process(into: &buffer, channels: channels, sampleRate: sampleRate)
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
