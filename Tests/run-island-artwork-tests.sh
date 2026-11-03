#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_ROOT="${AIRISLAND_ARTWORK_CHECK_ROOT:-$PROJECT_ROOT/build/checks/artwork-render-tests}"
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
# Let the fixture publish real track changes without starting a media provider.
s = p.read_text()
for field in ['albumArtTrackIdentifier', 'albumArtFlipDirection', 'isChangingTrack']:
    s = s.replace('@Published private(set) var ' + field, '@Published var ' + field)
s = s.replace('private func updateFromPlaybackState(', 'func updateFromPlaybackState(')
p.write_text(s)
p = check / 'AirIsland/components/Notch/ActivityPagesView.swift'
s = p.read_text()
token = 'TimerDurationForm(start: startTimer)'
assert token in s
s = s.replace(token, token + '.onAppear { IslandArtworkRenderProbe.startTimer = startTimer }')
token = '.buttonStyle(IslandActionButtonStyle(tint: tint, iconOnly: true))'
assert token in s
p.write_text(s.replace(token, token + '''.onAppear {
                IslandArtworkRenderProbe.actionHandlers[icon] = action
            }.background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        IslandArtworkRenderProbe.actionFrames[icon] = frame
                    }
                }
            }'''))
p = check / 'AirIsland/Presentation/IslandBackdrop.swift'
s = p.read_text()
p.write_text(s.replace('.clipped()', '''.clipped().background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                    IslandArtworkRenderProbe.musicBackgroundFrame = frame
                }
            }
        }'''))
p = check / 'AirIsland/managers/RemindersActivityManager.swift'
s = p.read_text(); start = s.index('    private init() {'); end = s.index('\n    func connect()', start)
s = s[:start] + '    private init() {}\n' + s[end:]
p.write_text(s.replace('@Published private(set)', '@Published'))
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
p = check / 'AirIsland/ContentView.swift'
s = p.read_text()
token = '.onChange(of: vm.notchState)'
assert token in s
s = s.replace(token, '''.onAppear {
                        IslandArtworkRenderProbe.selectPage = selectPage
                        IslandArtworkRenderProbe.horizontalGesture = handleHorizontalGesture
                    }
                    .onChange(of: pager.selection, initial: true) { _, page in
                        IslandArtworkRenderProbe.selectedPage = page
                    }
                    ''' + token)
token = '.clipShape(NotchShape(topCornerRadius: top, bottomCornerRadius: bottom))'
assert token in s
s = s.replace(token, '''.background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, size in
                        IslandArtworkRenderProbe.surfaceSize = size
                    }
                .onChange(of: pagePosition, initial: true) { _, position in
                    IslandArtworkRenderProbe.renderedPagePosition = position
                }
                }
            }
            ''' + token)
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
"$CHECK_DERIVED_DATA/Build/Products/Release/AirIsland.app/Contents/MacOS/AirIsland" "$CHECK_ROOT/frames" "$@"
