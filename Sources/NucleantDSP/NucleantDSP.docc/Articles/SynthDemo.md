# The synth

A polyphonic synth made of NucleantDSP's processors, with knobs and a scope drawn by PyShader.

@Metadata {
    @CallToAction(url: "/NucleantDSP/synth/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "synth", alt: "The demo synth: a scope, panels of glowing knobs, and a two-octave keyboard.")
}

## Overview

@Image(source: "synth", alt: "The demo synth: a scope, panels of glowing knobs for three oscillators, the filter, envelope, drive, delay and reverb, and a two-octave keyboard.")

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
folder, and a square wave through the bit crusher.

## How it is made

The demo is a package of its own in the repository's `Demo` folder:

```sh
cd Demo
swift run Synth
```

**The sound** (`Engine.swift`) is one `AudioProcessor` that the app's
`AudioPlayer` runs:

- Eight voices. Each is three ``Oscillator``s mixed by a ``Mixer``, into a
  ``StateVariableFilter`` or a ``LadderFilter``, into an ``Envelope``.
- Every oscillator has its own waveform, its tuning from the note in
  semitones and then cents (the fine tune), and its level in the mix. Two
  sawtooths a few cents apart beat against each other; a third an octave
  down fills out the bottom.
- A voice renders 64 samples at a time, and between blocks the envelope's
  level opens the filter by up to five octaves.
- The voices are summed, then go through the chosen shaper
  (``SoftSaturation``, ``CubicClipper``, ``Wavefolder`` or ``Bitcrusher``),
  a ``Delay``, a ``Reverb`` and a ``Gain``.
- A key steals the oldest voice when all eight are busy.

**The model** (`Model.swift`) is an `@Observable` class. A change to a
setting goes to the engine through `withProcessor`. Thirty times a second it
reads back the latest samples for the scope and how many voices are
sounding.

**The knobs and the scope** are PyShader shaders (`Shaders/`), compiled to
SPIR-V and drawn by NucleantUI's `Shader` view:

- The knob is the first kind on PyShader's
  [Knobs, encoders & sliders](https://nucleantui.github.io/PyShader/stdlib/encoders-sliders/)
  page: a black cap inside a ring of light up to its value, built from the
  standard library's `sdf` and `light`.
- The scope is handed the latest samples as they are. Each pixel lights by
  its distance to the line from one sample to the next.
