//
//  Panels.swift
//  Synth
//
//  A panel per stage of the sound: the voice's three oscillators (beside
//  the scope, SynthView), and under them, a page at a time in a TabView,
//  its filter and envelopes, the drive, the EQ and the output, and the
//  delay and the reverb.
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

/// The voice's three oscillators, one to a line, so they stack beside the
/// scope rather than spreading across the window. Their knobs are in
/// columns, named once on the title's line, over them.
@View
struct Oscillators {
    let model: SynthModel

    var body: some View {
        Panel("Oscillators") {
            HStack(spacing: 4) {
                ForEach(["Semi", "Fine", "Level", "Shape"], id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: Knob.width)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    OscillatorRow(model: model, index: index)
                }
            }
        }
    }
}

/// One oscillator: its wave, its tuning from the note (semitones, then
/// cents), its level in the voice's mix, and its shape: the pulse's width,
/// or the supersaw's detune and mix, dimmed for the waves without one.
@View
struct OscillatorRow {
    let model: SynthModel
    let index: Int

    var body: some View {
        let settings = model.settings.oscillators[index]
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.label)
                .frame(width: 14)
            Picker(selection: model.binding(\.oscillators[index].waveform)) {
                ForEach(Wave.allCases, id: \.self) { wave in
                    Text(wave.name).fixedSize().tag(wave)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            HStack(spacing: 4) {
                Knob(title: nil, position: model.knob(\.oscillators[index].semitones, -24...24),
                     text: settings.semitones.signedText, bipolar: true)
                Knob(title: nil, position: model.knob(\.oscillators[index].cents, .linear(-50...50)),
                     text: settings.cents.centsText, bipolar: true)
                Knob(title: nil, position: model.knob(\.oscillators[index].level, .linear(0...1)),
                     text: settings.level.percentText)
                Knob(title: nil, position: model.knob(\.oscillators[index].shape, .linear(0...1)),
                     text: settings.shapeText, tint: settings.waveform.isShaped ? Theme.accent : Theme.label)
            }
        }
    }
}

/// The pages of panels under the oscillators, one shown at a time in a
/// `TabView`: the filter and the envelopes; the drive, the EQ and the
/// output; the delay and the reverb.
enum ControlPage: CaseIterable, Hashable, Sendable {
    case filter, tone, space

    var title: String {
        switch self {
        case .filter: "Filter & Envelopes"
        case .tone: "Drive, EQ & Output"
        case .space: "Delay & Reverb"
        }
    }
}

/// One page's panels, in a row. A panel with a picker, and the output's,
/// is as wide as what it holds; the others share what the row has left.
@View
struct Controls {
    @Bindable var model: SynthModel
    let page: ControlPage

    var body: some View {
        switch page {
        case .filter:
            HStack(spacing: 12) {
                Panel("Filter") {
                    // Fourteen of them: a menu.
                    Picker(selection: $model.settings.filter) {
                        ForEach(FilterKind.allCases) { kind in
                            Text(kind.name).tag(kind)
                        }
                    }
                    .frame(width: 150)
                } content: {
                    let kind = model.settings.filter
                    HStack(spacing: 4) {
                        Knob(title: "Cutoff", position: model.knob(\.cutoff, .exponential(40...16_000)),
                             text: model.settings.cutoff.hertzText)
                        // Each filter reads it its own way: resonance, an
                        // order, a ripple or a stop band.
                        Knob(title: kind.resonanceName, position: model.knob(\.resonance, .linear(0...1)),
                             text: kind.resonanceText(model.settings.resonance),
                             tint: kind.hasResonance ? Theme.accent : Theme.label)
                        Knob(title: "Env", position: model.knob(\.envelopeAmount, .linear(0...1)),
                             text: model.settings.envelopeAmount.percentText, tint: Theme.filterEnvelope)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                EnvelopePanel(title: "Filter Envelope", model: model, path: \.filterEnvelope, tint: Theme.filterEnvelope)
                EnvelopePanel(title: "Amp Envelope", model: model, path: \.amplitude, tint: Theme.envelope)
            }
        case .tone:
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
                .fixedSize(horizontal: true, vertical: false)
                EqualizerPanel(model: model)
                Panel("Output") {
                    HStack(spacing: 4) {
                        Knob(title: "Low Cut", position: model.knob(\.lowCut, .exponential(20...500)),
                             text: model.settings.lowCut.hertzText)
                        Knob(title: "Volume", position: model.knob(\.volume, .linear(0...1)),
                             text: model.settings.volume.percentText)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        case .space:
            HStack(spacing: 12) {
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
            }
        }
    }
}

/// The three bands and the tilt, after the drive.
@View
struct EqualizerPanel {
    let model: SynthModel

    var body: some View {
        let settings = model.settings
        Panel("EQ") {
            HStack(spacing: 4) {
                Knob(title: "Low", position: model.knob(\.eqLow, .linear(-12...12)),
                     text: settings.eqLow.decibelText, bipolar: true, tint: Theme.drive)
                Knob(title: "Mid", position: model.knob(\.eqMid, .linear(-12...12)),
                     text: settings.eqMid.decibelText, bipolar: true, tint: Theme.drive)
                Knob(title: "High", position: model.knob(\.eqHigh, .linear(-12...12)),
                     text: settings.eqHigh.decibelText, bipolar: true, tint: Theme.drive)
                Knob(title: "Tilt", position: model.knob(\.tilt, .linear(-6...6)),
                     text: settings.tilt.decibelText, bipolar: true, tint: Theme.drive)
            }
        }
    }
}

/// An envelope's four knobs, for the settings at `path`.
@View
struct EnvelopePanel {
    let title: String
    let model: SynthModel
    let path: WritableKeyPath<SynthSettings, EnvelopeSettings>
    let tint: Color

    var body: some View {
        let settings = model.settings[keyPath: path]
        Panel(title) {
            HStack(spacing: 4) {
                Knob(title: "Attack", position: model.knob(path.appending(path: \.attack), .exponential(0.001...4)),
                     text: settings.attack.secondsText, tint: tint)
                Knob(title: "Decay", position: model.knob(path.appending(path: \.decay), .exponential(0.005...4)),
                     text: settings.decay.secondsText, tint: tint)
                Knob(title: "Sustain", position: model.knob(path.appending(path: \.sustain), .linear(0...1)),
                     text: settings.sustain.percentText, tint: tint)
                Knob(title: "Release", position: model.knob(path.appending(path: \.release), .exponential(0.005...6)),
                     text: settings.release.secondsText, tint: tint)
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

extension OscillatorSettings {
    /// The Shape knob's value as the wave reads it: the pulse's width, the
    /// supersaw's detune; nothing for the others.
    var shapeText: String {
        switch waveform {
        case .pulse: String(format: "%.0f%%", (0.5 - 0.45 * shape) * 100)
        case .supersaw: String(format: "%.0f%%", shape * 100)
        default: "–"
        }
    }
}

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

    var decibelText: String {
        abs(self) < 0.05 ? "0 dB" : String(format: "%+.1f dB", self)
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
