//
//  Complex.swift
//  NucleantDSP
//
//  The complex numbers the filter designs work in: poles and zeros in the s
//  and z planes. In Double, where every platform has its math functions.
//
//  Part of the Swift rewrite of Vinnie Falco's DSPFilters (MIT License,
//  Copyright (c) 2009 by Vinnie Falco; Licenses/DSPFilters.txt).
//

import Foundation

struct Complex: Equatable, Sendable {
    var real: Double
    var imaginary: Double

    init(_ real: Double, _ imaginary: Double = 0) {
        self.real = real
        self.imaginary = imaginary
    }

    static let zero = Complex(0)
    /// A pole or zero at infinity: a prototype's zeros, for a low-pass.
    static let infinity = Complex(.infinity)

    var isInfinity: Bool { real == .infinity && imaginary == 0 }

    /// The point `radius` from 0 at `angle` radians.
    init(radius: Double, angle: Double) {
        self.init(radius * cos(angle), radius * sin(angle))
    }

    var conjugate: Complex { Complex(real, -imaginary) }
    /// The squared magnitude.
    var norm: Double { real * real + imaginary * imaginary }
    var magnitude: Double { hypot(real, imaginary) }

    /// The principal square root: its real part is never negative, and its
    /// imaginary part has the sign of this one's, -0 included.
    var squareRoot: Complex {
        let size = magnitude
        let re = sqrt(max((size + real) / 2, 0))
        let im = sqrt(max((size - real) / 2, 0))
        return Complex(re, Double(signOf: imaginary, magnitudeOf: im))
    }

    var isNaN: Bool { real.isNaN || imaginary.isNaN }

    static func + (a: Complex, b: Complex) -> Complex { Complex(a.real + b.real, a.imaginary + b.imaginary) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.real - b.real, a.imaginary - b.imaginary) }
    static prefix func - (a: Complex) -> Complex { Complex(-a.real, -a.imaginary) }

    static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.real * b.real - a.imaginary * b.imaginary, a.real * b.imaginary + a.imaginary * b.real)
    }

    static func * (a: Double, b: Complex) -> Complex { Complex(a * b.real, a * b.imaginary) }

    static func / (a: Complex, b: Complex) -> Complex {
        // Scaled by the larger part of b, so neither part overflows.
        if abs(b.real) >= abs(b.imaginary) {
            let ratio = b.imaginary / b.real
            let divisor = b.real + b.imaginary * ratio
            return Complex((a.real + a.imaginary * ratio) / divisor, (a.imaginary - a.real * ratio) / divisor)
        }
        let ratio = b.real / b.imaginary
        let divisor = b.real * ratio + b.imaginary
        return Complex((a.real * ratio + a.imaginary) / divisor, (a.imaginary * ratio - a.real) / divisor)
    }

    static func / (a: Complex, b: Double) -> Complex { Complex(a.real / b, a.imaginary / b) }
    static func + (a: Complex, b: Double) -> Complex { Complex(a.real + b, a.imaginary) }
    static func + (a: Double, b: Complex) -> Complex { Complex(a + b.real, b.imaginary) }
    static func - (a: Double, b: Complex) -> Complex { Complex(a - b.real, -b.imaginary) }

    static func += (a: inout Complex, b: Complex) { a = a + b }
    static func += (a: inout Complex, b: Double) { a = a + b }
    static func *= (a: inout Complex, b: Complex) { a = a * b }
    static func *= (a: inout Complex, b: Double) { a = b * a }

    /// `self` + `factor`·`other`: DSPFilters' addmul.
    func adding(_ factor: Double, times other: Complex) -> Complex {
        Complex(real + factor * other.real, imaginary + factor * other.imaginary)
    }
}
