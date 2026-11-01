#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/airisland-transition-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_ROOT/AirIsland/animations/drop.swift" \
  "$PROJECT_ROOT/AirIsland/Presentation/IslandBackdrop.swift" \
  "$PROJECT_ROOT/AirIsland/components/Notch/NotchShape.swift" \
  "$PROJECT_ROOT/Tests/IslandTransitionRenderTests.swift" \
  -o "$TEST_OUTPUT/IslandTransitionRenderTests"
"$TEST_OUTPUT/IslandTransitionRenderTests" "$@"
