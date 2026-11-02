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

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false
    @State private var measuredCompactWidth: CGFloat = 0

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
            return !coordinator.firstLaunch && !musicManager.songTitle.isEmpty
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
                let mainLayout = CompactNotchLayout()
                    .padding(.horizontal, cornerRadiusInsets.closed.bottom)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                                guard width > 0, abs(measuredCompactWidth - width) > 0.1 else { return }
                                if measuredCompactWidth == 0 {
                                    // Seed the first measurement without animating from zero.
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) { measuredCompactWidth = width }
                                } else {
                                    measuredCompactWidth = width
                                }
                            }
                        }
                    }
                    .animation(islandAnimation, value: activities.current?.kind)
                    .modifier(IslandExpansionSurface(
                        vm: vm, expansion: vm.notchState == .open ? 1 : 0,
                        closedSurfaceHeight: closedSurfaceHeight,
                        compactWidth: measuredCompactWidth,
                        expandedSize: openNotchSize,
                        expandedLeadingInset: expandedHorizontalInset + MusicPlayerImageSizes.panelPadding + MusicPlayerImageSizes.padding,
                        expandedContent: ExpandedNotchLayout(),
                        keepsCompactVisible: coordinator.helloAnimationRunning,
                        scalesCorners: Defaults[.cornerRadiusScaling], artwork: musicManager.albumArt,
                        isArtworkPaused: !musicManager.isPlaybackActive, showsArtwork: showsArtwork,
                        showsAmbience: vm.notchState == .open
                            && musicManager.isPlaybackActive && !musicManager.songTitle.isEmpty && Defaults[.lightingEffect]
                    ))
                    .animation(islandAnimation, value: vm.notchState)
                    .animation(islandAnimation, value: measuredCompactWidth)
                    .animation(islandAnimation, value: closedSurfaceHeight)
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
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation(islandAnimation) {
                                isHovering = false
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
        .animation(islandAnimation, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
    }

    @ViewBuilder
    func CompactNotchLayout() -> some View {
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
                        && Defaults[.showPowerStatusNotifications]
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
                                BatteryView(
                                    levelBattery: batteryModel.levelBattery,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    batteryWidth: 30
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if presentation.feedback != nil {
                          InlineHUD(type: activities.current?.kind ?? .volume, value: Binding(get: { activities.current?.value ?? 0 }, set: { activities.updateFeedbackValue($0) }), icon: activities.current?.icon ?? "", hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if presentation.showsMusic && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                  }
              }
              .conditionalModifier(presentation.feedback != nil) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
        }
    }

    private func ExpandedNotchLayout() -> some View {
        VStack(alignment: .leading, spacing: MusicPlayerImageSizes.sectionSpacing) {
            Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
            if vm.notchState == .open {
                NotchHomeView()
                    .transition(.opacity)
                    .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .padding(.horizontal, expandedHorizontalInset + MusicPlayerImageSizes.panelPadding)
        .padding(.bottom, MusicPlayerImageSizes.panelPadding)
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
                                textColor: Color(nsColor: musicManager.avgColor),
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Color(nsColor: musicManager.avgColor)
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
                            Color(nsColor: musicManager.avgColor).gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .mask {
                            AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying && vm.notchState == .closed))
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

    private func doOpen() {
        vm.open()
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
                    
                    if self.vm.notchState == .open {
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
            gestureProgress = .zero
            vm.close()

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

/// Width, height, outline and cover use the same rendered expansion. A compact
/// content change is interpolated here too, never by a second outer frame.
private struct IslandExpansionSurface<ExpandedContent: View>: AnimatableModifier {
    let vm: IslandViewModel
    var expansion: CGFloat
    var closedSurfaceHeight: CGFloat
    var compactWidth: CGFloat
    let expandedSize: CGSize
    let expandedLeadingInset: CGFloat
    let expandedContent: ExpandedContent
    let keepsCompactVisible: Bool
    let scalesCorners: Bool
    let artwork: NSImage
    let isArtworkPaused: Bool
    let showsArtwork: Bool
    let showsAmbience: Bool

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(expansion, AnimatablePair(compactWidth, closedSurfaceHeight)) }
        set {
            expansion = newValue.first
            compactWidth = newValue.second.first
            closedSurfaceHeight = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        let closedHeight = vm.effectiveClosedNotchHeight
        let top = interpolate(cornerRadiusInsets.closed.top, scalesCorners ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top)
        let bottom = interpolate(cornerRadiusInsets.closed.bottom, scalesCorners ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom)
        content.opacity(keepsCompactVisible ? 1 : 1 - expansion)
            .allowsHitTesting(vm.notchState == .closed)
            .accessibilityHidden(vm.notchState == .open)
            // The expansion already supplies each frame. Scope this to the
            // layout itself; compact content retains its own transitions.
            .animation(nil) { compact in
                IslandSurfaceLayout(expansion: expansion, compactWidth: compactWidth, closedHeight: closedSurfaceHeight, expandedSize: expandedSize) {
                    compact
                }
            }
            .overlay(alignment: .top) {
                expandedContent
                    .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                    .opacity(expansion)
                    .allowsHitTesting(vm.notchState == .open)
                    .accessibilityHidden(vm.notchState == .closed)
            }
            .overlay {
                AlbumArtPresentation(vm: vm, expansion: expansion, closedHeight: closedHeight,
                                     expandedLeadingInset: expandedLeadingInset,
                                     scalesCorners: scalesCorners, isArtworkPaused: isArtworkPaused)
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

/// Measure the existing compact content without making its retiring/expanded
/// siblings determine the surface width. Only the surface's rendered expansion
/// drives this layout; there is no second width animation.
private struct IslandSurfaceLayout: Layout {
    let expansion: CGFloat
    let compactWidth: CGFloat
    let closedHeight: CGFloat
    let expandedSize: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = compactWidth > 0 ? compactWidth : subviews.first?.sizeThatFits(.unspecified).width ?? 0
        return CGSize(width: width + (expandedSize.width - width) * expansion,
                      height: closedHeight + (expandedSize.height - closedHeight) * expansion)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let compact = subviews.first else { return }
        let width = compact.sizeThatFits(.unspecified).width
        compact.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                      proposal: ProposedViewSize(width: width, height: bounds.height))
    }
}

#Preview {
    let vm = IslandViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
