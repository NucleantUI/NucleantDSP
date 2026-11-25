# Filters and where they come from

Which filter to reach for, and the code or paper each one follows.

## Overview

NucleantDSP's filters fall into three groups: classic designs of any order,
worked out from their poles and zeros; models of analog synth filters; and
small, single-purpose filters from the [musicdsp.org](https://www.musicdsp.org)
archive. All of them are `AudioProcessor`s and chain like the rest.

## Designed filters

``Butterworth``, ``ChebyshevI``, ``ChebyshevII``, ``Elliptic``, ``Bessel``
and ``Legendre`` are rewritten in Swift from Vinnie Falco's
[DSPFilters](https://github.com/vinniefalco/DSPFilters) (MIT). Each takes an
order from 1 to 16 and a response:

| Design | At its frequency | Character | Responses |
|---|---|---|---|
| ``Butterworth`` | −3 dB | As flat as can be where it passes | Low, high, band-pass, band-stop, low, high and band shelf |
| ``ChebyshevI`` | Down by `ripple` | Steeper, for a ripple where it passes | The same seven |
| ``ChebyshevII`` | Down by `stopBand` | Flat where it passes; zeros hold the stop band down | The same seven |
| ``Elliptic`` | Down by `ripple` | The steepest for its order; ripple on both sides | Low, high, band-pass, band-stop |
| ``Bessel`` | Near full; −3 dB above it | The flattest delay: a step barely overshoots | Low, high, band-pass, band-stop, low shelf |
| ``Legendre`` | −3 dB | The steepest that never ripples | Low, high, band-pass, band-stop |

Each is designed the way DSPFilters does it: an analog prototype's poles and
zeros in the s plane, moved to the z plane by the bilinear transform (with
a further transform for a band), then run as second-order sections one
after another. The Bessel and Legendre poles are found numerically, by
Laguerre's method; the elliptic zeros come from the Jacobi elliptic
function sn. The sections run in Double, four channels to a vector, so a
high order or a low cutoff stays clean.

A change of frequency is designed again on the audio thread, at the next
buffer, into room made when the filter is made: once it has run, it does
not allocate, so an envelope can sweep any of them. The prototypes of the
Bessel, Legendre and elliptic filters, the costly part, are only made again
when their order or shape changes.

``Biquad`` is DSPFilters' other half, Robert Bristow-Johnson's cookbook, as a
single second-order section.

## Synth filters

- ``MoogLadder``: Antti Huovilainen's non-linear model of the Moog ladder
  (DAFx 2004), with the tuning and resonance corrections of Victor
  Lazzarini's Csound version. It needs twice the output's rate, and runs
  there.
- ``ThreePoleLowPass``: Josep M. Comajuncosas' resonant 18 dB/octave
  low-pass with tanh in its feedback and on its output.
- ``FormantFilter``: Alex's vowel filter: A, E, I, O and U as tenth-order
  all-pole filters, crossfaded between.
- ``LadderFilter`` and ``StateVariableFilter``: Vult's examples
  (<doc:VultProcessors>).

## Utility filters

- ``LinkwitzRiley``: a crossover's two halves, which add back up to the
  signal.
- ``DCBlocker``: takes an offset away.
- ``ThreeBandEqualizer`` and ``TiltEqualizer``: a mixer channel's EQ, and
  one knob for the tone.

## Oversampling

Anything that adds harmonics, a waveshaper or a saturating filter, adds
some above the output's Nyquist frequency, and those fold back as tones of
their own. ``Oversampled`` runs a processor at 2, 4, 8 or 16 times the
output's rate and filters them out on the way down:

```swift
var drive = Wavefolder(level: 0.8).oversampled(4)
```

Each doubling is a polyphase half-band filter of two allpass chains (after
Dave Waugh's at musicdsp.org, and Laurent de Soras' HIIR): flat to 0.48 of
the lower rate and 104 dB down from 0.52 of it. ``MoogLadder`` and
``Supersaw`` use the same filter to run at twice the rate on their own.
