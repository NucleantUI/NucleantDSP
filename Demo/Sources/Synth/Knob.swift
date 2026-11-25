//
//  Knob.swift
//  Synth
//

import Foundation
import NucleantUI

/// How a knob's travel, 0 at its left end to 1 at its right, maps onto a
/// setting.
enum KnobScale {
    case linear(ClosedRange<Double>)
    /// Equal turns multiply the value by the same factor: frequencies and
    /// times.
    case exponential(ClosedRange<Double>)

    func value(at position: Double) -> Double {
        let position = min(max(position, 0), 1)
        switch self {
        case .linear(let range):
            return range.lowerBound + position * (range.upperBound - range.lowerBound)
        case .exponential(let range):
            return range.lowerBound * pow(range.upperBound / range.lowerBound, position)
        }
    }

    func position(of value: Double) -> Double {
        switch self {
        case .linear(let range):
            return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        case .exponential(let range):
            return log(max(value, range.lowerBound) / range.lowerBound) / log(range.upperBound / range.lowerBound)
        }
    }
}

/// A knob drawn by Shaders/Knob.py: a black cap inside a ring of light up to
/// its value. Dragged up or down to turn it; its name and value under it —
/// or only its value, where a column of knobs is named once above them.
@View
struct Knob {
    let title: String?
    /// 0…1, along the knob's travel.
    @Binding var position: Double
    let text: String
    /// The ring runs from the top, either way, as for a pan.
    let bipolar: Bool
    let tint: Color

    /// Where the drag began, so the knob turns by how far it has moved.
    @State private var dragStart: Double?

    init(title: String?, position: Binding<Double>, text: String, bipolar: Bool = false,
         tint: Color = Theme.accent, _viewID: ViewID = #viewID) {
        self.title = title
        self._position = position
        self.text = text
        self.bipolar = bipolar
        self.tint = tint
        self._viewID = _viewID
    }

    /// Points of drag for the whole travel.
    static let travel = 160.0

    /// As wide as its widest name or value, so a value's change of length
    /// moves nothing beside it.
    static let width = 72.0

    var body: some View {
        VStack(spacing: 2) {
            Shader(SpirvFunction(spirv: ShaderModules.shared.knob, isAnimated: false) {
                Float(position)
                Float(bipolar ? 1 : 0)
                tint
                Theme.panel
            })
            .frame(width: 58, height: 58)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        let start = dragStart ?? position
                        dragStart = start
                        position = min(max(start - drag.translation.height / Knob.travel, 0), 1)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: 11, design: .monospaced))
        }
        .frame(width: Knob.width)
    }
}
