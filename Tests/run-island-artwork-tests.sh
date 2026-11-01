#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_ROOT="$PROJECT_ROOT/build/checks/artwork-render-tests"
CHECK_PROJECT="$CHECK_ROOT/project"
CHECK_DERIVED_DATA="${AIRISLAND_DERIVED_DATA:-$CHECK_ROOT/DerivedData}"
mkdir -p "$CHECK_ROOT"
python3 - "$PROJECT_ROOT" "$CHECK_PROJECT" <<'PY'
from pathlib import Path
import re, shutil, sys
root, check = map(Path, sys.argv[1:])
for folder in ['AirIsland', 'AirIsland.xcodeproj', 'AirIslandHelper', 'mediaremote-adapter']:
    shutil.copytree(root / folder, check / folder, dirs_exist_ok=True, ignore=shutil.ignore_patterns('xcuserdata'))
# Keep production views and scheduling. Prevent real provider startup and isolate preference writes
# by using inert source initializers and an independent test bundle identifier below.
p = check / 'AirIsland/managers/MusicManager.swift'
s = p.read_text(); start = s.index('    init() {'); end = s.index('\n    public func destroy()', start)
p.write_text(s[:start] + '    init() {}\n' + s[end:])
p = check / 'AirIsland/IslandWindowCoordinator.swift'
s = p.read_text(); start = s.index('    private init() {')
p.write_text(s[:start] + '    private init() {}\n}\n')
p = check / 'AirIsland/models/IslandViewModel.swift'
p.write_text(p.read_text().replace('        setupDetectorObserver()', '        // No live device observation in the rendering test.'))
for p in (check / 'AirIsland').rglob('*.swift'):
    s = p.read_text()
    s = re.sub(r'@Environment\(\\\.accessibilityReduceMotion\) private var reduceMotion',
               'private var reduceMotion: Bool { IslandArtworkRenderProbe.reduceMotion }', s)
    p.write_text(s)
p = check / 'AirIsland/components/Notch/NotchHomeView.swift'
s = p.read_text(); token = '.onAppear { reset() }'; assert token in s
p.write_text(s.replace(token, '.onAppear { IslandArtworkRenderProbe.appearances += 1; reset() }'))
p = check / 'AirIsland/AirIslandApp.swift'
s = p.read_text().replace('@main\nstruct AirIslandApp', 'struct AirIslandApp', 1)
p.write_text(s + '\n' + (root / 'Tests/IslandArtworkRenderTests.swift').read_text())
PY
ARTWORK_BUILD_ARGS=(-project "$CHECK_PROJECT/AirIsland.xcodeproj" -scheme AirIsland
  -configuration Release -derivedDataPath "$CHECK_DERIVED_DATA")
if [[ -n "${AIRISLAND_SOURCE_PACKAGES:-}" ]]; then
  ARTWORK_BUILD_ARGS+=(-clonedSourcePackagesDirPath "$AIRISLAND_SOURCE_PACKAGES" -disableAutomaticPackageResolution -skipPackageUpdates)
fi
if ! xcodebuild "${ARTWORK_BUILD_ARGS[@]}" \
  build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  PRODUCT_BUNDLE_IDENTIFIER=local.airisland.artworkrendertests CODE_SIGN_ENTITLEMENTS= \
  ENABLE_DEBUG_DYLIB=NO ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES > "$CHECK_ROOT/build.log" 2>&1; then
  tail -80 "$CHECK_ROOT/build.log"
  exit 1
fi
"$CHECK_DERIVED_DATA/Build/Products/Release/AirIsland.app/Contents/MacOS/AirIsland" "$CHECK_ROOT/frames"
