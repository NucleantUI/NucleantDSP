//
//  NucleantDSP.swift
//  NucleantDSP
//
//  Audio processors, each an `AudioProcessor` from NucleantAudio's
//  AudioProtocols: whatever runs one (NucleantAudio's `AudioPlayer`) plays
//  it on every platform. Written in Swift (Oscillator, Gain, Biquad, Then),
//  in C (Delay, Reverb), and in Vult, generated as C++ behind a C API
//  (StateVariableFilter, LadderFilter, SoftSaturation, CubicClipper,
//  Wavefolder, Bitcrusher).
//

@_exported import AudioProtocols
