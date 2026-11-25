#!/bin/bash
# Builds the documentation site for GitHub Pages: the DocC catalog in
# Sources/NucleantDSP/NucleantDSP.docc with NucleantDSP's symbols, and the
# demo synth (Demo/), built for WebAssembly, next to it.
#
#   Scripts/build-docs.sh [output-dir]
#
# Output defaults to .build/docs-site, laid out to be served at
# https://nucleantui.github.io/NucleantDSP/ — the site's root is the
# repository's Pages path. To look at it locally:
#
#   mkdir -p /tmp/pages && ln -sfn "$PWD/.build/docs-site" /tmp/pages/NucleantDSP
#   uv run --no-project python -m http.server -d /tmp/pages 8000
#   open http://localhost:8000/NucleantDSP/
#
# HOSTING_BASE_PATH (default NucleantDSP) is that path. The synth's links in
# NucleantDSP.md and Articles/SynthDemo.md are written against it, so change
# them together. SKIP_SYNTH=1 leaves the synth out.
#
# The synth needs a swift.org toolchain and its matching WebAssembly Swift
# SDK (https://www.swift.org/documentation/articles/wasm-getting-started.html):
# SWIFT_TOOLCHAIN (default 6.3.3) names the toolchain in
# ~/Library/Developer/Toolchains. It is built by NucleantApplication's
# scripts/build_wasm_app.py, from the checkout the demo resolves, and run
# with uv. Its shaders are already compiled (Demo/Sources/Synth/Shaders).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$(mkdir -p "${1:-$ROOT/.build/docs-site}" && cd "${1:-$ROOT/.build/docs-site}" && pwd)"
BASE_PATH="${HOSTING_BASE_PATH:-NucleantDSP}"
CATALOG="$ROOT/Sources/NucleantDSP/NucleantDSP.docc"
GRAPHS="$ROOT/.build/symbol-graphs"
MODULE_GRAPHS="$ROOT/.build/symbol-graphs-NucleantDSP"

# 1. NucleantDSP's symbol graphs: its own, and its extension to
#    AudioProtocols' `AudioProcessor` (`then(_:)`). The flags reach every
#    module the build compiles, so only NucleantDSP's graphs are kept.
echo "Extracting NucleantDSP's symbols…"
rm -rf "$GRAPHS" "$MODULE_GRAPHS"
mkdir -p "$GRAPHS" "$MODULE_GRAPHS"
cd "$ROOT"
swift build --target NucleantDSP \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir -Xswiftc "$GRAPHS" \
    -Xswiftc -symbol-graph-minimum-access-level -Xswiftc public
cp "$GRAPHS"/NucleantDSP.symbols.json "$MODULE_GRAPHS"/
cp "$GRAPHS"/NucleantDSP@*.symbols.json "$MODULE_GRAPHS"/ 2>/dev/null || true

# 2. The catalog, converted for static hosting under /$BASE_PATH/.
echo "Converting the catalog…"
rm -rf "$OUTPUT"
xcrun docc convert "$CATALOG" \
    --fallback-display-name NucleantDSP \
    --fallback-bundle-identifier org.nucleantui.NucleantDSP \
    --additional-symbol-graph-dir "$MODULE_GRAPHS" \
    --transform-for-static-hosting \
    --hosting-base-path "$BASE_PATH" \
    --output-path "$OUTPUT"

# The site's root opens the documentation rather than DocC's empty route.
cat > "$OUTPUT/index.html" <<EOF
<!DOCTYPE html>
<meta charset="utf-8">
<title>NucleantDSP</title>
<meta http-equiv="refresh" content="0; url=/$BASE_PATH/documentation/nucleantdsp/">
<link rel="canonical" href="/$BASE_PATH/documentation/nucleantdsp/">
<a href="/$BASE_PATH/documentation/nucleantdsp/">NucleantDSP documentation</a>
EOF
touch "$OUTPUT/.nojekyll"

# 3. The synth, served at /$BASE_PATH/synth/.
if [ "${SKIP_SYNTH:-0}" != "1" ]; then
    echo "Building the synth for WebAssembly…"
    SWIFT="$HOME/Library/Developer/Toolchains/swift-${SWIFT_TOOLCHAIN:-6.3.3}-RELEASE.xctoolchain/usr/bin/swift"
    DEMO="$ROOT/Demo"
    WASM_SCRATCH="$DEMO/.build/wasm"
    # The checkouts the wasm build uses, so the build script and the page
    # runtime come from the NucleantApplication the demo resolves.
    WASM_BUILD=1 "$SWIFT" package resolve --package-path "$DEMO" --scratch-path "$WASM_SCRATCH"
    uv run --no-project python "$WASM_SCRATCH/checkouts/NucleantApplication/scripts/build_wasm_app.py" \
        Synth --package-path "$DEMO" --release --output "$OUTPUT/synth"
    # GitHub Pages serves .wasm uncompressed; the page runtime inflates a
    # module whose URL ends in .gz.
    gzip -9 -f "$OUTPUT/synth/Synth.wasm"
    sed -i '' 's|\./Synth\.wasm|./Synth.wasm.gz|' "$OUTPUT/synth/index.html"
fi

echo "Documentation site: $OUTPUT"
