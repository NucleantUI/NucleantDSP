//
//  Shapers.swift
//  NucleantDSP
//
//  Vult's waveshapers (Vult/effects): each sample changed on its own, with
//  no state.
//

import AudioProtocols
import CNucleantDSP

/// Vult's soft saturation (saturate_soft.vult): 16·tanh(x / 16) of the
/// signal times `drive`, held within ±24 first (the range its table covers).
/// Close to clean below ±4, rounding off above.
public struct SoftSaturation: AudioProcessor {
    /// What the signal is multiplied by before it is shaped.
    public var drive: Float

    public init(drive: Float = 1) {
        self.drive = drive
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let drive = drive
        buffer.withFrames(channels: channels) { samples, frames in
            let count = frames * channels
            for index in 0..<count { samples[index] *= drive }
            ndsp_saturate_soft(samples, count)
        }
    }
}

/// Vult's cubic clipper (clipper.vult): x − x³/3 of the signal times
/// `drive`, held at ±2/3 from ±1 on.
public struct CubicClipper: AudioProcessor {
    /// What the signal is multiplied by before it is shaped.
    public var drive: Float

    public init(drive: Float = 1) {
        self.drive = drive
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let drive = drive
        buffer.withFrames(channels: channels) { samples, frames in
            let count = frames * channels
            for index in 0..<count { samples[index] *= drive }
            ndsp_cubic_clip(samples, count)
        }
    }
}

/// Vult's wave folder (fold.vult): the signal's size multiplied by
/// 1 + 8·`level`, and folded back down each time it passes 1.
public struct Wavefolder: AudioProcessor {
    /// 0…1: 0 leaves a signal within ±1 as it is.
    public var level: Float

    public init(level: Float) {
        self.level = level
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let level = level
        buffer.withFrames(channels: channels) { samples, frames in
            ndsp_fold(samples, frames * channels, level)
        }
    }
}

/// Vult's bit crusher (bitcrush.vult): each sample rounded toward 0 to a
/// step of 1/f, where f = 10000·e^(−6 − 3·`amount`).
public struct Bitcrusher: AudioProcessor {
    /// 0…1: 0 leaves the signal as it is; above it, steps from 1/24.8 up
    /// to 1/1.23.
    public var amount: Float

    public init(amount: Float) {
        self.amount = amount
    }

    public mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        let amount = min(max(amount, 0), 1)
        buffer.withFrames(channels: channels) { samples, frames in
            ndsp_bitcrush(samples, frames * channels, amount)
        }
    }
}
