import Foundation
import NucleantDSP
import Testing

// MoogLadder, and the filters from musicdsp.org: ThreePoleLowPass,
// FormantFilter, DCBlocker, TiltEqualizer, ThreeBandEqualizer and
// LinkwitzRiley.

// MARK: - Helpers

private func render<P: AudioProcessor>(
    _ processor: inout P, _ input: [Float], channels: Int = 1, sampleRate: Double = 48_000
) -> [Float] {
    var samples = ContiguousArray(input)
    let block = 512 * channels
    var start = 0
    while start < samples.count {
        let end = min(start + block, samples.count)
        samples[start..<end].withUnsafeMutableBufferPointer { pointer in
            var span = pointer.mutableSpan
            processor.process(into: &span, channels: channels, sampleRate: sampleRate)
        }
        start = end
    }
    return Array(samples)
}

private func sine(_ frequency: Double, frames: Int, amplitude: Float = 0.1, sampleRate: Double = 48_000) -> [Float] {
    (0..<frames).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

private func rms(_ samples: some Collection<Float>) -> Float {
    Float(sqrt(Double(samples.reduce(0) { $0 + $1 * $1 }) / Double(samples.count)))
}

/// How much of a quiet sine at `frequency` gets through `processor`, once
/// it has settled.
private func gain<P: AudioProcessor>(
    of processor: P, at frequency: Double, amplitude: Float = 0.1, sampleRate: Double = 48_000
) -> Float {
    var processor = processor
    let input = sine(frequency, frames: Int(sampleRate * 0.6), amplitude: amplitude, sampleRate: sampleRate)
    let output = render(&processor, input, sampleRate: sampleRate)
    let skip = Int(sampleRate * 0.2)
    return rms(output.dropFirst(skip)) / rms(input.dropFirst(skip))
}

private func decibels(_ level: Float) -> Float { 20 * log10(level) }

// MARK: - Moog ladder

@Suite struct MoogLadderTests {
    @Test(arguments: [44_100.0, 48_000, 96_000])
    func isTwelveDecibelsDownAtItsCutoff(_ sampleRate: Double) {
        for cutoff: Float in [300, 1_000, 4_000] {
            let filter = MoogLadder(cutoff: cutoff)
            #expect(abs(decibels(gain(of: filter, at: Double(cutoff), sampleRate: sampleRate)) + 12) < 1.5)
            #expect(abs(gain(of: filter, at: Double(cutoff) / 10, sampleRate: sampleRate) - 1) < 0.03)
        }
    }

    @Test func fallsTwentyFourDecibelsAnOctave() {
        let filter = MoogLadder(cutoff: 500)
        let oneOctave = decibels(gain(of: filter, at: 2_000))
        let twoOctaves = decibels(gain(of: filter, at: 4_000))
        #expect(abs(oneOctave - twoOctaves - 24) < 2)
    }

    @Test func resonanceRingsAtTheCutoffAndThinsTheBass() {
        let plain = MoogLadder(cutoff: 1_000)
        let ringing = MoogLadder(cutoff: 1_000, resonance: 0.8)
        #expect(gain(of: ringing, at: 1_000) > gain(of: plain, at: 1_000) * 3)
        #expect(gain(of: ringing, at: 100) < gain(of: plain, at: 100) * 0.6)
    }

    @Test func selfOscillatesAtFullResonance() {
        var impulse = [Float](repeating: 0, count: 48_000)
        impulse[0] = 0.5
        var full = MoogLadder(cutoff: 800, resonance: 1)
        var high = MoogLadder(cutoff: 800, resonance: 0.8)
        let ringing = render(&full, impulse)
        let dying = render(&high, impulse)
        // Still ringing a second later, no quieter than halfway there.
        let middle = rms(ringing[19_200..<24_000])
        #expect(middle > 0.001)
        #expect(rms(ringing.suffix(4_800)) > middle / 2)
        #expect(rms(dying.suffix(4_800)) < 1e-4)
    }

    @Test func driveSaturatesTheStages() {
        // Pushed hard, the level out stops growing with the level in.
        let quiet = MoogLadder(cutoff: 2_000, drive: 1)
        let pushed = MoogLadder(cutoff: 2_000, drive: 20)
        #expect(abs(gain(of: quiet, at: 200) - 1) < 0.03)
        #expect(gain(of: pushed, at: 200, amplitude: 0.5) < 5)
    }

    @Test func aCopyCarriesOnFromTheSameState() {
        var original = MoogLadder(cutoff: 600, resonance: 0.7)
        _ = render(&original, sine(300, frames: 4_800))
        var copy = original
        let next = sine(300, frames: 1_000)
        #expect(render(&original, next) == render(&copy, next))
    }
}

// MARK: - musicdsp.org

@Suite struct MusicDSPFilterTests {
    @Test func threePoleFallsEighteenDecibelsAnOctave() {
        let filter = ThreePoleLowPass(cutoff: 500)
        #expect(abs(gain(of: filter, at: 20) - 1) < 0.01)
        let oneOctave = decibels(gain(of: filter, at: 2_000))
        let twoOctaves = decibels(gain(of: filter, at: 4_000))
        #expect(abs(oneOctave - twoOctaves - 18) < 2)
    }

    /// The cutoff is where it rings: without resonance about 17 dB down
    /// there, its peak rises just below the cutoff, and from about 0.85 on
    /// it oscillates on its own, at the cutoff.
    @Test func threePoleResonatesAtItsCutoff() {
        let plain = ThreePoleLowPass(cutoff: 1_000)
        #expect(abs(decibels(gain(of: plain, at: 1_000)) + 17) < 1)
        let resonant = ThreePoleLowPass(cutoff: 1_000, resonance: 0.7)
        #expect(gain(of: resonant, at: 900) > gain(of: plain, at: 900) * 5)
        #expect(gain(of: resonant, at: 900) > gain(of: resonant, at: 600))
        #expect(gain(of: resonant, at: 900) > gain(of: resonant, at: 1_330))

        for (resonance, sustains) in [(0.8, false), (0.9, true), (1, true)] as [(Float, Bool)] {
            var filter = ThreePoleLowPass(cutoff: 1_000, resonance: resonance)
            var impulse = [Float](repeating: 0, count: 48_000)
            impulse[0] = 0.5
            let tail = Array(render(&filter, impulse).suffix(24_000))
            #expect((tail.map(abs).max()! > 0.1) == sustains)
            if sustains {
                let rises = zip(tail, tail.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
                #expect(abs(rises - 500) < 25)
            }
        }
    }

    @Test func threePoleDistortionIsBoundedByTanh() {
        var filter = ThreePoleLowPass(cutoff: 5_000, resonance: 0.5, distortion: 4)
        let output = render(&filter, sine(200, frames: 9_600, amplitude: 1))
        #expect(output.allSatisfy { abs($0) <= 1 })
        #expect(output.max()! > 0.9)
    }

    /// A 110 Hz sawtooth through each vowel, at the rate it was made for:
    /// where its strongest harmonic below 1.2 kHz is, the first formant.
    private func firstFormant(_ vowel: FormantFilter.Vowel) -> Double {
        var voice = Oscillator(.sawtooth, frequency: 110, amplitude: 0.2).then(FormantFilter(vowel))
        let output = render(&voice, [Float](repeating: 0, count: 44_100), sampleRate: 44_100)
        let tail = Array(output.dropFirst(4_410))
        let harmonics = (1...10).map { Double($0) * 110 }
        return harmonics.max { strength(tail, $0) < strength(tail, $1) }!
    }

    private func strength(_ samples: [Float], _ frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * .pi * frequency * Double(index) / 44_100
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return real * real + imaginary * imaginary
    }

    @Test func vowelsHaveTheirOwnFirstFormant() {
        // A and O are open, I and U closed: a high and a low first formant.
        let a = firstFormant(.a), i = firstFormant(.i), o = firstFormant(.o), u = firstFormant(.u)
        #expect(a > i)
        #expect(a > u)
        #expect(o > u)
        #expect(Set([a, firstFormant(.e), i, o, u]).count >= 3)
    }

    @Test func betweenTwoVowelsIsTheirCrossfade() {
        let input = sine(220, frames: 4_800, amplitude: 0.2).enumerated().map { $0.element + Float($0.offset % 7) * 0.01 }
        var a = FormantFilter(.a), e = FormantFilter(.e), between = FormantFilter(vowel: 0.25)
        let fromA = render(&a, input), fromE = render(&e, input), mixed = render(&between, input)
        for index in stride(from: 0, to: input.count, by: 97) {
            #expect(abs(mixed[index] - (0.75 * fromA[index] + 0.25 * fromE[index])) < 1e-5)
        }
    }

    @Test func formantOutputStaysBounded() {
        for vowel in FormantFilter.Vowel.allCases {
            var voice = Oscillator(.sawtooth, frequency: 110, amplitude: 0.25).then(FormantFilter(vowel))
            let output = render(&voice, [Float](repeating: 0, count: 48_000))
            #expect(output.allSatisfy { $0.isFinite })
            #expect(output.map(abs).max()! < 4)
            #expect(rms(output.dropFirst(4_800)) > 0.01)
        }
    }

    @Test func dcBlockerTakesAwayAnOffset() {
        var blocker = DCBlocker()
        let output = render(&blocker, [Float](repeating: 0.5, count: 24_000))
        #expect(output[0] == 0.5)
        #expect(output.suffix(4_800).allSatisfy { abs($0) < 1e-4 })
        #expect(abs(gain(of: DCBlocker(), at: 1_000) - 1) < 0.002)
        #expect(abs(gain(of: DCBlocker(cutoff: 40), at: 40) - 0.7071) < 0.02)
    }

    @Test func tiltRaisesOneSideAndLowersTheOtherFiveTimesAsFar() {
        let flat = TiltEqualizer(frequency: 1_000, decibels: 0)
        #expect(gain(of: flat, at: 100) == 1)

        // Measured well away from the pivot on both sides.
        let up = TiltEqualizer(frequency: 400, decibels: 3)
        #expect(abs(decibels(gain(of: up, at: 12_000)) - 3) < 0.3)
        #expect(abs(decibels(gain(of: up, at: 5)) + 15) < 0.5)

        let down = TiltEqualizer(frequency: 400, decibels: -2)
        #expect(abs(decibels(gain(of: down, at: 5)) - 2) < 0.3)
        #expect(abs(decibels(gain(of: down, at: 12_000)) + 10) < 0.6)
    }

    @Test func threeBandAtZeroIsTheSignalThreeSamplesLate() {
        var eq = ThreeBandEqualizer()
        let input = sine(1_234, frames: 2_000, amplitude: 0.5)
        let output = render(&eq, input)
        #expect(output[0..<3].allSatisfy { abs($0) < 1e-6 })
        for index in 3..<input.count { #expect(abs(output[index] - input[index - 3]) < 1e-6) }
    }

    @Test func threeBandRaisesAndCutsEachBand() {
        let bass = ThreeBandEqualizer(low: 6)
        #expect(abs(decibels(gain(of: bass, at: 60)) - 6) < 0.5)
        #expect(abs(decibels(gain(of: bass, at: 12_000))) < 0.5)

        let treble = ThreeBandEqualizer(high: -6)
        #expect(abs(decibels(gain(of: treble, at: 16_000)) + 6) < 0.7)
        #expect(abs(decibels(gain(of: treble, at: 100))) < 0.5)

        let mids = ThreeBandEqualizer(mid: -12)
        #expect(decibels(gain(of: mids, at: 2_000)) < -6)
        #expect(abs(decibels(gain(of: mids, at: 40))) < 1)
    }

    @Test func linkwitzRileyHalvesAtItsFrequencyAndAddsBackUp() {
        let low = LinkwitzRiley(.lowPass, frequency: 1_000)
        let high = LinkwitzRiley(.highPass, frequency: 1_000)
        #expect(abs(gain(of: low, at: 1_000) - 0.5) < 0.01)
        #expect(abs(gain(of: high, at: 1_000) - 0.5) < 0.01)
        #expect(abs(gain(of: low, at: 50) - 1) < 0.01)
        #expect(abs(gain(of: high, at: 15_000) - 1) < 0.01)
        #expect(decibels(gain(of: low, at: 4_000)) < -40)

        // As low as a low cut goes: still flat above, and still settling.
        let lowCut = LinkwitzRiley(.highPass, frequency: 20)
        #expect(abs(gain(of: lowCut, at: 1_000) - 1) < 0.001)
        #expect(abs(gain(of: lowCut, at: 20) - 0.5) < 0.01)
        var settling = lowCut
        var impulse = [Float](repeating: 0, count: 96_000)
        impulse[0] = 1
        #expect(render(&settling, impulse).suffix(4_800).allSatisfy { abs($0) < 1e-5 })

        // Split, then summed: every frequency at full level.
        for frequency in [100.0, 700, 1_000, 1_500, 8_000] {
            var lows = low, highs = high
            let input = sine(frequency, frames: 28_800)
            let sum = zip(render(&lows, input), render(&highs, input)).map { $0 + $1 }
            #expect(abs(rms(sum.dropFirst(9_600)) / rms(input.dropFirst(9_600)) - 1) < 0.01)
        }
    }
}
