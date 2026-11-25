//
//  Model.swift
//  Synth
//

import Foundation
import NucleantAudio
import NucleantDSP
import Observation

/// The synth as the window sees it: the settings the panels change, the
/// notes held, and what the scope shows. Every change of setting goes to
/// the engine on the audio thread; the scope and the voice count come back
/// from it 30 times a second.
@MainActor
@Observable
final class SynthModel {
    var settings = SynthSettings() {
        didSet {
            guard settings != oldValue else { return }
            let settings = settings
            player?.withProcessor { $0.settings = settings }
        }
    }

    /// The preset last chosen; choosing one sets every setting.
    var preset = Preset.classic {
        didSet { settings = preset.settings }
    }

    private(set) var heldNotes: Set<Int> = []
    /// The latest samples of the first channel, starting where the wave
    /// rises through zero, so a steady tone stands still.
    private(set) var scope = [Float](repeating: 0, count: SynthModel.scopeLength)
    private(set) var voices = 0
    /// Why there is no sound, when there is none.
    private(set) var problem: String?

    /// As many as Shaders/Scope.py draws (its COUNT).
    static let scopeLength = 1_024

    private let player: AudioPlayer<SynthEngine>?

    init() {
        do {
            // The engine starts from the default settings, which are the
            // Classic preset's, as the model's do.
            let player = try AudioPlayer(SynthEngine(), channels: 2)
            try player.start()
            self.player = player
        } catch {
            player = nil
            problem = "No audio output: \(error)"
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0 / 30))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func press(_ note: Int) {
        guard heldNotes.insert(note).inserted else { return }
        player?.withProcessor { $0.noteOn(note) }
    }

    func release(_ note: Int) {
        guard heldNotes.remove(note) != nil else { return }
        player?.withProcessor { $0.noteOff(note) }
    }

    func releaseAll() {
        heldNotes.removeAll()
        player?.withProcessor { $0.allNotesOff() }
    }

    private func refresh() {
        guard let player else { return }
        let (recent, active) = player.withProcessor { ($0.scope, $0.activeVoices) }
        if voices != active { voices = active }
        // The window starts at the first rise through zero in the older
        // half, so a steady tone is drawn from the same point every time.
        let window = SynthModel.scopeLength
        var start = recent.count - window
        for index in 1..<(recent.count - window) where recent[index - 1] < 0 && recent[index] >= 0 {
            start = index
            break
        }
        let shown = Array(recent[start..<(start + window)])
        if shown != scope { scope = shown }
    }
}
