"""A synth knob: a black cap with its pointer, inside a ring of light from
the start of its travel to its value — or, bipolar, from the top either way.

After the knobs on PyShader's "Knobs, encoders & sliders" page: the knob
turns 270°, 135° each way from the top, and value v (0..1) points at
(2v - 1) · 0.75π, measured clockwise from the top.
"""
from pyshader import *
from pyshader.stdlib.fragment import sdf, light
from pyshader.stdlib.fragment.matrix import rotate2d

SWEEP = 0.75 * PI    # 270° of travel: 135° each way from the top
RING = 0.36          # the radius the value ring runs on
CAP = 0.25


class Knob:
    value: float         # 0..1
    bipolar: float       # 1: the ring runs from the top, as for a pan
    tint: float4         # the ring's light
    background: float4   # the panel behind the knob


def ring_piece(p: float2, start: float, end: float, r: float, th: float) -> float:
    """sd_ring from `start` to `end`, radians clockwise from the top."""
    half = max(0.5 * (end - start), 0.0005)
    return sdf.sd_ring(rotate2d(0.5 * (start + end)) * p, float2(cos(half), sin(half)), r, th)


def turn(v: float) -> float:
    """Where value v (0..1) points on the travel."""
    return (2.0 * v - 1.0) * SWEEP


def cap(p: float2, a: float) -> float3:
    """A plain black knob, its pointer at angle a."""
    n = light.bevel_normal(sdf.sd_circle(p, CAP), normalize(p + float2(0.0001)), 0.05)
    l = normalize(float3(-0.4, 0.6, 1.0))
    c = float3(0.035) * (0.3 + 0.7 * light.lambert(n, l)) + float3(0.12) * light.blinn_phong(n, l, 20.0)
    tip = float2(sin(a), cos(a))
    return mix(c, float3(0.8), sdf.fill_smooth(sdf.sd_segment(p, tip * 0.1, tip * 0.19) - 0.01, 0.003))


def main(uv: float2, resolution: float2, knob: Knob) -> float4:
    # The knob in the middle of the view, its square the shorter side.
    side = min(resolution.x, resolution.y)
    p = (uv - 0.5) * resolution / side
    v = clamp(knob.value, 0.0, 1.0)
    a = turn(v)

    groove = float3(0.03) * sdf.fill_smooth(ring_piece(p, -SWEEP, SWEEP, RING, 0.0) - 0.012, 0.002)
    if knob.bipolar > 0.5:
        lit = ring_piece(p, min(a, 0.0), max(a, 0.0), RING, 0.0)
    else:
        lit = ring_piece(p, -SWEEP, a, RING, 0.0)
    glow = light.tonemap_exposure(groove + light.neon(lit, knob.tint.xyz, 0.014, 0.025), 1.4)

    c = knob.background.xyz + glow
    c *= 1.0 - 0.7 * light.drop_shadow(sdf.sd_circle(p - float2(0.02, -0.03), CAP), 0.03)
    c = mix(c, cap(p, a), sdf.fill_smooth(sdf.sd_circle(p, CAP), 0.003))
    return float4(c, 1.0)
