//
//  Keyboard.swift
//  Synth
//

import NucleantUI

/// Two octaves of piano keys, C3 to C5, played with the pointer — one note
/// per finger on a touch screen, and a drag slides from key to key — or with
/// the computer's keys, whose letters are on the keys they play.
@View
struct Keyboard {
    let model: SynthModel

    /// Which note each pointer holds down.
    @State private var touches: [Int: Int] = [:]

    var body: some View {
        GeometryReader { proxy in
            let layout = KeyLayout(size: proxy.size)
            // The keys are placed by offset, which does not size the stack:
            // it is given the whole keyboard, so a press anywhere on it is
            // in the stack's own coordinates, the ones `layout` uses.
            ZStack(alignment: .topLeading) {
                ForEach(KeyLayout.whites, id: \.self) { note in
                    let frame = layout.frame(of: note)
                    WhiteKey(label: KeyLayout.label(for: note), isDown: model.heldNotes.contains(note))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.x, y: frame.y)
                }
                ForEach(KeyLayout.blacks, id: \.self) { note in
                    let frame = layout.frame(of: note)
                    BlackKey(label: KeyLayout.label(for: note), isDown: model.heldNotes.contains(note))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.x, y: frame.y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        let note = layout.note(at: drag.location)
                        guard touches[drag.id] != note else { return }
                        if let held = touches[drag.id] { model.release(held) }
                        touches[drag.id] = note
                        if let note { model.press(note) }
                    }
                    .onEnded { drag in
                        if let held = touches.removeValue(forKey: drag.id) { model.release(held) }
                    }
            )
        }
    }
}

@View
struct WhiteKey {
    let label: String?
    let isDown: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isDown ? Theme.accent : Color(hex: 0xE9ECF2))
            .overlay(alignment: .bottom) {
                Text(label ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x6B7280))
                    .padding(.bottom, 8)
            }
    }
}

@View
struct BlackKey {
    let label: String?
    let isDown: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isDown ? Theme.accent : Color(hex: 0x1B1E25))
            .overlay(alignment: .bottom) {
                Text(label ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: 0x9CA3AF))
                    .padding(.bottom, 6)
            }
    }
}

/// Where each key is, for a keyboard of `size`.
struct KeyLayout {
    let size: Size

    static let lowest = 48
    static let highest = 72
    static let whites = (lowest...highest).filter { !isBlack($0) }
    static let blacks = (lowest...highest).filter { isBlack($0) }

    static func isBlack(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(note % 12)
    }

    /// The computer's keys as a piano: the row from A to ' is the white keys
    /// from C3, the row above it the black ones between. Z and X shift the
    /// octave (SynthView).
    static let computerKeys: [Character: Int] = [
        "a": 48, "w": 49, "s": 50, "e": 51, "d": 52, "f": 53, "t": 54, "g": 55, "y": 56, "h": 57,
        "u": 58, "j": 59, "k": 60, "o": 61, "l": 62, "p": 63, ";": 64, "'": 65,
    ]

    /// The computer key that plays `note`, as it is printed on the key.
    static func label(for note: Int) -> String? {
        computerKeys.first { $0.value == note }.map { String($0.key).uppercased() }
    }

    var whiteWidth: Double { size.width / Double(KeyLayout.whites.count) }
    var blackWidth: Double { whiteWidth * 0.6 }
    var blackHeight: Double { size.height * 0.6 }

    /// A white key fills its column, less a gap; a black one sits on the
    /// line between the white keys either side of it.
    func frame(of note: Int) -> Rect {
        if KeyLayout.isBlack(note) {
            let below = KeyLayout.whites.firstIndex(of: note - 1) ?? 0
            let x = Double(below + 1) * whiteWidth - blackWidth / 2
            return Rect(x: x, y: 0, width: blackWidth, height: blackHeight)
        }
        let column = KeyLayout.whites.firstIndex(of: note) ?? 0
        return Rect(x: Double(column) * whiteWidth + 1, y: 0, width: whiteWidth - 2, height: size.height)
    }

    /// The key under `point`: a black key where one is, else the white key's
    /// column.
    func note(at point: Point) -> Int? {
        guard size.width > 0, point.y >= 0, point.y <= size.height else { return nil }
        if point.y < blackHeight {
            for note in KeyLayout.blacks {
                let frame = frame(of: note)
                if point.x >= frame.x && point.x < frame.x + frame.width { return note }
            }
        }
        let column = Int(point.x / whiteWidth)
        guard column >= 0 && column < KeyLayout.whites.count else { return nil }
        return KeyLayout.whites[column]
    }
}
