import AppKit
import AVFoundation
import Defaults
import Carbon
import Darwin
import SwiftUI

// The runner adds an appearance counter to the production artwork in its isolated copy.
func require(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { print("FAIL:", message()); exit(1) }
}

enum IslandArtworkRenderProbe {
    static var outsideEditingFrame: (() -> NSRect?)?
    static var outsideEditingActive: (() -> Bool)?
    static var outsideEditingLocal: ((NSEvent) -> NSEvent?)?
    static var outsideEditingGlobal: ((NSPoint) -> Void)?
    static var reminderPageBodies = 0
    static var reminderRowBodies = 0
    static var appearances = 0
    static var reduceMotion = false
    static var mediaKeys: [String] = []
    static var hudProgressFrame = CGRect.zero
    static var musicProgressFrame = CGRect.zero
    static var finishedTimerTexts = 0
    static var finishedTimerTextFrame = CGRect.zero
    static var surfaceSize = CGSize.zero
    static var musicBackgroundFrame = CGRect.zero
    static var availablePages: [IslandPage] = []
    static var selectedPage = IslandPage.music
    static var renderedPagePosition: CGFloat = 0
    static var expansionOverride: CGFloat?
    static var selectPage: ((IslandPage) -> Void)?
    static var horizontalGesture: ((Double, Double, NSEvent.Phase) -> Void)?
    static var hover: ((Bool) -> Void)?
    static var startTimer: ((TimeInterval) -> Void)?
    static var actionFrames: [String: CGRect] = [:]
    static var actionHandlers: [String: () -> Void] = [:]
    static var actionAppearances: [String: Int] = [:]
    static var completeReminder: [String: () -> Void] = [:]
    static var editReminder: [String: () -> Void] = [:]
    static var cancelReminder: [String: () -> Void] = [:]
    static var reminderCircleFrames: [String: CGRect] = [:]
    static var reminderTitleFrames: [String: CGRect] = [:]
    static var hoverReminderCount: ((Bool) -> Void)?
    static var creationActions: [String: () -> Void] = [:]
    static var creationFrames: [String: CGRect] = [:]
    static var reminderAdds: [String] = []
    static var reminderAddSucceeds = true
    static var reminderTitleWrites: [(String, String)] = []
    static var reminderTitleWriteSucceeds = true
    static var reminderWrites: [String] = []
    static var reminderWriteSucceeds = true
    static var settingsTitleFrame = CGRect.zero
    static var settingsBackFrame = CGRect.zero
}

private struct ActionButtonSizes: PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

// Record the actual AppKit boundary while retaining the production NSPanel behavior.
final class ReminderFocusTestWindow: IslandWindow {
    var onMakeKey: (() -> Void)?
    override func makeKey() {
        onMakeKey?()
        super.makeKey()
    }
}

@main struct IslandArtworkRenderTests {
    struct Frame {
        var islandWidth: CGFloat
        var islandHeight: CGFloat
        var artworkWidth: CGFloat
        var badgeWidth: CGFloat
    }

    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            verifyDefaultActivityPreferences()
            if CommandLine.arguments.contains("--onboarding-only") {
                await verifyOnboarding(output: output)
                exit(0)
            }
            let coordinator = IslandWindowCoordinator.shared
            coordinator.firstLaunch = false
            coordinator.helloAnimationRunning = false
            Defaults[.musicLiveActivityEnabled] = true
            Defaults[.enableSneakPeek] = true
            Defaults[.hudReplacement] = true
            Defaults[.enableShadow] = false
            Defaults[.cornerRadiusScaling] = true
            Defaults[.enableHaptics] = false
            Defaults[.remindersActivityEnabled] = false
            verifyDisplayWidths()
            let music = MusicManager.shared
            music.songTitle = "Deep Green"
            music.artistName = "Christian Kuria"
            music.isPlaying = true
            music.songDuration = 180
            music.usingAppIconForArtwork = false
            music.bundleIdentifier = "com.netease.163music"
            music.albumArt = artwork(size: 200)
            ActivityCoordinator.shared.setMusicActive(true)
            if CommandLine.arguments.contains("--card-expansion-only") {
                await verifyCardExpansion(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--media-keys-only") {
                verifyMediaKeys()
                exit(0)
            }
            if CommandLine.arguments.contains("--hud-width-only") {
                await verifyHUDProgressWidth(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--settings-only") {
                await verifySettingsHeader(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--paging-performance-only") {
                await measurePagingPerformance(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--personal-paging-only") {
                await verifyPersonalPaging(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--spectrum-only") {
                await verifySpectrum(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--music-entry-only") {
                await verifyMusicEntry(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--motion-only") {
                await verifyPersonalMotion(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--pages-only") {
                await verifyEnabledPages(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--navigation-only") {
                IslandArtworkRenderProbe.reduceMotion = true
                await verifyEnabledPages(output: output)
                await verifyResidentSelection(output: output)
                await verifyPersonalActivityRuntime(output: output)
                await verifyActionButtonSizes(output: output)
                await verifyAlarmMotion(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--reminder-focus-only") {
                await verifyReminderEditingFocus(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--reminder-edit-only") {
                await verifyReminderInlineEditing(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--reminders-only") {
                await renderRemindersPage(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--alarm-only") {
                await verifyAlarmMotion(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--compact-only") {
                await verifyCompactAlignment(output: output)
                await verifyWidthAdjustment(output: output)
                await renderSizingSettings(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--personal-only") {
                await verifyPersonalActivityRuntime(output: output)
                await verifyFinishedTimerCollapse(output: output)
                await verifyActionButtonSizes(output: output)
                await verifyAlarmMotion(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--timer-collapse-only") {
                await verifyFinishedTimerCollapse(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--focus-only") {
                await verifyResidentSelection(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--playback-only") {
                await verifyArtworkReadiness()
                await verifySeekingDoesNotAnnounceTrackChanges()
                await verifyTrackSwitchProgress(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--progress-only") {
                await verifyTrackSwitchProgress(output: output)
                exit(0)
            }
            for (index, screen) in NSScreen.screens.enumerated() {
                for lighting in [false, true] {
                    Defaults[.lightingEffect] = lighting
                    await verify(screen: screen, name: "screen\(index)-light\(lighting)", output: output)
                }
            }
            for screen in NSScreen.screens where screen.safeAreaInsets.top == 0 {
                for percent: CGFloat in [5, 10] {
                    Defaults[.nonNotchWidthPercentage] = percent
                    await verify(screen: screen, name: "non-notch-\(Int(percent))-percent", output: output)
                }
            }
            Defaults[.nonNotchWidthPercentage] = NonNotchWidth.defaultPercentage
            await verifyWidthAdjustment(output: output)
            Defaults[.lightingEffect] = false
            await verifyPausedArtwork(output: output)
            await verifyPausedArtwork(output: output, changing: true)
            IslandArtworkRenderProbe.reduceMotion = true
            await verify(screen: NSScreen.screens[0], name: "reduced-motion", output: output)
            await verifyArtworkReadiness()
            await verifySeekingDoesNotAnnounceTrackChanges()
            await verifyTrackSwitchProgress(output: output)
            await verifyMusicEntry(output: output)
            await verifyPersonalPaging(output: output)
            await verifyEnabledPages(output: output)
            await verifyResidentSelection(output: output)
            await verifyPersonalActivityRuntime(output: output)
            await verifyFinishedTimerCollapse(output: output)
            await verifyReminderInlineEditing(output: output)
            await verifyActionButtonSizes(output: output)
            await verifyAlarmMotion(output: output)
            await verifyCompactAlignment(output: output)
            print("PASS: production ContentView, single artwork identity, opaque rounded cover, clear text slots and synchronized geometry")
            exit(0)
        }
        NSApplication.shared.run()
    }

    @MainActor static func verifyReminderInlineEditing(output: URL) async {
        let source = RemindersActivityManager.shared
        let activities = ActivityCoordinator.shared
        let previousPolicy = NSApp.activationPolicy()
        let previousEnabled = Defaults[.remindersActivityEnabled]
        let previousSelection = Defaults[.reminderListIdentifier]
        let previousAuthorization = source.authorized
        NSApp.setActivationPolicy(.regular)
        Defaults[.remindersActivityEnabled] = true
        Defaults[.reminderListIdentifier] = ""
        source.authorized = true
        source.errorMessage = nil
        source.lists = [ReminderList(id: "personal", title: "Personal", account: "", writable: true)]
        TimerActivityManager.shared.cancel()
        activities.setMusicActive(false)
        let first = ReminderTask(id: "edit-first", title: "Buy milk", dueDate: Date(timeIntervalSince1970: 20000),
                                 listIdentifier: "personal", creationDate: Date(timeIntervalSince1970: 10000))
        let second = ReminderTask(id: "edit-second", title: "Book dentist", dueDate: nil,
                                  listIdentifier: "personal", creationDate: Date(timeIntervalSince1970: 10001))
        activities.setReminders([first, second])
        IslandArtworkRenderProbe.reminderWrites = []
        IslandArtworkRenderProbe.reminderTitleWrites = []
        IslandArtworkRenderProbe.reminderTitleWriteSucceeds = true
        let delegate = AppDelegate()
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        vm.hideOnClosed = false
        let window = delegate.createIslandWindow(for: NSScreen.screens[0], with: vm) as! ReminderFocusTestWindow
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        var creationKeyRequests = 0
        window.onMakeKey = { creationKeyRequests += 1 }
        NSApp.activate(ignoringOtherApps: true)
        defer {
            window.orderOut(nil); window.contentView = nil; window.close()
            vm.destroy(); delegate.vm.destroy()
            source.authorized = previousAuthorization; source.errorMessage = nil
            Defaults[.remindersActivityEnabled] = previousEnabled
            Defaults[.reminderListIdentifier] = previousSelection
            activities.setReminders([])
            NSApp.setActivationPolicy(previousPolicy)
        }
        vm.open()
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.selectPage?(.reminders)
        try? await Task.sleep(for: .seconds(0.25))
        let host = window.contentView!
        func capture(_ name: String) -> Double {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            var blue: Double = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    blue += max(0, c.blueComponent - c.redComponent)
                }
            }
            return blue
        }
        var editorStage = 0
        func beginEditing(_ id: String) async {
            // Button actions are invoked offscreen; supply the app activation a
            // real pointer click would provide after the panel relinquishes focus.
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .seconds(0.04))
            IslandArtworkRenderProbe.hover?(true)
            IslandArtworkRenderProbe.editReminder[id]?()
        }
        func editor() async -> NSTextView {
            editorStage += 1
            // Let the newly selected row mount and retarget the shared AppKit editor.
            try? await Task.sleep(for: .seconds(0.05))
            for _ in 0..<80 {
                if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return editor }
                try? await Task.sleep(for: .seconds(0.025))
            }
            require(false, "Inline editing did not acquire the native field editor at stage \(editorStage): editing=\(vm.isEditingActivity), key=\(window.isKeyWindow), appActive=\(NSApp.isActive), focusRequests=\(creationKeyRequests), state=\(vm.notchState), responder=\(String(describing: window.firstResponder))")
            fatalError()
        }
        func type(_ value: String, into editor: NSTextView) async {
            editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            try? await Task.sleep(for: .seconds(0.025))
        }
        func key(_ code: UInt16, characters: String, in editor: NSTextView) async {
            IslandArtworkRenderProbe.hover?(true)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code)!
            editor.keyDown(with: event)
            try? await Task.sleep(for: .seconds(0.1))
        }
        require(IslandArtworkRenderProbe.outsideEditingActive?() != true,
                "Outside-click observation remained mounted without editing")
        // Exercise queued-callback cancellation without observing the user's desktop.
        do {
            let view = OutsideEditingClickMonitor.CaptureView(frame: host.bounds)
            host.addSubview(view)
            var cancelled = 0
            let monitor = OutsideEditingClickMonitor.Coordinator { cancelled += 1 }
            monitor.install(on: view)
            let rect = monitor.screenFrame()!
            monitor.receive(screenPoint: NSPoint(x: rect.maxX + 100, y: rect.midY))
            monitor.remove()
            try? await Task.sleep(for: .seconds(0.05))
            require(cancelled == 0 && !monitor.isMonitoring, "Retired observer delivered a stale cancellation")
            view.removeFromSuperview()
        }
        for global in [false, true] {
            await beginEditing(first.id)
            let pending = await editor()
            await type("Outside draft", into: pending)
            require(IslandArtworkRenderProbe.outsideEditingActive?() == true,
                    "Editing did not install its outside-click observer")
            let rect = IslandArtworkRenderProbe.outsideEditingFrame!()!
            require(abs(rect.width - vm.expandedNotchSize.width) < 0.5
                        && abs(rect.height - expandedNotchHeight) < 0.5,
                    "Outside-click region does not match the expanded surface: \(rect)")
            func localDown(_ point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: .leftMouseDown, location: window.convertPoint(fromScreen: point),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            for point in [NSPoint(x: rect.midX, y: rect.midY), NSPoint(x: rect.midX, y: rect.maxY - 3)] {
                let event = localDown(point)
                require(IslandArtworkRenderProbe.outsideEditingLocal?(event) === event,
                        "Inside click was consumed")
                try? await Task.sleep(for: .seconds(0.03))
                require(vm.isEditingActivity && vm.notchState == .open,
                        "A click within the expanded/header area cancelled editing")
            }
            let point = global ? NSPoint(x: rect.maxX + 5000, y: rect.midY)
                               : NSPoint(x: rect.midX, y: rect.minY - 3)
            if global {
                IslandArtworkRenderProbe.outsideEditingGlobal?(point)
            } else {
                require(window.frame.contains(point), "Local outside fixture missed the transparent window margin")
                let event = localDown(point)
                require(IslandArtworkRenderProbe.outsideEditingLocal?(event) === event,
                        "Outside click was consumed instead of delivered normally")
            }
            try? await Task.sleep(for: .seconds(0.2))
            require(!vm.isEditingActivity && vm.notchState == .closed && activities.reminders[0] == first
                        && IslandArtworkRenderProbe.reminderTitleWrites.isEmpty
                        && IslandArtworkRenderProbe.reminderWrites.isEmpty,
                    "Outside click saved a draft, completed a task, or left the island expanded")
            require(!(window.firstResponder is NSTextView) && IslandArtworkRenderProbe.outsideEditingActive?() != true,
                    "Outside cancellation left focus/observation active: responder=\(String(describing: window.firstResponder)), monitor=\(String(describing: IslandArtworkRenderProbe.outsideEditingActive?()))")
            let staleGlobalHandler = IslandArtworkRenderProbe.outsideEditingGlobal
            vm.open()
            try? await Task.sleep(for: .seconds(0.6))
            IslandArtworkRenderProbe.hover?(true)
            IslandArtworkRenderProbe.selectPage?(.reminders)
            staleGlobalHandler?(point)
            try? await Task.sleep(for: .seconds(0.08))
            require(vm.notchState == .open, "A retired outside observer closed a later expansion")
        }
        // Creating a new task uses the same outside-cancel-and-close behavior.
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(0.04))
        IslandArtworkRenderProbe.actionHandlers["plus"]?()
        let addingField = await editor()
        await type("Discard new task", into: addingField)
        let addingRect = IslandArtworkRenderProbe.outsideEditingFrame!()!
        IslandArtworkRenderProbe.outsideEditingGlobal?(NSPoint(x: addingRect.maxX + 100, y: addingRect.midY))
        try? await Task.sleep(for: .seconds(0.2))
        require(vm.notchState == .closed && !vm.isEditingActivity && activities.reminders.count == 2
                    && IslandArtworkRenderProbe.reminderAdds.isEmpty,
                "Outside click committed an unfinished new task or did not close")
        vm.open()
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.hover?(true)
        IslandArtworkRenderProbe.selectPage?(.reminders)
        print("PASS: inside/header clicks retain editing; local transparent-margin and global outside clicks cancel without writes and close; observers are transient, non-consuming and reject stale callbacks; add drafts are discarded")
        let titleFrame = IslandArtworkRenderProbe.reminderTitleFrames[first.id]!
        let circleFrame = IslandArtworkRenderProbe.reminderCircleFrames[first.id]!
        require(!titleFrame.intersects(circleFrame), "Title editing overlaps the completion target")
        func titleInkBounds() -> CGRect {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
            for y in Int(titleFrame.minY * scale)..<Int(titleFrame.maxY * scale) {
                for x in Int((titleFrame.minX - 3) * scale)..<Int(titleFrame.maxX * scale) {
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if min(c.redComponent, c.greenComponent, c.blueComponent) > 0.45 {
                        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                    }
                }
            }
            require(maxX >= minX && maxY >= minY, "Missing actual title glyph pixels")
            return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        }
        let originalInk = titleInkBounds()
        IslandArtworkRenderProbe.hover?(true)
        await beginEditing(first.id)
        let field = await editor()
        require(vm.isEditingActivity && field.string == first.title && IslandArtworkRenderProbe.reminderWrites.isEmpty,
                "Clicking the title completed a reminder or lost its title")
        require(field.selectedRange().length == 0, "Inline edit selected all text instead of placing a caret")
        guard let nativeField = field.delegate as? NSTextField else {
            require(false, "Inline editor has no native text control"); return
        }
        require(!nativeField.isBordered && !nativeField.drawsBackground && nativeField.focusRingType == .none,
                "Inline edit reintroduced an input box or focus ring")
        let editedInk = titleInkBounds()
        _ = capture("reminder-native-caret")
        require(abs(editedInk.minX - originalInk.minX) <= 0.5 && abs(editedInk.minY - originalInk.minY) <= 0.5
                    && abs(editedInk.width - originalInk.width) <= 1 && abs(editedInk.height - originalInk.height) <= 1,
                "Editing moved or resized the actual title glyphs: label=\(originalInk), editor=\(editedInk)")
        await type("  Buy oat milk  ", into: field)
        _ = capture("reminder-inline-editing")
        await key(36, characters: "\r", in: field)
        require(activities.reminders[0] == first.renamed(to: "Buy oat milk") && activities.reminders.count == 2
                    && !vm.isEditingActivity && IslandArtworkRenderProbe.reminderTitleWrites.count == 1,
                "Return did not commit the title while preserving identity, metadata and count")
        await beginEditing(second.id)
        var failedField = await editor()
        await type("Call dentist", into: failedField)
        IslandArtworkRenderProbe.reminderTitleWriteSucceeds = false
        await key(36, characters: "\r", in: failedField)
        failedField = await editor()
        _ = capture("reminder-edit-failed-save")
        require(vm.isEditingActivity && failedField.string == "Call dentist" && activities.reminders[1] == second,
                "A failed save discarded the draft or changed committed content: editing=\(vm.isEditingActivity), draft=\(failedField.string), saved=\(activities.reminders)")
        await key(53, characters: "\u{1b}", in: failedField)
        require(!vm.isEditingActivity && activities.reminders[1] == second, "Escape saved an unwanted edit")
        require(!(window.firstResponder is NSTextView), "Escape retained the native field editor over the row label")
        source.errorMessage = nil
        IslandArtworkRenderProbe.reminderTitleWriteSucceeds = true
        await beginEditing(first.id)
        var blankField = await editor()
        await type("   ", into: blankField)
        let beforeBlank = IslandArtworkRenderProbe.reminderTitleWrites.count
        await key(36, characters: "\r", in: blankField)
        require(vm.isEditingActivity && IslandArtworkRenderProbe.reminderTitleWrites.count == beforeBlank,
                "Blank title was written or dismissed the editor")
        blankField = await editor()
        let external = first.renamed(to: "Changed elsewhere")
        activities.setReminders([external, second])
        await type("Local draft", into: blankField)
        await key(36, characters: "\r", in: blankField)
        require(activities.reminders[0] == external && vm.isEditingActivity,
                "An old edit overwrote a newer external title")
        blankField = await editor()
        await key(53, characters: "\u{1b}", in: blankField)
        source.errorMessage = nil
        await beginEditing(second.id)
        _ = await editor()
        activities.setReminders([external])
        try? await Task.sleep(for: .seconds(0.1))
        require(!vm.isEditingActivity, "Removing the edited task left the island editing lock active")
        require(!(window.firstResponder is NSTextView), "Deleting the row retained the native field editor")
        activities.setReminders([external, second])
        try? await Task.sleep(for: .seconds(0.4))
        await beginEditing(second.id)
        _ = await editor()
        Defaults[.reminderListIdentifier] = "personal"
        try? await Task.sleep(for: .seconds(0.1))
        require(!vm.isEditingActivity, "Changing lists retained an old row edit")
        await beginEditing(second.id)
        _ = await editor()
        source.authorized = false
        try? await Task.sleep(for: .seconds(0.1))
        require(!vm.isEditingActivity, "Losing reminder access retained the old editor")
        source.authorized = true
        try? await Task.sleep(for: .seconds(0.1))
        await beginEditing(second.id)
        _ = await editor()
        IslandArtworkRenderProbe.selectPage?(.music)
        try? await Task.sleep(for: .seconds(0.2))
        require(!vm.isEditingActivity, "Leaving reminders retained the row edit")
        IslandArtworkRenderProbe.selectPage?(.reminders)
        try? await Task.sleep(for: .seconds(0.4))
        IslandArtworkRenderProbe.hoverReminderCount?(false)
        try? await Task.sleep(for: .seconds(0.5))
        let normalBlue = capture("reminder-count-resting")
        IslandArtworkRenderProbe.hoverReminderCount?(true)
        try? await Task.sleep(for: .seconds(0.5))
        require(capture("reminder-count-hovered") < normalBlue - 10, "Count hover did not slightly dim its text")
        IslandArtworkRenderProbe.hoverReminderCount?(false)
        await beginEditing(first.id)
        let completingField = await editor()
        await type("Unsaved draft", into: completingField)
        let beforeCompletion = IslandArtworkRenderProbe.reminderTitleWrites.count
        IslandArtworkRenderProbe.completeReminder[first.id]?()
        require(activities.reminders.map(\.id) == [second.id] && IslandArtworkRenderProbe.reminderWrites == [first.id]
                    && IslandArtworkRenderProbe.reminderTitleWrites.count == beforeCompletion && !vm.isEditingActivity,
                "Circle click did not exclusively complete the intended task")
        // Reuse the production panel and real field editor for both submission paths.
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.reminderAdds = []
        func creationFrame(_ name: String) -> CGRect {
            host.layoutSubtreeIfNeeded()
            return IslandArtworkRenderProbe.creationFrames[name] ?? .zero
        }
        func verifyNoButtonOverlap() {
            let primary = creationFrame("primary")
            let cross = creationFrame("trailing")
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            // Sample the exposed right rim, outside the moving blue control.
            // System blue can contain red, so do not mistake its own fill for a cross.
            let sampleX = cross.maxX - 1
            guard sampleX > primary.maxX + 0.25 else { return }
            let x = Int(sampleX * scale), y = Int(cross.midY * scale)
            let red = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent
            if red > 0.025 {
                require(primary.maxX <= cross.minX + 0.5,
                        "Visible add and cross circles overlapped: primary=\(primary), cross=\(cross), red=\(red)")
            }
        }
        let resting = creationFrame("primary")
        require(resting.width == 44 && resting.height == 44, "Creation control lost its 44-point target")
        for mode in ["cancel", "failure", "check", "return", "reduced"] {
            IslandArtworkRenderProbe.reduceMotion = mode == "reduced"
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .seconds(0.04))
            IslandArtworkRenderProbe.hover?(true)
            window.resignKey()
            let beforeRequests = creationKeyRequests
            IslandArtworkRenderProbe.actionHandlers["plus"]?()
            var opening: [CGFloat] = []
            for _ in 0..<25 {
                try? await Task.sleep(for: .seconds(0.016))
                opening.append(creationFrame("primary").midX)
                verifyNoButtonOverlap()
                require(abs(creationFrame("trailing").midX - resting.midX) < 0.5,
                        "Fading cross moved from its trailing anchor")
            }
            _ = capture("reminder-add-\(mode)-opened")
            let left = creationFrame("primary")
            require(abs(resting.midX - left.midX - 52) < 0.5, "Check did not settle beside the cross in \(mode): resting=\(resting), trailing=\(creationFrame("trailing")), left=\(left), frames=\(opening)")
            if mode != "reduced" {
                require(Set(opening.map { Int($0 * 10) }).count >= 3
                            && opening.contains { $0 > left.midX + 3 && $0 < resting.midX - 3 },
                        "Primary plus-to-check motion snapped")
            }
            require(creationKeyRequests > beforeRequests, "New creation did not request committed native focus in \(mode)")
            let field = await editor()
            await type("New task \(mode)", into: field)
            let count = activities.reminders.count
            if mode == "cancel" {
                IslandArtworkRenderProbe.creationActions["cancel"]?()
                try? await Task.sleep(for: .seconds(0.65))
                require(activities.reminders.count == count && !vm.isEditingActivity,
                        "Cancel saved a reminder or retained editing")
                continue
            }
            if mode == "failure" {
                IslandArtworkRenderProbe.reminderAddSucceeds = false
                IslandArtworkRenderProbe.creationActions["save"]?()
                try? await Task.sleep(for: .seconds(0.12))
                require(vm.isEditingActivity && field.string == "New task failure"
                            && abs(creationFrame("primary").midX - left.midX) < 0.5
                            && activities.reminders.count == count,
                        "Failed add moved the check, dismissed its draft or added a task")
                IslandArtworkRenderProbe.reminderAddSucceeds = true
                IslandArtworkRenderProbe.creationActions["cancel"]?()
                try? await Task.sleep(for: .seconds(0.65))
                continue
            }
            if mode == "return" {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                field.keyDown(with: event)
            } else {
                IslandArtworkRenderProbe.creationActions["save"]?()
            }
            require(activities.reminders.count == count + 1, "Creation animation delayed the committed add")
            var closing: [CGFloat] = []
            for index in 0..<32 {
                try? await Task.sleep(for: .seconds(0.016))
                closing.append(creationFrame("primary").midX)
                verifyNoButtonOverlap()
                if index == 3 { _ = capture("reminder-add-\(mode)-returning") }
            }
            if mode != "reduced" {
                require(Set(closing.map { Int($0 * 10) }).count >= 4
                            && closing.contains { $0 > left.midX + 3 && $0 < resting.midX - 3 },
                        "Successful add did not move the check continuously into the plus position: \(closing)")
            }
            require(abs(creationFrame("primary").midX - resting.midX) < 0.5 && !vm.isEditingActivity,
                    "Successful add failed to settle at the resting plus position")
            _ = capture("reminder-add-\(mode)-settled")
        }
        IslandArtworkRenderProbe.reduceMotion = false
        print("PASS: persistent plus moves left into check and reverses right on both native Return and button submission, cross fades only outside the moving circle with painted pixels verified, cancellation/failure preserve data, writes are immediate and Reduce Motion settles directly")
        print("PASS: click-only titles avoid idle hover hosts; borderless native editing preserves title position and places a caret, title action never completes, Return saves, Escape/failure/conflict/empty title retain valid data, removal/list/page changes release focus, count hover is visible, separate circle action completes")
    }

    @MainActor static func verifyReminderEditingFocus(output: URL) async {
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let source = RemindersActivityManager.shared
        let previousAuthorization = source.authorized
        let previousEnabled = Defaults[.remindersActivityEnabled]
        source.authorized = true
        Defaults[.remindersActivityEnabled] = true
        defer { source.authorized = previousAuthorization; Defaults[.remindersActivityEnabled] = previousEnabled }
        for launch in 0..<3 {
            let delegate = AppDelegate()
            let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
            vm.hideOnClosed = false
            let window = delegate.createIslandWindow(for: NSScreen.screens[0], with: vm) as! ReminderFocusTestWindow
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            NSApp.activate(ignoringOtherApps: true)
            defer {
                window.onMakeKey = nil
                window.orderOut(nil); window.contentView = nil; window.close()
                vm.destroy(); delegate.vm.destroy()
            }
            vm.open()
            try? await Task.sleep(for: .seconds(0.6))
            IslandArtworkRenderProbe.selectPage?(.reminders)
            try? await Task.sleep(for: .seconds(0.2))
            var requests = 0
            var uncommittedRequests = 0
            var publishingEditing = false
            window.onMakeKey = {
                requests += 1
                if publishingEditing || !vm.isEditingActivity { uncommittedRequests += 1 }
            }
            // @Published emits before assigning the property. AppKit must not be
            // invoked on that synchronous stack, and cancelled work must stay cancelled.
            for scenario in 0..<4 {
                vm.isEditingActivity = false
                window.resignKey()
                try? await Task.sleep(for: .seconds(0.03))
                let before = requests
                publishingEditing = true
                vm.isEditingActivity = true
                require(requests == before, "Key focus reentered an uncommitted editing update")
                switch scenario {
                case 0: vm.isEditingActivity = false
                case 1: vm.close()
                case 2: window.orderOut(nil)
                default: window.alphaValue = 0
                }
                publishingEditing = false
                try? await Task.sleep(for: .seconds(0.1))
                require(requests == before, "Cancelled/closed/hidden editor stole keyboard focus")
                vm.isEditingActivity = false
                window.alphaValue = 1
                window.orderFrontRegardless()
                vm.open()
                try? await Task.sleep(for: .seconds(0.15))
            }
            IslandArtworkRenderProbe.selectPage?(.reminders)
            try? await Task.sleep(for: .seconds(0.2))
            for attempt in 0..<4 {
                IslandArtworkRenderProbe.hover?(true)
                // Offscreen fixtures have no hover. Cancelling legitimately
                // closes the panel, so reopen as a user would for the next add.
                vm.open()
                try? await Task.sleep(for: .seconds(0.3))
                IslandArtworkRenderProbe.selectPage?(.reminders)
                try? await Task.sleep(for: .seconds(0.15))
                IslandArtworkRenderProbe.hover?(true)
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(for: .seconds(0.04))
                window.resignKey()
                let before = requests
                guard let begin = IslandArtworkRenderProbe.actionHandlers["plus"] else {
                    require(false, "Missing actual reminder add action"); return
                }
                begin()
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .seconds(0.18))
                // Other applications may take key status while this async test
                // yields. Check the committed request and actual field editor.
                require(vm.isEditingActivity && (requests > before || window.firstResponder is NSTextView),
                        "Actual add action failed to request deferred keyboard focus (editing: \(vm.isEditingActivity), state: \(vm.notchState), visible: \(window.isVisible), key: \(window.isKeyWindow), requests: \(requests), before: \(before))")
                for _ in 0..<20 {
                    if window.firstResponder is NSTextView { break }
                    try? await Task.sleep(for: .seconds(0.025))
                }
                require(window.firstResponder is NSTextView,
                        "Reminder text field failed to install its native field editor (launch: \(launch), attempt: \(attempt), key: \(window.isKeyWindow), active: \(NSApp.isActive), requests: \(requests), before: \(before), responder: \(String(describing: window.firstResponder)))")
                if attempt == 0 {
                    let host = window.contentView!
                    let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: image)
                    try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("reminder-editing-launch-\(launch).png"))
                }
                IslandArtworkRenderProbe.actionHandlers["xmark"]?()
                try? await Task.sleep(for: .seconds(0.12))
                require(!vm.isEditingActivity, "Cancelling add left editing enabled")
            }
            require(uncommittedRequests == 0, "Key-window callbacks ran during stale SwiftUI/Published state")
        }
        print("PASS: production nonactivating panels defer key focus beyond publishing, reject cancelled/closed/hidden requests, and open the native reminder editor across three cold windows and repeated add/cancel transitions; EventKit is inert")
    }

    @MainActor static func verifyMediaKeys() {
        let interceptor = MediaKeyInterceptor.shared
        func send(_ code: Int, down: Bool, flags: CGEventFlags = []) -> Bool {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
            event.flags = flags
            if let returned = interceptor.handleEvent(event) { _ = returned.takeRetainedValue(); return false }
            return true
        }
        IslandArtworkRenderProbe.mediaKeys = []
        require(!send(kVK_ANSI_A, down: true) && !send(kVK_F13, down: true), "Ordinary typing/function keys were consumed")
        require(send(kVK_F14, down: true) && send(kVK_F14, down: false), "F14 brightness down was not paired")
        require(send(kVK_F15, down: true, flags: .maskSecondaryFn) && send(kVK_F15, down: false), "Fn F15 brightness up was not paired")
        require(IslandArtworkRenderProbe.mediaKeys == ["3:1", "2:1"], "Legacy brightness decoded into the wrong actions")
        for flags: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate] {
            require(!send(kVK_F14, down: true, flags: flags) && !send(kVK_F14, down: false), "Reserved modifier shortcut was swallowed")
        }
        let fine: CGEventFlags = [.maskAlternate, .maskShift]
        require(send(kVK_F15, down: true, flags: fine) && send(kVK_F15, down: true, flags: fine), "Fine adjustment or repeat was lost")
        require(send(kVK_F15, down: false, flags: .maskCommand), "Consumed release was lost when modifiers changed")
        require(Array(IslandArtworkRenderProbe.mediaKeys.suffix(2)) == ["2:4", "2:4"], "Fine adjustment divisor changed")
        require(!send(kVK_F15, down: false), "An unrelated key-up was swallowed")
        require(send(kVK_F14, down: true), "Cleanup fixture failed to consume key")
        interceptor.stop()
        require(!send(kVK_F14, down: false), "Stopping input retained stale pressed keys")
        func media(_ code: Int, state: Int, flags: NSEvent.ModifierFlags = []) -> Bool {
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (code << 16) | (state << 8), data2: 0)!.cgEvent!
            if let returned = interceptor.handleEvent(event) { _ = returned.takeRetainedValue(); return false }
            return true
        }
        require(media(0, state: 0xA) && media(1, state: 0xA) && media(7, state: 0xA), "Existing volume/mute path regressed")
        require(Array(IslandArtworkRenderProbe.mediaKeys.suffix(3)) == ["0:1", "1:1", "7:1"], "Volume actions were remapped")
        require(!media(0, state: 0xB) && !media(0, state: 0xA, flags: .option), "Native media shortcuts were swallowed")
        print("PASS: real F14/F15 and NX media decoding, paired releases, repeat/fine adjustment, reserved modifiers, ordinary key passthrough and stale key cleanup; no tap installed and no device values changed")
    }

    @MainActor static func verifyHUDProgressWidth(output: URL) async {
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; vm.destroy() }
        for locale in ["en", "zh-Hans"] {
            for hovering in [false, true] {
                for type in [IslandActivityKind.volume, .brightness, .backlight] {
                    var first: CGRect?
                    for value in [0.0, 0.09, 0.99, 1.0, 0.99] {
                        IslandArtworkRenderProbe.hudProgressFrame = .zero
                        let host = NSHostingView(rootView: InlineHUD(type: type, value: .constant(value), icon: "", hoverAnimation: .constant(hovering))
                            .environmentObject(vm).environment(\.locale, Locale(identifier: locale)).background(.black))
                        window.contentView = host; window.orderBack(nil)
                        try? await Task.sleep(for: .seconds(0.05))
                        host.layoutSubtreeIfNeeded()
                        let frame = IslandArtworkRenderProbe.hudProgressFrame
                        require(frame.width > 10 && frame.height > 0, "HUD progress track was not measured")
                        if let first {
                            require(abs(frame.width - first.width) < 0.01 && abs(frame.minX - first.minX) < 0.01,
                                    "HUD track moved/resized at \(value): \(first) → \(frame), \(locale), \(type), hover \(hovering)")
                        } else { first = frame }
                        if value == 0.99 || value == 1 {
                            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                            host.cacheDisplay(in: host.bounds, to: image)
                            try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("hud-\(locale)-\(type)-hover-\(hovering)-\(Int(value * 100)).png"))
                        }
                    }
                }
            }
        }
        print("PASS: actual HUD track width and position stay fixed for 0/9/99/100/99 across volume, brightness, backlight, hover and English/Chinese; no device values changed")
    }

    @MainActor static func verifyCardExpansion(output: URL) async {
        let activities = ActivityCoordinator.shared
        let timer = TimerActivityManager.shared
        let reminders = RemindersActivityManager.shared
        let previousMotion = IslandArtworkRenderProbe.reduceMotion
        let previousAuthorization = reminders.authorized
        let previousReminders = Defaults[.remindersActivityEnabled]
        let previousTimer = Defaults[.timerActivityEnabled]
        let previousLighting = Defaults[.lightingEffect]
        Defaults[.remindersActivityEnabled] = true
        Defaults[.timerActivityEnabled] = true
        Defaults[.lightingEffect] = false
        reminders.authorized = true
        activities.setReminders([ReminderTask(id: "blur-fixture", title: "Review the card transition", dueDate: nil)])
        timer.start(duration: 1500)
        let timerID = activities.timer?.id
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(vm).background(.black))
        window.contentView = host; window.orderBack(nil)
        defer {
            IslandArtworkRenderProbe.expansionOverride = nil
            IslandArtworkRenderProbe.reduceMotion = previousMotion
            window.orderOut(nil); window.contentView = nil; vm.destroy()
            timer.cancel(); activities.setReminders([]); reminders.authorized = previousAuthorization
            Defaults[.remindersActivityEnabled] = previousReminders
            Defaults[.timerActivityEnabled] = previousTimer
            Defaults[.lightingEffect] = previousLighting
        }
        func capture(_ name: String, page: IslandPage) -> Double {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            // cacheDisplay omits Core Animation blur filters. Use ImageRenderer
            // for the real page + shared modifier, while the host capture above
            // checks that closing still retains the actual page tree.
            let pageView: AnyView
            switch page {
            case .music: pageView = AnyView(NotchHomeView())
            case .reminders: pageView = AnyView(RemindersActivityPage())
            case .timer: pageView = AnyView(TimerActivityPage())
            }
            let rendered = ImageRenderer(content: pageView
                .frame(width: vm.expandedNotchSize.width - 80, height: 130)
                .modifier(IslandCardContentTransition(expansion: 0.85))
                .padding(20).background(.black).environmentObject(vm).preferredColorScheme(.dark))
            rendered.scale = 2
            let image = NSBitmapImageRep(cgImage: rendered.cgImage!)
            try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + "-filtered.png"))
            let scale: CGFloat = 2
            let fromX: CGFloat = 20
            let toX = CGFloat(image.pixelsWide) / scale - 20
            let fromY: CGFloat = 20
            let toY = CGFloat(image.pixelsHigh) / scale - 20
            func brightness(_ x: Int, _ y: Int) -> Double {
                let p = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                return max(p.redComponent, p.greenComponent, p.blueComponent)
            }
            var signal = 0.0, edges = 0.0
            for y in Int(fromY * scale)..<Int(toY * scale) {
                for x in Int(fromX * scale)..<Int(toX * scale) {
                    let p = brightness(x, y)
                    signal += p
                    edges += abs(p - brightness(x + 1, y)) + abs(p - brightness(x, y + 1))
                }
            }
            require(signal > 5, "Card body vanished before the closing surface finished: \(name)")
            let hostSignal = (100..<min(180, rep.pixelsHigh)).reduce(0.0) { total, y in
                total + (0..<rep.pixelsWide).reduce(0.0) { sum, x in
                    let pixel = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return sum + max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
                }
            }
            require(hostSignal > 5, "Closing removed the real page before expansion reached zero")
            return edges / signal
        }
        for page in IslandPage.allCases {
            IslandArtworkRenderProbe.reduceMotion = false
            IslandArtworkRenderProbe.expansionOverride = 1
            vm.open()
            try? await Task.sleep(for: .seconds(0.65))
            IslandArtworkRenderProbe.selectPage?(page)
            try? await Task.sleep(for: .seconds(0.65))
            IslandArtworkRenderProbe.expansionOverride = 0.85
            vm.close()
            try? await Task.sleep(for: .seconds(0.5))
            let blurred = capture("card-expansion-\(page)-blur", page: page)
            IslandArtworkRenderProbe.reduceMotion = true
            vm.objectWillChange.send()
            try? await Task.sleep(for: .seconds(0.3))
            let sharp = capture("card-expansion-\(page)-reduced-motion", page: page)
            require(blurred < sharp * 0.8, "\(page) did not blur its real rendered content: \(blurred) versus \(sharp)")
            print("PASS: \(page) closing content retained and blurred; Reduce Motion keeps it sharp (edge ratios \(blurred), \(sharp))")
        }
        require(activities.timer?.id == timerID && activities.timer?.phase == .running,
                "A presentation-only transition changed the real timer lifecycle")
    }

    @MainActor static func verifyOnboarding(output: URL) async {
        // No providers are started by the isolated runner. Inspect the real
        // AVPlayerLayer to verify playback, rather than asserting source text.
        let previousMotion = IslandArtworkRenderProbe.reduceMotion
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingLayout.size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        defer {
            window.orderOut(nil); window.contentView = nil; window.close()
            IslandArtworkRenderProbe.reduceMotion = previousMotion
            NSApp.setActivationPolicy(previousPolicy)
        }
        for name in ["CardSwitchingGuide", "CardSwitchingGuideDark"] {
            let url = Bundle.main.url(forResource: name, withExtension: "mp4")!
            let asset = AVURLAsset(url: url)
            let duration = try! await asset.load(.duration)
            let audio = try! await asset.loadTracks(withMediaType: .audio)
            require(abs(duration.seconds - 7.5) < 0.1 && audio.isEmpty, "Welcome illustration has wrong duration or audio")
        }
        require(NSImage(named: "CardSwitchingGuidePoster") != nil, "Reduced-motion poster missing")
        let movie = CardSwitchingMovieView(url: Bundle.main.url(forResource: "CardSwitchingGuide", withExtension: "mp4")!)
        window.contentView = movie
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        movie.setPlaybackRequested(true)
        let player = (movie.layer!.sublayers!.first as! AVPlayerLayer).player!
        for _ in 0..<40 {
            if player.currentTime().seconds > 0.15 { break }
            try? await Task.sleep(for: .seconds(0.1))
        }
        require(player.currentTime().seconds > 0.15 && player.rate > 0, "Visible welcome illustration did not play")
        movie.setPlaybackRequested(false)
        try? await Task.sleep(for: .seconds(0.15))
        let paused = player.currentTime().seconds
        try? await Task.sleep(for: .seconds(0.2))
        require(player.rate == 0 && abs(player.currentTime().seconds - paused) < 0.05, "Inactive illustration kept playing")
        movie.setPlaybackRequested(true)
        window.orderOut(nil)
        try? await Task.sleep(for: .seconds(0.2))
        require(player.rate == 0, "Hidden welcome window kept playing")
        window.close()
        try? await Task.sleep(for: .seconds(0.15))
        require((player as! AVQueuePlayer).items().isEmpty && (movie.layer!.sublayers!.first as! AVPlayerLayer).player == nil,
                "Closed welcome window retained playback resources")

        func movieViews(_ view: NSView) -> [CardSwitchingMovieView] {
            (view as? CardSwitchingMovieView).map { [$0] } ?? view.subviews.flatMap(movieViews)
        }
        for dark in [false, true] {
            for reduced in [false, true] {
                IslandArtworkRenderProbe.reduceMotion = reduced
                for language in ["zh-Hans", "en"] {
                    for finished in [false, true] {
                        let host = NSHostingView(rootView: OnboardingView(step: finished ? .finished : .welcome, onFinish: {}, onOpenSettings: {})
                            .environment(\.locale, Locale(identifier: language))
                            .preferredColorScheme(dark ? .dark : .light))
                        window.contentView = host
                        window.makeKeyAndOrderFront(nil)
                        try? await Task.sleep(for: .seconds(0.4))
                        host.layoutSubtreeIfNeeded()
                        require(host.bounds.size == OnboardingLayout.size, "Welcome content and window sizes diverged")
                        require(movieViews(host).count == (finished && !reduced ? 1 : 0), "Welcome or Reduced Motion instantiated an unexpected player")
                        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("onboarding-\(finished ? "guide" : "welcome")-\(language)-\(dark ? "dark" : "light")-\(reduced ? "static" : "movie").png"))
                    }
                }
            }
        }
        print("PASS: local silent welcome movies, visible playback, inactive/hidden pause, resource cleanup, both welcome steps in Chinese/English and light/dark at 560×560, and Reduce Motion static fallback")
    }

    @MainActor static func verifyDefaultActivityPreferences() {
        let defaults = UserDefaults.standard
        let keys = ["remindersActivityEnabled", "timerActivityEnabled", "enableSneakPeek", "showPageIndicators"]
        let previous = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier!) ?? [:]
        defer {
            for key in keys {
                if let value = previous[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        require(Defaults[.remindersActivityEnabled] && Defaults[.timerActivityEnabled] && Defaults[.enableSneakPeek] && Defaults[.showPageIndicators],
                "Personal activities, song peek or page indicators are not enabled for a fresh preference state")
        Defaults[.remindersActivityEnabled] = false
        Defaults[.timerActivityEnabled] = false
        Defaults[.enableSneakPeek] = false
        Defaults[.showPageIndicators] = false
        require(!Defaults[.remindersActivityEnabled] && !Defaults[.timerActivityEnabled] && !Defaults[.enableSneakPeek] && !Defaults[.showPageIndicators],
                "An explicit off preference was forced back on")
        print("PASS: personal activities/song peek/page indicators default on while explicit off preferences remain effective")
    }

    @MainActor static func verifySettingsHeader(output: URL) async {
        let controller = SettingsWindowController.shared
        let window = controller.window!
        defer { window.orderOut(nil) }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for size in [CGSize(width: 760, height: 600), CGSize(width: 1000, height: 760)] {
                window.setFrame(NSRect(origin: CGPoint(x: -10000, y: -10000), size: size), display: true)
                window.orderBack(nil)
                try? await Task.sleep(for: .seconds(0.2))
                let pages: [(String, ActivitySettingsPage?)] = [
                    ("general", nil), ("activities", .music), ("activities", .reminders),
                    ("activities", .timer), ("activities", .feedback),
                    ("activities", nil), ("presentation", nil), ("about", nil)
                ]
                for (page, activity) in pages {
                    controller.navigation.selectedPage = SettingsPage(rawValue: page)
                    try? await Task.sleep(for: .seconds(0.05))
                    controller.navigation.activityPage = activity
                    try? await Task.sleep(for: .seconds(0.1))
                    let host = window.contentView!
                    host.layoutSubtreeIfNeeded()
                    guard let split = window.contentViewController as? NSSplitViewController,
                          let sidebar = split.splitViewItems.first?.viewController.view,
                          let detail = split.splitViewItems.last?.viewController.view else {
                        fatalError("Settings must use native sidebar and detail columns")
                    }
                    let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
                    let detailFrame = detail.convert(detail.safeAreaRect, to: nil)
                    require(abs(sidebarFrame.minX) < 0.5 &&
                            abs(sidebarFrame.width - SettingsView.sidebarWidth) < 0.5 &&
                            sidebarFrame.maxY > window.contentLayoutRect.maxY + 20,
                            "Sidebar does not extend through its titlebar: \(sidebarFrame)")
                    require(detailFrame.minX >= sidebarFrame.maxX &&
                            detailFrame.maxY <= window.contentLayoutRect.maxY + 0.5,
                            "Detail column escaped its native content area: \(detailFrame)")
                    let title = IslandArtworkRenderProbe.settingsTitleFrame
                    let header = window.titlebarAccessoryViewControllers.first!.view
                    let titleInWindow = header.convert(NSRect(
                        x: title.minX, y: header.isFlipped ? title.minY : header.bounds.height - title.maxY,
                        width: title.width, height: title.height), to: nil)
                    require(title.width > 20 && titleInWindow.minX > SettingsView.sidebarWidth,
                            "Settings title disappeared or crossed into the sidebar: \(titleInWindow)")
                    require(!header.isHiddenOrHasHiddenAncestor && titleInWindow.minY >= window.contentLayoutRect.maxY,
                            "Settings title is outside native titlebar layout: title=\(titleInWindow), content=\(window.contentLayoutRect)")
                    let back = IslandArtworkRenderProbe.settingsBackFrame
                    let backFrame = header.convert(NSRect(x: back.minX,
                        y: header.isFlipped ? back.minY : header.bounds.height - back.maxY,
                        width: back.width, height: back.height), to: nil)
                    require(abs(backFrame.midY - titleInWindow.midY) < 1,
                            "Back button and title are not vertically aligned: \(backFrame), \(titleInWindow)")
                    require(backFrame.width <= 36 && backFrame.height <= 28,
                            "Back button exceeds compact navigation size: \(backFrame)")
                    func scrollViews(_ view: NSView) -> [NSScrollView] {
                        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                    }
                    for scroll in scrollViews(host) {
                        let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
                        guard viewport.minX > SettingsView.sidebarWidth else { continue }
                        require(viewport.maxY <= window.contentLayoutRect.maxY + 0.5 && viewport.maxY <= titleInWindow.minY,
                                "Detail scrolling viewport overlaps the navigation title: \(viewport), \(titleInWindow)")
                        if let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height {
                            scroll.contentView.scroll(to: NSPoint(x: 0,
                                y: document.bounds.height - scroll.contentView.bounds.height))
                            scroll.reflectScrolledClipView(scroll.contentView)
                            let scrolled = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
                            require(scrolled.maxY <= titleInWindow.minY, "Scrolling entered the titlebar")
                        }
                    }
                    let frameView = host.superview!
                    let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)!
                    frameView.cacheDisplay(in: frameView.bounds, to: rep)
                    let filename = "settings-\(name)-\(Int(size.width))-\(activity?.rawValue ?? page).png"
                    try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
                }
            }
        }
        print("PASS: full-height native sidebar, separate detail titlebar and scrolling content in light/dark, both sizes, all settings pages")
    }

    @MainActor static func verifySpectrum(output: URL) async {
        verifySpectrumPixelSpacing(output: output)
        let legacySpectrum = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier!)?["realTimeSpectrum"]
        UserDefaults.standard.set(false, forKey: "realTimeSpectrum")
        let previousReminders = Defaults[.remindersActivityEnabled]
        let previousTimer = Defaults[.timerActivityEnabled]
        Defaults[.remindersActivityEnabled] = true
        Defaults[.timerActivityEnabled] = true
        let activities = ActivityCoordinator.shared
        let timer = TimerActivityManager.shared
        timer.cancel()
        for kind in IslandActivityKind.allCases where kind != .music { activities.end(kind) }
        activities.setMusicActive(true)
        activities.setMusicSpectrumSource(bundleIdentifier: "fixture.player", playing: true, trackIdentifier: UUID())
        await verifySpectrumSettling(output: output)
        let screen = NSScreen.screens[0]
        let vm = IslandViewModel(screenUUID: screen.displayUUID)
        vm.hideOnClosed = false
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer {
            if let legacySpectrum { UserDefaults.standard.set(legacySpectrum, forKey: "realTimeSpectrum") }
            else { UserDefaults.standard.removeObject(forKey: "realTimeSpectrum") }
            Defaults[.remindersActivityEnabled] = previousReminders
            Defaults[.timerActivityEnabled] = previousTimer
            timer.cancel()
            window.orderOut(nil); window.contentView = nil; vm.destroy()
        }
        try? await Task.sleep(for: .seconds(0.3))
        require(activities.spectrumRequest != nil, "Visible music did not enable spectrum automatically or an obsolete off preference blocked it")
        let lease = activities.spectrumRequest!
        let firstSelectPage = IslandArtworkRenderProbe.selectPage!
        activities.receiveSpectrum([0.2, 0.4, 0.6, 0.8, 1, 0.3], for: lease)
        try? await Task.sleep(for: .seconds(0.1))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("spectrum-six-bands.png"))
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        let right = (host.bounds.width + IslandArtworkRenderProbe.surfaceSize.width) / 2
        var bands: [Int] = [], currentHeight = 0
        var compactSpans: [ClosedRange<Int>] = [], bandStart: Int?
        for x in Int((right - 48) * scale)..<Int((right - 2) * scale) {
            var height = 0
            for y in 0..<Int(vm.effectiveClosedNotchHeight * scale) {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if max(c.redComponent, c.greenComponent, c.blueComponent) > 0.3 { height += 1 }
            }
            if height > 0 {
                if bandStart == nil { bandStart = x }
                currentHeight = max(currentHeight, height)
            } else if currentHeight > 0 {
                compactSpans.append(bandStart!...x - 1); bandStart = nil
                bands.append(currentHeight); currentHeight = 0
            }
        }
        if currentHeight > 0 {
            compactSpans.append(bandStart!...Int((right - 2) * scale) - 1)
            bands.append(currentHeight)
        }
        require(bands.count == 6 && Set(bands).count >= 4, "Rendered spectrum did not contain six independently driven bars: \(bands)")
        requireUniformSpectrumSpans(compactSpans, context: "compact spectrum")
        let height = vm.effectiveClosedNotchHeight
        let rightInset = right - CGFloat(compactSpans.last!.upperBound + 1) / scale
        require(abs(rightInset - MusicPlayerImageSizes.compactOuterInset(height: height)) <= 1,
                "Compact spectrum right inset does not match the cover: \(rightInset)")
        require(abs(CGFloat(bands.max()!) / scale - MusicPlayerImageSizes.compactSide(height: height)) < 2,
                "Compact spectrum ceiling is shorter than its cover")

        let originalArtist = MusicManager.shared.artistName
        MusicManager.shared.artistName = "" // Isolate the trailing spectrum pixels from artist glyphs.
        activities.post(.musicChange)
        try? await Task.sleep(for: .seconds(0.6))
        require(IslandPresentation(activity: activities.current).showsMusicPeek && activities.spectrumRequest == nil,
                "Song peek did not stop spectrum capture")
        host.layoutSubtreeIfNeeded()
        let peek = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: peek)
        let peekRight = (host.bounds.width + IslandArtworkRenderProbe.surfaceSize.width) / 2
        for x in Int((peekRight - 45) * scale)..<Int((peekRight - 8) * scale) {
            for y in Int(4 * scale)..<Int((vm.effectiveClosedNotchHeight - 4) * scale) {
                let c = peek.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                require(max(c.redComponent, c.greenComponent, c.blueComponent) < 0.05,
                        "Song peek rendered spectrum pixels in the empty artist region")
            }
        }
        MusicManager.shared.artistName = originalArtist
        try? await Task.sleep(for: .seconds(0.1))
        host.cacheDisplay(in: host.bounds, to: peek)
        try! peek.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("spectrum-song-peek-without-bars.png"))
        activities.end(.musicChange)
        try? await Task.sleep(for: .seconds(0.6))
        require(activities.current?.kind == .music && activities.spectrumRequest != nil,
                "Regular music did not restore its spectrum after the peek")
        var restoredLease = activities.spectrumRequest!

        // Keep compact bars live while they fade away on opening, including
        // browsing another card before expansion has finished.
        let compactRight = (host.bounds.width + IslandArtworkRenderProbe.surfaceSize.width) / 2
        IslandArtworkRenderProbe.expansionOverride = 0.2
        vm.open()
        try? await Task.sleep(for: .seconds(0.3))
        firstSelectPage(.reminders)
        try? await Task.sleep(for: .seconds(0.15))
        require(activities.spectrumRequest == restoredLease, "Opening withdrew still-visible compact capture")
        func openingBandHeight(_ amplitude: Double, name: String) async -> Int {
            activities.receiveSpectrum(Array(repeating: amplitude, count: 6), for: restoredLease)
            try? await Task.sleep(for: .seconds(0.08))
            host.layoutSubtreeIfNeeded()
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            return (Int((compactRight - 48) * scale)..<Int((compactRight - 2) * scale)).map { x in
                (0..<Int(vm.effectiveClosedNotchHeight * scale)).filter { y in
                    let c = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return max(c.redComponent, c.greenComponent, c.blueComponent) > 0.1
                }.count
            }.max()!
        }
        let outgoingLoud = await openingBandHeight(1, name: "spectrum-opening-loud")
        let outgoingSoft = await openingBandHeight(0.25, name: "spectrum-opening-soft")
        require(outgoingLoud >= Int((vm.effectiveClosedNotchHeight - 14) * scale)
                && outgoingSoft > 0 && Double(outgoingSoft) < Double(outgoingLoud) * 0.55,
                "Opening flattened/froze outgoing compact bars: \(outgoingLoud), \(outgoingSoft)")
        IslandArtworkRenderProbe.expansionOverride = 1
        vm.objectWillChange.send()
        try? await Task.sleep(for: .seconds(0.3))
        require(activities.spectrumRequest == nil, "Hidden compact spectrum retained capture on another card")
        firstSelectPage(.music)
        try? await Task.sleep(for: .seconds(0.15))
        require(activities.spectrumRequest != nil, "Expanded music failed to resume after opening")
        restoredLease = activities.spectrumRequest!
        IslandArtworkRenderProbe.expansionOverride = nil
        vm.close()
        try? await Task.sleep(for: .seconds(1.5))
        print("PASS: outgoing compact bars consume live frames until expansion hides them, then release capture on other cards")

        // Retiring music must keep both its drawing and its shared capture lease.
        // Hide compact content so it cannot mask an early expanded-demand release.
        vm.hideOnClosed = true
        vm.open()
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.expansionOverride = 0.85
        vm.close()
        try? await Task.sleep(for: .seconds(0.2))
        require(activities.spectrumRequest == restoredLease,
                "Closing withdrew capture before the expanded music was hidden")
        func closingBandHeight(_ amplitude: Double, name: String) async -> Int {
            activities.receiveSpectrum(Array(repeating: amplitude, count: 6), for: restoredLease)
            try? await Task.sleep(for: .seconds(0.1))
            host.layoutSubtreeIfNeeded()
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            let right = (host.bounds.width + vm.expandedNotchSize.width) / 2
                - cornerRadiusInsets.opened.top - MusicPlayerImageSizes.panelPadding
            let top = max(24, vm.effectiveClosedNotchHeight) + MusicPlayerImageSizes.sectionSpacing
            return (Int((right - 20) * scale)..<Int(right * scale)).map { x in
                (Int((top + 6) * scale)..<Int((top + 36) * scale)).filter { y in
                    let c = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return max(c.redComponent, c.greenComponent, c.blueComponent) > 0.1
                }.count
            }.max()!
        }
        let retiringLoud = await closingBandHeight(1, name: "spectrum-closing-loud")
        let retiringSoft = await closingBandHeight(0.25, name: "spectrum-closing-soft")
        require(retiringLoud >= Int(16 * scale) && retiringSoft > 0 && Double(retiringSoft) < Double(retiringLoud) * 0.55,
                "Retiring spectrum flattened or stopped consuming live frames: \(retiringLoud), \(retiringSoft)")
        IslandArtworkRenderProbe.expansionOverride = 1
        vm.open()
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest == restoredLease, "Reversing a close restarted capture")
        IslandArtworkRenderProbe.expansionOverride = 0
        vm.close()
        try? await Task.sleep(for: .seconds(1.5))
        require(activities.spectrumRequest == nil, "Fully hidden music retained its capture demand (surface: \(IslandArtworkRenderProbe.surfaceSize), state: \(vm.notchState), hidden: \(vm.hideOnClosed))")
        IslandArtworkRenderProbe.expansionOverride = nil
        vm.hideOnClosed = false
        vm.objectWillChange.send()
        try? await Task.sleep(for: .seconds(0.15))
        require(activities.spectrumRequest != nil, "Compact spectrum did not resume after the completed close")
        restoredLease = activities.spectrumRequest!
        print("PASS: closing music continues real spectrum frames until fully hidden; reversing preserves the lease")

        // A second display consumes the same lease; it never starts another source.
        let vm2 = IslandViewModel(screenUUID: screen.displayUUID)
        vm2.hideOnClosed = false
        let host2 = NSHostingView(rootView: ContentView().environmentObject(vm2))
        let window2 = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window2.isReleasedWhenClosed = false
        window2.contentView = host2; window2.orderBack(nil)
        defer { window2.orderOut(nil); window2.contentView = nil; vm2.destroy() }
        try? await Task.sleep(for: .seconds(0.1))
        let secondSelectPage = IslandArtworkRenderProbe.selectPage!
        require(activities.spectrumRequest == restoredLease, "A second display restarted shared capture")
        vm.open()
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest == restoredLease, "Opening one display stopped the other display's spectrum")
        vm2.open()
        try? await Task.sleep(for: .seconds(0.6))
        require(activities.spectrumRequest == restoredLease,
                "Expanded music restarted or stopped its shared spectrum")
        activities.receiveSpectrum(Array(repeating: 1, count: 6), for: restoredLease)
        try? await Task.sleep(for: .seconds(0.1))
        host.layoutSubtreeIfNeeded()
        let expanded = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: expanded)
        try! expanded.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("spectrum-expanded-music.png"))
        let contentRight = (host.bounds.width + vm.expandedNotchSize.width) / 2
            - cornerRadiusInsets.opened.top - MusicPlayerImageSizes.panelPadding
        let contentTop = max(24, vm.effectiveClosedNotchHeight) + MusicPlayerImageSizes.sectionSpacing
        var expandedBands: [Int] = [], bandHeight = 0
        var expandedSpans: [ClosedRange<Int>] = [], expandedStart: Int?
        for x in Int((contentRight - 20) * scale)..<Int(contentRight * scale) {
            var height = 0
            for y in Int((contentTop + 6) * scale)..<Int((contentTop + 36) * scale) {
                let c = expanded.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if min(c.redComponent, c.greenComponent, c.blueComponent) > 0.5 { height += 1 }
            }
            if height > 0 {
                if expandedStart == nil { expandedStart = x }
                bandHeight = max(bandHeight, height)
            } else if bandHeight > 0 {
                expandedSpans.append(expandedStart!...x - 1); expandedStart = nil
                expandedBands.append(bandHeight); bandHeight = 0
            }
        }
        if bandHeight > 0 {
            expandedSpans.append(expandedStart!...Int(contentRight * scale) - 1)
            expandedBands.append(bandHeight)
        }
        require(expandedBands.count == 6 && expandedBands.min()! >= Int(16 * scale),
                "Expanded music did not reserve a full six-bar spectrum at the information area's right edge: \(expandedBands)")
        requireUniformSpectrumSpans(expandedSpans, context: "expanded spectrum")
        activities.post(.musicChange)
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest == restoredLease, "A song-change emphasis stopped the visible expanded spectrum")
        activities.end(.musicChange)
        Defaults[.musicLiveActivityEnabled] = false
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest == restoredLease, "Turning off compact music disabled explicitly visible expanded music")
        Defaults[.musicLiveActivityEnabled] = true
        try? await Task.sleep(for: .seconds(0.1))
        firstSelectPage(.reminders)
        secondSelectPage(.timer)
        try? await Task.sleep(for: .seconds(0.2))
        require(activities.spectrumRequest == nil && activities.spectrumSnapshot == MusicSpectrumState.quiet,
                "Browsing away from all music pages retained capture")
        vm.close()
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest != nil && activities.spectrumRequest != lease, "Visible spectrum did not acquire a fresh lease")
        activities.receiveSpectrum(Array(repeating: 1, count: 6), for: lease)
        require(activities.spectrumSnapshot == MusicSpectrumState.quiet, "A queued frame revived after reopening")
        timer.start(duration: 1500)
        require(activities.current?.kind == .timer && activities.spectrumRequest == nil,
                "Spectrum bypassed scheduled timer priority")
        timer.cancel()
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest != nil, "Music spectrum did not recover after timer cancellation")
        activities.setMusicSpectrumSource(bundleIdentifier: nil, playing: false)
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.spectrumRequest == nil, "Losing the player source left capture active")
        print("PASS: automatically enabled six-band spectrum, obsolete off preference ignored, cover-height ceiling, shared compact/expanded lease, peek exclusion, hidden/source-loss stop, stale-frame rejection and timer preemption/recovery; hardware capture is inert in this fixture")
    }

    @MainActor static func verifySpectrumSettling(output: URL) async {
        let activities = ActivityCoordinator.shared
        let consumer = UUID()
        activities.setSpectrumVisible(true, consumer: consumer, expanded: true)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AudioSpectrumView(isPlaying: .constant(true), maximumHeight: 40)
            .foregroundStyle(.white).background(.black))
        window.contentView = host; window.orderBack(nil)
        defer {
            IslandArtworkRenderProbe.reduceMotion = false
            window.orderOut(nil); window.contentView = nil
            activities.setSpectrumVisible(false, consumer: consumer)
        }
        func height(_ name: String) -> Int {
            host.layoutSubtreeIfNeeded()
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            return (0..<image.pixelsWide).map { x in
                (0..<image.pixelsHigh).filter { y in
                    image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent > 0.25
                }.count
            }.max()!
        }
        try? await Task.sleep(for: .seconds(0.1))
        activities.receiveSpectrum(Array(repeating: 1, count: 6), for: activities.spectrumRequest!)
        try? await Task.sleep(for: .seconds(0.06))
        let loud = height("spectrum-reset-before")
        activities.setMusicSpectrumSource(bundleIdentifier: "fixture.player", playing: true, trackIdentifier: UUID())
        try? await Task.sleep(for: .seconds(0.025))
        let early = height("spectrum-reset-early")
        try? await Task.sleep(for: .seconds(0.07))
        let middle = height("spectrum-reset-middle")
        try? await Task.sleep(for: .seconds(0.18))
        let quiet = height("spectrum-reset-quiet")
        require(early > middle && middle > quiet * 2 && quiet < loud / 5,
                "Track reset did not visibly settle through intermediate heights: \(loud), \(early), \(middle), \(quiet)")
        activities.receiveSpectrum(Array(repeating: 0.8, count: 6), for: activities.spectrumRequest!)
        try? await Task.sleep(for: .seconds(0.04))
        let resumed = height("spectrum-reset-resumed")
        require(Double(resumed) > Double(loud) * 0.7, "Live frames acquired an unwanted extra interpolation")
        IslandArtworkRenderProbe.reduceMotion = true
        activities.receiveSpectrum(Array(repeating: 0.6, count: 6), for: activities.spectrumRequest!)
        try? await Task.sleep(for: .seconds(0.025))
        require(height("spectrum-reset-reduced-motion") <= quiet + 1, "Reduce Motion animated the spectrum reset")
        print("PASS: source reset visibly settles, live frames stay direct, and Reduce Motion resets immediately (heights \(loud), \(early), \(middle), \(quiet))")
    }

    @MainActor static func verifySpectrumPixelSpacing(output: URL) {
        for scale: CGFloat in [1, 2] {
            let renderer = ImageRenderer(content:
                AudioSpectrumView(isPlaying: .constant(false), maximumHeight: 20)
                    .foregroundStyle(.white)
                    .background(.black)
                    .environment(\.displayScale, scale))
            renderer.scale = scale
            let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
            var spans: [ClosedRange<Int>] = [], start: Int?
            for x in 0..<rep.pixelsWide {
                let visible = (0..<rep.pixelsHigh).contains { y in
                    let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return color.redComponent > 0.3
                }
                if visible, start == nil { start = x }
                if !visible, let first = start { spans.append(first...x - 1); start = nil }
            }
            if let first = start { spans.append(first...rep.pixelsWide - 1) }
            try! rep.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent("spectrum-grid-\(Int(scale))x.png"))
            requireUniformSpectrumSpans(spans, context: "\(Int(scale))x spectrum")
        }
    }

    static func requireUniformSpectrumSpans(_ spans: [ClosedRange<Int>], context: String) {
        let widths = spans.map { $0.count }
        let gaps = zip(spans, spans.dropFirst()).map { $1.lowerBound - $0.upperBound - 1 }
        require(spans.count == 6 && Set(widths).count == 1 && Set(gaps).count == 1,
                "\(context) has unequal pixel widths or gaps: widths=\(widths), gaps=\(gaps)")
    }

    @MainActor static func verifyMusicEntry(output: URL) async {
        let previousReminders = Defaults[.remindersActivityEnabled]
        let previousTimer = Defaults[.timerActivityEnabled]
        let previousLighting = Defaults[.lightingEffect]
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        defer {
            Defaults[.remindersActivityEnabled] = previousReminders
            Defaults[.timerActivityEnabled] = previousTimer
            Defaults[.lightingEffect] = previousLighting
            IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
        }
        Defaults[.remindersActivityEnabled] = true
        Defaults[.timerActivityEnabled] = true
        Defaults[.lightingEffect] = true
        IslandArtworkRenderProbe.reduceMotion = false
        TimerActivityManager.shared.cancel()
        let music = MusicManager.shared
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        vm.hideOnClosed = false
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil; vm.destroy() }
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        let appearances = IslandArtworkRenderProbe.appearances
        let identity = music.albumArtTrackIdentifier
        let inset = cornerRadiusInsets.opened.top + MusicPlayerImageSizes.panelPadding + MusicPlayerImageSizes.padding
        let side = MusicPlayerImageSizes.expandedSide(headerHeight: max(24, vm.effectiveClosedNotchHeight))
        let leading = (host.bounds.width - vm.expandedNotchSize.width) / 2
        let top = max(24, vm.effectiveClosedNotchHeight) + MusicPlayerImageSizes.sectionSpacing + MusicPlayerImageSizes.padding

        // Read the cover and title pixels, not just the animation's inputs.
        var capturedTitleLeading: CGFloat?
        func capture(_ name: String? = nil) -> CGFloat? {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            if let name {
                try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            }
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let titleLeft = (Int((leading + 12) * scale)..<rep.pixelsWide).first { x in
                (Int(top * scale)..<Int((top + 25) * scale)).contains { y in
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return min(c.redComponent, c.greenComponent, c.blueComponent) > 0.96
                }
            }
            capturedTitleLeading = titleLeft.map { CGFloat($0) / scale }
            let row = Int((top + side / 2) * scale)
            let right = (0..<rep.pixelsWide).last { x in
                let c = rep.colorAt(x: x, y: row)!.usingColorSpace(.deviceRGB)!
                return c.redComponent > 0.78 && c.redComponent < 0.94 && c.greenComponent > 0.97 && c.blueComponent > 0.97
            }
            return right.map { CGFloat($0 + 1) / scale }
        }
        let finalRight = capture("music-entry-resting")!
        let finalTitleLeading = capturedTitleLeading!
        require(abs(finalRight - (leading + inset + side)) < 2, "Resting cover moved out of its original slot")

        let gestureInput = HorizontalPagingGesture.Coordinator { delta, seconds, phase in
            IslandArtworkRenderProbe.horizontalGesture?(delta, seconds, phase)
        }
        defer { gestureInput.remove() }
        var eventTime: Double = 1000
        func sendNative(_ phase: CGScrollPhase, delta: Int32 = 0, seconds: Double = 0.02) {
            eventTime += seconds
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                             wheel1: 0, wheel2: -delta, wheel3: 0)!
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            cg.timestamp = UInt64(eventTime * 1_000_000_000)
            _ = gestureInput.handleScrollEvent(NSEvent(cgEvent: cg)!)
        }

        // Pull beyond the music boundary, release, then reverse toward reminders.
        // A return to the same page must keep the persistent cover on the page's
        // rendered curve; the separate incoming-cover spring belongs to a page switch.
        for reduced in [false, true] {
            IslandArtworkRenderProbe.reduceMotion = reduced
            sendNative(.began)
            for _ in 0..<16 {
                sendNative(.changed, delta: -18, seconds: 0.05)
                try? await Task.sleep(for: .seconds(0.05))
            }
            require(IslandArtworkRenderProbe.selectedPage == .music, "Boundary pull changed the selected page")
            sendNative(.ended)
            var maxError: CGFloat = 0
            for index in 0..<18 {
                try? await Task.sleep(for: .seconds(0.016))
                let edge = capture(index % 4 == 0 ? "music-boundary-return-\(reduced)-\(index)" : nil)!
                let expected = finalRight - IslandArtworkRenderProbe.renderedPagePosition * vm.expandedNotchSize.width
                maxError = max(maxError, abs(edge - expected))
            }
            require(maxError < 3, "Boundary return detached cover from music card by \(maxError) points (Reduce Motion: \(reduced))")
            // Resting fingers on the trackpad emits mayBegin before the next
            // actual swipe. This used to replay the previous full boundary pull.
            sendNative(.mayBegin, seconds: 0.5)
            for index in 0..<8 {
                try? await Task.sleep(for: .seconds(0.016))
                let edge = capture(index == 0 ? "music-native-preparation-\(reduced)" : nil)!
                require(abs(edge - finalRight) < 2 && abs(capturedTitleLeading! - finalTitleLeading) < 2,
                        "Native preparation restored the old card offset: cover=\(edge - finalRight), title=\(capturedTitleLeading! - finalTitleLeading)")
            }
            let beforeReverse = capture()!
            sendNative(.began)
            sendNative(.changed, delta: 4, seconds: 0.05)
            try? await Task.sleep(for: .seconds(0.016))
            let afterReverse = capture("music-boundary-reverse-\(reduced)")!
            require(abs(afterReverse - beforeReverse) < 6 && abs(capturedTitleLeading! - finalTitleLeading) < 6,
                    "Slow reverse swipe jumped the music card")
            sendNative(.changed, delta: Int32(vm.expandedNotchSize.width / 2))
            sendNative(.ended)
            try? await Task.sleep(for: .seconds(0.4))
            require(IslandArtworkRenderProbe.selectedPage == .reminders && capture() == nil,
                    "Reverse swipe did not settle on reminders")
            IslandArtworkRenderProbe.selectPage?(.music)
            try? await Task.sleep(for: .seconds(0.7))
        }
        IslandArtworkRenderProbe.reduceMotion = false

        for page in [IslandPage.reminders, .timer] {
            IslandArtworkRenderProbe.selectPage?(page)
            try? await Task.sleep(for: .seconds(0.4))
            require(capture() == nil, "Cover remained on a non-music page")
            IslandArtworkRenderProbe.selectPage?(.music)
            var samples: [(TimeInterval, CGFloat, CGFloat?)] = []
            let began = Date()
            for index in 0..<35 {
                try? await Task.sleep(for: .seconds(0.016))
                let edge = capture(index % 4 == 0 ? "music-entry-\(page)-\(index)" : nil)
                samples.append((Date().timeIntervalSince(began), IslandArtworkRenderProbe.renderedPagePosition, edge))
            }
            let trailing = samples.filter { abs($0.1) < 0.01 && ($0.2 ?? -10000) < finalRight - 3 }
            let visible = samples.compactMap(\.2)
            require(!trailing.isEmpty, "Cover did not trail the settled page: \(samples)")
            require(Set(visible.map { Int($0) }).count >= 5 && abs(visible.last! - finalRight) < 2,
                    "Cover did not move continuously from the left and settle into its slot: \(samples)")
            require(zip(visible, visible.dropFirst()).allSatisfy { $1 >= $0 - 1.5 }, "Cover overshot or moved backward")
            let pageSettled = samples.first { abs($0.1) < 0.01 }!.0
            require(pageSettled < 0.24, "The existing page transition was slowed down: \(pageSettled)")
        }
        // A sub-threshold drag still follows the finger and returns to its page.
        IslandArtworkRenderProbe.selectPage?(.reminders)
        try? await Task.sleep(for: .seconds(0.4))
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
        IslandArtworkRenderProbe.horizontalGesture?(-30, 0.1, .changed)
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
        try? await Task.sleep(for: .seconds(0.4))
        require(IslandArtworkRenderProbe.selectedPage == .reminders && capture() == nil, "Cancelled swipe exposed the cover")
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
        IslandArtworkRenderProbe.horizontalGesture?(-vm.expandedNotchSize.width / 2, 0.02, .changed)
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
        try? await Task.sleep(for: .seconds(0.19))
        let midSwipe = capture("music-entry-swipe-trailing")
        require(abs(IslandArtworkRenderProbe.renderedPagePosition) < 0.01 && (midSwipe ?? -10000) < finalRight - 3,
                "Committed swipe lost the independent cover follow-through")
        // Reverse while the cover is still catching up; its identity must survive.
        IslandArtworkRenderProbe.selectPage?(.reminders)
        try? await Task.sleep(for: .seconds(0.045))
        IslandArtworkRenderProbe.selectPage?(.music)
        try? await Task.sleep(for: .seconds(0.7))
        require(abs(capture()! - finalRight) < 2 && IslandArtworkRenderProbe.appearances == appearances
                    && music.albumArtTrackIdentifier == identity,
                "Rapid reversal recreated the cover or restored a stale position")

        // Reopening follows the resident activity, rather than playing a page entry.
        // Read cover pixels against each rendered expansion frame, not a settled snapshot.
        for (page, closedWait): (IslandPage, TimeInterval) in [
            (.reminders, 0.65), (.timer, 0.65), (.reminders, 0.08), (.timer, 0.08)
        ] {
            IslandArtworkRenderProbe.selectPage?(page)
            try? await Task.sleep(for: .seconds(0.35))
            vm.close()
            try? await Task.sleep(for: .seconds(closedWait))
            require(ActivityCoordinator.shared.current?.kind == .music, "Fixture lost resident music")
            vm.open()
            var measured = 0
            for _ in 0..<24 {
                try? await Task.sleep(for: .seconds(0.016))
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / host.bounds.width
                let surface = IslandArtworkRenderProbe.surfaceSize
                let p = min(1, max(0, (surface.height - vm.effectiveClosedNotchHeight)
                    / (vm.expandedNotchSize.height - vm.effectiveClosedNotchHeight)))
                let height = vm.effectiveClosedNotchHeight
                let compactSide = MusicPlayerImageSizes.compactSide(height: height)
                let compactInset = MusicPlayerImageSizes.compactOuterInset(height: height)
                let compactTop = MusicPlayerImageSizes.compactPadding(height: height)
                let coverSide = compactSide + (side - compactSide) * p
                let expected = (host.bounds.width - surface.width) / 2
                    + compactInset + (inset - compactInset) * p + coverSide
                let row = Int((compactTop + (top - compactTop) * p + coverSide / 2) * scale)
                var right = -1
                for x in 0..<rep.pixelsWide / 2 {
                    let c = rep.colorAt(x: x, y: row)!.usingColorSpace(.deviceRGB)!
                    if c.redComponent > 0.78 && c.redComponent < 0.94 && c.greenComponent > 0.97 && c.blueComponent > 0.97 {
                        right = max(right, x)
                    }
                }
                if p > 0.12 && right >= 0 {
                    let actual = CGFloat(right + 1) / scale
                    require(abs(actual - expected) < 3,
                            "Reopening from \(page) replayed horizontal cover entry: actual=\(actual), expected=\(expected), expansion=\(p)")
                    measured += 1
                }
            }
            require(measured >= 6 && IslandArtworkRenderProbe.selectedPage == .music,
                    "Reopen regression did not measure the music cover through expansion")
        }

        IslandArtworkRenderProbe.reduceMotion = true
        IslandArtworkRenderProbe.selectPage?(.reminders)
        try? await Task.sleep(for: .seconds(0.1))
        IslandArtworkRenderProbe.selectPage?(.music)
        try? await Task.sleep(for: .seconds(0.04))
        require(abs(capture("music-entry-reduced-motion")! - finalRight) < 2,
                "Reduce Motion retained a delayed cover animation")
        IslandArtworkRenderProbe.reduceMotion = false
        print("PASS: native boundary pull/return/preparation/reverse keeps card and cover stable, music entry timing, swipe commit/cancel, rapid reversal, resident-page reopening, persistent identity and Reduce Motion")
    }

    @MainActor static func renderRemindersPage(output: URL) async {
        let source = RemindersActivityManager.shared
        let activities = ActivityCoordinator.shared
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        defer { vm.destroy() }
        var addButtonFrame: CGRect?
        func snapshot(_ name: String, verifyScroll: Bool = false, timer: Bool = false) async {
            IslandArtworkRenderProbe.actionFrames = [:]
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 190),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.orderOut(nil); window.contentView = nil }
            let host = NSHostingView(rootView: Group {
                if timer { TimerActivityPage() }
                else { RemindersActivityPage() }
            }.environmentObject(vm)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .preferredColorScheme(.dark)
                .frame(width: 418, height: 138).frame(width: 480, height: 190).background(.black))
            window.contentView = host
            window.orderBack(nil)
            try? await Task.sleep(for: .seconds(0.7))
            host.layoutSubtreeIfNeeded()
            if let frame = IslandArtworkRenderProbe.actionFrames["plus"] { addButtonFrame = frame }
            if timer {
                guard let start = IslandArtworkRenderProbe.actionFrames["play.fill"], let add = addButtonFrame else {
                    require(false, "Could not measure the timer and reminder page buttons")
                    return
                }
                require(abs(start.width - 44) < 0.1 && abs(start.height - 44) < 0.1
                            && abs(start.minX - add.minX) < 0.1 && abs(start.minY - add.minY) < 0.1
                            && abs(start.width - add.width) < 0.1 && abs(start.height - add.height) < 0.1,
                        "Start and add buttons differ in size or position: start=\(start), add=\(add)")
                func timeWheels(in view: NSView) -> [NSScrollView] {
                    if let scroll = view as? NSScrollView { return [scroll] }
                    return view.subviews.flatMap { timeWheels(in: $0) }
                }
                let wheels = timeWheels(in: host)
                let originalCenter = (190.0 - 138.0) / 2 + (138.0 - 48.0) / 2
                require(wheels.count == 3 && wheels.allSatisfy {
                    let frame = $0.convert($0.bounds, to: host)
                    let center = host.isFlipped ? frame.midY : host.bounds.height - frame.midY
                    return abs(center - originalCenter) < 1
                }, "Fixing the start button moved the picker away from its original centered position")
            }
            if verifyScroll {
                func scrollView(in view: NSView) -> NSScrollView? {
                    if let scroll = view as? NSScrollView { return scroll }
                    return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
                }
                guard let scroll = scrollView(in: host), let document = scroll.documentView else {
                    require(false, "Reminders page has no native scroll region")
                    return
                }
                let viewport = scroll.convert(scroll.bounds, to: host)
                let scrollBottom = host.isFlipped ? viewport.maxY : host.bounds.height - viewport.minY
                require(addButtonFrame.map { abs(scrollBottom - $0.maxY) < 1 } == true && viewport.height > 100,
                        "Reminder scroll region did not align with the add button bottom: bottom=\(scrollBottom), button=\(String(describing: addButtonFrame))")
                let target = document.isFlipped ? max(0, document.bounds.maxY - scroll.contentView.bounds.height) : document.bounds.minY
                scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
                scroll.reflectScrolledClipView(scroll.contentView)
                try? await Task.sleep(for: .seconds(0.3))
                host.layoutSubtreeIfNeeded()
                require(!document.isFlipped || scroll.documentVisibleRect.maxY >= document.bounds.maxY - 1,
                        "Could not scroll to the last reminder")
            }
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        Defaults[.remindersActivityEnabled] = true
        Defaults[.reminderListIdentifier] = ""
        source.authorized = false
        await snapshot("reminders-disconnected")
        source.accessDenied = true
        await snapshot("reminders-permission-denied")
        source.authorized = true
        source.accessDenied = false
        activities.setReminders([ReminderTask(id: "1", title: "体检", dueDate: nil),
                                 ReminderTask(id: "2", title: "剪头发", dueDate: nil)])
        await snapshot("reminders-authorized-all")
        source.lists = [ReminderList(id: "personal", title: "个人待办", account: "", writable: true)]
        Defaults[.reminderListIdentifier] = "personal"
        await snapshot("reminders-authorized-list")
        activities.setReminders((1...12).map {
            ReminderTask(id: "\($0)", title: "第 \($0) 项待办：检查完整滚动区域与右侧按钮留白", dueDate: nil)
        })
        await snapshot("reminders-long-list-bottom", verifyScroll: true)
        Defaults[.timerActivityEnabled] = true
        activities.setTimer(nil)
        await snapshot("timer-start-button-alignment", timer: true)
        print("PASS: reminder page snapshots rendered with isolated permission/list fixtures; no EventKit connection")
    }

    @MainActor static func verifyActionButtonSizes(output: URL) async {
        let actions: [(String, String, String, Color?)] = [
            ("reset", "Reset timer", "xmark", nil), ("start", "Start", "play.fill", .orange),
            ("pause", "Pause timer", "pause.fill", .orange), ("resume", "Resume timer", "play.fill", .orange),
            ("restart", "Restart timer", "arrow.clockwise", .orange), ("close", "Close", "xmark", nil),
            ("add", "Add reminder", "plus", .blue),
            ("disabled", "Start", "play.fill", .orange)
        ]
        var sizes: [String: CGSize] = [:]
        let fixture = HStack(spacing: 12) {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                IslandActionButton(LocalizedStringKey(action.1), icon: action.2, tint: action.3) {}
                    .disabled(action.0 == "disabled")
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ActionButtonSizes.self, value: [action.0: geometry.size])
                        }
                    }
            }
        }
        .onPreferenceChange(ActionButtonSizes.self) { sizes = $0 }
        .frame(width: 480, height: 190).background(.black).preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 190),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil }
        let host = NSHostingView(rootView: fixture)
        window.contentView = host
        window.orderBack(nil)
        try? await Task.sleep(for: .seconds(0.4))
        host.layoutSubtreeIfNeeded()
        require(sizes.count == actions.count && sizes.values.allSatisfy { abs($0.width - 44) < 0.1 && abs($0.height - 44) < 0.1 },
                "Island actions did not keep equal 44-point visual and hit bounds: \(sizes)")
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("native-island-action-buttons.png"))
        print("PASS: all eight island action/disabled variants have equal 44-point bounds")
    }

    @MainActor static func verifyAlarmMotion(output: URL) async {
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        IslandArtworkRenderProbe.reduceMotion = false
        defer { IslandArtworkRenderProbe.reduceMotion = previousReduceMotion }
        let source = TimerActivityManager.shared
        Defaults[.timerActivityEnabled] = true
        source.start(duration: 1)
        try? await Task.sleep(for: .seconds(1.1))
        defer { source.cancel(); source.stop() }
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 190),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; vm.destroy() }
        func frames<V: View>(_ view: V, name: String, prepare: (() -> Void)? = nil) async -> Int {
            let host = NSHostingView(rootView: view.environmentObject(vm).preferredColorScheme(.dark)
                .frame(width: 418, height: 138).frame(width: 480, height: 190).background(.black))
            window.contentView = host
            window.orderBack(nil)
            try? await Task.sleep(for: .seconds(0.2))
            prepare?()
            try? await Task.sleep(for: .seconds(0.7))
            var distinct = Set<Data>()
            for index in 0..<45 {
                try? await Task.sleep(for: .seconds(0.08))
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                distinct.insert(Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
                if index % 5 == 0 {
                    try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("alarm-\(name)-\(index).png"))
                }
            }
            print("Alarm motion probe: \(name), \(distinct.count) distinct rendered frames")
            return distinct.count
        }
        let standalone = await frames(TimerFinishedIcon(), name: "standalone")
        require(standalone >= 8, "Alarm icon remained static while active")
        let page = await frames(TimerActivityPage(), name: "page")
        require(page >= 8, "Alarm animation stopped inside the production timer page")
        let automatic = await frames(ContentView(), name: "auto-expanded")
        require(automatic >= 8, "Alarm animation stopped inside the automatically expanded island")
        require(vm.notchState == .open && IslandArtworkRenderProbe.selectedPage == .timer
                    && abs(IslandArtworkRenderProbe.renderedPagePosition - CGFloat(IslandArtworkRenderProbe.availablePages.firstIndex(of: .timer) ?? 0)) < 0.01
                    && abs(IslandArtworkRenderProbe.surfaceSize.width - vm.expandedNotchSize.width) < 1
                    && abs(IslandArtworkRenderProbe.surfaceSize.height - vm.expandedNotchSize.height) < 1,
                "Pending completion did not automatically use the full timer page")
        let expanded = await frames(ContentView(), name: "expanded", prepare: { vm.open() })
        require(expanded >= 8, "Alarm animation stopped inside the expanded island")
        IslandArtworkRenderProbe.reduceMotion = true
        let reduced = await frames(TimerActivityPage(), name: "reduced-motion")
        require(reduced == 1, "Reduce Motion did not stop the alarm animation")
        IslandArtworkRenderProbe.reduceMotion = false
        let inactive = await frames(TimerActivityPage(active: false), name: "inactive")
        require(inactive == 1, "An inactive timer page kept animating its alarm")
    }

    @MainActor static func verifyDisplayWidths() {
        let original = Defaults[.nonNotchWidthPercentage]
        defer {
            Defaults[.nonNotchWidthPercentage] = original
        }
        for (screen, percent, expected): (CGFloat, CGFloat, CGFloat) in [
            (800, 10, 120), (1440, 10, 144), (1920, 10, 192),
            (2560, 10, 256), (5120, 10, 320), (1440, 20, 144),
            (1920, 5, 120), (1920, 100, 192), (1920, -1, 120),
            (1920, .nan, 192)
        ] {
            require(abs(NonNotchWidth.resolve(screenWidth: screen, percentage: percent) - expected) < 0.01,
                    "Incorrect proportional width for screen \(screen), percentage \(percent)")
        }
        for (base, screen, expected): (CGFloat, CGFloat, CGFloat) in [
            (120, 1920, 400), (192, 1920, 480), (256, 2560, 640),
            (320, 2560, 800), (320, 800, 760), (320, 300, 260), (500, 2560, 960)
        ] {
            require(abs(ExpandedNotchWidth.resolve(baseWidth: base, screenWidth: screen) - expected) < 0.01,
                    "Expanded width ignored its base, fixed multiplier or screen boundary")
        }
        for percent: CGFloat in [5, 10, 20] {
            Defaults[.nonNotchWidthPercentage] = percent
            for screen in NSScreen.screens {
                let size = getClosedNotchSize(screenUUID: screen.displayUUID)
                let expanded = getExpandedNotchSize(baseWidth: size.width, screenUUID: screen.displayUUID)
                if screen.safeAreaInsets.top == 0 {
                    let expected = min(320, max(120, screen.frame.width * min(10, max(5, percent)) / 100))
                    require(abs(size.width - expected) < 0.01, "Width used a different display or ignored its preference")
                    require(abs(expanded.width - min(screen.frame.width - 40, min(960, max(400, expected * 2.5)))) < 0.01,
                            "Expanded width used a different display or ignored its multiplier")
                } else if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                    require(abs(size.width - (screen.frame.width - left.width - right.width + 4)) < 0.01,
                            "Proportional sizing changed a physical notch")
                    require(expanded == CGSize(width: 480, height: 190), "Non-notch preferences resized a notched display")
                }
            }
        }
        print("PASS: proportional width, limits, persisted preference and per-display sizing")
    }

    @MainActor static func renderSizingSettings(output: URL) async {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 720, height: 980),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: PresentationSettings().formStyle(.grouped)
            .environment(\.locale, Locale(identifier: "zh-Hans")))
        window.contentView = host
        window.orderBack(nil)
        try? await Task.sleep(for: .seconds(0.2))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("proportional-width-settings.png"))
        window.orderOut(nil)
        window.contentView = nil
    }

    @MainActor static func verifyWidthAdjustment(output: URL) async {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top == 0 }) else { return }
        let originalPercentage = Defaults[.nonNotchWidthPercentage]
        defer {
            Defaults[.nonNotchWidthPercentage] = originalPercentage
        }
        Defaults[.nonNotchWidthPercentage] = 5
        Defaults[.lightingEffect] = true
        ActivityCoordinator.shared.setMusicActive(true)
        let vm = IslandViewModel(screenUUID: screen.displayUUID)
        defer { vm.destroy() }
        vm.hideOnClosed = false
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 210),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        let initial = IslandArtworkRenderProbe.surfaceSize.width
        Defaults[.nonNotchWidthPercentage] = 20
        vm.closedNotchSize = getClosedNotchSize(screenUUID: screen.displayUUID)
        let target = vm.expandedNotchSize.width
        var intermediates = 0
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(0.016))
            host.layoutSubtreeIfNeeded()
            let size = IslandArtworkRenderProbe.surfaceSize
            require(size.width >= initial - 1 && size.width <= target + 1, "Width adjustment overshot its endpoints")
            require(abs(IslandArtworkRenderProbe.musicBackgroundFrame.width - size.width) < 2,
                    "Music background did not follow the animated expanded width")
            if size.width > initial + 1 && size.width < target - 1 { intermediates += 1 }
        }
        require(intermediates >= 3 && abs(IslandArtworkRenderProbe.surfaceSize.width - target) < 1,
                "Changing width preferences snapped or failed to reach its derived width")
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("expanded-width-adjustment.png"))
        print("PASS: live expanded width adjustment, \(intermediates) intermediate frames, page background synchronized")
    }

    @MainActor static func verifyCompactAlignment(output: URL) async {
        let source = TimerActivityManager.shared
        let activities = ActivityCoordinator.shared
        Defaults[.timerActivityEnabled] = true
        Defaults[.lightingEffect] = false
        source.cancel()
        defer { source.cancel(); source.stop() }
        for (height, width): (CGFloat, CGFloat) in [(15, 185), (24, 120), (24, 185), (24, 320), (32, 120), (32, 185), (32, 320)] {
            let screen = NSScreen.screens.first { $0.safeAreaInsets.top == 0 } ?? NSScreen.screens[0]
            let vm = IslandViewModel(screenUUID: screen.displayUUID)
            vm.hideOnClosed = false
            vm.closedNotchSize = CGSize(width: width, height: height)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 210),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.setContentSize(vm.windowSize)
            let host = NSHostingView(rootView: ContentView().environmentObject(vm)
                .environment(\.locale, Locale(identifier: "zh-Hans")))
            window.contentView = host
            window.orderBack(nil)
            defer {
                window.orderOut(nil)
                window.contentView = nil
                vm.destroy()
            }
            func capture(_ name: String) -> CGFloat {
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("compact-\(Int(height))-\(Int(width))-\(name).png"))
                let scale = CGFloat(rep.pixelsWide) / host.bounds.width
                let surface = IslandArtworkRenderProbe.surfaceSize
                let surfaceLeft = (host.bounds.width - surface.width) / 2
                var first = rep.pixelsWide, last = -1
                var coverTop = rep.pixelsHigh, coverBottom = -1
                for y in 0..<Int(height * scale) {
                    for x in Int(ceil(surfaceLeft * scale))..<Int(floor((surfaceLeft + surface.width) * scale)) {
                        let pixel = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if pixel.alphaComponent > 0.5 && max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.15 {
                            first = min(first, x); last = max(last, x)
                            if x < rep.pixelsWide / 2 {
                                coverTop = min(coverTop, y)
                                coverBottom = max(coverBottom, y)
                            }
                            let point = (CGFloat(x) + 0.5) / scale
                            require(abs(point - host.bounds.midX) >= vm.closedNotchSize.width / 2,
                                    "Compact content entered the physical notch safe area: \(name)")
                        }
                    }
                }
                require(first < rep.pixelsWide / 2 && last > rep.pixelsWide / 2, "Missing compact content: \(name)")
                let leading = CGFloat(first) / scale - surfaceLeft
                let trailing = surfaceLeft + surface.width - CGFloat(last + 1) / scale
                require(abs(leading - trailing) <= 3,
                        "Unequal compact outer margins in \(name), height \(height): left \(leading), right \(trailing)")
                if name == "music" {
                    let expectedPadding: CGFloat = height == 15 ? 2.8125 : (height == 24 ? 4.5 : 6)
                    let expectedInset = (height == 15 ? 4.5 : 6) + expectedPadding
                    require(abs(leading - expectedInset) <= 1 && abs(trailing - expectedInset) <= 1,
                            "Music horizontal margins do not fit the height: left \(leading), right \(trailing)")
                    let top = CGFloat(coverTop) / scale
                    let bottom = height - CGFloat(coverBottom + 1) / scale
                    require(abs(top - expectedPadding) <= 1 && abs(bottom - expectedPadding) <= 1,
                            "Cover should grow with balanced vertical margins: top \(top), bottom \(bottom)")
                }
                require(surface.width <= vm.expandedNotchSize.width + 1, "Compact content exceeded its window budget")
                print("PASS: compact \(name), height \(height), outer margins \(leading)/\(trailing), width \(surface.width)")
                return surface.width
            }
            if height < 24 {
                try? await Task.sleep(for: .seconds(0.7))
                _ = capture("music")
                continue
            }
            source.start(duration: 1500)
            try? await Task.sleep(for: .seconds(0.7))
            let short = capture("timer-minutes")
            source.start(duration: 3660)
            try? await Task.sleep(for: .seconds(0.7))
            let long = capture("timer-hours")
            require(long > short + 5, "Compact timer width did not adapt to its longer time label")
            source.cancel()
            try? await Task.sleep(for: .seconds(0.7))
            _ = capture("music")
            for kind in IslandActivityKind.allCases where kind.isSystemFeedback {
                activities.post(kind, value: 0.5)
                try? await Task.sleep(for: .seconds(0.7))
                _ = capture(kind.rawValue)
                activities.end(kind)
            }
        }
    }

    @MainActor static func verifyFinishedTimerCollapse(output: URL) async {
        let source = TimerActivityManager.shared
        let activities = ActivityCoordinator.shared
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        let previousTimerEnabled = Defaults[.timerActivityEnabled]
        Defaults[.timerActivityEnabled] = true
        source.cancel()
        activities.setMusicActive(true)
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        vm.hideOnClosed = false
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer {
            source.cancel(); window.orderOut(nil); window.contentView = nil; vm.destroy()
            IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
            Defaults[.timerActivityEnabled] = previousTimerEnabled
        }
        func expansion() -> CGFloat {
            min(1, max(0, (IslandArtworkRenderProbe.surfaceSize.height - vm.effectiveClosedNotchHeight)
                / (vm.expandedNotchSize.height - vm.effectiveClosedNotchHeight)))
        }
        func snapshot(_ name: String, requireText: Bool) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            if requireText {
                let scale = CGFloat(rep.pixelsWide) / host.bounds.width
                let frame = IslandArtworkRenderProbe.finishedTimerTextFrame
                var orange = 0
                for y in max(0, Int(frame.minY * scale))..<min(rep.pixelsHigh, Int(frame.maxY * scale)) {
                    for x in max(0, Int(frame.minX * scale))..<min(rep.pixelsWide, Int(frame.maxX * scale)) {
                        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if c.redComponent > 0.5 && c.greenComponent > 0.2 && c.blueComponent < 0.2 { orange += 1 }
                    }
                }
                require(orange > 20, "Finished timer text vanished from an early closing frame")
            }
        }
        func wheels(in view: NSView) -> [NSScrollView] {
            if let scroll = view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap { wheels(in: $0) }
        }
        for (index, mode) in [(false, false, false, false), (true, false, false, false),
                              (false, true, false, false), (true, true, false, false),
                              (false, false, true, false), (true, false, true, false),
                              (false, false, false, true), (true, false, false, true)].enumerated() {
            let (restart, interrupt, reduced, external) = mode
            IslandArtworkRenderProbe.reduceMotion = reduced
            source.cancel()
            var finished = TimerSession(duration: 75, now: Date().addingTimeInterval(-76))!
            require(finished.finishIfDue(at: Date()), "Fixture did not reach its real deadline")
            activities.setTimer(finished)
            UserDefaults.standard.set(try! JSONEncoder().encode(finished), forKey: "AirIsland.timerSession.v1")
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(0.016))
                if vm.notchState == .open && expansion() > 0.999 && IslandArtworkRenderProbe.finishedTimerTexts > 0 { break }
            }
            require(IslandArtworkRenderProbe.finishedTimerTexts > 0, "Finished timer page was not mounted")
            snapshot("timer-dismiss-\(index)-before", requireText: true)
            let action = IslandArtworkRenderProbe.actionHandlers[restart ? "arrow.clockwise" : "xmark"]
            require(action != nil, "Finished timer action was not available")
            if external {
                // The shared source path used when another island window confirms.
                if restart { source.start(duration: finished.duration) }
                else { source.cancel() }
            } else { action?() }
            if restart {
                require(activities.timer?.phase == .running && activities.timer?.id != finished.id
                            && activities.timer?.duration == 75,
                        "Restart waited for the closing animation instead of creating the real timer")
            } else {
                require(activities.timer == nil && UserDefaults.standard.data(forKey: "AirIsland.timerSession.v1") == nil,
                        "Close delayed cancellation or retained the finished record")
            }
            var retainedFrames = 0
            for frame in 0..<(interrupt ? 4 : 35) {
                try? await Task.sleep(for: .seconds(0.016))
                let progress = expansion()
                if !reduced && progress > 0.03 {
                    require(IslandArtworkRenderProbe.finishedTimerTexts > 0,
                            "Close/restart flashed the next timer page before collapse at \(progress)")
                    retainedFrames += 1
                }
                snapshot("timer-dismiss-\(index)-\(frame)", requireText: !reduced && progress > 0.85)
                if progress < 0.001 { break }
            }
            if !reduced { require(retainedFrames >= 2, "Closing regression did not inspect intermediate frames") }
            vm.open()
            try? await Task.sleep(for: .seconds(0.025))
            IslandArtworkRenderProbe.selectPage?(.timer)
            try? await Task.sleep(for: .seconds(0.65))
            require(IslandArtworkRenderProbe.finishedTimerTexts == 0,
                    "Reopening restored a stale finished page")
            if restart {
                require(activities.timer?.phase == .running && activities.timer!.remaining(at: Date()) > 70,
                        "Retiring UI reset the restarted business timer")
                require(wheels(in: host).isEmpty, "Restart reopened the initial picker")
            } else {
                require(wheels(in: host).count == 3, "Close did not restore the initial three-wheel picker")
                IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
                require(activities.timer?.duration == 1500, "Close restored 00:00 instead of the default 00:25:00 picker")
            }
            snapshot("timer-dismiss-\(index)-reopened", requireText: false)
        }
        print("PASS: finished close/restart retain rendered completion through collapse, update business immediately, restore default picker/new timer after hiding, and handle interrupted reopening and Reduce Motion")
    }

    @MainActor static func verifyPersonalActivityRuntime(output: URL) async {
        let source = TimerActivityManager.shared
        let activities = ActivityCoordinator.shared
        Defaults[.timerActivityEnabled] = true
        source.cancel()
        defer { source.cancel(); source.stop() }
        source.start(duration: 1)
        let oldID = activities.timer!.id
        source.start(duration: 2)
        let currentID = activities.timer!.id
        require(oldID != currentID, "Replacement timer reused the old identity")
        try? await Task.sleep(for: .seconds(1.1))
        require(activities.timer?.id == currentID && activities.timer?.phase == .running,
                "Old deadline completed a replacement timer")
        source.togglePause()
        try? await Task.sleep(for: .seconds(1.1))
        require(activities.timer?.phase == .paused, "Paused timer continued to its previous deadline")
        source.togglePause()
        try? await Task.sleep(for: .seconds(1.1))
        require(activities.timer?.phase == .finished && activities.current?.kind == .timerFinished,
                "Real timer completion did not enter scheduled emphasis")
        let finishedID = activities.timer!.id
        try? await Task.sleep(for: .seconds(2))
        activities.setTimer(activities.timer)
        require(activities.current?.kind == .timerFinished, "Completion alert disappeared without acknowledgement")
        try? await Task.sleep(for: .seconds(1.1))
        require(activities.current?.kind == .timerFinished, "Completion alert still uses the former three-second timeout")
        require(activities.timer?.id == finishedID && activities.timer?.phase == .finished,
                "Pending completion lost its timer identity")
        activities.setTimer(activities.timer)
        require(activities.current?.kind == .timerFinished, "Refreshing the finished record dismissed its pending alert")
        activities.setMusicActive(false)
        require(activities.current?.kind == .timerFinished, "Stopping music dismissed the pending completion alert")
        activities.setMusicActive(true)

        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 190),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil }
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        defer { vm.destroy() }
        vm.hideOnClosed = false
        window.setContentSize(vm.windowSize)
        let alertHost = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = alertHost
        window.orderBack(nil)
        // First creation of the native page can delay the start of the transition.
        // Wait for the real endpoint instead of mistaking a cold-layout frame for it.
        func settleSurface(expanded: Bool) async {
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(0.016))
                alertHost.layoutSubtreeIfNeeded()
                let size = IslandArtworkRenderProbe.surfaceSize
                if expanded {
                    if activities.current?.kind == .timerFinished && vm.notchState == .open
                        && IslandArtworkRenderProbe.selectedPage == .timer
                        && abs(IslandArtworkRenderProbe.renderedPagePosition - CGFloat(IslandArtworkRenderProbe.availablePages.firstIndex(of: .timer) ?? 0)) < 0.001
                        && abs(size.width - vm.expandedNotchSize.width) < 0.1
                        && abs(size.height - vm.expandedNotchSize.height) < 0.1 { break }
                } else if vm.notchState == .closed && abs(size.height - vm.effectiveClosedNotchHeight) < 0.1 { break }
            }
        }
        await settleSurface(expanded: true)
        func requireTimerPage(_ message: String) {
            require(activities.current?.kind == .timerFinished && vm.notchState == .open
                        && IslandArtworkRenderProbe.selectedPage == .timer
                        && abs(IslandArtworkRenderProbe.renderedPagePosition - CGFloat(IslandArtworkRenderProbe.availablePages.firstIndex(of: .timer) ?? 0)) < 0.01
                        && abs(IslandArtworkRenderProbe.surfaceSize.width - vm.expandedNotchSize.width) < 1
                        && abs(IslandArtworkRenderProbe.surfaceSize.height - vm.expandedNotchSize.height) < 1,
                    "\(message): state=\(vm.notchState), page=\(IslandArtworkRenderProbe.selectedPage), offset=\(IslandArtworkRenderProbe.renderedPagePosition), surface=\(IslandArtworkRenderProbe.surfaceSize)")
        }
        requireTimerPage("Restored pending completion did not open the full timer page")
        vm.close() // Same close path used by hover departure and the keyboard shortcut.
        try? await Task.sleep(for: .seconds(0.2))
        requireTimerPage("Hover/shortcut close dismissed the pending full-size completion page")
        source.cancel()
        await settleSurface(expanded: false)
        require(vm.notchState == .closed && activities.current?.kind == .music
                    && IslandArtworkRenderProbe.surfaceSize.width < vm.expandedNotchSize.width,
                "Acknowledgement did not collapse the full page and restore music")
        source.start(duration: 1)
        await settleSurface(expanded: true)
        requireTimerPage("Timer completion while closed did not open the full timer page")
        source.cancel()
        await settleSurface(expanded: false)
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        require(IslandArtworkRenderProbe.selectedPage == .music, "Fixture failed to open the music page")
        source.start(duration: 1)
        await settleSurface(expanded: true)
        requireTimerPage("Timer completion while music was expanded did not switch to the full timer page")
        let alertImage = alertHost.bitmapImageRepForCachingDisplay(in: alertHost.bounds)!
        alertHost.cacheDisplay(in: alertHost.bounds, to: alertImage)
        try! alertImage.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("native-timer-completion-expanded.png"))
        vm.open()
        func snapshot<V: View>(_ view: V, name: String) async {
            let host = NSHostingView(rootView: view.environmentObject(vm)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .preferredColorScheme(.dark)
                .frame(width: 418, height: 138).frame(width: 480, height: 190).background(.black))
            window.contentView = host
            window.orderBack(nil)
            try? await Task.sleep(for: .seconds(0.4))
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        await snapshot(TimerActivityPage(), name: "native-timer-finished")
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        IslandArtworkRenderProbe.reduceMotion = true
        await snapshot(TimerActivityPage(), name: "native-timer-finished-reduced-motion")
        IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
        await snapshot(RemindersActivityPage(), name: "native-reminders-unconnected")
        await snapshot(TimerDurationForm(duration: .constant(1500)), name: "native-timer-picker")
        var minuteSelection = 25
        await snapshot(DurationColumn(value: Binding(get: { minuteSelection }, set: { minuteSelection = $0 }), count: 60, label: "Minutes"),
                       name: "native-minute-selection")
        require(minuteSelection == 25, "Native wheel initialization changed the requested duration")
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let nativeScroll = scrollView(in: window.contentView!)
        require(nativeScroll != nil, "Native minute picker has no system scroll view")
        let origin = nativeScroll!.contentView.bounds.origin
        nativeScroll!.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + 26))
        nativeScroll!.reflectScrolledClipView(nativeScroll!.contentView)
        try? await Task.sleep(for: .seconds(0.2))
        require(minuteSelection == 26, "Native wheel center and selected duration diverged after scrolling")
        var boundary = 0
        await snapshot(DurationColumn(value: Binding(get: { boundary }, set: { boundary = $0 }), count: 60, label: "Seconds"),
                       name: "native-second-zero")
        require(boundary == 0, "Native wheel moved its minimum value during layout")
        boundary = 59
        await snapshot(DurationColumn(value: Binding(get: { boundary }, set: { boundary = $0 }), count: 60, label: "Seconds"),
                       name: "native-second-maximum")
        require(boundary == 59, "Native wheel moved its maximum value during layout")
        source.cancel()
        require(activities.current?.kind == .music && activities.timer == nil,
                "Acknowledging completion did not clear the timer and restore music")
        require(UserDefaults.standard.data(forKey: "AirIsland.timerSession.v1") == nil,
                "Acknowledging completion retained the stored finished session")
        await snapshot(TimerActivityPage(), name: "native-timer-empty")
        func scrollViews(in view: NSView) -> [NSScrollView] {
            if let scroll = view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap { scrollViews(in: $0) }
        }
        let idleWheels = scrollViews(in: window.contentView!)
        require(idleWheels.count == 3, "Idle timer page did not directly show its three time wheels")
        require(!vm.isEditingActivity, "Idle timer picker blocked horizontal paging with a persistent editing lock")
        let defaultMinuteOrigin = idleWheels[1].contentView.bounds.origin
        idleWheels[1].contentView.scroll(to: NSPoint(x: defaultMinuteOrigin.x, y: defaultMinuteOrigin.y + 26))
        idleWheels[1].reflectScrolledClipView(idleWheels[1].contentView)
        try? await Task.sleep(for: .seconds(0.2))
        source.start(duration: 60)
        try? await Task.sleep(for: .seconds(0.7))
        require(scrollViews(in: window.contentView!).isEmpty, "Running timer retained the setup wheels")
        source.togglePause()
        source.cancel() // The running/paused page's X action.
        try? await Task.sleep(for: .seconds(0.7))
        let resetWheels = scrollViews(in: window.contentView!)
        require(resetWheels.count == 3 && abs(resetWheels[1].contentView.bounds.origin.y - defaultMinuteOrigin.y) < 1,
                "Cancelling a timer did not restore the default picker selection")
        // Capture the live page that actually transitioned through start/pause/reset.
        // Replacing its hosting view here would test a separate initial layout instead.
        let resetView = window.contentView!
        resetView.layoutSubtreeIfNeeded()
        let resetImage = resetView.bitmapImageRepForCachingDisplay(in: resetView.bounds)!
        resetView.cacheDisplay(in: resetView.bounds, to: resetImage)
        try! resetImage.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("native-timer-reset-picker.png"))
        source.start(duration: 1)
        try? await Task.sleep(for: .seconds(1.1))
        require(activities.current?.kind == .timerFinished, "A new timer did not produce its own completion alert")
        let completed = activities.timer!
        guard let restart = IslandArtworkRenderProbe.actionHandlers["arrow.clockwise"] else {
            require(false, "Finished timer did not expose its restart action")
            return
        }
        restart()
        require(activities.timer?.phase == .running && activities.current?.kind == .timer
                    && activities.timer?.duration == completed.duration && activities.timer?.id != completed.id,
                "Restart did not create a fresh timer of the completed duration or withdraw the old alert")
        let restarted = try! JSONDecoder().decode(TimerSession.self,
            from: UserDefaults.standard.data(forKey: "AirIsland.timerSession.v1")!)
        require(restarted == activities.timer, "Restarted countdown was not persisted")
        try? await Task.sleep(for: .seconds(1.1))
        require(activities.current?.kind == .timerFinished, "Restarted countdown did not produce its own completion")
        guard let close = IslandArtworkRenderProbe.actionHandlers["xmark"] else {
            require(false, "Finished timer did not expose its close action")
            return
        }
        close()
        require(activities.timer == nil && activities.current?.kind == .music
                    && UserDefaults.standard.data(forKey: "AirIsland.timerSession.v1") == nil,
                "Close did not clear the completed timer and restore music")
        source.start(duration: 1500)
        source.togglePause()
        await snapshot(TimerActivityPage(), name: "native-timer-paused")
        Defaults[.timerActivityEnabled] = false
        try? await Task.sleep(for: .seconds(0.1))
        require(activities.timer == nil && UserDefaults.standard.data(forKey: "AirIsland.timerSession.v1") == nil,
                "Disabling the timer retained a deadline or its stored session")
        Defaults[.timerActivityEnabled] = true
        print("PASS: real timer runtime replacement/pause/resume/persistent completion/acknowledgement/disable, native picker and timer page snapshots (isolated test domain)")
    }

    @MainActor static func measurePagingPerformance(output: URL) async {
        let activities = ActivityCoordinator.shared
        let reminders = RemindersActivityManager.shared
        Defaults[.remindersActivityEnabled] = true
        Defaults[.timerActivityEnabled] = true
        reminders.authorized = true
        reminders.errorMessage = nil
        TimerActivityManager.shared.cancel()
        let count = CommandLine.arguments.first { $0.hasPrefix("--performance-reminders=") }
            .flatMap { Int($0.split(separator: "=").last!) } ?? 24
        let label = CommandLine.arguments.first { $0.hasPrefix("--performance-label=") }
            .map { String($0.split(separator: "=").last!) } ?? "current"
        activities.setReminders((0..<count).map {
            ReminderTask(id: "performance-\($0)", title: "Task \($0): stable title for repeatable paging", dueDate: nil,
                         creationDate: Date(timeIntervalSince1970: Double(10000 + $0)))
        })
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil; vm.destroy(); activities.setReminders([]) }
        vm.open()
        try? await Task.sleep(for: .seconds(0.8))
        IslandArtworkRenderProbe.hover?(true)
        IslandArtworkRenderProbe.selectPage?(.music)
        try? await Task.sleep(for: .seconds(0.3))
        func viewCount(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + viewCount($1) } }
        let nativeViews = viewCount(host)
        IslandArtworkRenderProbe.reminderPageBodies = 0
        IslandArtworkRenderProbe.reminderRowBodies = 0
        func cpuSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                 + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let started = ProcessInfo.processInfo.systemUptime
        let cpuStart = cpuSeconds()
        var previousTick = started
        var intervals: [Double] = []
        func tick() async {
            try? await Task.sleep(for: .seconds(0.016))
            host.layoutSubtreeIfNeeded()
            let stamp = ProcessInfo.processInfo.systemUptime
            intervals.append(stamp - previousTick)
            previousTick = stamp
        }
        print("PERFORMANCE READY pid=\(ProcessInfo.processInfo.processIdentifier) reminders=\(count)")
        for _ in 0..<2 {
            for (target, direction): (IslandPage, Double) in [(.reminders, 1), (.timer, 1), (.reminders, -1), (.music, -1)] {
                IslandArtworkRenderProbe.horizontalGesture?(0, 0.016, .began)
                for _ in 0..<32 {
                    IslandArtworkRenderProbe.horizontalGesture?(direction * vm.expandedNotchSize.width * 0.009, 0.016, .changed)
                    await tick()
                }
                IslandArtworkRenderProbe.horizontalGesture?(0, 0.016, .ended)
                for _ in 0..<18 { await tick() }
                require(IslandArtworkRenderProbe.selectedPage == target, "Performance swipe missed target \(target), selected=\(IslandArtworkRenderProbe.selectedPage), position=\(IslandArtworkRenderProbe.renderedPagePosition)")
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let cpu = cpuSeconds() - cpuStart
        let sorted = intervals.sorted()
        let result: [String: Any] = [
            "label": label, "reminders": count, "swipes": 8, "ticks": intervals.count,
            "wall_seconds": elapsed, "cpu_seconds": cpu, "cpu_percent": cpu / elapsed * 100,
            "tick_p50_ms": sorted[sorted.count / 2] * 1000,
            "tick_p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000,
            "ticks_over_25ms": intervals.filter { $0 > 0.025 }.count,
            "native_views": nativeViews,
            "reminder_page_bodies": IslandArtworkRenderProbe.reminderPageBodies,
            "reminder_row_bodies": IslandArtworkRenderProbe.reminderRowBodies,
            "scope": "isolated production ContentView, 8 phased swipes at 16ms cadence, offscreen AppKit layout; tick intervals are event-loop cadence, not hardware FPS"
        ]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: output.appendingPathComponent("paging-performance-\(label)-\(count).json"))
        print(String(data: data, encoding: .utf8)!)
    }

    @MainActor static func verifyPersonalPaging(output: URL) async {
        let activities = ActivityCoordinator.shared
        let source = TimerActivityManager.shared
        let reminders = RemindersActivityManager.shared
        let previousAuthorization = reminders.authorized
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        let previousTimerEnabled = Defaults[.timerActivityEnabled]
        let previousRemindersEnabled = Defaults[.remindersActivityEnabled]
        Defaults[.timerActivityEnabled] = true
        Defaults[.remindersActivityEnabled] = true
        reminders.authorized = true
        activities.setReminders([ReminderTask(id: "paging-fixture", title: "Task", dueDate: nil)])
        IslandArtworkRenderProbe.reduceMotion = false
        source.cancel()
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(vm).preferredColorScheme(.dark).background(Color.white))
        window.contentView = host; window.orderBack(nil)
        defer {
            source.cancel(); activities.setReminders([]); reminders.authorized = previousAuthorization
            IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
            Defaults[.timerActivityEnabled] = previousTimerEnabled
            Defaults[.remindersActivityEnabled] = previousRemindersEnabled
            window.orderOut(nil); window.contentView = nil; vm.destroy()
        }
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        var captured = 0
        var digitMask: [CGPoint] = []
        var checkDigitPosition = false
        func capture(_ phase: String) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let width = vm.expandedNotchSize.width
            let left = (host.bounds.width - width) / 2
            let position = IslandArtworkRenderProbe.renderedPagePosition
            let timerLeft = left + (2 - position) * width
            let reminderLeft = left + (1 - position) * width
            // NotchShape's straight sides sit inside its top shoulders.
            // These samples are below the shoulders and above the bottom arcs.
            let surfaceLeft = (host.bounds.width - IslandArtworkRenderProbe.surfaceSize.width) / 2 + cornerRadiusInsets.opened.top
            let surfaceRight = host.bounds.width - surfaceLeft
            let rgba = rep.bitsPerSample == 8 && rep.samplesPerPixel == 4 && !rep.isPlanar
                && (rep.bitmapFormat == [] || rep.bitmapFormat == .alphaNonpremultiplied)
            let bytes = rep.bitmapData!
            func isOrange(_ x: Int, _ y: Int) -> Bool {
                guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh else { return false }
                let r: Double, g: Double, b: Double
                if rgba {
                    let offset = y * rep.bytesPerRow + x * 4
                    r = Double(bytes[offset]) / 255; g = Double(bytes[offset + 1]) / 255; b = Double(bytes[offset + 2]) / 255
                } else {
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    r = c.redComponent; g = c.greenComponent; b = c.blueComponent
                }
                return r > 0.5 && g > 0.2 && g < 0.85 && b < 0.18
            }
            if phase == "reference" {
                // The leading '2' stays unchanged while seconds roll. Track its
                // actual pixels, not merely a layout frame or absence of leaks.
                let xs = Int((left + 8) * scale)..<Int((left + 100) * scale)
                let ys = Int(60 * scale)..<Int(130 * scale)
                let first = xs.first { x in ys.contains { isOrange(x, $0) } }!
                digitMask = (first..<first + Int(10 * scale)).flatMap { x in
                    ys.compactMap { y in isOrange(x, y) ? CGPoint(x: CGFloat(x) - timerLeft * scale, y: CGFloat(y)) : nil }
                }
                require(digitMask.count > 30, "Missing stable timer digit reference")
            }
            var expectedDigitPixels = 0, matchedDigitPixels = 0
            if checkDigitPosition {
                for point in digitMask {
                    let x = Int((timerLeft * scale + point.x).rounded()), y = Int(point.y)
                    // The outer island mask can be narrower than the page's
                    // layout frame. Clipped pixels must not count as missing.
                    guard CGFloat(x) >= surfaceLeft * scale + 2, CGFloat(x) < surfaceRight * scale - 2 else { continue }
                    expectedDigitPixels += 1
                    let tolerance = Int(2 * scale)
                    if (-tolerance...tolerance).contains(where: { dx in (-tolerance...tolerance).contains { dy in isOrange(x + dx, y + dy) } }) {
                        matchedDigitPixels += 1
                    }
                }
            }
            let displacedDigit = expectedDigitPixels > 30 && Double(matchedDigitPixels) / Double(expectedDigitPixels) < 0.8
            var timerLeaks = 0, reminderLeaks = 0
            for y in Int((max(24, vm.effectiveClosedNotchHeight) + 10) * scale)..<Int(185 * scale) {
                for x in Int(left * scale)..<Int((left + width) * scale) {
                    let r: Double, g: Double, b: Double
                    if rgba {
                        let offset = y * rep.bytesPerRow + x * 4
                        r = Double(bytes[offset]) / 255; g = Double(bytes[offset + 1]) / 255; b = Double(bytes[offset + 2]) / 255
                    } else {
                        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        r = c.redComponent; g = c.greenComponent; b = c.blueComponent
                    }
                    let px = CGFloat(x) / scale
                    if r > 0.5 && g > 0.2 && g < 0.85 && b < 0.18 && (px < timerLeft - 2 || px > timerLeft + width + 2) { timerLeaks += 1 }
                    if b > 0.5 && g > 0.2 && r < 0.2 && (px < reminderLeft - 2 || px > reminderLeft + width + 2) { reminderLeaks += 1 }
                }
            }
            if captured % 5 == 0 || timerLeaks > 0 || reminderLeaks > 0 || displacedDigit {
                try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("personal-paging-\(phase)-\(captured).png"))
            }
            captured += 1
            require(timerLeaks == 0 && reminderLeaks == 0,
                    "Adjacent pages overlapped in \(phase): timer pixels=\(timerLeaks), reminder pixels=\(reminderLeaks), page=\(position)")
            require(!displacedDigit,
                    "Countdown detached from its page in \(phase): matched \(matchedDigitPixels)/\(expectedDigitPixels) digit pixels, page=\(position)")
        }
        for starting in [false, true] {
            source.cancel()
            if !starting { source.start(duration: 1500) }
            IslandArtworkRenderProbe.selectPage?(.timer)
            try? await Task.sleep(for: .seconds(0.7))
            checkDigitPosition = !starting
            if !starting { capture("reference") }
            if starting {
                IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
                try? await Task.sleep(for: .seconds(0.04))
            }
            for (from, to, direction): (IslandPage, IslandPage, Double) in [(.timer, .reminders, -1), (.reminders, .timer, 1)] {
                IslandArtworkRenderProbe.selectPage?(from)
                try? await Task.sleep(for: .seconds(starting && from == .timer ? 0.015 : 0.55))
                IslandArtworkRenderProbe.horizontalGesture?(0, 0.1, .began)
                var committed = false
                for _ in 0..<32 {
                    IslandArtworkRenderProbe.horizontalGesture?(direction * vm.expandedNotchSize.width * 0.015, 0.1, .changed)
                    try? await Task.sleep(for: .seconds(0.08))
                    capture("\(from)-to-\(to)-drag")
                    if IslandArtworkRenderProbe.selectedPage == to { committed = true; break }
                }
                require(committed, "Slow paging never crossed its existing threshold")
                IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
                for _ in 0..<30 {
                    try? await Task.sleep(for: .seconds(0.016))
                    capture("\(from)-to-\(to)-settle")
                }
                require(activities.timer?.phase == .running, "Paging changed countdown state")
            }
        }
        // Releasing before the threshold must return without exposing the other
        // page's independently animated content. Cover both motion preferences.
        for reducedMotion in [false, true] {
            checkDigitPosition = true
            IslandArtworkRenderProbe.reduceMotion = reducedMotion
            for (from, direction): (IslandPage, Double) in [(.timer, -1), (.reminders, 1)] {
                IslandArtworkRenderProbe.selectPage?(from)
                try? await Task.sleep(for: .seconds(0.5))
                IslandArtworkRenderProbe.horizontalGesture?(0, 0.1, .began)
                for _ in 0..<6 {
                    IslandArtworkRenderProbe.horizontalGesture?(direction * vm.expandedNotchSize.width * 0.015, 0.1, .changed)
                    try? await Task.sleep(for: .seconds(0.08))
                    capture("\(from)-cancelled-drag-reduced\(reducedMotion)")
                }
                require(IslandArtworkRenderProbe.selectedPage == from, "Sub-threshold swipe selected a different page")
                IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
                for _ in 0..<25 {
                    try? await Task.sleep(for: .seconds(0.016))
                    capture("\(from)-return-reduced\(reducedMotion)")
                }
                require(abs(IslandArtworkRenderProbe.renderedPagePosition - CGFloat(from.rawValue)) < 0.01,
                        "Cancelled swipe did not return to its page")
            }
        }
        print("PASS: running/starting timer and reminders stay inside their own page in both slow threshold transitions, clock ticks and cancelled returns, including Reduce Motion; countdown stays running (isolated fixtures)")
    }

    @MainActor static func verifyPersonalMotion(output: URL) async {
        let timer = TimerActivityManager.shared
        let activities = ActivityCoordinator.shared
        let reminders = RemindersActivityManager.shared
        let previousAuthorization = reminders.authorized
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        Defaults[.timerActivityEnabled] = true
        Defaults[.remindersActivityEnabled] = true
        reminders.authorized = true
        IslandArtworkRenderProbe.reduceMotion = false
        timer.cancel()
        defer {
            timer.cancel(); activities.setReminders([])
            reminders.authorized = previousAuthorization
            IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
        }
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        defer { vm.destroy() }
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 420, height: 164),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil }
        IslandArtworkRenderProbe.actionAppearances = [:]
        let timerHost = NSHostingView(rootView: TimerActivityPage().environmentObject(vm)
            .preferredColorScheme(.dark).background(Color.black))
        window.contentView = timerHost
        window.orderBack(nil)
        try? await Task.sleep(for: .seconds(0.7))
        func button(_ icon: String) -> CGRect {
            timerHost.layoutSubtreeIfNeeded()
            guard let frame = IslandArtworkRenderProbe.actionFrames[icon] else {
                require(false, "Missing motion action frame: \(icon)"); return .zero
            }
            return frame
        }
        func snapshot(_ view: NSView, _ name: String) {
            view.layoutSubtreeIfNeeded()
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        let idle = button("play.fill")
        snapshot(timerHost, "motion-timer-idle")
        IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
        require(activities.timer?.phase == .running && activities.timer?.duration == 1500,
                "Primary action delayed the countdown or changed the selected default duration")
        var centers: [CGFloat] = []
        for index in 0..<30 {
            try? await Task.sleep(for: .seconds(0.016))
            centers.append(button("pause.fill").midY)
            if index == 5 { snapshot(timerHost, "motion-timer-start-midway") }
        }
        let running = button("pause.fill")
        require(Set(centers.map { Int(($0 * 10).rounded()) }).count >= 5
                    && abs(running.midX - idle.midX) < 1 && running.midY < idle.midY - 30,
                "Start control jumped or changed horizontal anchor: \(centers)")
        snapshot(timerHost, "motion-timer-running")
        IslandArtworkRenderProbe.actionHandlers["pause.fill"]?()
        require(activities.timer?.phase == .paused, "Pause was delayed by its animation")
        try? await Task.sleep(for: .seconds(0.2))
        require(abs(button("play.fill").midY - running.midY) < 1, "Pause moved the primary button")
        IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
        require(activities.timer?.phase == .running, "Resume did not use the persistent primary action")
        try? await Task.sleep(for: .seconds(0.1))
        IslandArtworkRenderProbe.actionHandlers["xmark"]?()
        require(activities.timer == nil && UserDefaults.standard.data(forKey: "AirIsland.timerSession.v1") == nil,
                "Cancel waited for the visual return before clearing the countdown")
        centers = []
        for _ in 0..<6 {
            try? await Task.sleep(for: .seconds(0.016))
            centers.append(button("play.fill").midY)
        }
        // The icon-keyed geometry probe can still contain the previous pause
        // icon's position during a reversal. Measure the actual orange control
        // pixels on both sides of the interruption instead of that stale entry.
        func renderedPrimaryY() -> CGFloat {
            timerHost.layoutSubtreeIfNeeded()
            let image = timerHost.bitmapImageRepForCachingDisplay(in: timerHost.bounds)!
            timerHost.cacheDisplay(in: timerHost.bounds, to: image)
            let scale = CGFloat(image.pixelsWide) / timerHost.bounds.width
            let x = Int((timerHost.bounds.width - 28) * scale)
            let rows = (0..<image.pixelsHigh).filter { y in
                let c = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                return c.redComponent > 0.08 && c.redComponent > c.greenComponent * 1.4 && c.blueComponent < 0.08
            }
            require(!rows.isEmpty, "Could not locate the real persistent timer control")
            return CGFloat(rows.first! + rows.last!) / (2 * scale)
        }
        let reversing = renderedPrimaryY()
        IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
        try? await Task.sleep(for: .seconds(0.016))
        let reversed = renderedPrimaryY()
        // Capturing a native frame can exceed one 16 ms display interval.
        // Require a real intermediate reversal, not a wall-time assumption.
        require(activities.timer?.phase == .running && reversed > running.midY + 1
                    && reversed < reversing && reversed < idle.midY - 1,
                "Rapid restart jumped to an endpoint: \(reversing) → \(reversed), phase \(String(describing: activities.timer?.phase))")
        timer.cancel()
        try? await Task.sleep(for: .seconds(0.7))
        require(abs(button("play.fill").midY - idle.midY) < 1
                    && IslandArtworkRenderProbe.actionAppearances["play.fill"] == 1,
                "Primary button was replaced rather than carried through start/pause/resume/cancel")
        IslandArtworkRenderProbe.reduceMotion = true
        IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
        try? await Task.sleep(for: .seconds(0.06))
        require(abs(button("pause.fill").midY - running.midY) < 1, "Reduce Motion retained button travel")
        timer.cancel()
        IslandArtworkRenderProbe.reduceMotion = false
        let reminderHost = NSHostingView(rootView: RemindersActivityPage().environmentObject(vm)
            .preferredColorScheme(.dark).background(Color.black))
        window.contentView = reminderHost
        func tasks(_ prefix: String, count: Int) -> [ReminderTask] {
            (0..<count).map { ReminderTask(id: "\(prefix)-\($0)", title: "Task \($0)", dueDate: nil) }
        }
        func pixels() -> (bottom: Int, white: Int) {
            reminderHost.layoutSubtreeIfNeeded()
            let rep = reminderHost.bitmapImageRepForCachingDisplay(in: reminderHost.bounds)!
            reminderHost.cacheDisplay(in: reminderHost.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / reminderHost.bounds.width
            var bottom = 0, white = 0
            for y in Int(20 * scale)..<rep.pixelsHigh {
                for x in 0..<Int(18 * scale) {
                    let p = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if p.blueComponent > 0.4 && p.blueComponent > p.redComponent * 1.3 { bottom = max(bottom, y) }
                    if p.redComponent > 0.65 && p.greenComponent > 0.65 && p.blueComponent > 0.65 { white += 1 }
                }
            }
            return (bottom, white)
        }
        activities.setReminders(tasks("success", count: 3))
        try? await Task.sleep(for: .seconds(0.5))
        let originalBottom = pixels().bottom
        IslandArtworkRenderProbe.reminderWrites = []
        IslandArtworkRenderProbe.reminderWriteSucceeds = true
        IslandArtworkRenderProbe.completeReminder["success-0"]?()
        IslandArtworkRenderProbe.completeReminder["success-0"]?()
        require(activities.reminders.count == 2 && IslandArtworkRenderProbe.reminderWrites == ["success-0"],
                "Successful completion was delayed or wrote twice")
        var bottoms: [Int] = [], checkPixels = 0
        for index in 0..<25 {
            try? await Task.sleep(for: .seconds(0.016))
            let frame = pixels(); bottoms.append(frame.bottom); checkPixels = max(checkPixels, frame.white)
            if index == 3 { snapshot(reminderHost, "motion-reminder-completion-midway") }
        }
        require(checkPixels > 2 && Set(bottoms).count >= 4 && bottoms.last! < originalBottom - 20,
                "Completion did not visibly acknowledge and smoothly close the gap: white=\(checkPixels), bottoms=\(bottoms)")
        snapshot(reminderHost, "motion-reminder-completion-settled")
        activities.setReminders(tasks("failure", count: 2))
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.reminderWriteSucceeds = false
        IslandArtworkRenderProbe.completeReminder["failure-0"]?()
        try? await Task.sleep(for: .seconds(0.5))
        require(activities.reminders.count == 2 && pixels().white == 0, "Failed completion displayed success or removed the task")
        activities.setReminders(tasks("rapid", count: 3))
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.reminderWriteSucceeds = true
        IslandArtworkRenderProbe.completeReminder["rapid-0"]?()
        IslandArtworkRenderProbe.completeReminder["rapid-1"]?()
        require(activities.reminders.map(\.id) == ["rapid-2"], "Rapid completion removed the wrong task or delayed its result")
        try? await Task.sleep(for: .seconds(0.6))
        require(pixels().bottom < originalBottom - 40, "Rapid completion left gaps in the list")
        activities.setReminders(tasks("last", count: 1))
        try? await Task.sleep(for: .seconds(0.6))
        IslandArtworkRenderProbe.reminderWriteSucceeds = true
        IslandArtworkRenderProbe.completeReminder["last-0"]?()
        checkPixels = 0
        for _ in 0..<20 {
            try? await Task.sleep(for: .seconds(0.016)); checkPixels = max(checkPixels, pixels().white)
        }
        require(activities.reminders.isEmpty && checkPixels > 2, "Last-task completion skipped its acknowledgement")
        snapshot(reminderHost, "motion-reminder-empty")
        print("PASS: persistent primary button, intermediate start/return/reversal frames, immediate timer actions, Reduce Motion, acknowledged/failed/duplicate/last reminder completion and smooth list reflow")
    }

    @MainActor static func verifyEnabledPages(output: URL) async {
        let timer = TimerActivityManager.shared
        let activities = ActivityCoordinator.shared
        let reminders = RemindersActivityManager.shared
        let previousReminders = Defaults[.remindersActivityEnabled]
        let previousTimer = Defaults[.timerActivityEnabled]
        let previousIndicators = Defaults[.showPageIndicators]
        Defaults[.showPageIndicators] = true
        let previousAuthorization = reminders.authorized
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        IslandArtworkRenderProbe.reduceMotion = false
        timer.cancel()
        activities.setMusicActive(true)
        reminders.authorized = true // Fixture only; never connects EventKit.
        defer {
            timer.cancel()
            reminders.authorized = previousAuthorization
            IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
            Defaults[.remindersActivityEnabled] = previousReminders
            Defaults[.timerActivityEnabled] = previousTimer
            Defaults[.showPageIndicators] = previousIndicators
        }
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        vm.hideOnClosed = false
        defer { vm.destroy() }
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: vm.windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        func capture(_ name: String, dots: Int) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let leading = (host.bounds.width - IslandArtworkRenderProbe.surfaceSize.width) / 2
            var runs = 0, previous = false
            for x in Int((leading + 10) * scale)..<Int((leading + 100) * scale) {
                let bright = (Int(4 * scale)..<Int(24 * scale)).contains { y in
                    let p = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return max(p.redComponent, p.greenComponent, p.blueComponent) > 0.2
                }
                if bright && !previous { runs += 1 }
                previous = bright
            }
            require(runs == dots, "Wrong visible pagination dots in \(name): expected \(dots), found \(runs)")
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        for (r, t, pages): (Bool, Bool, [IslandPage]) in [
            (true, true, [.music, .reminders, .timer]), (true, false, [.music, .reminders]),
            (false, true, [.music, .timer]), (false, false, [.music])
        ] {
            Defaults[.remindersActivityEnabled] = r
            Defaults[.timerActivityEnabled] = t
            try? await Task.sleep(for: .seconds(0.3))
            require(IslandArtworkRenderProbe.availablePages == pages, "Disabled page remained in the production pager")
            capture("enabled-pages-\(r)-\(t)", dots: pages.count > 1 ? pages.count : 0)
        }
        Defaults[.remindersActivityEnabled] = true
        Defaults[.timerActivityEnabled] = true
        try? await Task.sleep(for: .seconds(0.3))
        let sizeWithDots = IslandArtworkRenderProbe.surfaceSize
        Defaults[.showPageIndicators] = false
        try? await Task.sleep(for: .seconds(0.2))
        capture("enabled-pages-hidden-indicators", dots: 0)
        require(IslandArtworkRenderProbe.availablePages == IslandPage.allCases
                    && IslandArtworkRenderProbe.surfaceSize == sizeWithDots,
                "Hiding page indicators removed a page or changed island geometry")
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
        IslandArtworkRenderProbe.horizontalGesture?(vm.expandedNotchSize.width / 2, 0.02, .changed)
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
        try? await Task.sleep(for: .seconds(0.3))
        require(IslandArtworkRenderProbe.selectedPage == .reminders, "Hidden indicators disabled paging")
        Defaults[.showPageIndicators] = true
        try? await Task.sleep(for: .seconds(0.2))
        capture("enabled-pages-restored-indicators", dots: 3)
        require(IslandArtworkRenderProbe.selectedPage == .reminders, "Showing indicators changed the selected page")
        IslandArtworkRenderProbe.selectPage?(.reminders)
        try? await Task.sleep(for: .seconds(0.3))
        IslandArtworkRenderProbe.actionHandlers["plus"]?()
        try? await Task.sleep(for: .seconds(0.1))
        require(vm.isEditingActivity, "Fixture failed to enter reminder editing")
        Defaults[.remindersActivityEnabled] = false
        try? await Task.sleep(for: .seconds(0.3))
        require(!vm.isEditingActivity && IslandArtworkRenderProbe.selectedPage == .music
                    && abs(IslandArtworkRenderProbe.renderedPagePosition) < 0.01,
                "Disabling the edited page left keyboard editing or a stale offset")
        // Ending explicit editing follows the existing hover-close behavior.
        // Reopen before exercising the next gesture.
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
        IslandArtworkRenderProbe.horizontalGesture?(vm.expandedNotchSize.width / 2, 0.02, .changed)
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
        try? await Task.sleep(for: .seconds(0.3))
        require(IslandArtworkRenderProbe.selectedPage == .timer
                    && abs(IslandArtworkRenderProbe.renderedPagePosition - 1) < 0.01,
                "Swipe did not skip the disabled middle page")
        capture("enabled-pages-music-timer", dots: 2)
        timer.start(duration: 1500)
        Defaults[.timerActivityEnabled] = false
        try? await Task.sleep(for: .seconds(0.3))
        require(activities.timer == nil && activities.current?.kind == .music
                    && IslandArtworkRenderProbe.selectedPage == .music,
                "Disabling the timer retained a countdown or its page")
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
        IslandArtworkRenderProbe.horizontalGesture?(1000, 0.02, .changed)
        IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
        try? await Task.sleep(for: .seconds(0.2))
        require(abs(IslandArtworkRenderProbe.renderedPagePosition) < 0.01, "Single page still moved on swipe")
        capture("enabled-pages-only-music", dots: 0)
        Defaults[.remindersActivityEnabled] = true
        Defaults[.timerActivityEnabled] = true
        try? await Task.sleep(for: .seconds(0.3))
        vm.close()
        try? await Task.sleep(for: .seconds(0.7))
        vm.open()
        for index in 0..<30 {
            try? await Task.sleep(for: .seconds(0.016))
            if index == 2 { Defaults[.remindersActivityEnabled] = false }
            if index == 3 {
                require(IslandArtworkRenderProbe.surfaceSize.height < expandedNotchHeight - 5,
                        "Removing a page snapped an in-progress island expansion")
            }
        }
        require(IslandArtworkRenderProbe.availablePages == [.music, .timer], "Page failed to re-enable or remove again")
        print("PASS: enabled-page combinations, optional/restored indicators without geometry changes, paging with hidden indicators, editing removal, skipped pages, timer cancellation, single-page swipe and continuous expansion")
    }

    @MainActor static func verifyResidentSelection(output: URL) async {
        let activities = ActivityCoordinator.shared
        let source = TimerActivityManager.shared
        let previousReminders = Defaults[.remindersActivityEnabled]
        Defaults[.remindersActivityEnabled] = true
        let previousLighting = Defaults[.lightingEffect]
        Defaults[.lightingEffect] = true
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        Defaults[.timerActivityEnabled] = true
        Defaults[.musicLiveActivityEnabled] = true
        Defaults[.enableSneakPeek] = true
        Defaults[.hudReplacement] = true
        IslandArtworkRenderProbe.reduceMotion = false
        source.cancel()
        for kind in IslandActivityKind.allCases where kind != .music { activities.end(kind) }
        activities.setMusicActive(false)
        activities.setMusicActive(true)
        defer {
            Defaults[.lightingEffect] = previousLighting
            source.cancel(); source.stop()
            activities.setReminders([])
            Defaults[.remindersActivityEnabled] = previousReminders
            for kind in IslandActivityKind.allCases where kind != .music { activities.end(kind) }
            activities.setMusicActive(false)
            activities.setMusicActive(true)
            IslandArtworkRenderProbe.reduceMotion = previousReduceMotion
            IslandArtworkRenderProbe.selectPage = nil
            IslandArtworkRenderProbe.horizontalGesture = nil
            IslandArtworkRenderProbe.startTimer = nil
        }
        source.start(duration: 1500)
        require(activities.current?.kind == .timer, "Default priority no longer prefers the timer")
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 260),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        vm.hideOnClosed = false
        window.setContentSize(vm.windowSize)
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil; vm.destroy() }
        try? await Task.sleep(for: .seconds(0.3))
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        func verifyAmbience(visible: Bool) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let x = (host.bounds.width - vm.expandedNotchSize.width) / 2 + 20
            let pixel = rep.colorAt(x: Int(x * scale), y: Int(110 * scale))!.usingColorSpace(.deviceRGB)!
            let brightness = max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
            require(visible ? brightness > 0.025 : brightness < 0.015,
                    "Music ambience visibility does not match the selected page: \(IslandArtworkRenderProbe.selectedPage), \(brightness)")
        }
        verifyAmbience(visible: false)
        require(IslandArtworkRenderProbe.selectedPage == .timer, "Automatic opening did not follow the timer")
        require(IslandArtworkRenderProbe.selectPage != nil && IslandArtworkRenderProbe.horizontalGesture != nil,
                "Production page interaction probes were not installed")
        // Drive the production swipe handler: the empty reminders page must not replace the resident timer.
        func swipeLeft() async {
            IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
            IslandArtworkRenderProbe.horizontalGesture?(-300, 0.02, .changed)
            IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
            try? await Task.sleep(for: .seconds(0.2))
        }
        await swipeLeft()
        verifyAmbience(visible: false)
        require(IslandArtworkRenderProbe.selectedPage == .reminders && activities.current?.kind == .timer,
                "Browsing an empty page changed the resident activity")
        await swipeLeft()
        require(IslandArtworkRenderProbe.selectedPage == .music && activities.current?.kind == .music,
                "Manual swipe did not select resident music")
        try? await Task.sleep(for: .seconds(0.5))
        verifyAmbience(visible: true)
        func verifyMusicBottom(_ name: String, visible: Bool = true) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let x = (host.bounds.width - vm.expandedNotchSize.width) / 2 + 70
                - IslandArtworkRenderProbe.renderedPagePosition * vm.expandedNotchSize.width
            let pixel = rep.colorAt(x: Int(x * scale), y: Int(184 * scale))!.usingColorSpace(.deviceRGB)!
            let brightness = max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
            try! rep.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent("music-background-\(name).png"))
            require(visible ? brightness > 0.035 : brightness < 0.015,
                    "Music background stopped covering its bottom during \(name): \(brightness), host=\(host.bounds), background=\(IslandArtworkRenderProbe.musicBackgroundFrame), page=\(IslandArtworkRenderProbe.renderedPagePosition), surface=\(IslandArtworkRenderProbe.surfaceSize)")
        }
        verifyMusicBottom("initial")
        IslandArtworkRenderProbe.horizontalGesture?(0, 0, .began)
        for frame in 0..<8 {
            IslandArtworkRenderProbe.horizontalGesture?(-16, 0.12, .changed)
            try? await Task.sleep(for: .seconds(0.04))
            verifyMusicBottom("drag-\(frame)")
        }
        IslandArtworkRenderProbe.horizontalGesture?(0, 0, .ended)
        for frame in 0..<12 {
            try? await Task.sleep(for: .seconds(0.04))
            verifyMusicBottom("return-\(frame)")
        }
        // Expose the moving page edge inside the island, where the outer mask
        // cannot supply the background's own lower corner.
        IslandArtworkRenderProbe.horizontalGesture?(0, 0, .began)
        for frame in 0..<4 {
            IslandArtworkRenderProbe.horizontalGesture?(12, 0.12, .changed)
            try? await Task.sleep(for: .seconds(0.04))
            verifyMusicBottom("corner-drag-\(frame)")
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let right = (host.bounds.width + vm.expandedNotchSize.width) / 2
                - IslandArtworkRenderProbe.renderedPagePosition * vm.expandedNotchSize.width
            let x = right - cornerRadiusInsets.opened.top - 2
            let pixel = rep.colorAt(x: Int(x * scale), y: Int(186 * scale))!.usingColorSpace(.deviceRGB)!
            require(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.015,
                    "Moving music background has a square corner inside the island")
        }
        IslandArtworkRenderProbe.horizontalGesture?(0, 0, .ended)
        try? await Task.sleep(for: .seconds(0.5))
        Defaults[.lightingEffect] = false
        try? await Task.sleep(for: .seconds(0.15))
        verifyMusicBottom("disabled", visible: false)
        Defaults[.lightingEffect] = true
        try? await Task.sleep(for: .seconds(0.15))
        verifyMusicBottom("reenabled")
        print("PASS: music background fills the bottom during drag/return; preference toggles it immediately")
        source.togglePause()
        require(activities.current?.kind == .music, "A timer payload update overwrote the resident choice")
        vm.close()
        try? await Task.sleep(for: .seconds(0.7))
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        require(IslandArtworkRenderProbe.selectedPage == .music, "Reopening forgot the manual resident choice")
        IslandArtworkRenderProbe.selectPage?(.timer)
        try? await Task.sleep(for: .seconds(0.2))
        require(activities.current?.kind == .timer, "Page-dot selection did not select resident timer")
        try? await Task.sleep(for: .seconds(0.5))
        verifyAmbience(visible: false)
        print("PASS: production music page has ambience; reminder and timer pages have a black background")
        vm.close()
        try? await Task.sleep(for: .seconds(0.7))
        func snapshot(_ name: String) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        activities.post(.musicChange)
        try? await Task.sleep(for: .seconds(0.7))
        require(IslandPresentation(activity: activities.current).showsMusicPeek && vm.notchState == .closed,
                "Song change did not temporarily show the compact song/artist peek")
        snapshot("resident-timer-song-peek")
        try? await Task.sleep(for: .seconds(2.5))
        require(activities.current?.kind == .timer && vm.notchState == .closed,
                "Song peek expiry did not restore the selected timer")
        try? await Task.sleep(for: .seconds(0.7))
        snapshot("resident-timer-restored")
        activities.prefer(.music)
        activities.post(.volume, value: 0.5)
        require(activities.current?.kind == .volume, "Manual choice blocked system feedback")
        try? await Task.sleep(for: .seconds(1.7))
        require(activities.current?.kind == .music, "System feedback did not restore selected music")
        Defaults[.musicLiveActivityEnabled] = false
        try? await Task.sleep(for: .seconds(0.2))
        require(activities.current?.kind == .timer, "Disabling selected music did not fall back to timer")
        Defaults[.musicLiveActivityEnabled] = true
        try? await Task.sleep(for: .seconds(0.2))
        require(activities.current?.kind == .timer, "Re-enabling music revived an invalidated resident choice")
        activities.prefer(.music)
        source.start(duration: 1)
        try? await Task.sleep(for: .seconds(1.7))
        activities.post(.musicChange)
        require(activities.current?.kind == .timerFinished && vm.notchState == .open
                    && IslandArtworkRenderProbe.selectedPage == .timer,
                "Manual choice or song peek blocked the full timer completion page")
        activities.end(.musicChange)
        source.cancel()
        try? await Task.sleep(for: .seconds(0.7))
        require(activities.current?.kind == .music && vm.notchState == .closed,
                "Acknowledging completion did not restore selected music and collapse")
        // Automatic alarm navigation must not silently make a later timer resident.
        source.start(duration: 1500)
        require(activities.current?.kind == .music, "Automatic alarm navigation overwrote the resident choice")
        source.cancel()
        Defaults[.remindersActivityEnabled] = true
        activities.setReminders([ReminderTask(id: "resident-regression", title: "Task", dueDate: nil)])
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        func swipeRight() async {
            IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
            IslandArtworkRenderProbe.horizontalGesture?(300, 0.02, .changed)
            IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
            try? await Task.sleep(for: .seconds(0.2))
        }
        await swipeRight()
        require(IslandArtworkRenderProbe.selectedPage == .reminders && activities.current?.kind == .music,
                "Browsing reminders changed the resident music activity")
        await swipeRight()
        require(IslandArtworkRenderProbe.selectedPage == .timer && activities.current?.kind == .music,
                "Empty timer page unexpectedly created an activity")
        require(IslandArtworkRenderProbe.startTimer != nil, "Timer page did not expose its production start action")
        IslandArtworkRenderProbe.startTimer?(1500)
        require(activities.current?.kind == .timer && activities.timer?.phase == .running,
                "Starting a timer on its page left reminders resident")
        vm.close()
        try? await Task.sleep(for: .seconds(0.7))
        require(vm.notchState == .closed && activities.current?.kind == .timer,
                "Closing a newly started timer restored the intervening reminders page")
        snapshot("resident-new-timer-after-reminders")
        source.togglePause()
        require(activities.current?.kind == .timer, "Pausing the new timer lost its resident selection")
        activities.post(.volume, value: 0.5)
        try? await Task.sleep(for: .seconds(1.7))
        require(activities.current?.kind == .timer, "Feedback failed to restore the newly started resident timer")
        source.cancel()
        activities.setMusicActive(false)
        for kind in IslandActivityKind.allCases where kind != .reminders { activities.end(kind) }
        require(activities.current == nil && activities.reminders.count == 1,
                "Reminders remained resident after music and timer ended")
        activities.prefer(.reminders)
        require(activities.current == nil, "Browsing reminders created a resident activity")
        IslandArtworkRenderProbe.selectPage?(.reminders)
        vm.close()
        try? await Task.sleep(for: .seconds(0.7))
        require(IslandPresentation(activity: activities.current) == .idle,
                "Panel-only reminders did not leave the island idle")
        snapshot("panel-only-reminders-closed")
        let reminderSource = RemindersActivityManager.shared
        let previousAuthorization = reminderSource.authorized
        reminderSource.authorized = true
        vm.open()
        try? await Task.sleep(for: .seconds(0.7))
        require(IslandArtworkRenderProbe.selectedPage == .reminders && activities.current == nil,
                "Opening the reminders panel created a resident activity")
        snapshot("panel-only-reminders-expanded")
        for page in [IslandPage.music, .timer, .reminders] {
            IslandArtworkRenderProbe.selectPage?(page)
            vm.close()
            try? await Task.sleep(for: .seconds(0.6))
            vm.open()
            try? await Task.sleep(for: .seconds(0.6))
            require(IslandArtworkRenderProbe.selectedPage == page && activities.current == nil && activities.timer == nil,
                    "Idle reopening lost the manually browsed page or fabricated an activity: \(page)")
        }
        IslandArtworkRenderProbe.selectPage?(.music)
        for page in [IslandPage.reminders, .timer] {
            IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .began)
            IslandArtworkRenderProbe.horizontalGesture?(vm.expandedNotchSize.width / 2, 0.02, .changed)
            IslandArtworkRenderProbe.horizontalGesture?(0, 0.02, .ended)
            vm.close()
            try? await Task.sleep(for: .seconds(0.6))
            vm.open()
            try? await Task.sleep(for: .seconds(0.6))
            require(IslandArtworkRenderProbe.selectedPage == page && activities.current == nil,
                    "Idle swipe selection did not survive reopening: \(page)")
        }
        Defaults[.timerActivityEnabled] = false
        try? await Task.sleep(for: .seconds(0.15))
        vm.close()
        try? await Task.sleep(for: .seconds(0.6))
        vm.open()
        try? await Task.sleep(for: .seconds(0.6))
        require(IslandArtworkRenderProbe.selectedPage == .music && activities.current == nil,
                "Disabling the remembered page did not fall back to music")
        Defaults[.timerActivityEnabled] = true
        reminderSource.authorized = previousAuthorization
        print("PASS: production swipe/dot resident selection, empty-page browsing, song peek expiry, source disable, alarm override and restoration (isolated offscreen runtime)")
    }

    @MainActor static func artwork(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // A light cover distinguishable from white titles and gray controls in pixel checks.
            NSColor(calibratedRed: 0.85, green: 1, blue: 1, alpha: 1).setFill()
            rect.fill()
            return true
        }
    }

    @MainActor static func verifyTrackSwitchProgress(output: URL) async {
        let music = MusicManager.shared
        let previousReduceMotion = IslandArtworkRenderProbe.reduceMotion
        defer { IslandArtworkRenderProbe.reduceMotion = previousReduceMotion }
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 150),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        let host = NSHostingView(rootView: AnyView(MusicControlsView().preferredColorScheme(.dark).background(.black)))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        func update(_ payload: String) -> NowPlayingUpdate {
            try! JSONDecoder().decode(NowPlayingUpdate.self, from: Data(payload.utf8))
        }
        func fill(_ name: String) -> Double {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            let frame = IslandArtworkRenderProbe.musicProgressFrame
            require(frame.width > 100, "Production music progress track was not measured")
            // Locate the continuous track in the bitmap itself; a hosting view's
            // global Y can use a different origin from its cached image.
            let columns = [frame.minX + 5, frame.midX, frame.maxX - 5].map { Int($0 * scale) }
            let trackRows = (0..<rep.pixelsHigh).filter { y in
                columns.allSatisfy { x in
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return min(c.redComponent, c.greenComponent, c.blueComponent) > 0.15
                }
            }
            require(!trackRows.isEmpty, "Could not locate the rendered music progress track")
            // Sample its interior, not a fractional antialiased top edge.
            let row = trackRows[trackRows.count / 2]
            let filled = (Int(frame.minX * scale)..<Int(frame.maxX * scale)).filter { x in
                let c = rep.colorAt(x: x, y: row)!.usingColorSpace(.deviceRGB)!
                return max(c.redComponent, c.greenComponent, c.blueComponent) > 0.65
            }.count
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            return Double(filled) / Double(frame.width * scale)
        }
        for (direction, reduced): (String, Bool) in [("next", false), ("previous", false), ("next-reduced", true), ("previous-reduced", true)] {
            IslandArtworkRenderProbe.reduceMotion = reduced
            var session = NowPlayingPlaybackSession()
            let initial = update(#"{"diff":false,"payload":{"bundleIdentifier":"com.netease.163music","title":"Original","artist":"Artist","album":"Album","duration":300,"elapsedTime":60,"playing":true,"playbackRate":1}}"#)
            music.updateFromPlaybackState(session.receive(initial, neteaseIsRunning: true))
            try? await Task.sleep(for: .seconds(0.25))
            require(fill("progress-\(direction)-initial") > 0.15, "Initial real playback progress was missing")
            music.updateFromPlaybackState(session.beginTrackChange())
            require(music.estimatedPlaybackPosition() == 0, "Requested \(direction) switch still extrapolated the old song")
            var falling: [Double] = []
            for frame in 0..<12 {
                try? await Task.sleep(for: .seconds(0.016))
                falling.append(fill("progress-\(direction)-return-\(frame)"))
            }
            require(falling.last! < 0.01 && zip(falling, falling.dropFirst()).allSatisfy { $1 <= $0 + 0.005 },
                    "Reset did not settle monotonically at zero: \(falling)")
            if reduced {
                require(falling.allSatisfy { $0 < 0.01 }, "Reduce Motion retained a progress reset animation")
            } else {
                require(falling.filter { $0 > 0.01 && $0 < 0.19 }.count >= 2,
                        "Progress did not show intermediate reset frames: \(falling)")
            }
            let packets = [
                #"{"diff":true,"payload":{"elapsedTime":180,"playing":true,"playbackRate":0}}"#,
                #"{"diff":true,"payload":{"title":"Destination","duration":90,"playbackRate":0}}"#,
                #"{"diff":true,"payload":{"elapsedTime":0,"playing":false}}"#,
            ]
            for (index, packet) in packets.enumerated() {
                music.updateFromPlaybackState(session.receive(update(packet), neteaseIsRunning: true))
                for frame in 0..<4 {
                    try? await Task.sleep(for: .seconds(0.016))
                    require(fill("progress-\(direction)-loading-\(index)-\(frame)") < 0.01,
                            "Old progress flashed while duration/playback packets arrived separately")
                }
            }
            let ready = update(#"{"diff":true,"payload":{"elapsedTime":0.1,"playing":true,"playbackRate":1}}"#)
            music.updateFromPlaybackState(session.receive(ready, neteaseIsRunning: true))
            try? await Task.sleep(for: .seconds(0.025))
            require(fill("progress-\(direction)-ready") < 0.02, "New song reused the old slider value")
            let seek = update(#"{"diff":true,"payload":{"elapsedTime":40}}"#)
            music.updateFromPlaybackState(session.receive(seek, neteaseIsRunning: true))
            try? await Task.sleep(for: .seconds(0.025))
            let sought = fill("progress-\(direction)-seek")
            require(sought > 0.4 && sought < 0.5, "Same-song real seek stopped updating the progress immediately")
            music.updateFromPlaybackState(session.beginTrackChange())
            music.updateFromPlaybackState(session.confirmPendingPause(now: Date().addingTimeInterval(9)))
            require(music.estimatedPlaybackPosition() > 30, "Failed switch did not restore the source's actual progress")
        }
        // A recently released seek must retain the user's value until the source
        // acknowledges it, even when its preceding timestamp is only 0.2 s old.
        IslandArtworkRenderProbe.reduceMotion = false
        let released = Date()
        func seekFixture(position: Double, anchor: Date, changing: Bool = false, duration: Double = 90) -> AnyView {
            AnyView(MusicSliderView(sliderValue: .constant(65), duration: .constant(duration),
                lastDragged: .constant(released), color: .white, dragging: .constant(false),
                estimatedPosition: position, timestampDate: anchor, isChangingTrack: changing,
                onValueChange: { _ in }).preferredColorScheme(.dark).background(.black))
        }
        host.rootView = seekFixture(position: 40, anchor: released.addingTimeInterval(-0.2))
        try? await Task.sleep(for: .seconds(0.025))
        require(fill("progress-seek-awaiting-ack") > 0.7, "Released seek snapped back before source acknowledgement")
        host.rootView = seekFixture(position: 70, anchor: released.addingTimeInterval(0.1))
        try? await Task.sleep(for: .seconds(0.025))
        require(fill("progress-seek-acknowledged") > 0.76, "Acknowledged seek stayed stuck on local input")
        host.rootView = seekFixture(position: 40, anchor: released.addingTimeInterval(-0.2), changing: true)
        try? await Task.sleep(for: .seconds(0.22))
        require(fill("progress-switch-clears-seek") < 0.01, "Track change retained a previous seek")

        // A cached next song can become ready before the 0.18 s return ends.
        // Neither its duration nor regular progress ticks may interrupt the fill.
        host.rootView = seekFixture(position: 120, anchor: released.addingTimeInterval(0.1), duration: 300)
        try? await Task.sleep(for: .seconds(0.025))
        host.rootView = seekFixture(position: 0, anchor: released.addingTimeInterval(0.1), changing: true)
        try? await Task.sleep(for: .seconds(0.04))
        let warmStart = fill("progress-warm-reset-start")
        host.rootView = seekFixture(position: 0.1, anchor: released.addingTimeInterval(0.1))
        try? await Task.sleep(for: .seconds(0.025))
        let warmMiddle = fill("progress-warm-reset-ready")
        require(warmStart < 0.405 && warmStart > warmMiddle && warmMiddle > 0.02,
                "Early playback cut short or stretched the reset: \(warmStart), \(warmMiddle)")
        try? await Task.sleep(for: .seconds(0.18))
        require(fill("progress-warm-reset-end") < 0.01, "Warm switch retained the old fill")
        print("PASS: next/previous ease to zero with intermediate monotonic frames, Reduce Motion resets directly, split packets/warm playback cannot interrupt reset, seek acknowledgement and failure recovery stay stable")
    }

    @MainActor static func verifyArtworkReadiness() async {
        let music = MusicManager.shared
        // An existing installation may have disabled the removed appearance option.
        UserDefaults.standard.set(false, forKey: "coloredSpectrogram")
        func imageData(_ size: CGFloat) -> Data {
            NSBitmapImageRep(data: artwork(size: size).tiffRepresentation!)!
                .representation(using: .png, properties: [:])!
        }
        func settle() async { try? await Task.sleep(for: .seconds(0.25)) }
        var state = PlaybackState(bundleIdentifier: "com.netease.163music", sourceTrackIdentifier: "loaded",
                                  isPlaying: true, title: "Loaded", artist: "Artist", album: "Album")
        state.artwork = imageData(200)
        music.updateFromPlaybackState(state)
        await settle()
        let coverColor = music.avgColor.usingColorSpace(.deviceRGB)!
        require(coverColor.redComponent < 0.94 && coverColor.greenComponent > 0.97
                    && coverColor.blueComponent > 0.97,
                "Artwork color must be calculated even when the removed preference was disabled")
        let initial = music.albumArtTrackIdentifier
        let initialImage = ObjectIdentifier(music.albumArt)

        state.title = "Slow load"
        state.sourceTrackIdentifier = "slow"
        state.isPlaying = false
        state.isChangingTrack = true
        state.playbackRate = 0
        state.artwork = imageData(400)
        music.updateFromPlaybackState(state)
        await settle()
        require(music.albumArtTrackIdentifier == initial && ObjectIdentifier(music.albumArt) == initialImage,
                "Decoded cover flipped before the requested song was ready")
        require(music.isPlaybackActive, "Loading incorrectly became a visual pause")
        state.isPlaying = true // A provisional playing=true at rate=0 is still loading.
        state.artwork = imageData(500)
        music.updateFromPlaybackState(state)
        await settle()
        require(music.albumArtTrackIdentifier == initial, "Provisional playback prematurely released the cover")
        state.isChangingTrack = false
        state.playbackRate = 1
        music.updateFromPlaybackState(state)
        await settle()
        let loaded = music.albumArtTrackIdentifier
        require(loaded != initial && music.albumArt.size.width == 500,
                "Ready playback did not release the newest decoded cover")
        state.artwork = imageData(600)
        music.updateFromPlaybackState(state)
        await settle()
        require(music.albumArtTrackIdentifier == loaded && music.albumArt.size.width == 600,
                "Artwork refinement changed the loaded song's flip identity")

        state.title = "Playback before cover"
        state.sourceTrackIdentifier = "no-cover"
        state.artwork = nil
        music.updateFromPlaybackState(state)
        await settle()
        require(music.albumArtTrackIdentifier == loaded, "Missing cover triggered an early flip")
        state.artwork = imageData(300)
        music.updateFromPlaybackState(state)
        await settle()
        let next = music.albumArtTrackIdentifier
        require(next != loaded && music.albumArt.size.width == 300, "Late cover was not displayed after playback became ready")

        state.title = "Failed load"
        state.sourceTrackIdentifier = "failed"
        state.isPlaying = false
        state.isChangingTrack = true
        state.playbackRate = 0
        state.artwork = imageData(400)
        music.updateFromPlaybackState(state)
        await settle()
        state.isChangingTrack = false
        music.updateFromPlaybackState(state)
        await settle()
        require(music.albumArtTrackIdentifier == next, "Failed load flipped to an unplayable destination")
        state.isPlaying = true
        state.playbackRate = 1
        music.updateFromPlaybackState(state)
        await settle()
        require(music.albumArtTrackIdentifier != next && music.albumArt.size.width == 400,
                "Resuming the failed load did not release its matching cover")
        print("PASS: production MusicManager waits for playback and decoded artwork, preserves late/refined covers and handles failure/resume")
    }

    @MainActor static func verifySeekingDoesNotAnnounceTrackChanges() async {
        let music = MusicManager.shared
        let activities = ActivityCoordinator.shared
        activities.setTimer(nil)
        activities.setReminders([])
        for bundle in ["com.tencent.QQMusicMac", "com.netease.163music", "com.apple.Music", "com.spotify.client", "other-player"] {
            var state = PlaybackState(bundleIdentifier: bundle, sourceTrackIdentifier: "original", isPlaying: true,
                                      title: "Seek regression", artist: "Artist", album: "Album", duration: 306)
            state.artwork = NSBitmapImageRep(data: artwork(size: 200).tiffRepresentation!)!
                .representation(using: .png, properties: [:])!
            music.updateFromPlaybackState(state)
            try? await Task.sleep(for: .seconds(0.25))
            require(activities.current?.kind == .musicChange, "A new song did not produce its track-change activity: \(bundle)")
            activities.end(.musicChange)
            let identity = music.albumArtTrackIdentifier
            for (index, position) in [109.0, 3, 250, 0].enumerated() {
                state.currentTime = position
                state.sourceTrackIdentifier = "seek-\(index)"
                state.artwork = NSBitmapImageRep(data: artwork(size: CGFloat(240 + index * 20)).tiffRepresentation!)!
                    .representation(using: .png, properties: [:])!
                music.updateFromPlaybackState(state)
                try? await Task.sleep(for: .seconds(0.25))
                require(music.elapsedTime == position, "Seek did not update the actual progress: \(bundle)")
                require(music.albumArtTrackIdentifier == identity, "Seek triggered a cover flip: \(bundle)")
                require(activities.current?.kind == .music, "Seek or cover refresh posted a track-change activity: \(bundle)")
                state.isPlaying = false
                music.updateFromPlaybackState(state)
                state.isPlaying = true
                music.updateFromPlaybackState(state)
                require(activities.current?.kind == .music, "Same-song resume posted a track-change activity: \(bundle)")
            }
            state.title = "Actual next song"
            state.sourceTrackIdentifier = "next"
            music.updateFromPlaybackState(state)
            try? await Task.sleep(for: .seconds(0.25))
            require(music.albumArtTrackIdentifier != identity, "Real track change no longer flips its cover: \(bundle)")
            require(activities.current?.kind == .musicChange, "Real track change no longer posts its activity: \(bundle)")
            activities.end(.musicChange)
            state.artwork = NSBitmapImageRep(data: artwork(size: 500).tiffRepresentation!)!
                .representation(using: .png, properties: [:])!
            music.updateFromPlaybackState(state)
            try? await Task.sleep(for: .seconds(0.25))
            require(activities.current?.kind == .music, "Late artwork replayed the track-change activity: \(bundle)")
        }
        print("PASS: production MusicManager seeking, regenerated IDs, cover refresh and resume keep song identity without musicChange; real track changes still flip and announce")
    }

    @MainActor static func verifyPausedArtwork(output: URL, changing: Bool = false) async {
        let music = MusicManager.shared
        let vm = IslandViewModel(screenUUID: NSScreen.screens[0].displayUUID)
        vm.open()
        music.isPlaying = false
        music.isChangingTrack = changing
        let phase = changing ? "loading-flip" : "paused-flip"
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 210),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(vm.windowSize)
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        var frames = 0
        var widths: [Int] = []
        var pausedReferenceGreen: Int?
        func capture() {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let filename = "\(phase)-\(frames).png"
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
            frames += 1
            var left = rep.pixelsWide, right = -1
            var top = rep.pixelsHigh, bottom = -1
            var brightPixels = 0
            var maximumGreen = 0
            let rgba = rep.bitsPerSample == 8 && rep.samplesPerPixel == 4 && !rep.isPlanar
                && (rep.bitmapFormat == [] || rep.bitmapFormat == .alphaNonpremultiplied)
            let bytes = rep.bitmapData!
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide / 2 {
                    let red: Int, green: Int, blue: Int, alpha: Int
                    if rgba {
                        let offset = y * rep.bytesPerRow + x * 4
                        red = Int(bytes[offset]); green = Int(bytes[offset + 1])
                        blue = Int(bytes[offset + 2]); alpha = Int(bytes[offset + 3])
                    } else {
                        let pixel = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        red = Int(pixel.redComponent * 255); green = Int(pixel.greenComponent * 255)
                        blue = Int(pixel.blueComponent * 255); alpha = Int(pixel.alphaComponent * 255)
                    }
                    // Cyan identifies the synthetic cover; white labels and the red app badge do not match.
                    if green - red > 1, blue - red > 1, alpha > 242 {
                        if changing {
                            if green > 153 { brightPixels += 1 }
                        } else {
                            require(green < 153,
                                    "Undimmed paused cover escaped its shading in \(filename) at (\(x), \(y))")
                        }
                        maximumGreen = max(maximumGreen, green)
                        left = min(left, x); right = max(right, x)
                        top = min(top, y); bottom = max(bottom, y)
                    }
                }
            }
            if !changing, right >= left {
                if pausedReferenceGreen == nil {
                    let center = rep.colorAt(x: (left + right) / 2, y: (top + bottom) / 2)!.usingColorSpace(.deviceRGB)!
                    pausedReferenceGreen = Int((center.greenComponent * 255).rounded())
                }
                require(maximumGreen <= pausedReferenceGreen! + 3,
                        "Paused cover has a bright antialiased fringe in \(filename): edge \(maximumGreen), interior \(pausedReferenceGreen!)")
            }
            if changing { require(brightPixels > 20, "Loading cover incorrectly dimmed in \(filename)") }
            if right >= left { widths.append(right - left + 1) }
        }
        try? await Task.sleep(for: .seconds(0.65))
        capture()
        let scale = CGFloat(host.bitmapImageRepForCachingDisplay(in: host.bounds)!.pixelsWide) / host.bounds.width
        let expectedSide = MusicPlayerImageSizes.expandedSide(headerHeight: max(24, vm.effectiveClosedNotchHeight))
            * (changing ? 1 : 0.85) * scale
        require(abs(CGFloat(widths.last ?? 0) - expectedSide) < 3,
                "Incorrect cover scale in \(phase): expected \(expectedSide), measured \(widths.last ?? 0)")
        for direction in [AlbumArtFlipDirection.next, .previous] {
            music.albumArtFlipDirection = direction
            music.albumArtTrackIdentifier = UUID()
            music.albumArt = artwork(size: 200)
            for index in 0..<24 {
                try? await Task.sleep(for: .seconds(0.016))
                capture()
                if index == 3 { music.albumArt = artwork(size: 400) }
            }
            try? await Task.sleep(for: .seconds(0.3))
        }
        if !changing {
            require((widths.max() ?? 0) > (widths.min() ?? 0) + 20,
                    "Paused regression did not capture the cover's actual flip deformation: \(widths)")
        }
        print("PASS: \(phase), \(frames) frames, correct shading/scale through next/previous track updates and artwork refinements")
        window.orderOut(nil)
        window.contentView = nil
        vm.destroy()
        music.isPlaying = true
        music.isChangingTrack = false
    }

    @MainActor static func verify(screen: NSScreen, name: String, output: URL) async {
        IslandArtworkRenderProbe.appearances = 0
        let vm = IslandViewModel(screenUUID: screen.displayUUID)
        vm.hideOnClosed = false
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 210),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(vm.windowSize)
        let host = NSHostingView(rootView: ContentView().environmentObject(vm))
        window.contentView = host
        window.orderBack(nil)
        var frames = 0
        var maximumResizeDifference: CGFloat = 0
        func capture(_ phase: String, expectsCover: Bool = true) -> Frame {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let filename = "\(name)-\(phase)-\(String(format: "%03d", frames)).png"
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
            frames += 1
            let width = rep.pixelsWide, height = rep.pixelsHigh
            let scale = CGFloat(width) / host.bounds.width
            func color(_ x: Int, _ y: Int) -> NSColor { rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)! }
            if phase.hasPrefix("feedback-expanded") {
                let left = Int((host.bounds.width - vm.notchSize.width) / 2 * scale + 24 * scale)
                let right = width - left
                let headerBottom = Int(max(0, vm.physicalNotchHeight - 2) * scale)
                let dotsRight = Int(((host.bounds.width - vm.expandedNotchSize.width) / 2 + cornerRadiusInsets.opened.top + 8 + 54) * scale)
                for y in stride(from: Int(2 * scale), to: headerBottom, by: 2) {
                    for x in stride(from: left, to: right, by: 2) {
                        // The approved page dots occupy only the leading safe area.
                        if x < dotsRight { continue }
                        let pixel = color(x, y)
                        require(pixel.alphaComponent > 0.99 && max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.02,
                                "Expanded header displayed system feedback in \(filename) at (\(x), \(y))")
                    }
                }
            }
            func isCover(_ color: NSColor) -> Bool {
                color.alphaComponent > 0.99 && color.redComponent > 0.78 && color.redComponent < 0.94
                    && color.greenComponent > 0.97 && color.blueComponent > 0.97
            }
            var left = width, right = -1, top = height, bottom = -1
            var badgeLeft = width, badgeRight = -1, badgeTop = height, badgeBottom = -1
            let rgba = rep.bitsPerSample == 8 && rep.samplesPerPixel == 4 && !rep.isPlanar
                && (rep.bitmapFormat == [] || rep.bitmapFormat == .alphaNonpremultiplied)
            let bytes = rep.bitmapData!
            for y in 0..<height {
                for x in 0..<width / 2 {
                    let offset = y * rep.bytesPerRow + x * 4
                    let matches = rgba
                        ? bytes[offset] > 199 && bytes[offset] < 240 && bytes[offset + 1] > 247
                            && bytes[offset + 2] > 247 && bytes[offset + 3] > 252
                        : isCover(color(x, y))
                    if matches {
                        left = min(left, x); right = max(right, x)
                        top = min(top, y); bottom = max(bottom, y)
                    }
                    let red: Bool
                    if rgba {
                        red = bytes[offset] > 30 && Int(bytes[offset]) > Int(bytes[offset + 1]) * 2
                            && Int(bytes[offset]) > Int(bytes[offset + 2]) * 2 && bytes[offset + 3] > 252
                    } else {
                        let pixel = color(x, y)
                        red = pixel.redComponent > 0.12 && pixel.redComponent > pixel.greenComponent * 2
                            && pixel.redComponent > pixel.blueComponent * 2 && pixel.alphaComponent > 0.99
                    }
                    if red {
                        badgeLeft = min(badgeLeft, x); badgeRight = max(badgeRight, x)
                        badgeTop = min(badgeTop, y); badgeBottom = max(badgeBottom, y)
                    }
                }
            }
            let islandBottom = (0..<height).last { color(width / 2, $0).alphaComponent > 0.99 }!
            let renderedHeight = CGFloat(islandBottom + 1) / scale
            let progress = min(1, max(0, (renderedHeight - vm.effectiveClosedNotchHeight)
                                      / (vm.expandedNotchSize.height - vm.effectiveClosedNotchHeight)))
            let topRadius = cornerRadiusInsets.closed.top + (cornerRadiusInsets.opened.top - cornerRadiusInsets.closed.top) * progress
            let bottomRadius = cornerRadiusInsets.closed.bottom + (cornerRadiusInsets.opened.bottom - cornerRadiusInsets.closed.bottom) * progress
            let sideRow = Int((topRadius + max(0, renderedHeight - topRadius - bottomRadius) / 2) * scale)
            let opaqueColumns = (0..<width).filter { color($0, sideRow).alphaComponent > 0.99 }
            let renderedWidth = CGFloat(opaqueColumns.last! - opaqueColumns.first! + 1) / scale + 2 * topRadius
            require(abs(renderedWidth - IslandArtworkRenderProbe.surfaceSize.width) < 3,
                    "Rendered outline and layout width diverged in \(filename): pixels \(renderedWidth), layout \(IslandArtworkRenderProbe.surfaceSize.width)")
            if !expectsCover {
                require(right < left, "Hidden artwork remained visible in \(filename)")
                require(badgeRight < badgeLeft, "Hidden badge remained visible in \(filename)")
                return Frame(islandWidth: renderedWidth, islandHeight: CGFloat(islandBottom + 1) / scale, artworkWidth: 0, badgeWidth: 0)
            }
            require(right >= left && bottom >= top, "Cover faded, duplicated or disappeared in \(filename)")
            let coverWidth = right - left + 1, coverHeight = bottom - top + 1
            require(abs(coverWidth - coverHeight) <= 3, "Cover clipped by a rectangular slot in \(filename)")
            for xFraction in [0.25, 0.5, 0.75] {
                for yFraction in [0.25, 0.5, 0.75] {
                    let pixel = color(left + Int(Double(coverWidth - 1) * xFraction),
                                      top + Int(Double(coverHeight - 1) * yFraction))
                    require(isCover(pixel), "Text/background obscured the artwork in \(filename)")
                }
            }
            require(!isCover(color(left + 1, top + 1)),
                         "Square artwork ghost outside the rounded corner in \(filename)")
            require(bottom <= islandBottom + 1, "Cover escaped the island in \(filename)")
            if badgeRight >= badgeLeft {
                let centerX = CGFloat(badgeLeft + badgeRight) / 2
                let centerY = CGFloat(badgeTop + badgeBottom) / 2
                require(centerX <= CGFloat(right) + 2 * scale && centerY <= CGFloat(bottom) + 2 * scale,
                        "Music badge detached to the right/below the cover in \(filename): cover edge (\(right), \(bottom)), badge center (\(centerX), \(centerY))")
            }
            let side = (0..<width / 2).first { color($0, max(2, islandBottom / 2)).alphaComponent > 0.99 }!
            let corner = (0..<width / 2).first { color($0, max(0, islandBottom - 1)).alphaComponent > 0.99 }!
            require(corner - side > Int(2 * scale), "Island corner became rectangular in \(filename)")
            return Frame(islandWidth: renderedWidth, islandHeight: CGFloat(islandBottom + 1) / scale, artworkWidth: CGFloat(coverWidth) / scale,
                         badgeWidth: badgeRight >= badgeLeft ? CGFloat(badgeRight - badgeLeft + 1) / scale : 0)
        }
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        for _ in 0..<6 {
            await wait(0.016)
            let startup = capture("initial-measurement")
            require(startup.islandWidth >= vm.closedNotchSize.width,
                    "Initial compact measurement animated from zero")
        }
        await wait(0.65)
        let compact = capture("compact")
        vm.open()
        // First expansion creates the approved pages and native scroll controls.
        // Establish a settled endpoint before testing intermediate frames; don't
        // confuse their one-time layout cost with the shared animation progress.
        for _ in 0..<90 {
            await wait(0.016)
            if abs(IslandArtworkRenderProbe.surfaceSize.width - vm.expandedNotchSize.width) < 0.1,
               abs(IslandArtworkRenderProbe.surfaceSize.height - vm.expandedNotchSize.height) < 0.1 { break }
        }
        await wait(0.04)
        let expanded = capture("expanded")
        require(compact.islandWidth > 0 && abs(expanded.islandWidth - vm.expandedNotchSize.width) < 1, "Surface size probe did not measure the real layout: compact \(compact), expanded \(expanded), layout \(IslandArtworkRenderProbe.surfaceSize)")
        require(expanded.badgeWidth > 10, "The regression must exercise a real music app badge")
        func assertSynchronized(_ frame: Frame, compactWidth: CGFloat? = nil) {
            let islandProgress = (frame.islandHeight - compact.islandHeight) / (expanded.islandHeight - compact.islandHeight)
            let coverProgress = (frame.artworkWidth - compact.artworkWidth) / (expanded.artworkWidth - compact.artworkWidth)
            maximumResizeDifference = max(maximumResizeDifference, abs(islandProgress - coverProgress))
            require(abs(islandProgress - coverProgress) < 0.035,
                    "Cover and island use different resize rates in \(name), frame \(frames): island \(islandProgress), cover \(coverProgress), measured \(frame)")
            let closedWidth = compactWidth ?? compact.islandWidth
            let expectedWidth = closedWidth + (expanded.islandWidth - closedWidth) * islandProgress
            require(abs(frame.islandWidth - expectedWidth) < 3,
                    "Width and height diverged in \(name), frame \(frames): expected width \(expectedWidth), actual \(frame.islandWidth), height progress \(islandProgress)")
        }
        for expand in [false, true, false] {
            if expand { vm.open() } else { vm.close() }
            for index in 0..<18 {
                await wait(0.016)
                assertSynchronized(capture(expand ? "expand" : "collapse"))
                if index == 3 { MusicManager.shared.albumArt = artwork(size: 400) }
            }
            await wait(0.3)
        }
        let activities = ActivityCoordinator.shared
        activities.post(.musicChange)
        await wait(0.65)
        let peek = capture("peek")
        for expand in [true, false] {
            if expand { vm.open() } else { vm.close() }
            for _ in 0..<22 {
                activities.post(.musicChange) // Keep this target stable; expiry is exercised separately below.
                await wait(0.016)
                assertSynchronized(capture(expand ? "peek-expand" : "peek-collapse"), compactWidth: peek.islandWidth)
            }
            await wait(0.3)
        }
        activities.end(.musicChange)
        await wait(0.65)
        for index in 0..<6 {
            if index % 2 == 0 { vm.open() } else { vm.close() }
            for _ in 0..<3 { await wait(0.016); assertSynchronized(capture("reverse")) }
        }
        await wait(0.65)
        _ = capture("settled")

        // Ending a sneak peek while expanded must not resize the open panel.
        // Then interrupt collapse with another peek and let it end during reversal.
        activities.post(.musicChange)
        vm.open()
        await wait(0.65)
        activities.end(.musicChange)
        for _ in 0..<8 {
            await wait(0.016)
            let held = capture("peek-end-expanded")
            require(abs(held.islandWidth - expanded.islandWidth) < 3
                        && abs(held.islandHeight - expanded.islandHeight) < 1,
                    "Ending a sneak peek resized the expanded player")
        }
        activities.post(.musicChange)
        vm.close()
        for index in 0..<18 {
            if index == 2 { vm.open() }
            if index == 4 { activities.end(.musicChange); vm.close() }
            await wait(0.016)
            _ = capture("peek-end-reverse")
        }
        await wait(0.65)
        let settled = capture("peek-end-settled")
        require(abs(settled.islandWidth - compact.islandWidth) < 3
                    && abs(settled.islandHeight - compact.islandHeight) < 1,
                "Peek expiry/reversal did not return to the original compact size")
        activities.post(.volume, value: 0.5)
        await wait(0.65)
        let feedback = capture("feedback", expectsCover: false)
        require(abs(feedback.islandHeight - max(24, vm.closedNotchSize.height)) <= 1,
                "System feedback height changed")
        activities.end(.volume)
        for kind in IslandActivityKind.allCases where kind.isSystemFeedback {
            activities.post(kind, value: 0.5)
            await wait(0.1)
            let closedFeedback = capture("feedback-closed-\(kind.rawValue)", expectsCover: false)
            require(abs(closedFeedback.islandHeight - compact.islandHeight) < 1,
                    "Closed feedback height changed for \(kind)")
            activities.end(kind)
        }
        activities.post(.power)
        await wait(0.65)
        let power = capture("power-closed", expectsCover: false)
        require(abs(power.islandHeight - compact.islandHeight) < 1,
                "Power notification changed its compact height")
        activities.end(.power)
        activities.setMusicActive(false)
        await wait(0.65)
        let idle = capture("idle", expectsCover: false)
        require(abs(idle.islandHeight - compact.islandHeight) < 1 && idle.islandWidth < compact.islandWidth,
                "Idle surface did not retain its original compact layout")
        activities.setMusicActive(true)
        await wait(0.65)
        let restored = capture("music-restored")
        require(abs(restored.islandWidth - compact.islandWidth) < 3,
                "Music failed to restore its compact size after system feedback and idle")
        vm.open()
        await wait(0.65)
        for kind in IslandActivityKind.allCases where kind.isSystemFeedback {
            activities.post(kind, value: 0.5)
            await wait(0.1)
            let feedbackExpanded = capture("feedback-expanded-\(kind.rawValue)")
            require(vm.notchState == .open && abs(feedbackExpanded.islandHeight - expanded.islandHeight) < 1,
                    "System feedback changed the expanded panel")
            activities.end(kind)
        }
        require(IslandArtworkRenderProbe.appearances == 1,
                     "Artwork view was recreated \(IslandArtworkRenderProbe.appearances) times across layout transitions")
        print("PASS: \(name), \(frames) frames, 1 persistent artwork view, maximum resize difference \(maximumResizeDifference)")
        activities.end(.musicChange)
        window.orderOut(nil)
        window.contentView = nil
        vm.destroy()
        await wait(0.1)
    }
}
