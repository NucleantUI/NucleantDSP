# NucleantDSP

Audio processors for Swift: oscillators, an envelope, filters and equalizers,
waveshapers, oversampling, a delay and a reverb. Each one is an `AudioProcessor` from
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
| `PulseOscillator` | Swift | A pulse whose width can move while it plays: two PolyBLEP sawtooths, one shifted ([musicdsp](https://www.musicdsp.org/en/latest/Synthesis/8-pulsewidth-modulation.html)). |
| `Supersaw` | Swift | The JP-8000's seven detuned sawtooths, run at twice the output's rate ([atosynth](https://atosynth.blogspot.com/2026/02/the-super-saw-code.html)). |
| `Envelope` | Swift | ADSR, applied to the buffer: `open()` starts a note, `close()` lets it go. |
| `Gain` | Swift, SIMD | A level or decibels, with changes smoothed over 5 ms. |
| `Biquad` | Swift, SIMD | Bristow-Johnson's cookbook filters: low-, high-, band- and all-pass, notch, peak, and low and high shelves. Four channels per vector. |
| `Butterworth`, `ChebyshevI`, `ChebyshevII`, `Elliptic`, `Bessel`, `Legendre` | Swift, SIMD | Orders 1 to 16: low-, high- and band-pass, band-stop, and shelves where the design has them. Rewritten from [DSPFilters](https://github.com/vinniefalco/DSPFilters). |
| `MoogLadder` | Swift | Huovilainen's non-linear Moog ladder, at twice the output's rate ([musicdsp](https://www.musicdsp.org/en/latest/Filters/196-moog-filter.html)). |
| `ThreePoleLowPass` | Swift | Comajuncosas' resonant 18 dB/octave low-pass with tanh ([musicdsp](https://www.musicdsp.org/en/latest/Filters/72-18db-oct-resonant-3-pole-lpf-with-tanh-dist.html)). |
| `FormantFilter` | Swift | The vowels A, E, I, O and U, and between them ([musicdsp](https://www.musicdsp.org/en/latest/Filters/110-formant-filter.html)). |
| `LinkwitzRiley` | Swift | A fourth-order crossover's low- or high-pass ([musicdsp](https://www.musicdsp.org/en/latest/Filters/266-4th-order-linkwitz-riley-filters.html)). |
| `DCBlocker` | Swift | Takes away an offset ([musicdsp](https://www.musicdsp.org/en/latest/Filters/135-dc-filter.html)). |
| `ThreeBandEqualizer` | Swift | Lows, mids and highs ([musicdsp](https://www.musicdsp.org/en/latest/Filters/236-3-band-equaliser.html)). |
| `TiltEqualizer` | Swift | One knob tilting the tone ([musicdsp](https://www.musicdsp.org/en/latest/Filters/267-simple-tilt-equalizer.html)). |
| `Oversampled` | Swift | Any processor at 2, 4, 8 or 16 times the output's rate, through polyphase half-band filters ([musicdsp](https://www.musicdsp.org/en/latest/Filters/39-polyphase-filters.html)). |
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
NucleantUI window: eight voices, each three oscillators in a `Mixer` (any
of the waveforms, the pulse or the supersaw), tuned in semitones and cents,
through any of fourteen filters, which its own envelope opens, and an amp
envelope; then an oversampled drive, an EQ, the delay and the reverb, and a
low cut. The panels after the oscillators are on tabs.

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
- The Butterworth, Chebyshev, elliptic, Bessel and Legendre filters are
  rewritten from Vinnie Falco's DSPFilters: MIT, Copyright (c) 2009 by
  Vinnie Falco ([Licenses/DSPFilters.txt](Licenses/DSPFilters.txt)).
- `MoogLadder`, `ThreePoleLowPass`, `FormantFilter`, `LinkwitzRiley`,
  `DCBlocker`, `ThreeBandEqualizer`, `TiltEqualizer`, `PulseOscillator`
  and the half-band filters follow the algorithms their authors published
  at [musicdsp.org](https://www.musicdsp.org); each file names its source.
- `Supersaw` follows the JP-8000's code as read at
  [atosynth](https://atosynth.blogspot.com/2026/02/the-super-saw-code.html),
  and Adam Szabo's high-pass.
- `Reverb` follows Jezar at Dreampoint's Freeverb, which is public domain.
