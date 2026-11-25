# Getting started

Add NucleantDSP, play a processor, chain several, and change them while they play.

## Add the package

NucleantDSP makes the sound; NucleantAudio plays it. Depend on both:

```swift
dependencies: [
    .package(url: "https://github.com/NucleantUI/NucleantDSP.git", .upToNextMinor(from: "0.0.0")),
    .package(url: "https://github.com/NucleantUI/NucleantAudio.git", .upToNextMinor(from: "0.0.0")),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "NucleantDSP", package: "NucleantDSP"),
            .product(name: "NucleantAudio", package: "NucleantAudio"),
        ]
    ),
]
```

## Play a processor

An `AudioPlayer` runs one `AudioProcessor`, asking it for a buffer of
samples at a time on the audio thread. An ``Oscillator`` fills the buffer
with a tone:

```swift
import NucleantAudio
import NucleantDSP

let player = try AudioPlayer(Oscillator(.sine, frequency: 440, amplitude: 0.2), channels: 2)
try player.start()
```

In a browser the page stays silent until it is clicked or a key is pressed;
the player starts then on its own.

## Chain processors

``Then`` runs one processor after another on the same buffer, and
`then(_:)` builds it. The first fills the buffer, and each one after it
changes what is there:

```swift
let voice = Oscillator(.sawtooth, frequency: 110, amplitude: 0.3)
    .then(StateVariableFilter(.lowPass, cutoff: 600, resonance: 1))
    .then(SoftSaturation(drive: 4))
    .then(Delay(time: 0.3, feedback: 0.4, mix: 0.3))
```

Every processor in the chain stays reachable by its place in it:
`voice.first.first.second` is the filter above.

## Mix processors

``Mixer`` plays several processors of one kind side by side. Each is handed
the buffer as it came, and what they leave is added together, each at its
own level: oscillators are mixed, and filters or effects run in parallel on
the same sound.

```swift
let oscillators = Mixer([
    Oscillator(.sawtooth, frequency: 110),
    Oscillator(.sawtooth, frequency: 110.64),  // 10 cents up
    Oscillator(.square, frequency: 55),        // an octave down
], levels: [0.3, 0.3, 0.2])
```

A change of level, such as `oscillators.inputs[2].level = 0.4`, is spread
over the next buffer, so it does not click.

## Change it while it plays

`withProcessor` hands you the player's processor between two buffers, so a
change never lands halfway through one:

```swift
player.withProcessor { voice in
    voice.first.first.second.cutoff = 1_200
}
```

An ``Envelope`` shapes a note: `open()` starts it, `close()` lets it go.

```swift
let player = try AudioPlayer(
    Oscillator(.square, frequency: 220, amplitude: 0.2)
        .then(Envelope(attack: 0.01, decay: 0.2, sustain: 0.5, release: 0.4)),
    channels: 2
)
try player.start()
player.withProcessor { $0.second.open() }   // key down
player.withProcessor { $0.second.close() }  // key up
```

## Write your own

A processor is any `Sendable` type with one method. It is handed the
buffer, interleaved, as a `MutableSpan<Float>`:

```swift
struct Tremolo: AudioProcessor {
    var rate = 5.0
    var depth: Float = 0.5
    private var phase = 0.0

    mutating func process(into buffer: inout MutableSpan<Float>, channels: Int, sampleRate: Double) {
        for frame in 0..<(buffer.count / channels) {
            let level = 1 - depth * Float(0.5 + 0.5 * sin(2 * .pi * phase))
            for channel in 0..<channels { buffer[frame * channels + channel] *= level }
            phase = (phase + rate / sampleRate).truncatingRemainder(dividingBy: 1)
        }
    }
}
```

It chains with the rest: `Oscillator(frequency: 220).then(Tremolo())`.

A processor is a value, and the ones built on C state copy it before a
change while another copy shares it. So a copy of a processor carries on
from the same state, on its own.
