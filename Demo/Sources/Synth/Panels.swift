//
//  Panels.swift
//  Synth
//
//  A panel per stage of the sound, in the order the sound goes through
//  them: the voice's oscillator, filter and envelope, then the drive, the
//  delay and the reverb, and the volume.
//

import Foundation
import NucleantDSP
import NucleantUI

/// A titled box of controls.
@View
struct Panel<Content: View> {
    let title: String
    let content: Content

    init(_ title: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.label)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
        .cornerRadius(12)
    }
}

/// Every panel, in two rows.
@View
struct Controls {
    @Bindable var model: SynthModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Panel("Oscillator") {
                    Picker(selection: $model.settings.waveform) {
                        Text("Sine").fixedSize().tag(Oscillator.Waveform.sine)
                        Text("Saw").fixedSize().tag(Oscillator.Waveform.sawtooth)
                        Text("Square").fixedSize().tag(Oscillator.Waveform.square)
                        Text("Triangle").fixedSize().tag(Oscillator.Waveform.triangle)
                    }
                    .pickerStyle(.segmented)
                    Picker(selection: $model.settings.octave) {
                        ForEach(-2...2, id: \.self) { octave in
                            Text(octave > 0 ? "+\(octave)" : "\(octave)").fixedSize().tag(octave)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Panel("Filter") {
                    Picker(selection: $model.settings.filter) {
                        ForEach(FilterKind.allCases) { kind in
                            Text(kind.name).fixedSize().tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 4) {
                        Knob(title: "Cutoff", position: model.knob(\.cutoff, .exponential(40...16_000)),
                             text: model.settings.cutoff.hertzText)
                        Knob(title: "Resonance", position: model.knob(\.resonance, .linear(0...1)),
                             text: model.settings.resonance.percentText)
                        Knob(title: "Envelope", position: model.knob(\.envelopeAmount, .linear(0...1)),
                             text: model.settings.envelopeAmount.percentText, tint: Theme.envelope)
                    }
                }
                Panel("Envelope") {
                    HStack(spacing: 4) {
                        Knob(title: "Attack", position: model.knob(\.attack, .exponential(0.001...4)),
                             text: model.settings.attack.secondsText, tint: Theme.envelope)
                        Knob(title: "Decay", position: model.knob(\.decay, .exponential(0.005...4)),
                             text: model.settings.decay.secondsText, tint: Theme.envelope)
                        Knob(title: "Sustain", position: model.knob(\.sustain, .linear(0...1)),
                             text: model.settings.sustain.percentText, tint: Theme.envelope)
                        Knob(title: "Release", position: model.knob(\.release, .exponential(0.005...6)),
                             text: model.settings.release.secondsText, tint: Theme.envelope)
                    }
                }
            }
            HStack(spacing: 12) {
                Panel("Drive") {
                    Picker(selection: $model.settings.drive) {
                        ForEach(DriveKind.allCases) { kind in
                            Text(kind.name).fixedSize().tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    Knob(title: "Amount", position: model.knob(\.driveAmount, .linear(0...1)),
                         text: model.settings.driveAmount.percentText, tint: Theme.drive)
                }
                Panel("Delay") {
                    HStack(spacing: 4) {
                        Knob(title: "Time", position: model.knob(\.delayTime, .exponential(0.02...1.2)),
                             text: model.settings.delayTime.secondsText, tint: Theme.space)
                        Knob(title: "Feedback", position: model.knob(\.delayFeedback, .linear(0...0.9)),
                             text: model.settings.delayFeedback.percentText, tint: Theme.space)
                        Knob(title: "Mix", position: model.knob(\.delayMix, .linear(0...1)),
                             text: model.settings.delayMix.percentText, tint: Theme.space)
                    }
                }
                Panel("Reverb") {
                    HStack(spacing: 4) {
                        Knob(title: "Size", position: model.knob(\.reverbSize, .linear(0...1)),
                             text: model.settings.reverbSize.percentText, tint: Theme.space)
                        Knob(title: "Damping", position: model.knob(\.reverbDamping, .linear(0...1)),
                             text: model.settings.reverbDamping.percentText, tint: Theme.space)
                        Knob(title: "Mix", position: model.knob(\.reverbMix, .linear(0...1)),
                             text: model.settings.reverbMix.percentText, tint: Theme.space)
                    }
                }
                Panel("Output") {
                    Knob(title: "Volume", position: model.knob(\.volume, .linear(0...1)),
                         text: model.settings.volume.percentText)
                }
                .frame(width: 110)
            }
        }
    }
}

extension SynthModel {
    /// A knob's position for the setting at `path`, read and written through
    /// `scale`.
    func knob<Value: BinaryFloatingPoint>(_ path: WritableKeyPath<SynthSettings, Value>, _ scale: KnobScale) -> Binding<Double> {
        Binding(
            get: { scale.position(of: Double(self.settings[keyPath: path])) },
            set: { self.settings[keyPath: path] = Value(scale.value(at: $0)) }
        )
    }
}

// How the knobs show their values.

extension Float {
    var hertzText: String {
        self >= 1_000 ? String(format: "%.1f kHz", self / 1_000) : String(format: "%.0f Hz", self)
    }

    var percentText: String {
        String(format: "%.0f%%", self * 100)
    }
}

extension Double {
    var secondsText: String {
        self >= 1 ? String(format: "%.2f s", self) : String(format: "%.0f ms", self * 1_000)
    }
}
