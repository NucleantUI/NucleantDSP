// swift-tools-version: 6.3

import PackageDescription
import Foundation

// NucleantAudio from the sibling checkout under `NUCLEANT_LOCAL_DEV=1`, its
// 0.0 releases otherwise.
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "NucleantDSP",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Audio processors: each an `AudioProcessor` from NucleantAudio's
        // AudioProtocols, so `AudioPlayer` plays them on every platform.
        .library(
            name: "NucleantDSP",
            targets: ["NucleantDSP"]
        ),
    ],
    dependencies: [
        // Only its AudioProtocols product: no platform target of
        // NucleantAudio's is ever built for NucleantDSP.
        localDev
            ? .package(path: "../NucleantAudio")
            : .package(url: "https://github.com/NucleantUI/NucleantAudio.git", .upToNextMinor(from: "0.0.0")),
    ],
    targets: [
        // The processors written in C, and the C API around the ones Vult
        // generates as C++ (vult/, from Scripts/generate_vult.py). Swift
        // imports only include/CNucleantDSP.h, plain C.
        .target(
            name: "CNucleantDSP"
        ),
        .target(
            name: "NucleantDSP",
            dependencies: [
                .product(name: "AudioProtocols", package: "NucleantAudio"),
                "CNucleantDSP",
            ]
        ),
        .testTarget(
            name: "NucleantDSPTests",
            dependencies: ["NucleantDSP"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
