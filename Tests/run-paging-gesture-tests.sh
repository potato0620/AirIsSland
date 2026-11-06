#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/airisland-paging-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_ROOT/AirIsland/extensions/HorizontalPagingGesture.swift" \
  "$PROJECT_ROOT/Tests/HorizontalPagingGestureTests.swift" \
  -o "$TEST_OUTPUT/HorizontalPagingGestureTests"
"$TEST_OUTPUT/HorizontalPagingGestureTests"
