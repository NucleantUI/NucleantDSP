import Foundation
import NucleantDSP
import Testing

// The filters rewritten from DSPFilters: Butterworth, Chebyshev I and II,
// elliptic, Bessel and Legendre.

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

private func sine(_ frequency: Double, frames: Int, sampleRate: Double = 48_000) -> [Float] {
    (0..<frames).map { 0.25 * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

private func rms(_ samples: some Collection<Float>) -> Float {
    Float(sqrt(Double(samples.reduce(0) { $0 + $1 * $1 }) / Double(samples.count)))
}

/// How much of a sine at `frequency` gets through `processor`, once it has
/// settled.
private func gain<P: AudioProcessor>(of processor: P, at frequency: Double, sampleRate: Double = 48_000) -> Float {
    var processor = processor
    let input = sine(frequency, frames: Int(sampleRate * 0.6), sampleRate: sampleRate)
    let output = render(&processor, input, sampleRate: sampleRate)
    let skip = Int(sampleRate * 0.2)
    return rms(output.dropFirst(skip)) / rms(input.dropFirst(skip))
}

private func decibels(_ level: Float) -> Float { 20 * log10(level) }

/// An impulse through `processor`: finite throughout, and died away by its
/// last tenth.
private func settles<P: AudioProcessor>(_ processor: P) -> Bool {
    var processor = processor
    var input = [Float](repeating: 0, count: 48_000)
    input[0] = 1
    let output = render(&processor, input)
    guard output.allSatisfy(\.isFinite) else { return false }
    return output.suffix(4_800).allSatisfy { abs($0) < 1e-4 }
}

// MARK: - Butterworth

@Suite struct ButterworthTests {
    @Test(arguments: 1...8)
    func lowPassIsHalfPowerAtItsCutoff(_ order: Int) {
        let filter = Butterworth(.lowPass, order: order, frequency: 1_000)
        #expect(abs(gain(of: filter, at: 100) - 1) < 0.01)
        #expect(abs(gain(of: filter, at: 1_000) - 0.7071) < 0.01)
        // 6 dB an octave per order, two octaves up.
        #expect(decibels(gain(of: filter, at: 4_000)) < -11.5 * Float(order))
    }

    @Test func highPassMirrorsTheLowPass() {
        let filter = Butterworth(.highPass, order: 4, frequency: 1_000)
        #expect(gain(of: filter, at: 100) < 0.001)
        #expect(abs(gain(of: filter, at: 1_000) - 0.7071) < 0.01)
        #expect(abs(gain(of: filter, at: 10_000) - 1) < 0.01)
    }

    @Test func bandPassAndBandStop() {
        let pass = Butterworth(.bandPass(width: 400), order: 4, frequency: 2_000)
        #expect(abs(gain(of: pass, at: 2_000) - 1) < 0.02)
        #expect(gain(of: pass, at: 500) < 0.01)
        #expect(gain(of: pass, at: 8_000) < 0.01)

        let stop = Butterworth(.bandStop(width: 400), order: 4, frequency: 2_000)
        #expect(gain(of: stop, at: 2_000) < 0.01)
        #expect(abs(gain(of: stop, at: 200) - 1) < 0.02)
        #expect(abs(gain(of: stop, at: 12_000) - 1) < 0.02)
    }

    @Test func shelves() {
        let low = Butterworth(.lowShelf(decibels: 6), order: 4, frequency: 1_000)
        #expect(abs(decibels(gain(of: low, at: 50)) - 6) < 0.2)
        #expect(abs(decibels(gain(of: low, at: 15_000))) < 0.2)

        let high = Butterworth(.highShelf(decibels: -9), order: 4, frequency: 1_000)
        #expect(abs(decibels(gain(of: high, at: 50))) < 0.2)
        #expect(abs(decibels(gain(of: high, at: 15_000)) + 9) < 0.2)

        let band = Butterworth(.bandShelf(width: 500, decibels: 8), order: 3, frequency: 3_000)
        #expect(abs(decibels(gain(of: band, at: 3_000)) - 8) < 0.3)
        #expect(abs(decibels(gain(of: band, at: 100))) < 0.3)
        #expect(abs(decibels(gain(of: band, at: 18_000))) < 0.3)
    }

    @Test func aChangeOfOrderTakesEffect() {
        var filter = Butterworth(.lowPass, order: 2, frequency: 1_000)
        let gentle = gain(of: filter, at: 4_000)
        filter.order = 8
        #expect(gain(of: filter, at: 4_000) < gentle / 100)
    }

    @Test func filtersEachChannelOnItsOwn() {
        let frames = 9_600
        let tone = sine(200, frames: frames)
        var input = [Float](repeating: 0, count: frames * 5)
        for frame in 0..<frames { input[frame * 5 + 4] = tone[frame] }
        var filter = Butterworth(.lowPass, order: 6, frequency: 1_000)
        let output = render(&filter, input, channels: 5)
        for channel in 0..<4 {
            #expect(stride(from: channel, to: output.count, by: 5).allSatisfy { output[$0] == 0 })
        }
        let fifth = stride(from: 4, to: output.count, by: 5).map { output[$0] }
        #expect(abs(rms(fifth.dropFirst(4_800)) / rms(tone.dropFirst(4_800)) - 1) < 0.01)
    }
}

// MARK: - Chebyshev

@Suite struct ChebyshevTests {
    @Test(arguments: [0.5, 1, 3] as [Float])
    func typeIIsDownByItsRippleAtTheCutoff(_ ripple: Float) {
        let filter = ChebyshevI(.lowPass, order: 5, frequency: 2_000, ripple: ripple)
        #expect(abs(decibels(gain(of: filter, at: 2_000)) + ripple) < 0.15)
        // Within the ripple below the cutoff.
        for frequency in [200.0, 800, 1_400, 1_800] {
            let level = decibels(gain(of: filter, at: frequency))
            #expect(level < 0.05 && level > -ripple - 0.05)
        }
    }

    @Test func typeIIsSteeperThanAButterworth() {
        let butterworth = Butterworth(.lowPass, order: 4, frequency: 1_000)
        let chebyshev = ChebyshevI(.lowPass, order: 4, frequency: 1_000, ripple: 1)
        #expect(gain(of: chebyshev, at: 2_000) < gain(of: butterworth, at: 2_000) / 2)
    }

    @Test func typeIHighPassBandPassAndShelf() {
        let high = ChebyshevI(.highPass, order: 4, frequency: 1_000, ripple: 0.5)
        #expect(gain(of: high, at: 200) < 0.01)
        #expect(abs(decibels(gain(of: high, at: 8_000))) < 0.6)

        let band = ChebyshevI(.bandPass(width: 600), order: 3, frequency: 3_000, ripple: 0.5)
        #expect(abs(decibels(gain(of: band, at: 3_000))) < 0.6)
        #expect(gain(of: band, at: 600) < 0.01)

        let shelf = ChebyshevI(.lowShelf(decibels: 6), order: 4, frequency: 500, ripple: 0.5)
        #expect(abs(decibels(gain(of: shelf, at: 40)) - 6) < 0.6)
        #expect(abs(decibels(gain(of: shelf, at: 12_000))) < 0.3)
    }

    @Test func aShelfOfNoGainLeavesTheSignal() {
        let flat = ChebyshevI(.highShelf(decibels: 0), order: 4, frequency: 1_000)
        #expect(abs(gain(of: flat, at: 300) - 1) < 0.001)
        #expect(abs(gain(of: flat, at: 9_000) - 1) < 0.001)
    }

    @Test(arguments: [20, 40, 60] as [Float])
    func typeIIHoldsItsStopBandDown(_ stopBand: Float) {
        let filter = ChebyshevII(.lowPass, order: 6, frequency: 2_000, stopBand: stopBand)
        #expect(abs(decibels(gain(of: filter, at: 2_000)) + stopBand) < 1)
        for frequency in [2_500.0, 4_000, 9_000, 20_000] {
            #expect(decibels(gain(of: filter, at: frequency)) < -stopBand + 0.5)
        }
        // Flat well below.
        #expect(abs(gain(of: filter, at: 300) - 1) < 0.01)
    }

    @Test func typeIIHighPass() {
        let filter = ChebyshevII(.highPass, order: 5, frequency: 1_000, stopBand: 40)
        #expect(decibels(gain(of: filter, at: 500)) < -39.5)
        #expect(abs(gain(of: filter, at: 10_000) - 1) < 0.01)
    }
}

// MARK: - Elliptic, Bessel, Legendre

@Suite struct EllipticBesselLegendreTests {
    @Test(arguments: [2, 3, 4, 5, 6])
    func ellipticPassesWithinItsRipple(_ order: Int) {
        let filter = Elliptic(.lowPass, order: order, frequency: 2_000, ripple: 1)
        for frequency in [100.0, 600, 1_200, 1_700] {
            let level = decibels(gain(of: filter, at: frequency))
            #expect(level < 0.05 && level > -1.05)
        }
        #expect(decibels(gain(of: filter, at: 8_000)) < -20)
    }

    @Test func ellipticIsSteeperThanAChebyshev() {
        let chebyshev = ChebyshevI(.lowPass, order: 4, frequency: 2_000, ripple: 1)
        let elliptic = Elliptic(.lowPass, order: 4, frequency: 2_000, ripple: 1, rolloff: -4)
        #expect(gain(of: elliptic, at: 2_600) < gain(of: chebyshev, at: 2_600))
    }

    /// A lower rolloff falls faster past the cutoff; a higher one holds the
    /// stop band further down.
    @Test func ellipticRolloffTradesSteepnessForDepth() {
        let steep = Elliptic(.lowPass, order: 4, frequency: 2_000, ripple: 1, rolloff: -4)
        let deep = Elliptic(.lowPass, order: 4, frequency: 2_000, ripple: 1, rolloff: 2)
        #expect(gain(of: steep, at: 2_400) < gain(of: deep, at: 2_400))
        let band = [6_000.0, 8_000, 11_000, 15_000, 20_000]
        let steepFloor = band.map { gain(of: steep, at: $0) }.max()!
        let deepFloor = band.map { gain(of: deep, at: $0) }.max()!
        #expect(deepFloor < steepFloor)
    }

    @Test func ellipticHighPassAndBands() {
        let high = Elliptic(.highPass, order: 4, frequency: 2_000, ripple: 0.5)
        #expect(decibels(gain(of: high, at: 400)) < -20)
        #expect(abs(decibels(gain(of: high, at: 12_000))) < 0.6)

        let pass = Elliptic(.bandPass(width: 1_000), order: 3, frequency: 4_000, ripple: 0.5)
        #expect(abs(decibels(gain(of: pass, at: 4_000))) < 0.6)
        #expect(decibels(gain(of: pass, at: 1_000)) < -20)

        let stop = Elliptic(.bandStop(width: 1_000), order: 3, frequency: 4_000, ripple: 0.5)
        #expect(decibels(gain(of: stop, at: 4_000)) < -20)
        #expect(abs(decibels(gain(of: stop, at: 300))) < 0.6)
    }

    /// The prototype is scaled for its delay, not its −3 dB point: that lies
    /// above `frequency`, further the higher the order.
    @Test(arguments: [(2, 1.36), (4, 2.11)] as [(Int, Double)])
    func besselIsHalfPowerAboveItsFrequency(_ order: Int, _ ratio: Double) {
        let filter = Bessel(.lowPass, order: order, frequency: 500)
        #expect(abs(gain(of: filter, at: 500 * ratio) - 0.7071) < 0.02)
        #expect(abs(gain(of: filter, at: 50) - 1) < 0.01)
    }

    @Test func besselKeepsAPulseFromOvershooting() {
        // A step through each: the Butterworth overshoots, the Bessel
        // barely does.
        let step = [Float](repeating: 0.5, count: 4_800)
        var bessel = Bessel(.lowPass, order: 6, frequency: 1_000)
        var butterworth = Butterworth(.lowPass, order: 6, frequency: 1_000)
        #expect(render(&bessel, step).max()! < 0.51)
        #expect(render(&butterworth, step).max()! > 0.55)
    }

    @Test func besselShelfAndHighPass() {
        let shelf = Bessel(.lowShelf(decibels: -6), order: 3, frequency: 500)
        #expect(abs(decibels(gain(of: shelf, at: 30)) + 6) < 0.3)
        #expect(abs(decibels(gain(of: shelf, at: 15_000))) < 0.3)

        let high = Bessel(.highPass, order: 4, frequency: 2_000)
        #expect(gain(of: high, at: 100) < 0.01)
        #expect(abs(gain(of: high, at: 20_000) - 1) < 0.02)
    }

    @Test(arguments: 1...8)
    func legendreIsHalfPowerAtItsCutoffAndNeverRipples(_ order: Int) {
        let filter = Legendre(.lowPass, order: order, frequency: 1_000)
        #expect(abs(gain(of: filter, at: 1_000) - 0.7071) < 0.01)
        // Falling all the way: each step up passes less.
        let levels = [100.0, 300, 500, 700, 900].map { gain(of: filter, at: $0) }
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $1 <= $0 + 0.0005 })
        #expect(abs(levels[0] - 1) < 0.01)
    }

    @Test func legendreIsBetweenButterworthAndChebyshev() {
        let legendre = gain(of: Legendre(.lowPass, order: 5, frequency: 1_000), at: 1_600)
        let butterworth = gain(of: Butterworth(.lowPass, order: 5, frequency: 1_000), at: 1_600)
        let chebyshev = gain(of: ChebyshevI(.lowPass, order: 5, frequency: 1_000, ripple: 1), at: 1_600)
        #expect(legendre < butterworth)
        #expect(legendre > chebyshev)
    }
}

// MARK: - Every order of every design

@Suite struct FilterStabilityTests {
    @Test(arguments: 1...16)
    func everyOrderSettles(_ order: Int) {
        let frequency: Float = 1_000
        #expect(settles(Butterworth(.lowPass, order: order, frequency: frequency)))
        #expect(settles(Butterworth(.highPass, order: order, frequency: frequency)))
        #expect(settles(Butterworth(.bandPass(width: 400), order: order, frequency: frequency)))
        #expect(settles(Butterworth(.bandStop(width: 400), order: order, frequency: frequency)))
        #expect(settles(Butterworth(.lowShelf(decibels: 6), order: order, frequency: frequency)))
        #expect(settles(Butterworth(.highShelf(decibels: -6), order: order, frequency: frequency)))
        #expect(settles(Butterworth(.bandShelf(width: 400, decibels: 6), order: order, frequency: frequency)))

        #expect(settles(ChebyshevI(.lowPass, order: order, frequency: frequency, ripple: 1)))
        #expect(settles(ChebyshevI(.highPass, order: order, frequency: frequency, ripple: 1)))
        #expect(settles(ChebyshevI(.bandPass(width: 400), order: order, frequency: frequency)))
        #expect(settles(ChebyshevI(.bandStop(width: 400), order: order, frequency: frequency)))
        #expect(settles(ChebyshevI(.lowShelf(decibels: 6), order: order, frequency: frequency)))
        #expect(settles(ChebyshevI(.highShelf(decibels: 6), order: order, frequency: frequency)))
        #expect(settles(ChebyshevI(.bandShelf(width: 400, decibels: -6), order: order, frequency: frequency)))

        #expect(settles(ChebyshevII(.lowPass, order: order, frequency: frequency)))
        #expect(settles(ChebyshevII(.highPass, order: order, frequency: frequency)))
        #expect(settles(ChebyshevII(.bandPass(width: 400), order: order, frequency: frequency)))
        #expect(settles(ChebyshevII(.bandStop(width: 400), order: order, frequency: frequency)))
        #expect(settles(ChebyshevII(.lowShelf(decibels: 6), order: order, frequency: frequency)))

        #expect(settles(Elliptic(.lowPass, order: order, frequency: frequency)))
        #expect(settles(Elliptic(.highPass, order: order, frequency: frequency)))
        #expect(settles(Elliptic(.bandPass(width: 400), order: order, frequency: frequency)))
        #expect(settles(Elliptic(.bandStop(width: 400), order: order, frequency: frequency)))

        #expect(settles(Bessel(.lowPass, order: order, frequency: frequency)))
        #expect(settles(Bessel(.highPass, order: order, frequency: frequency)))
        #expect(settles(Bessel(.bandPass(width: 400), order: order, frequency: frequency)))
        #expect(settles(Bessel(.bandStop(width: 400), order: order, frequency: frequency)))
        #expect(settles(Bessel(.lowShelf(decibels: 6), order: order, frequency: frequency)))

        #expect(settles(Legendre(.lowPass, order: order, frequency: frequency)))
        #expect(settles(Legendre(.highPass, order: order, frequency: frequency)))
        #expect(settles(Legendre(.bandPass(width: 400), order: order, frequency: frequency)))
        #expect(settles(Legendre(.bandStop(width: 400), order: order, frequency: frequency)))
    }

    @Test func aCopyCarriesOnFromTheSameState() {
        var original = Elliptic(.lowPass, order: 6, frequency: 900)
        _ = render(&original, sine(800, frames: 4_800))
        var copy = original
        let next = sine(800, frames: 1_000)
        #expect(render(&original, next) == render(&copy, next))
    }
}
