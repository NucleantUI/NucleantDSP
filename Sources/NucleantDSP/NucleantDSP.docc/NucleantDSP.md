# ``NucleantDSP``

Audio processors in Swift, C and Vult: oscillators, an envelope, filters, waveshapers, a delay and a reverb, played on every platform through NucleantAudio.

@Metadata {
    @CallToAction(url: "/NucleantDSP/synth/", purpose: link, label: "Play the synth in your browser")
    @PageImage(purpose: card, source: "synth", alt: "The demo synth: three oscillators beside a scope, then glowing knobs for the filter, its envelope, the amp envelope, drive, delay and reverb, and a two-octave keyboard.")
}

## Overview

@Image(source: "synth", alt: "The demo synth: three oscillators beside a scope, then glowing knobs for the filter, its envelope, the amp envelope, drive, delay and reverb, and a two-octave keyboard.")

Every processor here is an `AudioProcessor`, the protocol from NucleantAudio's
AudioProtocols that NucleantAudio's `AudioPlayer` runs on the audio thread of
macOS, iOS, Linux, Android and the browser. NucleantDSP depends on
AudioProtocols alone, never on a platform, so what you build from its
processors plays wherever NucleantAudio does.

```swift
import NucleantAudio
import NucleantDSP

var voice = Oscillator(.sawtooth, frequency: 110, amplitude: 0.3)
    .then(LadderFilter(cutoff: 800, resonance: 0.5))
    .then(Envelope(attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.5))
    .then(Reverb(roomSize: 0.7, mix: 0.25))
voice.first.second.open()

let player = try AudioPlayer(voice, channels: 2)
try player.start()
```

The processors are written three ways, and you use them all the same way:

- **Swift**: ``Oscillator``, ``Envelope``, ``Gain``, ``Biquad``, ``Mixer`` and
  ``Then``.
  ``Gain`` and ``Biquad`` work on four samples or channels at a time as one
  `SIMD4<Float>`.
- **C**: ``Delay`` and ``Reverb``, a Freeverb.
- **Vult**: ``StateVariableFilter``, ``LadderFilter``, ``SoftSaturation``,
  ``CubicClipper``, ``Wavefolder`` and ``Bitcrusher``. They are Vult's own
  example processors, compiled to C++ and called through a C API. See
  <doc:VultProcessors>.

The <doc:SynthDemo> puts every one of them in a polyphonic synth that runs in
your browser.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:SynthDemo>
- ``AudioProcessor``

### Making sound

- ``Oscillator``
- ``Envelope``

### Filters

- ``Biquad``
- ``StateVariableFilter``
- ``LadderFilter``

### Shaping

- ``SoftSaturation``
- ``CubicClipper``
- ``Wavefolder``
- ``Bitcrusher``

### Time and space

- ``Delay``
- ``Reverb``

### Level and routing

- ``Gain``
- ``Mixer``
- ``Then``

### Behind the processors

- <doc:VultProcessors>
