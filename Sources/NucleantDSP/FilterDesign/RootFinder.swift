//
//  RootFinder.swift
//  NucleantDSP
//
//  The complex roots of a polynomial, by Laguerre's method: DSPFilters'
//  RootFinder, which the Bessel and Legendre designs find their poles with.
//
//  Part of the Swift rewrite of Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import Foundation

struct RootFinder: Sendable {
    /// The polynomial a[0] + a[1]·x + … + a[degree]·x^degree.
    var coefficients: ContiguousArray<Complex>
    /// Its roots after `solve`, sorted by descending imaginary part.
    private(set) var roots: ContiguousArray<Complex>
    /// The coefficients as each root is divided out.
    private var deflated: ContiguousArray<Complex>

    init(maximumDegree: Int) {
        coefficients = ContiguousArray(repeating: .zero, count: maximumDegree + 1)
        deflated = ContiguousArray(repeating: .zero, count: maximumDegree + 1)
        roots = ContiguousArray(repeating: .zero, count: maximumDegree)
    }

    /// Finds the `degree` roots of `coefficients`, polishes each against the
    /// whole polynomial, and sorts them.
    mutating func solve(degree: Int) {
        let epsilon = 1.0e-30
        for index in 0...degree { deflated[index] = coefficients[index] }
        for index in stride(from: degree - 1, through: 0, by: -1) {
            var x = Complex.zero
            RootFinder.laguerre(degree: index + 1, deflated, &x)
            if abs(x.imaginary) <= 2 * epsilon * abs(x.real) { x = Complex(x.real) }
            roots[index] = x
            // Divide (x − root) out.
            var b = deflated[index + 1]
            for inner in stride(from: index, through: 0, by: -1) {
                let c = deflated[inner]
                deflated[inner] = b
                b = x * b + c
            }
        }
        for index in 0..<degree {
            RootFinder.laguerre(degree: degree, coefficients, &roots[index])
        }
        sort(degree: degree)
    }

    /// The first `degree` roots, by descending imaginary part.
    mutating func sort(degree: Int) {
        guard degree > 1 else { return }
        for index in 1..<degree {
            let x = roots[index]
            var inner = index - 1
            while inner >= 0, roots[inner].imaginary < x.imaginary {
                roots[inner + 1] = roots[inner]
                inner -= 1
            }
            roots[inner + 1] = x
        }
    }

    /// Keeps the roots whose real part is 0 or less, at the front, in the
    /// order they were.
    mutating func keepLeftHalfPlane(of degree: Int) {
        var kept = 0
        for index in 0..<degree where roots[index].real <= 0 {
            roots[kept] = roots[index]
            kept += 1
        }
    }

    /// How far along its step a stalled iteration goes instead, every tenth
    /// one, to break out of a cycle.
    private static let fractions: [Double] = [0, 0.5, 0.25, 0.75, 0.13, 0.38, 0.62, 0.88, 1]

    /// Improves `x` as a root of the polynomial `a` of `degree`.
    private static func laguerre(degree: Int, _ a: ContiguousArray<Complex>, _ x: inout Complex) {
        let steps = 8, every = 10
        let epsilon = Double.ulpOfOne
        let m = degree
        for iteration in 1...(steps * every) {
            var b = a[m]
            var error = b.magnitude
            var d = Complex.zero, f = Complex.zero
            let size = x.magnitude
            for index in stride(from: m - 1, through: 0, by: -1) {
                f = x * f + d
                d = x * d + b
                b = x * b + a[index]
                error = b.magnitude + size * error
            }
            error *= epsilon
            if b.magnitude <= error { return }
            let g = d / b
            let g2 = g * g
            let h = g2 - (2 * f) / b
            let root = (Double(m - 1) * (Double(m) * h - g2)).squareRoot
            var gp = g + root
            let gm = g - root
            let plus = gp.magnitude, minus = gm.magnitude
            if plus < minus { gp = gm }
            let dx = max(plus, minus) > 0
                ? Complex(Double(m)) / gp
                : Complex(radius: 1 + size, angle: Double(iteration))
            let next = x - dx
            if x == next { return }
            if iteration % every != 0 {
                x = next
            } else {
                x = x - RootFinder.fractions[iteration / every] * dx
            }
        }
    }
}
