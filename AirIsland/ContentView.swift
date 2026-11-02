//
//  ContentView.swift
//  AirIslandApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: IslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var coordinator = IslandWindowCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @ObservedObject private var activities = ActivityCoordinator.shared

    private var presentation: IslandPresentation { IslandPresentation(activity: activities.current) }

    private var islandAnimation: Animation? {
        IslandAnimations.animation(reduceMotion: reduceMotion)
    }

    private var expandedHorizontalInset: CGFloat {
        Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom
    }

    private var showsArtwork: Bool {
        if vm.notchState == .open {
            return coordinator.currentView == .home && !coordinator.firstLaunch && !musicManager.songTitle.isEmpty
        }
        return presentation.showsMusic && !vm.hideOnClosed
    }

    private var closedSurfaceHeight: CGFloat {
        if presentation.feedback != nil {
            return max(24, vm.closedNotchSize.height) + (isHovering ? 8 : 0)
        }
        return vm.effectiveClosedNotchHeight
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? expandedHorizontalInset
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? MusicPlayerImageSizes.panelPadding : 0)
                    .frame(width: vm.notchState == .open ? vm.notchSize.width : nil, alignment: .top)
                    .modifier(IslandExpansionSurface(
                        vm: vm, expansion: vm.notchState == .open ? 1 : 0,
                        closedSurfaceHeight: closedSurfaceHeight,
                        expandedHeight: openNotchSize.height,
                        expandedLeadingInset: expandedHorizontalInset + MusicPlayerImageSizes.panelPadding + MusicPlayerImageSizes.padding,
                        scalesCorners: Defaults[.cornerRadiusScaling], artwork: musicManager.albumArt,
                        isPlaying: musicManager.isPlaying, showsArtwork: showsArtwork,
                        showsAmbience: vm.notchState == .open && coordinator.currentView == .home
                            && musicManager.isPlaying && !musicManager.songTitle.isEmpty && Defaults[.lightingEffect]
                    ))
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation(islandAnimation) {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        // Animate presentation changes, never artwork resolution or playback progress.
        .animation(islandAnimation, value: vm.notchState)
        .animation(islandAnimation, value: coordinator.currentView)
        .animation(islandAnimation, value: gestureProgress)
        .animation(islandAnimation, value: activities.current?.kind)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading, spacing: MusicPlayerImageSizes.sectionSpacing) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if presentation == .power
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Color.clear
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                IslandBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if presentation.feedback != nil && vm.notchState == .closed {
                          InlineHUD(type: activities.current?.kind ?? .volume, value: Binding(get: { activities.current?.value ?? 0 }, set: { activities.updateFeedbackValue($0) }), icon: activities.current?.icon ?? "", hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if presentation.showsMusic && vm.notchState == .closed && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                       } else if vm.notchState == .open {
                           IslandHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                  }
              }
              .conditionalModifier(presentation.feedback != nil && vm.notchState == .closed) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView()
                    case .shelf:
                        ShelfView()
                    }
                }
                .transition(.opacity)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Color.clear
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Color.clear
                .overlay(
                    HStack(alignment: .top) {
                        if presentation.showsMusicPeek
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                        }
                    }
                )
                .frame(
                    width: (presentation.showsMusicPeek)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }

            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.shelfEnabled] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(islandAnimation) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(islandAnimation) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  presentation.feedback == nil,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          self.presentation.feedback == nil else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(islandAnimation) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(islandAnimation) { gestureProgress = .zero }
            return
        }

        withAnimation(islandAnimation) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(islandAnimation) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open else { return }

        withAnimation(islandAnimation) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(islandAnimation) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(islandAnimation) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

/// The island outline and cover share the same rendered expansion value, rather
/// than independently starting layout and matched-geometry animations.
private struct IslandExpansionSurface: AnimatableModifier {
    let vm: IslandViewModel
    var expansion: CGFloat
    let closedSurfaceHeight: CGFloat
    let expandedHeight: CGFloat
    let expandedLeadingInset: CGFloat
    let scalesCorners: Bool
    let artwork: NSImage
    let isPlaying: Bool
    let showsArtwork: Bool
    let showsAmbience: Bool

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func body(content: Content) -> some View {
        let closedHeight = vm.effectiveClosedNotchHeight
        let top = interpolate(cornerRadiusInsets.closed.top, scalesCorners ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top)
        let bottom = interpolate(cornerRadiusInsets.closed.bottom, scalesCorners ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom)
        content
            .frame(height: interpolate(closedSurfaceHeight, expandedHeight), alignment: .top)
            .overlay {
                AlbumArtPresentation(vm: vm, expansion: expansion, closedHeight: closedHeight,
                                     expandedLeadingInset: expandedLeadingInset,
                                     scalesCorners: scalesCorners, isPlaying: isPlaying)
                    .opacity(showsArtwork ? 1 : 0)
                    .allowsHitTesting(vm.notchState == .open && showsArtwork)
                    .accessibilityHidden(!showsArtwork)
            }
            .background {
                IslandBackdrop(artwork: artwork, topClearance: max(vm.physicalNotchHeight, closedHeight),
                               showsArtwork: showsAmbience)
            }
            .clipShape(NotchShape(topCornerRadius: top, bottomCornerRadius: bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(.black).frame(height: 1).padding(.horizontal, top)
            }
    }

    private func interpolate(_ compact: CGFloat, _ expanded: CGFloat) -> CGFloat {
        compact + (expanded - compact) * expansion
    }
}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = IslandViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
