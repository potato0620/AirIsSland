//
//  IslandViewModel.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class IslandViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = IslandWindowCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    private var animation: Animation? {
        IslandAnimations.animation(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    @Published private(set) var notchState: NotchState = .closed
    @Published var isEditingActivity = false

    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true


    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    /// Page content can request extra height (agent sessions). The window follows
    /// through the existing notchHeightChanged notification.
    @Published var expandedHeightDelta: CGFloat = 0

    var expandedNotchSize: CGSize {
        var size = getExpandedNotchSize(baseWidth: closedNotchSize.width, screenUUID: screenUUID)
        size.height += max(0, expandedHeightDelta)
        return size
    }

    var windowSize: CGSize {
        CGSize(width: expandedNotchSize.width + 2 * shadowPadding,
               height: expandedNotchSize.height + shadowPadding)
    }
    
    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(self?.animation) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    /// Use this window's display, not the globally preferred display on another monitor.
    var physicalNotchHeight: CGFloat {
        let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return max(0, screen?.safeAreaInsets.top ?? 0)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    func open() {
        self.notchSize = expandedNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func close() {
        guard !IslandPresentation(activity: ActivityCoordinator.shared.current).requiresExpandedTimer else { return }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed

    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
