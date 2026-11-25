import Foundation
import NucleantDSP
import Testing

// Oversampled, the Supersaw and the PulseOscillator.

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

private func silence(_ frames: Int, channels: Int = 1) -> [Float] {
    [Float](repeating: 0, count: frames * channels)
}

private func sine(_ frequency: Double, frames: Int, amplitude: Float = 0.25, sampleRate: Double = 48_000) -> [Float] {
    (0..<frames).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

private func rms(_ samples: some Collection<Float>) -> Float {
    Float(sqrt(Double(samples.reduce(0) { $0 + $1 * $1 }) / Double(samples.count)))
}

/// The amplitude of the component of `samples` at `frequency`, through a
/// Hann window: a single bin of a DFT, anywhere between bins.
private func amplitude(of samples: some Collection<Float>, at frequency: Double, sampleRate: Double = 48_000) -> Double {
    let n = samples.count
    var real = 0.0, imaginary = 0.0
    for (index, sample) in samples.enumerated() {
        let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(n - 1))
        let phase = 2 * .pi * frequency * Double(index) / sampleRate
        real += window * Double(sample) * cos(phase)
        imaginary -= window * Double(sample) * sin(phase)
    }
    return 2 * (real * real + imaginary * imaginary).squareRoot() / (Double(n) * 0.5)
}

private func decibels(_ ratio: Double) -> Double { 20 * log10(ratio) }

// MARK: - Oversampled

@Suite struct OversampledTests {
    @Test(arguments: [2, 4, 8, 16])
    func passesWhatIsHeardAsItIs(_ factor: Int) {
        // A processor that leaves the buffer alone: only the doubling and
        // halving are heard.
        for frequency in [100.0, 1_000, 15_000] {
            var oversampled = Gain(level: 1).oversampled(factor)
            let input = sine(frequency, frames: 24_000)
            let output = render(&oversampled, input)
            #expect(abs(rms(output.dropFirst(4_800)) / rms(input.dropFirst(4_800)) - 1) < 0.01)
        }
    }

    @Test func factorIsAPowerOfTwoUpToSixteen() {
        #expect(Oversampled(Gain(), factor: 1).factor == 2)
        #expect(Oversampled(Gain(), factor: 3).factor == 4)
        #expect(Oversampled(Gain(), factor: 8).factor == 8)
        #expect(Oversampled(Gain(), factor: 100).factor == 16)
    }

    @Test func runsItsProcessorAtTheHigherRate() {
        // A generator inside still plays its own frequency.
        var tone = Oscillator(.sine, frequency: 1_000, amplitude: 0.5).oversampled(4)
        let output = render(&tone, silence(48_000))
        let tail = Array(output.dropFirst(4_800))
        #expect(abs(amplitude(of: tail, at: 1_000) - 0.5) < 0.01)
        tone.processor.frequency = 2_000
        #expect(tone.processor.frequency == 2_000)
    }

    @Test func keepsAShapersHarmonicsFromFoldingBack() {
        // A hard-driven 5 kHz sine: its 9th harmonic, 45 kHz, folds back to
        // 3 kHz at 48 kHz, where nothing harmonic is.
        let input = sine(5_000, frames: 48_000, amplitude: 0.9)
        var plain = CubicClipper(drive: 4)
        var oversampled = CubicClipper(drive: 4).oversampled(8)
        let flat = Array(render(&plain, input).dropFirst(4_800))
        let clean = Array(render(&oversampled, input).dropFirst(4_800))
        let aliasPlain = decibels(amplitude(of: flat, at: 3_000) / amplitude(of: flat, at: 5_000))
        let aliasClean = decibels(amplitude(of: clean, at: 3_000) / amplitude(of: clean, at: 5_000))
        #expect(aliasPlain > -50)
        #expect(aliasClean < aliasPlain - 30)
    }

    @Test func filtersEachChannelOnItsOwn() {
        let tone = sine(440, frames: 4_800)
        var input = silence(4_800, channels: 3)
        for frame in 0..<4_800 { input[frame * 3 + 1] = tone[frame] }
        var oversampled = Gain(level: 1).oversampled(4)
        let output = render(&oversampled, input, channels: 3)
        #expect(stride(from: 0, to: output.count, by: 3).allSatisfy { output[$0] == 0 })
        #expect(stride(from: 2, to: output.count, by: 3).allSatisfy { output[$0] == 0 })
        let middle = stride(from: 1, to: output.count, by: 3).map { output[$0] }
        #expect(abs(rms(middle.dropFirst(480)) / rms(tone.dropFirst(480)) - 1) < 0.01)
    }
}

// MARK: - Oscillators

@Suite struct PulseAndSupersawTests {
    @Test func pulseAtHalfWidthIsASquare() {
        var pulse = PulseOscillator(frequency: 100, width: 0.5, amplitude: 0.5)
        let output = render(&pulse, silence(48_000))
        #expect(abs(output.max()! - 0.5) < 0.01)
        #expect(abs(output.min()! + 0.5) < 0.01)
        #expect(abs(output.reduce(0, +) / Float(output.count)) < 0.001)
    }

    @Test(arguments: [0.1, 0.25, 0.7] as [Float])
    func pulseSpendsItsWidthHighAndHasNoOffset(_ width: Float) {
        var pulse = PulseOscillator(frequency: 100, width: width)
        let output = render(&pulse, silence(48_000))
        let high = output.filter { $0 > 0 }.count
        #expect(abs(Float(high) / Float(output.count) - width) < 0.005)
        #expect(abs(output.reduce(0, +) / Float(output.count)) < 0.002)
        // Levels 2 apart, around 0: −2w and 2 − 2w.
        // 480 samples a period: the middle of the second one's high part,
        // and of its low part.
        #expect(abs(output[480 + Int(width / 2 * 480)] - (2 - 2 * width)) < 0.001)
        #expect(abs(output[480 + Int((width + (1 - width) / 2) * 480)] + 2 * width) < 0.001)
    }

    @Test func pulseAtNoWidthIsSilent() {
        var pulse = PulseOscillator(frequency: 220, width: 0)
        #expect(render(&pulse, silence(4_800)).allSatisfy { abs($0) < 1e-6 })
    }

    @Test func pulseFillsEveryChannelAlike() {
        var pulse = PulseOscillator(frequency: 330, width: 0.3)
        let output = render(&pulse, silence(4_800, channels: 2), channels: 2)
        #expect(stride(from: 0, to: output.count, by: 2).allSatisfy { output[$0] == output[$0 + 1] })
    }

    @Test func supersawInUnisonIsOneSawtooth() {
        // No detune: all seven are the same sawtooth, high-passed at its
        // pitch.
        var saw = Supersaw(frequency: 200, detune: 0, mix: 1, amplitude: 0.5)
        let output = Array(render(&saw, silence(48_000)).dropFirst(4_800))
        let fundamental = amplitude(of: output, at: 200)
        #expect(fundamental > 0.1)
        // Its harmonics fall as a sawtooth's do: the second is 3/2 of the
        // third.
        #expect(abs(amplitude(of: output, at: 400) / amplitude(of: output, at: 600) - 1.5) < 0.1)
        #expect(amplitude(of: output, at: 221.55) < fundamental / 100)
    }

    @Test func supersawDetunesItsSidesByTheTable() {
        // At full detune the outer two are 704/128 and −720/128 of
        // 164352/2²³ off the pitch.
        let base = 164_352.0 / 8_388_608 / 128
        let above = 200 * (1 + 704 * base), below = 200 * (1 - 720 * base)
        var tight = Supersaw(frequency: 200, detune: 0, mix: 1)
        var wide = Supersaw(frequency: 200, detune: 1, mix: 1)
        let unison = Array(render(&tight, silence(48_000)).dropFirst(4_800))
        let detuned = Array(render(&wide, silence(48_000)).dropFirst(4_800))
        #expect(amplitude(of: unison, at: above) < amplitude(of: unison, at: 200) / 100)
        #expect(amplitude(of: detuned, at: above) > amplitude(of: detuned, at: 200) / 3)
        #expect(amplitude(of: detuned, at: below) > amplitude(of: detuned, at: 200) / 3)
    }

    @Test func supersawMixLeavesTheSidesAFaintPresenceAtZero() {
        // At no mix the side sawtooths are 1/25 of the middle one, as the
        // JP-8000's are: there, not gone.
        let above = 200 * (1 + 704 * 164_352.0 / 8_388_608 / 128)
        var faint = Supersaw(frequency: 200, detune: 1, mix: 0)
        let output = Array(render(&faint, silence(48_000)).dropFirst(4_800))
        let ratio = amplitude(of: output, at: above) / amplitude(of: output, at: 200)
        #expect(ratio > 0.03 && ratio < 0.06)
    }

    @Test func supersawStaysAboutAsLoudWhateverItsMix() {
        var faint = Supersaw(frequency: 220, detune: 1, mix: 0)
        var full = Supersaw(frequency: 220, detune: 1, mix: 1)
        let one = rms(render(&faint, silence(48_000)).dropFirst(4_800))
        let seven = rms(render(&full, silence(48_000)).dropFirst(4_800))
        #expect(abs(decibels(Double(seven / one))) < 3)
    }

    @Test func supersawAliasesLessThanOneSawtoothAtTheOutputRate() {
        // 3.1 kHz: its 10th harmonic, 31 kHz, folds back to 17 kHz.
        var supersaw = Supersaw(frequency: 3_100, detune: 0, mix: 0)
        var single = Oscillator(.sawtooth, frequency: 3_100)
        let doubled = Array(render(&supersaw, silence(48_000)).dropFirst(4_800))
        let plain = Array(render(&single, silence(48_000)).dropFirst(4_800))
        let aliasDoubled = decibels(amplitude(of: doubled, at: 17_000) / amplitude(of: doubled, at: 3_100))
        let aliasPlain = decibels(amplitude(of: plain, at: 17_000) / amplitude(of: plain, at: 3_100))
        #expect(aliasDoubled < aliasPlain - 15)
    }
}
