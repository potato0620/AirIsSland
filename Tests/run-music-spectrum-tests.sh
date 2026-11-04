#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/airisland-spectrum-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_ROOT/AirIsland/Activities/MusicSpectrum.swift" \
  "$PROJECT_ROOT/AirIsland/managers/MusicSpectrumAnalyzer.swift" \
  "$PROJECT_ROOT/Tests/MusicSpectrumTests.swift" \
  -o "$TEST_OUTPUT/MusicSpectrumTests"
"$TEST_OUTPUT/MusicSpectrumTests"
