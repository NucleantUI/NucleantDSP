"""An oscilloscope: the synth's latest samples, as they are, drawn as a line
of light from one to the next.

Each sample is a point, left to right across the view, its value up from the
middle; a pixel lights by its distance to the nearest of the line's segments.
Only the segments within a couple of pixels' reach of its column are
measured.
"""
from pyshader import *
from pyshader.stdlib.fragment import sdf, light


class Sample:
    value: float


BACKGROUND = float3(0.035, 0.038, 0.047)
GRID = float3(0.09, 0.1, 0.12)
TRACE = float3(0.15, 0.85, 1.0)
HEIGHT = 0.45   # a full-scale sample reaches this far from the middle
# How many samples the app hands it (SynthModel.scopeLength). Not
# len(samples): that counts the whole buffer bound, which can be longer than
# what was written into it.
COUNT = 1024


def point(samples: list[Sample], i: int, resolution: float2) -> float2:
    """Sample i, in pixels."""
    x = float(i) / float(COUNT - 1) * resolution.x
    y = (0.5 + HEIGHT * clamp(samples[i].value, -1.0, 1.0)) * resolution.y
    return float2(x, y)


def main(frag_coord: float2, resolution: float2, samples: list[Sample]) -> float4:
    # The middle line and a line at half scale either side.
    middle = abs(frag_coord.y - 0.5 * resolution.y)
    half = abs(abs(frag_coord.y - 0.5 * resolution.y) - 0.5 * HEIGHT * resolution.y)
    c = BACKGROUND
    c = mix(c, GRID, 1.0 - smoothstep(0.0, 1.0, middle))
    c = mix(c, GRID * 0.7, 1.0 - smoothstep(0.0, 1.0, half))

    n = COUNT

    # The samples per pixel, and the ones whose segments can reach this one.
    per_pixel = float(n - 1) / resolution.x
    reach = 3.0 * max(per_pixel, 1.0)
    first = clamp(int(floor(frag_coord.x * per_pixel - reach)), 0, n - 2)
    last = clamp(int(ceil(frag_coord.x * per_pixel + reach)), 0, n - 2)
    d = 1.0e6
    for i in range(first, last + 1):
        d = min(d, sdf.sd_segment(frag_coord, point(samples, i, resolution), point(samples, i + 1, resolution)))

    c += light.tonemap_exposure(light.neon(d, TRACE, 1.2, 6.0), 1.2)
    return float4(c, 1.0)
