#!/usr/bin/env python3
"""Generate the Vult processors' code in Sources/CNucleantDSP/vult from Vult/.

    uv run Scripts/generate_vult.py

Vult (https://github.com/vult-dsp/vult) writes C++. That output and Vult's
runtime (vultin.h, vultin.cpp) are compiled as they are, and never seen by
Swift: Sources/CNucleantDSP/vult_api.cpp puts a C API around them, and
Swift imports only the C header (include/CNucleantDSP.h). So no C++ interop
is needed in NucleantDSP or in anything that uses it.

The Vult sources in Vult/ are Vult's own examples, unchanged. They are
compiled together into one output, so what they share (Util) is defined
once.

Needs Node.js: the compiler is Vult's npm release, run through npx.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
VULT_SOURCES = PACKAGE_ROOT / "Vult"
OUTPUT_DIR = PACKAGE_ROOT / "Sources" / "CNucleantDSP" / "vult"
OUTPUT = "vult_processors"

VULT_VERSION = "0.4.15"
# The processors, in the order they are generated.
SOURCES = [
    "filters/svf.vult",
    "filters/ladder.vult",
    "effects/saturate_soft.vult",
    "effects/clipper.vult",
    "effects/fold.vult",
    "effects/bitcrush.vult",
]
# Where Vult looks for the modules the processors use (Util, Saturate_soft).
INCLUDES = ["util", "effects"]
# Vult's runtime, from the same release as the compiler.
RUNTIME = ["vultin.h", "vultin.cpp"]
RUNTIME_URL = f"https://raw.githubusercontent.com/vult-dsp/vult/v{VULT_VERSION}/runtime/{{name}}"


def main() -> int:
    npx = shutil.which("npx")
    if npx is None:
        sys.exit("error: npx not found; Vult's compiler runs on Node.js")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    command = [npx, "--yes", f"vult@{VULT_VERSION}", "-ccode", "-real", "float"]
    for include in INCLUDES:
        command += ["-i", include]
    command += [*SOURCES, "-o", str(OUTPUT_DIR / OUTPUT)]
    print("+", " ".join(command[1:]), flush=True)
    result = subprocess.run(command, cwd=VULT_SOURCES, capture_output=True, text=True)
    if result.returncode != 0 or result.stderr.strip():
        sys.exit(f"error: vultc failed:\n{result.stdout}{result.stderr}")

    for name in RUNTIME:
        url = RUNTIME_URL.format(name=name)
        print(f"+ {url}", flush=True)
        with urllib.request.urlopen(url) as response:
            (OUTPUT_DIR / name).write_bytes(response.read())

    for path in sorted(OUTPUT_DIR.iterdir()):
        print(f"  {path.relative_to(PACKAGE_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
