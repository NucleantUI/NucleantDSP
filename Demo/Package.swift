// swift-tools-version: 6.3

import PackageDescription
import Foundation

// NucleantDSP's demo: a synth made of its processors, played through
// NucleantAudio, its window drawn by NucleantUI. NucleantDSP is this
// package's parent; NucleantAudio and NucleantUI are the sibling checkouts
// under `NUCLEANT_LOCAL_DEV=1`, their releases otherwise.
//
//     swift run Synth
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "NucleantDSPDemo",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    dependencies: [
        .package(path: ".."),
        localDev
            ? .package(path: "../../NucleantAudio")
            : .package(url: "https://github.com/NucleantUI/NucleantAudio.git", .upToNextMinor(from: "0.0.0")),
        localDev
            ? .package(path: "../../NucleantUI")
            : .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.3.0")),
    ],
    targets: [
        .executableTarget(
            name: "Synth",
            dependencies: [
                .product(name: "NucleantDSP", package: "NucleantDSP"),
                .product(name: "NucleantAudio", package: "NucleantAudio"),
                .product(name: "NucleantUI", package: "NucleantUI"),
            ],
            // The knob's and the scope's PyShader shaders, compiled to SPIR-V
            // by ../Scripts/compile_demo_shaders.py from Shaders/.
            resources: [.copy("Shaders")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
