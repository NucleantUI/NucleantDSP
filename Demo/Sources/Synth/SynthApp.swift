//
//  SynthApp.swift
//  Synth
//
//  NucleantDSP's demo: a polyphonic synth whose every sound is one of
//  NucleantDSP's processors (Engine.swift), played through NucleantAudio's
//  AudioPlayer. Played from the keyboard on screen or the computer's keys;
//  the knobs and the scope are PyShader shaders (Shaders/).
//

import NucleantDSP
import NucleantUI

struct Theme {
    static let background = Color(hex: 0x0D0F13)
    static let panel = Color(hex: 0x171A21)
    static let label = Color(hex: 0x8B93A3)
    static let accent = Color(hex: 0x29C5FF)
    static let envelope = Color(hex: 0x7CF29A)
    static let drive = Color(hex: 0xFF8A3D)
    static let space = Color(hex: 0xC18BFF)
}

@View
struct Header {
    @Bindable var model: SynthModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Synth")
                    .font(.system(size: 24, weight: .bold))
                Text(model.problem ?? "NucleantDSP · keys A to ', octave Z and X")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label)
            }
            .fixedSize()
            Spacer()
            HStack(spacing: 8) {
                Text("Octave")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label)
                Picker(selection: $model.settings.octave) {
                    ForEach(-2...2, id: \.self) { octave in
                        Text(octave > 0 ? "+\(octave)" : "\(octave)").fixedSize().tag(octave)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Text(model.voices == 1 ? "1 voice" : "\(model.voices) voices")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.label)
            Picker(selection: $model.preset) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.name).tag(preset)
                }
            }
            .frame(width: 140)
        }
    }
}

@View
struct SynthView {
    @State private var model = SynthModel()
    @FocusState private var hasKeys: Bool
    /// The note each computer key held down plays, so it is the one let go
    /// even if the octave changed meanwhile.
    @State private var keysDown: [Character: Int] = [:]

    var body: some View {
        VStack(spacing: 12) {
            Header(model: model)
            // The scope takes what the panels and the keys leave.
            Scope(samples: model.scope)
                .frame(minHeight: 60, maxHeight: .infinity)
            Controls(model: model)
                .fixedSize(horizontal: false, vertical: true)
            Keyboard(model: model)
                .frame(height: 130)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .colorScheme(.dark)
        .tint(Theme.accent)
        .focusable()
        .focused($hasKeys)
        .onKeyPress(phases: [.down, .up]) { press in
            play(press)
        }
        .onAppear { hasKeys = true }
    }

    private func play(_ press: KeyPress) -> KeyPress.Result {
        guard let key = press.characters.lowercased().first else { return .ignored }
        if press.phase == .down, key == "z" || key == "x" {
            model.settings.octave = min(max(model.settings.octave + (key == "z" ? -1 : 1), -2), 2)
            return .handled
        }
        guard let note = KeyLayout.computerKeys[key] else { return .ignored }
        if press.phase == .down {
            guard keysDown[key] == nil else { return .handled }
            keysDown[key] = note
            model.press(note)
        } else if let held = keysDown.removeValue(forKey: key) {
            model.release(held)
        }
        return .handled
    }
}

@main
struct SynthApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Synth") {
            SynthView()
        }
        .defaultSize(width: 1100, height: 900)
    }
}
