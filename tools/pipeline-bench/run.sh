#!/usr/bin/env bash
# Builds the benchmark against the app's real stage code and runs it on macOS.
# Usage: tools/pipeline-bench/run.sh <image>... [--runs N] [--megapixels M]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
modules="$here/../../App/ios/ComputationalPortraitApp/Modules"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/bench" "$here/main.swift" "$modules/ImagingStages.swift" "$modules/ImagingIO.swift"
"$out/bench" "$@"
