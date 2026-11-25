# The Vult processors

How the filters and shapers written in Vult become Swift processors, with no C++ interop.

## Overview

[Vult](https://github.com/vult-dsp/vult) is a language for DSP that compiles
to C++. Six of NucleantDSP's processors are Vult's own example processors,
unchanged, from the repository's `Vult` folder:

| Processor | Vult source |
|---|---|
| ``StateVariableFilter`` | `filters/svf.vult` |
| ``LadderFilter`` | `filters/ladder.vult` |
| ``SoftSaturation`` | `effects/saturate_soft.vult` |
| ``CubicClipper`` | `effects/clipper.vult` |
| ``Wavefolder`` | `effects/fold.vult` |
| ``Bitcrusher`` | `effects/bitcrush.vult` |

## From Vult to Swift

`Scripts/generate_vult.py` compiles them, with Vult 0.4.15, into one C++
file. Compiling them together means what they share (Vult's `Util`) is
defined once. The script also fetches Vult's runtime.

That C++ is never seen by Swift. A small C++ file, `vult_api.cpp`, puts a C
API around it: opaque state per channel, created, copied and destroyed, and
a function that processes a whole buffer. Swift imports only that API's
plain C header. So neither NucleantDSP nor anything that uses it needs
Swift's C++ interop.

The generated code is kept in the repository, so building NucleantDSP needs
no Vult compiler.

## Tuned for 44.1 kHz

Vult's examples take a filter's cutoff as a control value on Vult's pitch
scale, worked out for 44.1 kHz. NucleantDSP's filters take the cutoff in
hertz and work out the control value that puts the cutoff there at the
output's actual rate, so a 1 kHz cutoff is 1 kHz at 44.1, 48 and 96 kHz.

The soft saturation's lookup table covers −24 to 24. Past its ends Vult
carries the last segment's curve on, so ``SoftSaturation`` holds its input
within that range first.
