import AppKit
import Defaults
import SwiftUI

// The runner adds an appearance counter to the production artwork in its isolated copy.
func require(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { print("FAIL:", message()); exit(1) }
}

enum IslandArtworkRenderProbe {
    static var appearances = 0
    static var reduceMotion = false
    static var surfaceSize = CGSize.zero
    static var musicBackgroundFrame = CGRect.zero
    static var availablePages: [IslandPage] = []
    static var selectedPage = IslandPage.music
    static var renderedPagePosition: CGFloat = 0
    static var selectPage: ((IslandPage) -> Void)?
    static var horizontalGesture: ((Double, Double, NSEvent.Phase) -> Void)?
    static var startTimer: ((TimeInterval) -> Void)?
    static var actionFrames: [String: CGRect] = [:]
    static var actionHandlers: [String: () -> Void] = [:]
    static var actionAppearances: [String: Int] = [:]
    static var completeReminder: [String: () -> Void] = [:]
    static var reminderWrites: [String] = []
    static var reminderWriteSucceeds = true
}

private struct ActionButtonSizes: PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
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
                await verifyActionButtonSizes(output: output)
                await verifyAlarmMotion(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--focus-only") {
                await verifyResidentSelection(output: output)
                exit(0)
            }
            if CommandLine.arguments.contains("--playback-only") {
                await verifyArtworkReadiness()
                await verifySeekingDoesNotAnnounceTrackChanges()
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
            await verifyEnabledPages(output: output)
            await verifyResidentSelection(output: output)
            await verifyPersonalActivityRuntime(output: output)
            await verifyActionButtonSizes(output: output)
            await verifyAlarmMotion(output: output)
            await verifyCompactAlignment(output: output)
            print("PASS: production ContentView, single artwork identity, opaque rounded cover, clear text slots and synchronized geometry")
            exit(0)
        }
        NSApplication.shared.run()
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
        for (height, width): (CGFloat, CGFloat) in [(24, 120), (24, 185), (24, 320), (32, 120), (32, 185), (32, 320)] {
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
            func capture(_ name: String) -> CGFloat {
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("compact-\(Int(height))-\(Int(width))-\(name).png"))
                let scale = CGFloat(rep.pixelsWide) / host.bounds.width
                let surface = IslandArtworkRenderProbe.surfaceSize
                let surfaceLeft = (host.bounds.width - surface.width) / 2
                var first = rep.pixelsWide, last = -1
                for y in 0..<Int(height * scale) {
                    for x in Int(ceil(surfaceLeft * scale))..<Int(floor((surfaceLeft + surface.width) * scale)) {
                        let pixel = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if pixel.alphaComponent > 0.5 && max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.15 {
                            first = min(first, x); last = max(last, x)
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
                require(surface.width <= vm.expandedNotchSize.width + 1, "Compact content exceeded its window budget")
                print("PASS: compact \(name), height \(height), outer margins \(leading)/\(trailing), width \(surface.width)")
                return surface.width
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
            window.orderOut(nil)
            window.contentView = nil
            vm.destroy()
        }
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
        let reversing = centers.last!
        IslandArtworkRenderProbe.actionHandlers["play.fill"]?()
        try? await Task.sleep(for: .seconds(0.016))
        require(activities.timer?.phase == .running && abs(button("pause.fill").midY - reversing) < 15,
                "Rapid restart jumped to an endpoint")
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
        print("PASS: enabled-page combinations, rendered dot counts, editing removal, skipped pages, timer cancellation, single-page swipe and continuous expansion")
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
