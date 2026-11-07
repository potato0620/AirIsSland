#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/airisland-icon-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_ROOT/AirIsland/helpers/AppIcons.swift" \
  "$PROJECT_ROOT/Tests/AppIconTests.swift" -o "$TEST_OUTPUT/AppIconTests"
"$TEST_OUTPUT/AppIconTests"
