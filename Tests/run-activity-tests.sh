#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/airisland-activity-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
TEST_FRAMEWORKS="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
TEST_LIBRARIES="$(xcrun --show-sdk-platform-path)/Developer/usr/lib"
SHARED_FRAMEWORKS="$(xcode-select -p)/../SharedFrameworks"

xcrun swiftc -swift-version 5 -parse-as-library \
  -F "$TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
  -I "$TEST_LIBRARIES" -L "$TEST_LIBRARIES" -Xlinker -rpath -Xlinker "$TEST_LIBRARIES" \
  -Xlinker -rpath -Xlinker "$SHARED_FRAMEWORKS" \
  "$PROJECT_ROOT/AirIsland/Activities/IslandActivity.swift" \
  "$PROJECT_ROOT/AirIsland/Activities/PersonalActivities.swift" \
  "$PROJECT_ROOT/AirIsland/Presentation/IslandPager.swift" \
  "$PROJECT_ROOT/AirIsland/Scheduling/ActivityScheduler.swift" \
  "$PROJECT_ROOT/AirIsland/Presentation/IslandPresentation.swift" \
  "$PROJECT_ROOT/Tests/ActivitySchedulerTests.swift" \
  "$PROJECT_ROOT/Tests/PersonalActivityTests.swift" \
  -o "$TEST_OUTPUT/ActivityTests"
"$TEST_OUTPUT/ActivityTests"
