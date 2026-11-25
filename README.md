# NucleantDSP

Audio processors for Swift: oscillators, an envelope, filters, waveshapers, a
delay and a reverb. Each one is an `AudioProcessor` from
[NucleantAudio](https://github.com/NucleantUI/NucleantAudio)'s
AudioProtocols. NucleantAudio's `AudioPlayer` plays them on every platform,
and NucleantDSP never depends on any of NucleantAudio's platform targets.

```swift
.package(url: "https://github.com/NucleantUI/NucleantDSP.git", .upToNextMinor(from: "0.0.0"))
```

Documentation, with the demo synth running in your browser:
https://nucleantui.github.io/NucleantDSP/

## Use

```swift
import NucleantAudio
import NucleantDSP

let voice = Oscillator(.sawtooth, frequency: 110, amplitude: 0.3)
    .then(LadderFilter(cutoff: 800, resonance: 0.5))
    .then(Delay(time: 0.25, feedback: 0.4, mix: 0.3))
    .then(Reverb(roomSize: 0.7, mix: 0.25))

let player = try AudioPlayer(voice, channels: 2)
try player.start()
player.withProcessor { $0.first.first.second.cutoff = 1_600 }
```

`then(_:)` runs one processor after another on the same buffer. Every
processor is a value: a copy carries on from the same state, on its own.

## Processors

| Processor | Written in | What it does |
|---|---|---|
| `Oscillator` | Swift | Sine, sawtooth, square and triangle. The sawtooth and square use PolyBLEP. |
| `Envelope` | Swift | ADSR, applied to the buffer: `open()` starts a note, `close()` lets it go. |
| `Gain` | Swift, SIMD | A level or decibels, with changes smoothed over 5 ms. |
| `Biquad` | Swift, SIMD | Bristow-Johnson's cookbook filters: low-, high-, band- and all-pass, notch, peak, and low and high shelves. Four channels per vector. |
| `Then` | Swift | Two processors, one after the other. |
| `Mixer` | Swift | Several processors side by side, each handed the same buffer, added together at their own levels: oscillators mixed, or effects in parallel. |
| `StateVariableFilter` | Vult | Low-, high- and band-pass, and notch ([svf.vult](Vult/filters/svf.vult)). |
| `LadderFilter` | Vult | A four-pole low-pass with resonance ([ladder.vult](Vult/filters/ladder.vult)). |
| `SoftSaturation` | Vult | 16·tanh(x/16) ([saturate_soft.vult](Vult/effects/saturate_soft.vult)). |
| `CubicClipper` | Vult | x − x³/3 ([clipper.vult](Vult/effects/clipper.vult)). |
| `Wavefolder` | Vult | Folds the signal back on itself ([fold.vult](Vult/effects/fold.vult)). |
| `Bitcrusher` | Vult | Coarser steps ([bitcrush.vult](Vult/effects/bitcrush.vult)). |
| `Delay` | C | A feedback delay line per channel. It reads between samples. |
| `Reverb` | C | Freeverb: eight combs and four allpasses per side. |

## Layout

- **NucleantDSP**: the processors, as `AudioProcessor`s. It re-exports
  AudioProtocols. Its vectors are the standard library's SIMD types
  (`SIMD4<Float>`), the same on every platform, with no simd module.
- **CNucleantDSP**: the processors written in C, and the Vult ones. Swift
  imports only its plain C header (`include/CNucleantDSP.h`), so neither
  NucleantDSP nor anything using it needs C++ interop.

## Demo

[Demo/](Demo) is a polyphonic synth made of these processors, with a
NucleantUI window: eight voices, each three oscillators in a `Mixer`, tuned
in semitones and cents, through either filter, which its own envelope
opens, and an amp envelope; then a drive, the delay and the reverb.

- Its knobs and scope are PyShader shaders (`Demo/Shaders`).
- `Scripts/compile_demo_shaders.py` compiles them to SPIR-V, which is kept
  in the repository, so building the demo needs no shader compiler.

```sh
cd Demo
swift run Synth
```

## Vult

[Vult](https://github.com/vult-dsp/vult) is a language for DSP that
compiles to C++. [Vult/](Vult) holds Vult's own example processors,
unchanged.

- `Scripts/generate_vult.py` compiles them with Vult 0.4.15 into
  `Sources/CNucleantDSP/vult/`, along with Vult's runtime.
- `Sources/CNucleantDSP/vult_api.cpp` wraps that C++ in a C API.
- The generated code is kept in the repository, so building NucleantDSP
  needs no Vult compiler.

The examples are tuned for 44.1 kHz. The filters take their cutoff in
hertz, and the Swift side works out the Vult control value that puts the
cutoff there at the output's actual rate.

## Licenses

- NucleantDSP: see [LICENSE](LICENSE).
- The Vult examples, the code generated from them, and Vult's runtime: MIT,
  Copyright (c) Leonardo Laguna Ruiz ([Vult/LICENSE](Vult/LICENSE)).
- `Reverb` follows Jezar at Dreampoint's Freeverb, which is public domain.
