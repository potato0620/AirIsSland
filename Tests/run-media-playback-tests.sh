#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-playback-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
TEST_FRAMEWORKS="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
TEST_LIBRARIES="$(xcrun --show-sdk-platform-path)/Developer/usr/lib"
SHARED_FRAMEWORKS="$(xcode-select -p)/../SharedFrameworks"

xcrun swiftc -swift-version 5 -parse-as-library \
  -F "$TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
  -I "$TEST_LIBRARIES" -L "$TEST_LIBRARIES" -Xlinker -rpath -Xlinker "$TEST_LIBRARIES" \
  -Xlinker -rpath -Xlinker "$SHARED_FRAMEWORKS" \
  "$PROJECT_ROOT/boringNotch/models/PlaybackState.swift" \
  "$PROJECT_ROOT/boringNotch/models/AlbumArtworkTransition.swift" \
  "$PROJECT_ROOT/boringNotch/models/NetEaseTrackMetadata.swift" \
  "$PROJECT_ROOT/boringNotch/MediaControllers/NowPlayingStream.swift" \
  "$PROJECT_ROOT/Tests/MediaPlaybackTests.swift" \
  -o "$TEST_OUTPUT/MediaPlaybackTests"
"$TEST_OUTPUT/MediaPlaybackTests"
