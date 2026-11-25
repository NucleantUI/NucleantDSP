//
//  Halfband.swift
//  NucleantDSP
//
//  Doubling and halving a sample rate: a half-band low-pass made of two
//  chains of allpass filters (Dave Waugh's polyphase filters at
//  musicdsp.org, "Polyphase Filters"; the method of Artur Krukowski and
//  Laurent de Soras' HIIR). Its steep 12th order: 104 dB down from 0.26 of
//  the doubled rate, flat to 0.24 of it.
//

/// One stage of doubling or halving, for any number of channels.
///
/// The low-pass is 0.5·(A(z²) + z⁻¹·B(z²)), A and B each six allpass
/// filters in a row. Split into its two phases it runs at the lower rate:
/// doubling, each sample in becomes A's output and then B's; halving, each
/// pair in becomes the mean of A on the second and B on the first.
struct Halfband: Sendable {
    private static let a: [Double] = [
        0.036681502163648017, 0.2746317593794541, 0.56109896978791948,
        0.769741833862266, 0.8922608180038789, 0.962094548378084,
    ]
    private static let b: [Double] = [
        0.13654762463195771, 0.42313861743656667, 0.6775400499741616,
        0.839889624849638, 0.9315419599631839, 0.9878163707328971,
    ]
    private static let sections = 6

    /// For each channel, each chain's sections: the input and output one
    /// sample before, at the lower rate. Channel c's chain A starts at
    /// c·4·sections, chain B 2·sections after it.
    private var state: ContiguousArray<Double>
    let channels: Int

    init(channels: Int) {
        self.channels = channels
        state = ContiguousArray(repeating: 0, count: channels * 4 * Halfband.sections)
    }

    /// `input` through one chain whose state starts at `offset`.
    private static func chain(
        _ input: Double, _ coefficients: UnsafeBufferPointer<Double>, _ state: UnsafeMutableBufferPointer<Double>,
        at offset: Int
    ) -> Double {
        var x = input
        for index in 0..<sections {
            let slot = offset + index * 2
            // y[n] = x[n − 1] + (x[n] − y[n − 1])·c
            let y = state[slot] + (x - state[slot + 1]) * coefficients[index]
            state[slot] = x
            state[slot + 1] = y
            x = y
        }
        return x
    }

    /// `frames` frames of `channels` from `source`, at twice the rate into
    /// `destination` (2·frames frames).
    mutating func upsample(_ source: UnsafePointer<Float>, into destination: UnsafeMutablePointer<Float>, frames: Int) {
        let channels = channels
        let span = 2 * Halfband.sections
        Halfband.a.withUnsafeBufferPointer { a in
            Halfband.b.withUnsafeBufferPointer { b in
                state.withUnsafeMutableBufferPointer { state in
                    for frame in 0..<frames {
                        for channel in 0..<channels {
                            let x = Double(source[frame * channels + channel])
                            let offset = channel * 2 * span
                            destination[(2 * frame) * channels + channel] = Float(Halfband.chain(x, a, state, at: offset))
                            destination[(2 * frame + 1) * channels + channel] =
                                Float(Halfband.chain(x, b, state, at: offset + span))
                        }
                    }
                }
            }
        }
    }

    /// `2·frames` frames of `channels` from `source`, at half the rate into
    /// `destination` (`frames` frames). It may be `source` itself.
    mutating func downsample(_ source: UnsafePointer<Float>, into destination: UnsafeMutablePointer<Float>, frames: Int) {
        let channels = channels
        let span = 2 * Halfband.sections
        Halfband.a.withUnsafeBufferPointer { a in
            Halfband.b.withUnsafeBufferPointer { b in
                state.withUnsafeMutableBufferPointer { state in
                    for frame in 0..<frames {
                        for channel in 0..<channels {
                            let first = Double(source[(2 * frame) * channels + channel])
                            let second = Double(source[(2 * frame + 1) * channels + channel])
                            let offset = channel * 2 * span
                            let y = 0.5 * (Halfband.chain(second, a, state, at: offset)
                                + Halfband.chain(first, b, state, at: offset + span))
                            destination[frame * channels + channel] = Float(y)
                        }
                    }
                }
            }
        }
    }
}
