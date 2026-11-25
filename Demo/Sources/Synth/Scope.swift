//
//  Scope.swift
//  Synth
//

import NucleantUI

/// The synth's latest samples, as they are, drawn by Shaders/Scope.py: the
/// shader reads the samples themselves and draws the line between them.
@View
struct Scope {
    let samples: [Float]

    var body: some View {
        Shader(SpirvFunction(spirv: ShaderModules.shared.scope, isAnimated: false) {
            samples
        })
        .frame(maxWidth: .infinity)
    }
}
