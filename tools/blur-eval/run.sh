#!/usr/bin/env bash
# Builds the app's real Swift sources on macOS and runs the blur evaluation harness.
# Usage: tools/blur-eval/run.sh metric|evaluate|oracle <image>... [--noise S] [--cases A/L,...] [--verbose]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
modules="$here/../../App/ios/ComputationalPortraitApp/Modules"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -O -o "$out/eval" "$here/main.swift" \
  "$modules/ImagingIO.swift" "$modules/SharpnessMetric.swift" "$modules/BlurDeconvolution.swift"
"$out/eval" "$@"
