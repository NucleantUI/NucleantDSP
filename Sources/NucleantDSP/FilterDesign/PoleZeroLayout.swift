//
//  PoleZeroLayout.swift
//  NucleantDSP
//
//  A filter as its poles and zeros, in the s plane (an analog prototype) or
//  the z plane (the digital filter made from it), and the transforms from
//  one to the other: DSPFilters' LayoutBase and PoleFilter.
//
//  Part of the Swift rewrite of Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import Foundation

/// Two poles or two zeros: a conjugate pair, or two real ones.
struct ComplexPair: Sendable {
    var first: Complex
    var second: Complex

    init(_ first: Complex, _ second: Complex = .zero) {
        self.first = first
        self.second = second
    }
}

/// The poles and zeros of one second-order section, or of a first-order
/// one when `poles.second` and `zeros.second` are 0.
struct PoleZeroPair: Sendable {
    var poles: ComplexPair
    var zeros: ComplexPair

    var isSinglePole: Bool { poles.second == .zero && zeros.second == .zero }
}

/// A filter's poles and zeros, in pairs, the single real one last, and what
/// its gain is to be at one frequency.
///
/// Room for `maximumPoles` is made once: designing into it again never
/// allocates, so it can happen on the audio thread.
struct PoleZeroLayout: Sendable {
    private(set) var pairs: ContiguousArray<PoleZeroPair>
    private(set) var poleCount = 0
    /// The angular frequency, 0…π, where the gain is `normalGain`.
    private(set) var normalW = 0.0
    private(set) var normalGain = 1.0

    init(maximumPoles: Int) {
        pairs = []
        pairs.reserveCapacity((maximumPoles + 1) / 2)
    }

    subscript(index: Int) -> PoleZeroPair { pairs[index] }

    mutating func reset() {
        pairs.removeAll(keepingCapacity: true)
        poleCount = 0
    }

    mutating func setNormal(w: Double, gain: Double) {
        normalW = w
        normalGain = gain
    }

    /// A single real pole and zero: the last of an odd count.
    mutating func add(pole: Complex, zero: Complex) {
        pairs.append(PoleZeroPair(poles: ComplexPair(pole), zeros: ComplexPair(zero)))
        poleCount += 1
    }

    /// `pole` and `zero`, and their conjugates.
    mutating func addConjugatePairs(pole: Complex, zero: Complex) {
        pairs.append(PoleZeroPair(poles: ComplexPair(pole, pole.conjugate), zeros: ComplexPair(zero, zero.conjugate)))
        poleCount += 2
    }

    /// Two poles and two zeros as they are: conjugates, or reals.
    mutating func add(poles: ComplexPair, zeros: ComplexPair) {
        pairs.append(PoleZeroPair(poles: poles, zeros: zeros))
        poleCount += 2
    }
}

// MARK: - From the s plane to the z plane

extension PoleZeroLayout {
    /// This layout becomes `analog`'s low-pass, cut at `frequency` (a share
    /// of the sample rate, 0…0.5), through the bilinear transform.
    mutating func makeLowPass(from analog: PoleZeroLayout, frequency: Double) {
        reset()
        let f = tan(Double.pi * frequency)
        func transform(_ c: Complex) -> Complex {
            if c.isInfinity { return Complex(-1) }
            let c = f * c
            return (1 + c) / (1 - c)
        }
        let pairCount = analog.poleCount / 2
        for index in 0..<pairCount {
            let pair = analog[index]
            addConjugatePairs(pole: transform(pair.poles.first), zero: transform(pair.zeros.first))
        }
        if analog.poleCount & 1 == 1 {
            let pair = analog[pairCount]
            add(pole: transform(pair.poles.first), zero: transform(pair.zeros.first))
        }
        setNormal(w: analog.normalW, gain: analog.normalGain)
    }

    /// `analog`'s high-pass, cut at `frequency`.
    mutating func makeHighPass(from analog: PoleZeroLayout, frequency: Double) {
        reset()
        let f = 1 / tan(Double.pi * frequency)
        func transform(_ c: Complex) -> Complex {
            if c.isInfinity { return Complex(1) }
            let c = f * c
            return -((1 + c) / (1 - c))
        }
        let pairCount = analog.poleCount / 2
        for index in 0..<pairCount {
            let pair = analog[index]
            addConjugatePairs(pole: transform(pair.poles.first), zero: transform(pair.zeros.first))
        }
        if analog.poleCount & 1 == 1 {
            let pair = analog[pairCount]
            add(pole: transform(pair.poles.first), zero: transform(pair.zeros.first))
        }
        setNormal(w: Double.pi - analog.normalW, gain: analog.normalGain)
    }

    /// `analog`'s band-pass around `center`, `width` wide (both shares of
    /// the sample rate): twice its poles.
    mutating func makeBandPass(from analog: PoleZeroLayout, center: Double, width: Double) {
        reset()
        let ww = 2 * Double.pi * width
        var wc2 = 2 * Double.pi * center - ww / 2
        var wc = wc2 + ww
        if wc2 < 1e-8 { wc2 = 1e-8 }
        if wc > Double.pi - 1e-8 { wc = Double.pi - 1e-8 }
        let a = cos((wc + wc2) * 0.5) / cos((wc - wc2) * 0.5)
        let b = 1 / tan((wc - wc2) * 0.5)
        let a2 = a * a, b2 = b * b, ab2 = 2 * a * b

        func transform(_ c: Complex) -> ComplexPair {
            if c.isInfinity { return ComplexPair(Complex(-1), Complex(1)) }
            let c = (1 + c) / (1 - c)
            var v = Complex.zero.adding(4 * (b2 * (a2 - 1) + 1), times: c)
            v += 8 * (b2 * (a2 - 1) - 1)
            v *= c
            v += 4 * (b2 * (a2 - 1) + 1)
            v = v.squareRoot
            var u = -v
            u = u.adding(ab2, times: c) + ab2
            v = v.adding(ab2, times: c) + ab2
            let d = Complex.zero.adding(2 * (b - 1), times: c) + 2 * (1 + b)
            return ComplexPair(u / d, v / d)
        }

        let pairCount = analog.poleCount / 2
        for index in 0..<pairCount {
            let pair = analog[index]
            let poles = transform(pair.poles.first)
            let zeros = transform(pair.zeros.first)
            addConjugatePairs(pole: poles.first, zero: zeros.first)
            addConjugatePairs(pole: poles.second, zero: zeros.second)
        }
        if analog.poleCount & 1 == 1 {
            let pair = analog[pairCount]
            add(poles: transform(pair.poles.first), zeros: transform(pair.zeros.first))
        }
        let wn = analog.normalW
        setNormal(w: 2 * atan(sqrt(tan((wc + wn) * 0.5) * tan((wc2 + wn) * 0.5))), gain: analog.normalGain)
    }

    /// `analog`'s band-stop around `center`, `width` wide.
    mutating func makeBandStop(from analog: PoleZeroLayout, center: Double, width: Double) {
        reset()
        let ww = 2 * Double.pi * width
        var wc2 = 2 * Double.pi * center - ww / 2
        var wc = wc2 + ww
        if wc2 < 1e-8 { wc2 = 1e-8 }
        if wc > Double.pi - 1e-8 { wc = Double.pi - 1e-8 }
        let a = cos((wc + wc2) * 0.5) / cos((wc - wc2) * 0.5)
        let b = tan((wc - wc2) * 0.5)
        let a2 = a * a, b2 = b * b

        func transform(_ c: Complex) -> ComplexPair {
            let c = c.isInfinity ? Complex(-1) : (1 + c) / (1 - c)
            var u = Complex.zero.adding(4 * (b2 + a2 - 1), times: c)
            u += 8 * (b2 - a2 + 1)
            u *= c
            u += 4 * (a2 + b2 - 1)
            u = u.squareRoot
            var v = -0.5 * u
            v += a
            v = v.adding(-a, times: c)
            u = 0.5 * u
            u += a
            u = u.adding(-a, times: c)
            let d = Complex(b + 1).adding(b - 1, times: c)
            return ComplexPair(u / d, v / d)
        }

        let pairCount = analog.poleCount / 2
        for index in 0..<pairCount {
            let pair = analog[index]
            let poles = transform(pair.poles.first)
            var zeros = transform(pair.zeros.first)
            // Both zeros the same: the second is the first's conjugate.
            if zeros.second == zeros.first { zeros.second = zeros.first.conjugate }
            addConjugatePairs(pole: poles.first, zero: zeros.first)
            addConjugatePairs(pole: poles.second, zero: zeros.second)
        }
        if analog.poleCount & 1 == 1 {
            let pair = analog[pairCount]
            add(poles: transform(pair.poles.first), zeros: transform(pair.zeros.first))
        }
        setNormal(w: center < 0.25 ? Double.pi : 0, gain: analog.normalGain)
    }
}
