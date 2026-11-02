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
}

@main struct IslandArtworkRenderTests {
    struct Frame {
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
            let music = MusicManager.shared
            music.songTitle = "Deep Green"
            music.artistName = "Christian Kuria"
            music.isPlaying = true
            music.songDuration = 180
            music.usingAppIconForArtwork = false
            music.bundleIdentifier = "com.netease.163music"
            music.albumArt = artwork(size: 200)
            ActivityCoordinator.shared.setMusicActive(true)
            for (index, screen) in NSScreen.screens.enumerated() {
                for lighting in [false, true] {
                    Defaults[.lightingEffect] = lighting
                    await verify(screen: screen, name: "screen\(index)-light\(lighting)", output: output)
                }
            }
            Defaults[.lightingEffect] = false
            await verifyPausedArtwork(output: output)
            await verifyPausedArtwork(output: output, changing: true)
            IslandArtworkRenderProbe.reduceMotion = true
            await verify(screen: NSScreen.screens[0], name: "reduced-motion", output: output)
            await verifyArtworkReadiness()
            print("PASS: production ContentView, single artwork identity, opaque rounded cover, clear text slots and synchronized geometry")
            exit(0)
        }
        NSApplication.shared.run()
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
                let headerBottom = Int((max(24, vm.effectiveClosedNotchHeight) - 2) * scale)
                for y in stride(from: Int(2 * scale), to: headerBottom, by: 2) {
                    for x in stride(from: left, to: right, by: 2) {
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
            if !expectsCover {
                require(right < left, "Hidden artwork remained visible in \(filename)")
                require(badgeRight < badgeLeft, "Hidden badge remained visible in \(filename)")
                return Frame(islandHeight: CGFloat(islandBottom + 1) / scale, artworkWidth: 0, badgeWidth: 0)
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
            return Frame(islandHeight: CGFloat(islandBottom + 1) / scale, artworkWidth: CGFloat(coverWidth) / scale,
                         badgeWidth: badgeRight >= badgeLeft ? CGFloat(badgeRight - badgeLeft + 1) / scale : 0)
        }
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        await wait(0.65)
        let compact = capture("compact")
        vm.open()
        await wait(0.65)
        let expanded = capture("expanded")
        require(expanded.badgeWidth > 10, "The regression must exercise a real music app badge")
        func assertSynchronized(_ frame: Frame) {
            let islandProgress = (frame.islandHeight - compact.islandHeight) / (expanded.islandHeight - compact.islandHeight)
            let coverProgress = (frame.artworkWidth - compact.artworkWidth) / (expanded.artworkWidth - compact.artworkWidth)
            maximumResizeDifference = max(maximumResizeDifference, abs(islandProgress - coverProgress))
            require(abs(islandProgress - coverProgress) < 0.035,
                    "Cover and island use different resize rates in \(name), frame \(frames): island \(islandProgress), cover \(coverProgress), measured \(frame)")
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
        _ = capture("peek")
        for expand in [true, false] {
            if expand { vm.open() } else { vm.close() }
            for _ in 0..<22 {
                await wait(0.016)
                assertSynchronized(capture(expand ? "peek-expand" : "peek-collapse"))
            }
            await wait(0.3)
        }
        for index in 0..<6 {
            if index % 2 == 0 { vm.open() } else { vm.close() }
            for _ in 0..<3 { await wait(0.016); assertSynchronized(capture("reverse")) }
        }
        await wait(0.65)
        _ = capture("settled")
        activities.end(.musicChange)
        activities.post(.volume, value: 0.5)
        await wait(0.65)
        let feedback = capture("feedback", expectsCover: false)
        require(abs(feedback.islandHeight - max(24, vm.closedNotchSize.height)) <= 1,
                "System feedback height changed")
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
