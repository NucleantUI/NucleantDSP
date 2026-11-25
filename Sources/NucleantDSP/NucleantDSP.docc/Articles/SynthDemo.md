# The synth

A polyphonic synth made of NucleantDSP's processors, with knobs and a scope drawn by PyShader.

@Metadata {
    @CallToAction(url: "/NucleantDSP/synth/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "synth", alt: "The demo synth: a scope, panels of glowing knobs, and a two-octave keyboard.")
}

## Overview

@Image(source: "synth", alt: "The demo synth: three oscillators beside a scope, then glowing knobs for the filter, its envelope, the amp envelope, drive, delay and reverb, and a two-octave keyboard.")

The button above opens it in your browser. It is the same Swift that runs as
a window on macOS: built for WebAssembly, drawn with WebGPU, and played
through Web Audio. You need a browser with WebGPU: Chrome or Edge 113 or
later, Safari 26, or Firefox 141 on Windows.

Click a key, or play from your computer's keyboard. The row from A to ' is
the white keys, the row above it the black ones, and Z and X shift the
octave. A browser keeps a page silent until it has been clicked or a key
pressed, so the first note is also what starts the sound. On a touch screen,
every finger plays its own note.

The presets show what the parts do together: a bass through the ladder
filter and the cubic clipper, a lead through the state variable filter into
a delay, a slow pad in a large reverb, a pluck, bells folded by the wave
folder, a square wave through the bit crusher, two supersaws through the
Moog ladder (Trance), a narrow pulse through the three-pole filter (Acid),
and the formant filter swept from vowel to vowel (Vowels).

The oscillators and the scope are always in view; the rest is on tabs: the
filter and the envelopes; the drive, the EQ and the output; the delay and
the reverb.

## How it is made

The demo is a package of its own in the repository's `Demo` folder:

```sh
cd Demo
swift run Synth
```

**The sound** (`Engine.swift`) is one `AudioProcessor` that the app's
`AudioPlayer` runs:

- Eight voices. Each is three oscillators mixed by a ``Mixer``, into one of
  fourteen filters, into an ``Envelope`` for its level: the amp envelope.
- Every oscillator has its own wave, its tuning from the note in semitones
  and then cents (the fine tune), and its level in the mix. Two sawtooths a
  few cents apart beat against each other; a third an octave down fills out
  the bottom. The wave is one of ``Oscillator``'s four, a
  ``PulseOscillator`` or a ``Supersaw``: its Shape knob narrows the pulse,
  from a square at 0 to a 5% pulse, or turns up the supersaw's detune and,
  with it, its mix.
- The filter is one of the state variable filter's four outputs, Vult's
  ladder, ``MoogLadder``, ``ThreePoleLowPass``, ``FormantFilter``, or a
  low-pass from ``Butterworth``, ``ChebyshevI``, ``ChebyshevII``,
  ``Elliptic``, ``Bessel`` or ``Legendre``. Its second knob is what that
  filter has: a resonance, an order (two to eight poles), a ripple or a
  stop band. The formant filter's vowel follows the cutoff, so its envelope
  moves it from vowel to vowel.
- The filter has an ``Envelope`` of its own. It runs over a block of ones,
  so what it leaves is its own curve. A voice renders 64 samples at a time,
  and between blocks the filter envelope's level opens the filter by up to
  five octaves.
- The voices are summed, then go through the chosen shaper
  (``SoftSaturation``, ``CubicClipper``, ``Wavefolder`` or ``Bitcrusher``),
  each ``Oversampled`` four times over, a ``DCBlocker``, a
  ``ThreeBandEqualizer`` and a ``TiltEqualizer``, a ``Delay``, a ``Reverb``,
  a ``LinkwitzRiley`` high-pass for the low cut, and a ``Gain``.
- A key steals the oldest voice when all eight are busy.

**The model** (`Model.swift`) is an `@Observable` class. A change to a
setting goes to the engine through `withProcessor`. Thirty times a second it
reads back the latest samples for the scope and how many voices are
sounding.

**The tabs** (`TabView.swift`) are a view of the demo's own: a row of tab
labels over the chosen page, which the view keeps in its `@State`. A click
on a label shows its page.

**The knobs and the scope** are PyShader shaders (`Shaders/`), compiled to
SPIR-V and drawn by NucleantUI's `Shader` view:

- The knob is the first kind on PyShader's
  [Knobs, encoders & sliders](https://nucleantui.github.io/PyShader/stdlib/encoders-sliders/)
  page: a black cap inside a ring of light up to its value, built from the
  standard library's `sdf` and `light`.
- The scope is handed the latest samples as they are. Each pixel lights by
  its distance to the line from one sample to the next.
