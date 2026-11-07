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
p = check / 'AirIsland/components/Live activities/DraggableProgressBar.swift'
s = p.read_text()
token = '.frame(height: isDragging ? 8 : 5)'
assert token in s
p.write_text(s.replace(token, token + '''.background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        IslandArtworkRenderProbe.hudProgressFrame = frame
                    }
                }
            }'''))
p = check / 'AirIsland/components/Notch/ActivityPagesView.swift'
s = p.read_text()
token = 'Text("Timer finished").font(.system(size: 28, weight: .light))'
assert token in s
s = s.replace(token, token + '''.onAppear { IslandArtworkRenderProbe.finishedTimerTexts += 1 }
                        .onDisappear { IslandArtworkRenderProbe.finishedTimerTexts -= 1 }.background {
                            GeometryReader { geometry in
                                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                                    IslandArtworkRenderProbe.finishedTimerTextFrame = frame
                                }
                            }
                        }''')
token = 'TimerDurationForm(duration: $duration)'
assert token in s
s = s.replace(token, token + '.onAppear { IslandArtworkRenderProbe.startTimer = start }')
token = '        Button { action(); IslandHaptics.alignment() } label: {'
assert token in s
s = s.replace(token, '        let _ = IslandArtworkRenderProbe.actionHandlers[icon] = action\n' + token)
token = '.buttonStyle(IslandActionButtonStyle(tint: tint, iconOnly: true))'
assert token in s
p.write_text(s.replace(token, token + '''.onAppear {
                IslandArtworkRenderProbe.actionAppearances[icon, default: 0] += 1
            }.onChange(of: icon, initial: true) { _, _ in
                IslandArtworkRenderProbe.actionHandlers[icon] = action
            }.background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        IslandArtworkRenderProbe.actionFrames[icon] = frame
                    }.onChange(of: icon, initial: true) { _, _ in
                        IslandArtworkRenderProbe.actionFrames[icon] = geometry.frame(in: .global)
                    }
                }
            }'''))
p = check / 'AirIsland/components/Notch/ActivityPagesView.swift'
s = p.read_text()
token = '.frame(height: 23).allowsHitTesting(!completed)'
assert token in s
p.write_text(s.replace(token, token + '''.onChange(of: task, initial: true) { _, _ in
            IslandArtworkRenderProbe.completeReminder[task.id] = finish
            IslandArtworkRenderProbe.editReminder[task.id] = edit
            IslandArtworkRenderProbe.cancelReminder[task.id] = cancel
        }'''))
p = check / 'AirIsland/components/Notch/ActivityPagesView.swift'
s = p.read_text()
token = 'return saved\n                                        }'
assert token in s
s = s.replace(token, token + '''.onChange(of: active, initial: true) { _, _ in
                                            IslandArtworkRenderProbe.editReminder[task.id] = { edit(task) }
                                        }''')
for title, field in [('Complete task', 'reminderCircleFrames'), ('Edit task', 'reminderTitleFrames')]:
    token = '.accessibilityLabel(Text("' + title + ': \\(task.title)"))'
    assert token in s
    s = s.replace(token, token + '''.background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        IslandArtworkRenderProbe.'''+field+'''[task.id] = frame
                    }
                }
            }''')
token = '.onHover { countHovered = $0 }'
assert token in s
s = s.replace(token, token + '''.onAppear {
                        IslandArtworkRenderProbe.hoverReminderCount = { countHovered = $0 }
                    }''')
p.write_text(s)
# Count real view body evaluations for the paging benchmark.
p = check / 'AirIsland/components/Notch/ActivityPagesView.swift'
s = p.read_text()
for type_name, counter in [('ReminderTaskRow', 'reminderRowBodies'), ('RemindersActivityPage', 'reminderPageBodies')]:
    a = s.index('struct ' + type_name + ':')
    b = s.index('    var body: some View {', a) + len('    var body: some View {')
    s = s[:b] + '\n        let _ = { IslandArtworkRenderProbe.' + counter + ' += 1 }()' + s[b:]
p.write_text(s)
# Observe the two persistent creation controls, including their rendered intermediate geometry.
p = check / 'AirIsland/components/Notch/ActivityPagesView.swift'
s = p.read_text()
a = s.index('private struct ReminderCreationControls:')
b = s.index('struct RemindersActivityPage:', a)
controls = s[a:b]
controls = controls.replace('        ZStack(alignment: .trailing) {', '''        let _ = IslandArtworkRenderProbe.creationActions = ["begin": begin, "save": save, "cancel": cancel]
        ZStack(alignment: .trailing) {''', 1)
for token, name in [('.animation(nil) { view in view.opacity(crossOpacity) }', 'trailing'), ('.animation(nil) { view in view.offset(x: -separation) }', 'primary')]:
    assert token in controls
    controls = controls.replace(token, '''.background {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                            IslandArtworkRenderProbe.creationFrames["''' + name + '''"] = frame
                        }
                    }
                }
                ''' + token)
p.write_text(s[:a] + controls + s[b:])
# Keep real local observation/geometry; global desktop input is injected into
# the production receiver so unrelated human clicks cannot cancel an offscreen fixture.
p = check / 'AirIsland/components/Notch/IslandWindow.swift'
s = p.read_text()
a = s.index('            globalMonitor = NSEvent.addGlobalMonitorForEvents')
b = s.index('\n        }', a)
s = s[:a] + '            // Global mouse-down is injected by this isolated fixture.' + s[b:]
token = '        context.coordinator.action = action'
assert token in s
s = s.replace(token, token + '''
        IslandArtworkRenderProbe.outsideEditingFrame = context.coordinator.screenFrame
        IslandArtworkRenderProbe.outsideEditingActive = { context.coordinator.isMonitoring }
        IslandArtworkRenderProbe.outsideEditingLocal = context.coordinator.handleLocalEvent
        IslandArtworkRenderProbe.outsideEditingGlobal = context.coordinator.receive
''', 1)
p.write_text(s)
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
s = s.replace('@Published private(set)', '@Published')
start = s.index('    @discardableResult func add(title: String)')
end = s.index('    @discardableResult func updateTitle(id: String', start)
s = s[:start] + '''    @discardableResult func add(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        IslandArtworkRenderProbe.reminderAdds.append(title)
        guard IslandArtworkRenderProbe.reminderAddSucceeds else { return false }
        ActivityCoordinator.shared.setReminders(ActivityCoordinator.shared.reminders + [
            ReminderTask(id: UUID().uuidString, title: title, dueDate: nil, creationDate: Date())
        ])
        return true
    }
''' + s[end:]

start = s.index('    @discardableResult func updateTitle(id: String')
end = s.index('    @discardableResult func complete(id: String)', start)
s = s[:start] + '''    @discardableResult func updateTitle(id: String, originalTitle: String, title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        IslandArtworkRenderProbe.reminderTitleWrites.append((id, title))
        guard IslandArtworkRenderProbe.reminderTitleWriteSucceeds else {
            errorMessage = "Controlled write failure"
            return false
        }
        guard let task = ActivityCoordinator.shared.reminders.first(where: { $0.id == id }),
              task.title == originalTitle else {
            errorMessage = String(localized: "This reminder changed. Reopen it to edit.")
            return false
        }
        errorMessage = nil
        ActivityCoordinator.shared.setReminders(ActivityCoordinator.shared.reminders.map {
            $0.id == id ? $0.renamed(to: title) : $0
        })
        return true
    }
''' + s[end:]
start = s.index('    @discardableResult func complete(id: String)')
end = s.index('\n    private var canWrite:', start)
s = s[:start] + '''    @discardableResult func complete(id: String) -> Bool {
        IslandArtworkRenderProbe.reminderWrites.append(id)
        guard IslandArtworkRenderProbe.reminderWriteSucceeds else { return false }
        ActivityCoordinator.shared.setReminders(ActivityCoordinator.shared.reminders.filter { $0.id != id })
        return true
    }
''' + s[end:]
p.write_text(s)
p = check / 'AirIsland/managers/MusicSpectrumSource.swift'
s = p.read_text(); start = s.index('    private init() {'); end = s.index('\n    func retry()', start)
p.write_text(s[:start] + '    private init() {}\n' + s[end:])
# Run real input decoding with inert device actions; never install a global tap.
p = check / 'AirIsland/observers/MediaKeyInterceptor.swift'
s = p.read_text().replace('private func handleEvent(', 'func handleEvent(')
a = s.index('        let stepDivisor:', s.index('private func handleKeyPress'))
b = s.index('\n    private func adjustBrightness', a)
s = s[:a] + '''        IslandArtworkRenderProbe.mediaKeys.append("\(keyType.rawValue):\(option && shift ? 4 : 1)")
    }
''' + s[b:]
p.write_text(s)
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
token = 'expansion: vm.notchState == .open ? 1 : 0,'
assert token in s
s = s.replace(token, 'expansion: IslandArtworkRenderProbe.expansionOverride ?? (vm.notchState == .open ? 1 : 0),', 1)
token = '.onChange(of: vm.notchState)'
assert token in s
s = s.replace(token, '''.onAppear {
                        IslandArtworkRenderProbe.selectPage = selectPage
                        IslandArtworkRenderProbe.horizontalGesture = handleHorizontalGesture
                        IslandArtworkRenderProbe.hover = handleHover
                    }
                    .onChange(of: pager.selection, initial: true) { _, page in
                        IslandArtworkRenderProbe.selectedPage = page
                    }
                    .onChange(of: enabledPages, initial: true) { _, pages in
                        IslandArtworkRenderProbe.availablePages = pages
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
p = check / 'AirIsland/components/Settings/SettingsView.swift'
s = p.read_text()
token = '.font(.system(size: 15, weight: .semibold))'
assert token in s
s = s.replace(token, token + '''.background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.frame(in: .named("settingsHeader")), initial: true) { _, frame in
                    IslandArtworkRenderProbe.settingsTitleFrame = frame
                }
            }
        }''')
token = '.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)'
assert token in s
s = s.replace(token, token + '.coordinateSpace(name: "settingsHeader")')
token = '.accessibilityLabel(Text("Back"))'
assert token in s
s = s.replace(token, token + '''.background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.frame(in: .named("settingsHeader")), initial: true) { _, frame in
                    IslandArtworkRenderProbe.settingsBackFrame = frame
                }
            }
        }''')
p.write_text(s)
p = check / 'AirIsland/components/Settings/SettingsWindowController.swift'
p.write_text(p.read_text().replace('private let navigation =', 'let navigation ='))
p = check / 'AirIsland/components/Notch/NotchHomeView.swift'
s = p.read_text(); token = '.onAppear { reset() }'; assert token in s
s = s.replace(token, '.onAppear { IslandArtworkRenderProbe.appearances += 1; reset() }')
token = '.frame(height: 10)\n            .contentShape(Rectangle())'
assert token in s
p.write_text(s.replace(token, '''.frame(height: 10).background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        IslandArtworkRenderProbe.musicProgressFrame = frame
                    }
                }
            }
            .contentShape(Rectangle())'''))
p = check / 'AirIsland/AirIslandApp.swift'
s = p.read_text().replace('@main\nstruct AirIslandApp', 'struct AirIslandApp', 1)
# Exercise production window creation and focus subscription without private-space registration.
s = s.replace('private func createIslandWindow(', 'func createIslandWindow(')
s = s.replace('let window = IslandWindow(contentRect: rect,', 'let window = ReminderFocusTestWindow(contentRect: rect,')
s = s.replace('NotchSpaceManager.shared.notchSpace.windows.insert(window)', '// No private-space registration in the fixture.')
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
