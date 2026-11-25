//
//  LinkwitzRiley.swift
//  NucleantDSP
//
//  The fourth-order Linkwitz-Riley filters at musicdsp.org ("4th order
//  Linkwitz-Riley filters", Lubomir I. Ivanov's optimised version of T.
//  Lossius' code for the ttblue project).
//

import AudioProtocols
import Foundation

/// A Linkwitz-Riley crossover's half: a fourth-order low- or high-pass,
/// 24 dB an octave, −6 dB at `frequency`. Its low-pass and its high-pass at
/// the same frequency add back up to the signal's every frequency at full
/// level, so a sound split in two by them, each part treated on its own,
/// can be summed back together.
///
///     var lows = LinkwitzRiley(.lowPass, frequency: 200)
///     var highs = LinkwitzRiley(.highPass, frequency: 200)
///
/// It is a Butterworth squared: two second-order Butterworths in a row,
/// run here as one fourth-order filter in Double.
public struct LinkwitzRiley: AudioProcessor {
    public enum Response: Sendable, Equatable {
        case lowPass
        case highPass
    }

    public var response: Response
    /// In hertz, below the output's Nyquist frequency.
    public var frequency: Float

    /// Per channel: the last four inputs and outputs.
    private struct History: Sendable {
        var x = SIMD4<Double>.zero
        var y = SIMD4<Double>.zero
    }

    private var history = ContiguousArray<History>()

    public init(_ response: Response, frequency: Float) {
        self.response = response
        self.frequency = frequency
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        if history.count != channels { history = ContiguousArray(repeating: History(), count: channels) }
        let fc = min(max(Double(frequency), 1), sampleRate * 0.45)
        let wc = 2 * Double.pi * fc
        let wc2 = wc * wc, wc3 = wc2 * wc, wc4 = wc2 * wc2
        let k = wc / tan(Double.pi * fc / sampleRate)
        let k2 = k * k, k3 = k2 * k, k4 = k2 * k2
        let sqrt2 = 2.0.squareRoot()
        let t1 = sqrt2 * wc3 * k
        let t2 = sqrt2 * wc * k3
        let a = 4 * wc2 * k2 + 2 * t1 + k4 + 2 * t2 + wc4
        // The feedback coefficients, for y[n − 1] to y[n − 4].
        let b = SIMD4<Double>(
            4 * (wc4 + t1 - k4 - t2) / a,
            (6 * wc4 - 8 * wc2 * k2 + 6 * k4) / a,
            4 * (wc4 - t1 + t2 - k4) / a,
            (k4 - 2 * t1 + wc4 - 2 * t2 + 4 * wc2 * k2) / a)
        // The feedforward ones, for x[n] and x[n − 1] to x[n − 4].
        let top = response == .lowPass ? wc4 : k4
        let sign: Double = response == .lowPass ? 1 : -1
        let a0 = top / a
        let feedforward = SIMD4<Double>(sign * 4 * top / a, 6 * top / a, sign * 4 * top / a, top / a)

        buffer.withFrames(channels: channels) { samples, frames in
            history.withUnsafeMutableBufferPointer { history in
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        let index = frame * channels + channel
                        let x = Double(samples[index])
                        var h = history[channel]
                        let y = a0 * x + (feedforward * h.x).sum() - (b * h.y).sum()
                        h.x = SIMD4(x, h.x[0], h.x[1], h.x[2])
                        h.y = SIMD4(y, h.y[0], h.y[1], h.y[2])
                        history[channel] = h
                        samples[index] = Float(y)
                    }
                }
            }
        }
    }
}
