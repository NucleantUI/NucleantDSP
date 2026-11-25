//
//  BiquadCascade.swift
//  NucleantDSP
//
//  A digital filter as second-order sections one after another, made from
//  its poles and zeros and scaled to its gain at one frequency: DSPFilters'
//  Cascade and Biquad. Channels are filtered four at a time, one in each
//  lane of a vector, in Double: a high order or a low cutoff needs it.
//
//  Part of the Swift rewrite of Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import Foundation

struct BiquadCascade: Sendable {
    /// One section's coefficients, divided through by a0.
    struct Section: Sendable {
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

        init(_ pair: PoleZeroPair) {
            if pair.isSinglePole {
                a1 = -pair.poles.first.real
                a2 = 0
                b0 = -pair.zeros.first.real
                b1 = 1
                b2 = 0
                return
            }
            (a1, a2) = Section.coefficients(pair.poles)
            (b1, b2) = Section.coefficients(pair.zeros)
            b0 = 1
        }

        /// The second- and first-order coefficients of (1 − p1·z⁻¹)(1 − p2·z⁻¹).
        private static func coefficients(_ pair: ComplexPair) -> (Double, Double) {
            if pair.first.imaginary != 0 {
                return (-2 * pair.first.real, pair.first.norm)
            }
            return (-(pair.first.real + pair.second.real), pair.first.real * pair.second.real)
        }
    }

    private(set) var sections: ContiguousArray<Section> = []
    let maximumSections: Int
    /// Two delayed values per section and channel group: for group `g` and
    /// section `s`, `state[(g·maximumSections + s)·2]` and the one after.
    private var state: ContiguousArray<SIMD4<Double>> = []
    /// How many sections the state was last run through: a change of order
    /// starts every section from silence.
    private var stateSections = 0

    init(maximumPoles: Int) {
        maximumSections = (maximumPoles + 1) / 2
        sections.reserveCapacity(maximumSections)
    }

    /// The sections become `layout`'s, the first scaled so the gain at the
    /// layout's normal frequency is its normal gain.
    mutating func setLayout(_ layout: PoleZeroLayout) {
        sections.removeAll(keepingCapacity: true)
        let count = (layout.poleCount + 1) / 2
        for index in 0..<count { sections.append(Section(layout[index])) }
        guard !sections.isEmpty else { return }
        let scale = layout.normalGain / response(at: layout.normalW / (2 * Double.pi)).magnitude
        sections[0].b0 *= scale
        sections[0].b1 *= scale
        sections[0].b2 *= scale
    }

    /// The filter's response at `frequency`, a share of the sample rate.
    func response(at frequency: Double) -> Complex {
        let w = 2 * Double.pi * frequency
        let z1 = Complex(radius: 1, angle: -w)
        let z2 = Complex(radius: 1, angle: -2 * w)
        var top = Complex(1)
        var bottom = Complex(1)
        for section in sections {
            top *= Complex(section.b0).adding(section.b1, times: z1).adding(section.b2, times: z2)
            bottom *= Complex(1).adding(section.a1, times: z1).adding(section.a2, times: z2)
        }
        return top / bottom
    }

    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        let groups = (channels + 3) / 4
        let size = groups * maximumSections * 2
        if state.count != size {
            state = ContiguousArray(repeating: .zero, count: size)
            stateSections = sections.count
        } else if stateSections != sections.count {
            for index in state.indices { state[index] = .zero }
            stateSections = sections.count
        }
        let maximumSections = maximumSections
        sections.withUnsafeBufferPointer { sections in
            state.withUnsafeMutableBufferPointer { state in
                for group in 0..<groups {
                    let first = group * 4
                    let lanes = min(4, channels - first)
                    let base = group * maximumSections * 2
                    for frame in 0..<frames {
                        let sample = samples + frame * channels + first
                        var x = SIMD4<Double>.zero
                        for lane in 0..<lanes { x[lane] = Double(sample[lane]) }
                        for index in 0..<sections.count {
                            let section = sections[index]
                            let slot = base + index * 2
                            // Direct form II, transposed.
                            let y = section.b0 * x + state[slot]
                            state[slot] = section.b1 * x - section.a1 * y + state[slot + 1]
                            state[slot + 1] = section.b2 * x - section.a2 * y
                            x = y
                        }
                        for lane in 0..<lanes { sample[lane] = Float(x[lane]) }
                    }
                }
            }
        }
    }
}
