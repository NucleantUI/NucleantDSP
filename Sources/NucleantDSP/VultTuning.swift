//
//  VultTuning.swift
//  NucleantDSP
//

import Foundation

/// The control value (cv) that tunes one of Vult's example filters to
/// `frequency` hertz in an output running at `sampleRate`.
///
/// The examples take their cutoff as a cv on Vult's pitch scale, and are
/// worked out for 44.1 kHz: cv becomes the MIDI pitch 24 + 120·cv, and that
/// the frequency 8.1758·e^(0.057762·pitch) of the filter at 44.1 kHz. A
/// filter running at another rate cuts at that frequency scaled by
/// rate/44.1 kHz, so the cv asked for is the one for `frequency` scaled back.
func vultCV(frequency: Float, sampleRate: Double) -> Float {
    let at44k1 = max(Double(frequency), 1) * 44_100 / sampleRate
    let pitch = log(at44k1 / 8.175798915643707) / 0.057762265046662105
    return Float((pitch - 24) / 120)
}
