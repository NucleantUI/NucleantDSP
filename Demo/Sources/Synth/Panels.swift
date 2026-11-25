//
//  Panels.swift
//  Synth
//
//  A panel per stage of the sound, in the order the sound goes through
//  them: the voice's three oscillators, filter and envelope, then the
//  drive, the delay and the reverb, and the volume.
//

import Foundation
import NucleantDSP
import NucleantUI

/// A titled box of controls. A picker that goes with the title (`accessory`)
/// sits on its line, at the right.
@View
struct Panel<Accessory: View, Content: View> {
    let title: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, _viewID: ViewID = #viewID,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .fixedSize()
                Spacer(minLength: 0)
                accessory
            }
            // As tall as a picker, so the knobs line up from panel to panel.
            .frame(minHeight: 32)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
        .cornerRadius(12)
    }
}

@MainActor
extension Panel where Accessory == EmptyView {
    init(_ title: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.init(title, _viewID: _viewID, accessory: { EmptyView() }, content: content)
    }
}

/// One of the voice's oscillators: its waveform, its tuning from the note
/// (semitones, then cents), and its level in the voice's mix.
@View
struct OscillatorPanel {
    let model: SynthModel
    let index: Int

    var body: some View {
        let settings = model.settings.oscillators[index]
        Panel("Osc \(index + 1)") {
            Picker(selection: model.binding(\.oscillators[index].waveform)) {
                Text("Sin").fixedSize().tag(Oscillator.Waveform.sine)
                Text("Saw").fixedSize().tag(Oscillator.Waveform.sawtooth)
                Text("Sqr").fixedSize().tag(Oscillator.Waveform.square)
                Text("Tri").fixedSize().tag(Oscillator.Waveform.triangle)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        } content: {
            HStack(spacing: 4) {
                Knob(title: "Semi", position: model.knob(\.oscillators[index].semitones, -24...24),
                     text: settings.semitones.signedText, bipolar: true)
                Knob(title: "Fine", position: model.knob(\.oscillators[index].cents, .linear(-50...50)),
                     text: settings.cents.centsText, bipolar: true)
                Knob(title: "Level", position: model.knob(\.oscillators[index].level, .linear(0...1)),
                     text: settings.level.percentText)
            }
        }
    }
}

/// Every panel, in three rows: the oscillators; the filter and the
/// envelope; the drive and the effects.
@View
struct Controls {
    @Bindable var model: SynthModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    OscillatorPanel(model: model, index: index)
                }
            }
            HStack(spacing: 12) {
                Panel("Filter") {
                    Picker(selection: $model.settings.filter) {
                        ForEach(FilterKind.allCases) { kind in
                            Text(kind.name).fixedSize().tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                } content: {
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
                    .fixedSize()
                } content: {
                    Knob(title: "Amount", position: model.knob(\.driveAmount, .linear(0...1)),
                         text: model.settings.driveAmount.percentText, tint: Theme.drive)
                }
                // Wide enough for its title and every kind of drive.
                .frame(width: 360)
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
    /// The setting at `path`, for a control to change.
    func binding<Value>(_ path: WritableKeyPath<SynthSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: path] },
            set: { self.settings[keyPath: path] = $0 }
        )
    }

    /// A knob's position for the whole-number setting at `path`, which it
    /// steps through `range` from end to end.
    func knob(_ path: WritableKeyPath<SynthSettings, Int>, _ range: ClosedRange<Int>) -> Binding<Double> {
        let span = Double(range.upperBound - range.lowerBound)
        return Binding(
            get: { Double(self.settings[keyPath: path] - range.lowerBound) / span },
            set: { self.settings[keyPath: path] = range.lowerBound + Int(($0 * span).rounded()) }
        )
    }

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

    var centsText: String {
        abs(self) < 0.5 ? "0 ct" : String(format: "%+.0f ct", self)
    }
}

extension Int {
    var signedText: String {
        self > 0 ? "+\(self)" : "\(self)"
    }
}

extension Double {
    var secondsText: String {
        self >= 1 ? String(format: "%.2f s", self) : String(format: "%.0f ms", self * 1_000)
    }
}
