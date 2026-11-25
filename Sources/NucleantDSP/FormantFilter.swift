//
//  FormantFilter.swift
//  NucleantDSP
//
//  Alex's formant filter (musicdsp.org, "Formant filter"; public source
//  code by alex@smartelectronix.com): a tenth-order all-pole filter per
//  vowel, its coefficients worked out for 44.1 kHz.
//

import AudioProtocols

/// A vowel's resonances laid over the sound, so a bright one (a sawtooth,
/// a square) speaks: A, E, I, O or U, or partway from one to the next.
///
///     var voice = Oscillator(.sawtooth, frequency: 110)
///         .then(FormantFilter(.o))
///
/// Each vowel is its own tenth-order all-pole filter, and all five run side
/// by side, so moving `vowel` from one to the next crossfades between two
/// that are already ringing. It is louder than what goes in: a sawtooth
/// comes out about one and a half (E, I) to three (A) times as loud. The
/// coefficients are worked out for 44.1 kHz: at another rate the formants
/// move with it, about 9% higher at 48 kHz.
public struct FormantFilter: AudioProcessor {
    public enum Vowel: Float, CaseIterable, Sendable {
        case a = 0, e = 1, i = 2, o = 3, u = 4
    }

    /// 0…4: A, E, I, O, U, and between two of them, both crossfaded.
    public var vowel: Float

    /// The input's factor, then the ten feedback coefficients, for A, E, I,
    /// O and U in turn.
    private static let coefficients: [Double] = [
        8.11044e-06, 8.943665402, -36.83889529, 92.01697887, -154.337906, 181.6233289,
        -151.8651235, 89.09614114, -35.10298511, 8.388101016, -0.923313471,

        4.36215e-06, 8.90438318, -36.55179099, 91.05750846, -152.422234, 179.1170248,
        -149.6496211, 87.78352223, -34.60687431, 8.282228154, -0.914150747,

        3.33819e-06, 8.893102966, -36.49532826, 90.96543286, -152.4545478, 179.4835618,
        -150.315433, 88.43409371, -34.98612086, 8.407803364, -0.932568035,

        1.13572e-06, 8.994734087, -37.2084849, 93.22900521, -156.6929844, 184.596544,
        -154.3755513, 90.49663749, -35.58964535, 8.478996281, -0.929252233,

        4.09431e-07, 8.997322763, -37.20218544, 93.11385476, -156.2530937, 183.7080141,
        -153.2631681, 89.59539726, -35.12454591, 8.338655623, -0.910251753,
    ]
    private static let vowels = 5
    private static let order = 10

    /// Per channel and vowel, its last ten outputs, held twice over so the
    /// ten from `head` on are the newest first, with no wrapping: channel
    /// c's vowel v starts at (c·5 + v)·20.
    private var history = ContiguousArray<Double>()
    /// Per channel, where the newest output is.
    private var heads = ContiguousArray<Int>()

    public init(_ vowel: Vowel = .a) {
        self.vowel = vowel.rawValue
    }

    public init(vowel: Float) {
        self.vowel = vowel
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        guard channels > 0 else { return }
        let order = FormantFilter.order
        let vowels = FormantFilter.vowels
        if heads.count != channels {
            heads = ContiguousArray(repeating: 0, count: channels)
            history = ContiguousArray(repeating: 0, count: channels * vowels * 2 * order)
        }
        let position = Double(min(max(vowel, 0), 4))
        let low = min(Int(position), 3)
        let blend = position - Double(low)

        buffer.withFrames(channels: channels) { samples, frames in
            FormantFilter.coefficients.withUnsafeBufferPointer { coefficients in
                history.withUnsafeMutableBufferPointer { history in
                    heads.withUnsafeMutableBufferPointer { heads in
                        for frame in 0..<frames {
                            for channel in 0..<channels {
                                let index = frame * channels + channel
                                let x = Double(samples[index])
                                let head = heads[channel]
                                // The slot the newest output goes in, one back.
                                let next = head == 0 ? order - 1 : head - 1
                                var lowOutput = 0.0, highOutput = 0.0
                                for v in 0..<vowels {
                                    let c = v * (order + 1)
                                    let base = (channel * vowels + v) * 2 * order
                                    var y = coefficients[c] * x
                                    for k in 0..<order { y += coefficients[c + 1 + k] * history[base + head + k] }
                                    history[base + next] = y
                                    history[base + next + order] = y
                                    if v == low { lowOutput = y }
                                    if v == low + 1 { highOutput = y }
                                }
                                heads[channel] = next
                                samples[index] = Float(lowOutput + (highOutput - lowOutput) * blend)
                            }
                        }
                    }
                }
            }
        }
    }
}
