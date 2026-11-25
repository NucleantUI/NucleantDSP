//
//  ShaderModules.swift
//  Synth
//

import Foundation

/// The demo's PyShader shaders (Demo/Shaders), compiled to SPIR-V by
/// Scripts/compile_demo_shaders.py and kept in the bundle as Shaders/*.spv.
final class ShaderModules: Sendable {
    static let shared = ShaderModules()

    /// A knob: its cap, pointer and ring of light (Shaders/Knob.py).
    let knob: [UInt32]
    /// The oscilloscope (Shaders/Scope.py).
    let scope: [UInt32]

    private init() {
        knob = ShaderModules.load("Knob")
        scope = ShaderModules.load("Scope")
    }

    private static func load(_ name: String) -> [UInt32] {
        // Where the resource bundle is: unpacked by the app where it runs on
        // Android and in a browser (NUCLEANT_APP_PATH), else `Bundle.module`.
        let bundle: URL? = if let root = ProcessInfo.processInfo.environment["NUCLEANT_APP_PATH"] {
            URL(fileURLWithPath: root).appendingPathComponent("NucleantDSPDemo_Synth.resources")
        } else {
            Bundle.module.resourceURL
        }
        guard let url = bundle?.appendingPathComponent("Shaders").appendingPathComponent("\(name).spv"),
              let data = try? Data(contentsOf: url)
        else { fatalError("Shaders/\(name).spv is missing from the bundle; run Scripts/compile_demo_shaders.py") }
        return data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }
}
