import Foundation
import NucleantDSP
import Testing

// MARK: - Helpers

/// `processor` run over `input` (interleaved, `channels` per frame) in
/// blocks of 512 frames, as an output would ask for it.
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

/// `frames` frames of silence followed by nothing: a generator's buffer.
private func silence(_ frames: Int, channels: Int = 1) -> [Float] {
    [Float](repeating: 0, count: frames * channels)
}

private func sine(_ frequency: Double, frames: Int, amplitude: Float = 0.25, sampleRate: Double = 48_000) -> [Float] {
    (0..<frames).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

/// The level of `samples` after the first `skip`, while a filter settles.
private func rms(_ samples: [Float], skip: Int = 4_800) -> Float {
    let tail = samples.dropFirst(skip)
    return Float(sqrt(Double(tail.reduce(0) { $0 + $1 * $1 }) / Double(tail.count)))
}

/// How much of a sine at `frequency` gets through `processor`.
private func gain<P: AudioProcessor>(of processor: P, at frequency: Double, sampleRate: Double = 48_000) -> Float {
    var processor = processor
    let input = sine(frequency, frames: Int(sampleRate / 2), sampleRate: sampleRate)
    return rms(render(&processor, input, sampleRate: sampleRate)) / rms(input)
}

private func impulse(_ frames: Int, channels: Int = 1) -> [Float] {
    var samples = silence(frames, channels: channels)
    for channel in 0..<channels { samples[channel] = 1 }
    return samples
}

// MARK: - Swift

@Suite struct SwiftProcessorTests {
    @Test func oscillatorPlaysItsFrequencyInEveryChannel() {
        var oscillator = Oscillator(.sine, frequency: 440, amplitude: 0.5)
        let output = render(&oscillator, silence(48_000, channels: 2), channels: 2)
        let left = stride(from: 0, to: output.count, by: 2).map { output[$0] }
        let right = stride(from: 1, to: output.count, by: 2).map { output[$0] }
        #expect(left == right)
        let upward = zip(left, left.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        #expect(abs(upward - 440) <= 1)
        #expect(left.map(abs).max()! <= 0.5)
        #expect(left.map(abs).max()! > 0.49)
    }

    @Test(arguments: [Oscillator.Waveform.sawtooth, .square, .triangle])
    func waveformsStayWithinTheirAmplitude(_ waveform: Oscillator.Waveform) {
        var oscillator = Oscillator(waveform, frequency: 1_000)
        let output = render(&oscillator, silence(4_800))
        #expect(output.map(abs).max()! <= 1.0001)
        #expect(rms(output, skip: 0) > 0.5)
    }

    @Test func gainScalesAndRampsToANewLevel() {
        var gain = Gain(decibels: -6)
        let output = render(&gain, [Float](repeating: 1, count: 1_000))
        #expect(abs(output[0] - 0.5012) < 0.001)
        #expect(Set(output).count == 1)

        gain.level = 1
        let ramp = render(&gain, [Float](repeating: 1, count: 4_800))
        // No jump: from about 0.5 a little at a time, to 1 by the end.
        #expect(ramp[0] < 0.52)
        #expect(zip(ramp, ramp.dropFirst()).allSatisfy { $1 >= $0 && $1 - $0 < 0.01 })
        #expect(abs(ramp.last! - 1) < 0.0001)
    }

    @Test func biquadLowPassPassesLowsAndCutsHighs() {
        let filter = Biquad(.lowPass, frequency: 1_000)
        #expect(abs(gain(of: filter, at: 100) - 1) < 0.02)
        #expect(abs(gain(of: filter, at: 1_000) - 0.7071) < 0.02)
        #expect(gain(of: filter, at: 10_000) < 0.02)
    }

    @Test func biquadPeakRaisesItsFrequency() {
        let filter = Biquad(.peak(decibels: 6), frequency: 2_000, q: 1)
        #expect(abs(gain(of: filter, at: 2_000) - 1.995) < 0.03)
        #expect(abs(gain(of: filter, at: 50) - 1) < 0.02)
    }

    @Test func biquadFiltersEachChannelOnItsOwn() {
        // Five channels: a group of four lanes and one more. Only the third
        // and the fifth carry a signal.
        let frames = 4_800
        let tone = sine(5_000, frames: frames)
        var input = silence(frames, channels: 5)
        for frame in 0..<frames {
            input[frame * 5 + 2] = tone[frame]
            input[frame * 5 + 4] = tone[frame]
        }
        var filter = Biquad(.highPass, frequency: 200)
        let output = render(&filter, input, channels: 5)
        for channel in 0..<5 {
            let samples = stride(from: channel, to: output.count, by: 5).map { output[$0] }
            if channel == 2 || channel == 4 {
                #expect(abs(rms(samples, skip: 480) / rms(tone, skip: 480) - 1) < 0.02)
            } else {
                #expect(samples.allSatisfy { $0 == 0 })
            }
        }
    }

    @Test func thenRunsOneAfterTheOther() {
        var chain = Oscillator(.square, frequency: 100).then(Gain(level: 0.25))
        let output = render(&chain, silence(4_800))
        #expect(abs(output.map(abs).max()! - 0.25) < 0.01)
        chain.second.level = 1
        #expect(chain.first.frequency == 100)
    }
}

// MARK: - Vult

@Suite struct VultProcessorTests {
    @Test func stateVariableFilterModes() {
        let low = StateVariableFilter(.lowPass, cutoff: 500)
        #expect(abs(gain(of: low, at: 50) - 1) < 0.05)
        #expect(gain(of: low, at: 8_000) < 0.02)

        let high = StateVariableFilter(.highPass, cutoff: 2_000)
        #expect(gain(of: high, at: 100) < 0.02)
        #expect(abs(gain(of: high, at: 15_000) - 1) < 0.05)

        let band = StateVariableFilter(.bandPass, cutoff: 1_000)
        #expect(gain(of: band, at: 1_000) > gain(of: band, at: 100) * 4)
        #expect(gain(of: band, at: 1_000) > gain(of: band, at: 10_000) * 4)

        let notch = StateVariableFilter(.notch, cutoff: 1_000, resonance: 1)
        #expect(gain(of: notch, at: 1_000) < 0.1)
    }

    /// svf.vult is worked out for 44.1 kHz; the cutoff is where it is asked
    /// for at any rate: −3 dB there for a Butterworth response.
    @Test(arguments: [44_100.0, 48_000, 96_000])
    func stateVariableFilterCutoffAtAnyRate(_ sampleRate: Double) {
        let filter = StateVariableFilter(.lowPass, cutoff: 1_000)
        #expect(abs(gain(of: filter, at: 1_000, sampleRate: sampleRate) - 0.7071) < 0.03)
    }

    @Test(arguments: [44_100.0, 48_000, 96_000])
    func ladderFilterCutsAboveItsCutoff(_ sampleRate: Double) {
        let filter = LadderFilter(cutoff: 1_000)
        #expect(gain(of: filter, at: 100, sampleRate: sampleRate) > 0.9)
        // Four poles: two octaves up, well under a hundredth.
        #expect(gain(of: filter, at: 4_000, sampleRate: sampleRate) < 0.03)
    }

    @Test func ladderFilterResonanceRingsAtTheCutoff() {
        let plain = LadderFilter(cutoff: 1_000, resonance: 0)
        let ringing = LadderFilter(cutoff: 1_000, resonance: 0.8)
        #expect(gain(of: ringing, at: 1_000) > gain(of: plain, at: 1_000) * 2)
    }

    @Test func shapers() {
        var saturation = SoftSaturation()
        let soft = render(&saturation, [0.5, -0.5, 20, 24, 100, -100])
        #expect(abs(soft[0] - Float(16 * tanh(0.5 / 16.0))) < 0.002)
        #expect(abs(soft[1] + Float(16 * tanh(0.5 / 16.0))) < 0.002)
        #expect(abs(soft[2] - Float(16 * tanh(20 / 16.0))) < 0.01)
        // Past ±24, held there.
        #expect(abs(soft[3] - Float(16 * tanh(24 / 16.0))) < 0.01)
        #expect(soft[4] == soft[3])
        #expect(soft[5] == -soft[3])

        var clipper = CubicClipper(drive: 2)
        let clipped = render(&clipper, [0.25, 1, -1])
        #expect(abs(clipped[0] - (0.5 - 0.125 / 3)) < 1e-6)
        #expect(abs(clipped[1] - Float(2) / 3) < 1e-6)
        #expect(abs(clipped[2] + Float(2) / 3) < 1e-6)

        var flat = Wavefolder(level: 0)
        #expect(render(&flat, [0.3, -0.7]) == [0.3, -0.7])
        var folder = Wavefolder(level: 1)
        // 0.3·9 = 2.7: past two folds, 0.7 up from the second.
        let folded = render(&folder, [0.3, -0.3])
        #expect(abs(folded[0] - 0.7) < 1e-5)
        #expect(abs(folded[1] + 0.7) < 1e-5)

        var clean = Bitcrusher(amount: 0)
        #expect(render(&clean, [0.123, -0.456]) == [0.123, -0.456])
        var crusher = Bitcrusher(amount: 1)
        // Steps of 1/1.234: 0.5 rounds to 0, 0.9 to one step.
        let crushed = render(&crusher, [0.5, 0.9, -0.9])
        let step = Float(1 / (10_000 * exp(-9.0)))
        #expect(crushed[0] == 0)
        #expect(abs(crushed[1] - step) < 0.01)
        #expect(abs(crushed[2] + step) < 0.01)
    }
}

// MARK: - C

@Suite struct CProcessorTests {
    @Test func delayEchoesAfterItsTimeAndAgainByItsFeedback() {
        var delay = Delay(time: 0.01, feedback: 0.5, mix: 1)
        let output = render(&delay, impulse(2_000))
        // 10 ms at 48 kHz: 480 frames.
        #expect(output[0] == 0)
        #expect(abs(output[480] - 1) < 1e-6)
        #expect(abs(output[960] - 0.5) < 1e-6)
        #expect(abs(output[1_440] - 0.25) < 1e-6)
        #expect(abs(output[1_920] - 0.125) < 1e-6)
        let echoes = [480, 960, 1_440, 1_920]
        #expect(output.enumerated().filter { !echoes.contains($0.offset) }.allSatisfy { abs($0.element) < 1e-6 })
    }

    @Test func delayReadsBetweenSamples() {
        var delay = Delay(time: 100.5 / 48_000, feedback: 0, mix: 1)
        let output = render(&delay, impulse(300))
        #expect(abs(output[100] - 0.5) < 1e-5)
        #expect(abs(output[101] - 0.5) < 1e-5)
    }

    @Test func dryMixLeavesTheInput() {
        var delay = Delay(time: 0.01, mix: 0)
        let tone = sine(440, frames: 2_000)
        #expect(render(&delay, tone) == tone)

        var reverb = Reverb(mix: 0)
        let stereo = (0..<2_000).flatMap { [tone[$0], -tone[$0]] }
        #expect(render(&reverb, stereo, channels: 2) == stereo)
    }

    @Test func reverbRingsAndFades() {
        var reverb = Reverb(roomSize: 0.8, mix: 1)
        let output = render(&reverb, impulse(96_000, channels: 2), channels: 2)
        let left = stride(from: 0, to: output.count, by: 2).map { output[$0] }
        let right = stride(from: 1, to: output.count, by: 2).map { output[$0] }
        let early = rms(Array(left[4_800..<14_400]), skip: 0)
        let late = rms(Array(left[72_000..<81_600]), skip: 0)
        #expect(early > 0.001)
        #expect(late > 0)
        #expect(late < early / 4)
        // Width 1: the two sides are their own.
        #expect(left != right)
    }

    @Test func reverbWidthZeroIsTheSameOnBothSides() {
        var reverb = Reverb(width: 0, mix: 1)
        let output = render(&reverb, impulse(9_600, channels: 2), channels: 2)
        for frame in 0..<9_600 {
            #expect(output[frame * 2] == output[frame * 2 + 1])
        }
    }
}

// MARK: - Values

@Suite struct ValueTests {
    /// A copy carries on from where the original was, and each then goes
    /// its own way: the C state under it is copied, not shared.
    @Test func aCopyOfAProcessorHasItsOwnState() {
        var original = Delay(time: 0.001, feedback: 0, mix: 1)
        _ = render(&original, impulse(10))
        var copy = original

        // The impulse is still in both lines: 48 frames after it went in.
        let fromOriginal = render(&original, silence(100))
        let fromCopy = render(&copy, silence(100))
        #expect(fromOriginal == fromCopy)
        #expect(abs(fromCopy[38] - 1) < 1e-6)

        // Feeding one does not reach the other.
        _ = render(&original, impulse(10))
        let later = render(&copy, silence(100))
        #expect(later.allSatisfy { $0 == 0 })
    }

    @Test func aFilterCopyCarriesOnTheSame() {
        var original = StateVariableFilter(.lowPass, cutoff: 800, resonance: 2)
        let tone = sine(800, frames: 4_800)
        _ = render(&original, tone)
        var copy = original
        let next = sine(800, frames: 1_000)
        #expect(render(&original, next) == render(&copy, next))
    }
}
