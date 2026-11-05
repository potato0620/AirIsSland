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
    @Default(.lightingEffect) private var musicBackgroundEnabled
    @Default(.remindersActivityEnabled) private var remindersEnabled
    @Default(.timerActivityEnabled) private var timerEnabled
    @Default(.showPageIndicators) private var showPageIndicators

    @ObservedObject var coordinator = IslandWindowCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false

    @State private var pager = IslandPager()
    @State private var pagePosition: CGFloat = 0
    @State private var musicPageHasEntered = true
    @State private var artworkPagingIsInteractive = false
    @State private var measuredCompactWidth: CGFloat = 0
    @State private var spectrumConsumer = UUID()
    @State private var expandedPagesVisible = false
    @State private var compactContentVisible = false

    @ObservedObject private var activities = ActivityCoordinator.shared

    private var presentation: IslandPresentation { IslandPresentation(activity: activities.current) }

    private var enabledPages: [IslandPage] {
        IslandPage.allCases.filter { page in
            switch page {
            case .music: return true
            case .reminders: return remindersEnabled
            case .timer: return timerEnabled
            }
        }
    }

    private var islandAnimation: Animation? {
        IslandAnimations.animation(reduceMotion: reduceMotion)
    }

    private var expandedHorizontalInset: CGFloat {
        Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom
    }

    private var showsArtwork: Bool {
        if vm.notchState == .open {
            return musicPageHasEntered && !coordinator.firstLaunch && !musicManager.songTitle.isEmpty
        }
        return presentation.showsMusic && !vm.hideOnClosed
    }

    private var closedSurfaceHeight: CGFloat {
        if presentation.feedback != nil {
            return max(24, vm.closedNotchSize.height) + (isHovering ? 8 : 0)
        }
        return vm.effectiveClosedNotchHeight
    }

    private enum SpectrumDisplay { case hidden, compact, expanded }
    private var spectrumDisplay: SpectrumDisplay {
        guard !reduceMotion else { return .hidden }
        // A closing page is still visible until the shared geometry reaches zero.
        // Keep its capture demand alive through that same rendered interval.
        if (vm.notchState == .open || expandedPagesVisible), pager.selection == .music,
           !musicManager.songTitle.isEmpty {
            return .expanded
        }
        guard vm.notchState == .closed || compactContentVisible else { return .hidden }
        return !vm.hideOnClosed && vm.effectiveClosedNotchHeight > 12 && presentation.showsMusicSpectrum ? .compact : .hidden
    }

    var body: some View {
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
                        expandedSize: vm.expandedNotchSize,
                        expandedLeadingInset: expandedArtworkLeadingInset,
                        expandedContent: { width, progress in ExpandedNotchLayout(width: width, expansion: progress) },
                        pagePosition: pagePosition,
                        artworkPageTarget: pagePosition,
                        artworkReturningToMusic: pager.selection == .music,
                        artworkPagingIsInteractive: artworkPagingIsInteractive,
                        keepsCompactVisible: coordinator.helloAnimationRunning,
                        compactVisibilityChanged: { compactContentVisible = $0 },
                        scalesCorners: Defaults[.cornerRadiusScaling],
                        isArtworkPaused: !musicManager.isPlaybackActive, showsArtwork: showsArtwork
                    ))
                    .animation(islandAnimation, value: vm.notchState)
                    .animation(islandAnimation, value: measuredCompactWidth)
                    .animation(islandAnimation, value: closedSurfaceHeight)
                    .animation(islandAnimation, value: vm.expandedNotchSize.width)
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .onChange(of: spectrumDisplay, initial: true) { _, display in
                        activities.setSpectrumVisible(display != .hidden, consumer: spectrumConsumer,
                                                      expanded: display == .expanded)
                    }
                    .onDisappear { activities.setSpectrumVisible(false, consumer: spectrumConsumer) }
                    .onChange(of: enabledPages, initial: true) { _, _ in
                        updateEnabledPages()
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .onChange(of: activities.current, initial: true) { previous, current in
                        if IslandPresentation(activity: current).requiresExpandedTimer {
                            hoverTask?.cancel()
                            showOpeningPage(.timer)
                            withAnimation(islandAnimation) { vm.open() }
                        } else if IslandPresentation(activity: previous).requiresExpandedTimer {
                            hoverTask?.cancel()
                            withAnimation(islandAnimation) {
                                isHovering = false
                                vm.close()
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .open {
                            let page: IslandPage
                            switch activities.current?.kind {
                            case .timer, .timerFinished: page = .timer
                            case .reminders: page = .reminders
                            case .none: page = pager.lastBrowsedPage ?? (activities.reminders.isEmpty ? .music : .reminders)
                            case .music, .musicChange, .volume, .brightness, .backlight, .mic, .power: page = .music
                            }
                            showOpeningPage(page)
                        } else {
                            vm.isEditingActivity = false
                            artworkPagingIsInteractive = false
                        }
                        if newState == .closed && isHovering {
                            withAnimation(islandAnimation) {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isEditingActivity) { _, editing in
                        if !editing && !isHovering { handleHover(false) }
                    }
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                    }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: vm.windowSize.width, maxHeight: vm.windowSize.height, alignment: .top)
        .compositingGroup()
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
                        CompactActivityLayout(notchWidth: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight, maximumWidth: vm.expandedNotchSize.width) {
                            Text(batteryModel.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            BatteryView(
                                levelBattery: batteryModel.levelBattery,
                                isPluggedIn: batteryModel.isPluggedIn,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                batteryWidth: 30
                            )
                        }
                      } else if presentation == .timer(finished: false), let timer = activities.current?.timer {
                          TimelineView(.periodic(from: .now, by: 1)) { context in
                              CompactActivityLayout(notchWidth: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight, maximumWidth: vm.expandedNotchSize.width) {
                                  Image(systemName: "timer").foregroundStyle(.orange)
                                  Text(timerText(timer.remaining(at: context.date)))
                                      .font(.caption).monospacedDigit().foregroundStyle(.orange)
                              }
                          }
                      } else if presentation.feedback != nil {
                          InlineHUD(type: activities.current?.kind ?? .volume, value: Binding(get: { activities.current?.value ?? 0 }, set: { activities.updateFeedbackValue($0) }), icon: activities.current?.icon ?? "", hoverAnimation: $isHovering)
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

    private var expandedArtworkLeadingInset: CGFloat {
        expandedHorizontalInset + MusicPlayerImageSizes.panelPadding + MusicPlayerImageSizes.padding
    }

    private func ExpandedNotchLayout(width: CGFloat, expansion: CGFloat) -> some View {
        let dotSide: CGFloat = 5
        let dotTargetWidth: CGFloat = 18
        return VStack(alignment: .leading, spacing: MusicPlayerImageSizes.sectionSpacing) {
            HStack(spacing: 0) {
                if enabledPages.count > 1 && showPageIndicators {
                    ForEach(enabledPages) { page in
                        Button { selectPage(page) } label: {
                            Circle()
                                .fill(page == .timer && activities.timer?.phase == .finished ? Color.orange : pager.selection == page ? .white : Color.gray.opacity(0.6))
                                .frame(width: dotSide, height: dotSide).frame(width: dotTargetWidth, height: 24)
                        }
                        .buttonStyle(.plain).accessibilityLabel(Text(page.title))
                        .accessibilityAddTraits(pager.selection == page ? .isSelected : [])
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, expandedArtworkLeadingInset - (dotTargetWidth - dotSide) / 2)
            .frame(height: max(24, vm.effectiveClosedNotchHeight))
            if vm.notchState == .open || expansion > 0 {
                HStack(spacing: 0) {
                    ForEach(enabledPages) { page in
                        expandedPage(page, width: width, expansion: expansion) {
                            switch page {
                            case .music: NotchHomeView(active: pager.selection == .music)
                            case .reminders: RemindersActivityPage(active: vm.notchState == .open && pager.selection == .reminders)
                            case .timer: TimerActivityPage(active: vm.notchState == .open && pager.selection == .timer)
                            }
                        }
                    }
                }
                    // This tree stays mounted through the rendered closing
                    // progress. Release demand only when it actually retires.
                    .onAppear { expandedPagesVisible = true }
                    .onDisappear { expandedPagesVisible = false }
                    .frame(width: width * CGFloat(enabledPages.count),
                           height: expandedPageHeight, alignment: .leading)
                    .offset(x: -pagePosition * width)
                    .frame(width: width, height: expandedPageHeight, alignment: .leading)
                    .clipped()
                    .background {
                        if enabledPages.count > 1 {
                            HorizontalPagingGesture(action: handleHorizontalGesture)
                        }
                    }
            }
        }
    }

    private var expandedPageHeight: CGFloat {
        max(0, expandedNotchHeight - max(24, vm.effectiveClosedNotchHeight) - MusicPlayerImageSizes.sectionSpacing)
    }

    private func expandedPage<Content: View>(_ page: IslandPage, width: CGFloat, expansion: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .modifier(IslandCardContentTransition(expansion: expansion))
            .padding(.horizontal, expandedHorizontalInset + MusicPlayerImageSizes.panelPadding)
            .padding(.bottom, MusicPlayerImageSizes.panelPadding)
            .frame(width: width, height: expandedPageHeight)
            .background {
                if page == .music {
                    IslandBackdrop(color: musicManager.avgColor,
                        topClearance: max(0, vm.physicalNotchHeight - max(24, vm.effectiveClosedNotchHeight) - MusicPlayerImageSizes.sectionSpacing),
                        showsArtwork: musicManager.isPlaybackActive && !musicManager.songTitle.isEmpty && musicBackgroundEnabled)
                        // The moving edge can be inside the stationary island mask.
                        // Give the background its own matching contour before paging.
                        .clipShape(NotchShape(
                            topCornerRadius: Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top,
                            bottomCornerRadius: Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom))
                }
            }
            // Resolve animated content inside its page before the pager moves it.
            // Numeric transitions must never draw into an adjacent activity.
            .compositingGroup()
            .clipped()
            .accessibilityHidden(pager.selection != page)
            .allowsHitTesting(pager.selection == page)
            .disabled(pager.selection != page)
    }

    private func selectPage(_ page: IslandPage) {
        guard enabledPages.contains(page) else { return }
        activities.prefer(page.activityKind)
        let changed = page != pager.selection
        pager.select(page, manually: true)
        guard changed else { return }
        vm.isEditingActivity = false
        artworkPagingIsInteractive = true
        if page == .music { musicPageHasEntered = true }
        withAnimation(IslandAnimations.pageCommit(reduceMotion: reduceMotion)) { pagePosition = CGFloat(pager.position) }
        IslandHaptics.alignment()
    }

    private func showOpeningPage(_ page: IslandPage) {
        // Restoring the resident page during expansion is not a user page switch.
        artworkPagingIsInteractive = false
        pager.updatePages(enabledPages)
        pager.select(enabledPages.contains(page) ? page : enabledPages[0])
        musicPageHasEntered = pager.selection == .music
        pagePosition = CGFloat(pager.position)
    }

    private func updateEnabledPages() {
        artworkPagingIsInteractive = false
        let previous = pager.selection
        pager.updatePages(enabledPages)
        if previous != pager.selection { vm.isEditingActivity = false }
        if pager.selection == .music { musicPageHasEntered = true }
        withTransaction(Transaction(animation: nil)) { pagePosition = CGFloat(pager.position) }
    }

    private func handleHorizontalGesture(_ delta: Double, _ seconds: Double, _ phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isEditingActivity, enabledPages.count > 1 else { return }
        if phase == .began {
            artworkPagingIsInteractive = true
            musicPageHasEntered = true
            pager.begin()
        }
        else if phase == .changed {
            if let page = pager.drag(delta: delta / vm.expandedNotchSize.width, seconds: seconds) {
                activities.prefer(page.activityKind)
                withAnimation(IslandAnimations.pageCommit(reduceMotion: reduceMotion)) { pagePosition = CGFloat(pager.position) }
                IslandHaptics.alignment()
            } else {
                guard pagePosition != CGFloat(pager.position) else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { pagePosition = CGFloat(pager.position) }
            }
        } else if phase == .ended {
            pager.end()
            withAnimation(IslandAnimations.pageReturn(reduceMotion: reduceMotion)) { pagePosition = CGFloat(pager.position) }
        }
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
                        ? min(380, max(0, vm.expandedNotchSize.width - 2 * cornerRadiusInsets.closed.bottom - 2 * max(0, vm.effectiveClosedNotchHeight - 12) - 16))
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            if presentation.showsMusicSpectrum {
                let spectrumHeight = max(0, vm.effectiveClosedNotchHeight - 12)
                Rectangle()
                    .fill(Color(nsColor: musicManager.avgColor).gradient)
                    .frame(width: 20, height: spectrumHeight)
                    .mask {
                        AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying),
                                          maximumHeight: spectrumHeight)
                            .frame(width: 20, height: spectrumHeight)
                    }
                    .frame(width: max(20, vm.effectiveClosedNotchHeight - 12),
                           height: max(0, vm.effectiveClosedNotchHeight - 12), alignment: .trailing)
            }
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    private func doOpen() {
        guard vm.notchState == .closed else { return }
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
            
            if vm.notchState == .closed { IslandHaptics.alignment() }
            
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
                    
                    if self.vm.notchState == .open && !self.vm.isEditingActivity {
                        self.vm.close()
                    }
                }
            }
        }
    }

}

/// Align visible content to the shared outer padding. Balanced, intrinsic side
/// widths keep the physical notch centered even when one label is much longer.
private struct CompactActivityLayout: Layout {
    let notchWidth: CGFloat
    let height: CGFloat
    let maximumWidth: CGFloat
    private let spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = sideWidth(subviews)
        return CGSize(width: max(0, notchWidth) + 2 * (side + spacing), height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let contentProposal = ProposedViewSize(width: sideWidth(subviews), height: height)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: contentProposal)
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: contentProposal)
    }

    private func sideWidth(_ subviews: Subviews) -> CGFloat {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let maximum = max(0, (maximumWidth - 2 * cornerRadiusInsets.closed.bottom - max(0, notchWidth)) / 2 - spacing)
        return min(ideal, maximum)
    }
}

/// Content follows the surface's rendered progress; page controls keep their own animations.
struct IslandCardContentTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let expansion: CGFloat

    func body(content: Content) -> some View {
        content.animation(nil) { page in
            page.blur(radius: reduceMotion ? 0 : 30 * (1 - min(1, max(0, expansion))))
        }
    }
}

/// Width, height, outline and cover use the same rendered expansion. A compact
/// content change is interpolated here too, never by a second outer frame.
private struct IslandExpansionSurface<ExpandedContent: View>: AnimatableModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let vm: IslandViewModel
    var expansion: CGFloat
    var closedSurfaceHeight: CGFloat
    var compactWidth: CGFloat
    var expandedSize: CGSize
    let expandedLeadingInset: CGFloat
    let expandedContent: (CGFloat, CGFloat) -> ExpandedContent
    var pagePosition: CGFloat
    let artworkPageTarget: CGFloat
    let artworkReturningToMusic: Bool
    let artworkPagingIsInteractive: Bool
    let keepsCompactVisible: Bool
    let compactVisibilityChanged: (Bool) -> Void
    let scalesCorners: Bool
    let isArtworkPaused: Bool
    let showsArtwork: Bool

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>> {
        get { AnimatablePair(expansion, AnimatablePair(compactWidth, AnimatablePair(closedSurfaceHeight, AnimatablePair(pagePosition, expandedSize.width)))) }
        set {
            expansion = newValue.first
            compactWidth = newValue.second.first
            closedSurfaceHeight = newValue.second.second.first
            pagePosition = newValue.second.second.second.first
            expandedSize.width = newValue.second.second.second.second
        }
    }

    func body(content: Content) -> some View {
        let closedHeight = vm.effectiveClosedNotchHeight
        let top = interpolate(cornerRadiusInsets.closed.top, scalesCorners ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top)
        let bottom = interpolate(cornerRadiusInsets.closed.bottom, scalesCorners ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom)
        let compactVisible = keepsCompactVisible || expansion < 1
        content.environment(\.musicSpectrumVisible, compactVisible)
            .onChange(of: compactVisible, initial: true) { _, visible in compactVisibilityChanged(visible) }
            .opacity(keepsCompactVisible ? 1 : 1 - expansion)
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
                expandedContent(expandedSize.width, expansion)
                    .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                    .opacity(expansion)
                    .allowsHitTesting(vm.notchState == .open)
                    .accessibilityHidden(vm.notchState == .closed)
            }
            .overlay {
                AlbumArtPresentation(vm: vm, expansion: expansion, closedHeight: closedHeight,
                                     expandedLeadingInset: expandedLeadingInset,
                                     scalesCorners: scalesCorners, isArtworkPaused: isArtworkPaused)
                    .animation(artworkPagingAnimation) { artwork in
                        artwork.modifier(ArtworkPageOffset(position: artworkPageTarget,
                            expandedWidth: expandedSize.width, expansion: expansion))
                    }
                    .opacity(showsArtwork ? 1 : 0)
                    .allowsHitTesting(vm.notchState == .open && showsArtwork)
                    .accessibilityHidden(!showsArtwork)
            }
            .background { Color.black }
            // Flatten page backgrounds and the persistent cover before applying
            // the one island mask, including unanimated trackpad updates.
            .compositingGroup()
            .clipShape(NotchShape(topCornerRadius: top, bottomCornerRadius: bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(.black).frame(height: 1).padding(.horizontal, top)
            }
    }

    private func interpolate(_ compact: CGFloat, _ expanded: CGFloat) -> CGFloat {
        compact + (expanded - compact) * expansion
    }

    private var artworkPagingAnimation: Animation? {
        guard artworkPagingIsInteractive else { return nil }
        return artworkReturningToMusic
            ? IslandAnimations.animation(reduceMotion: reduceMotion)
            : IslandAnimations.pageCommit(reduceMotion: reduceMotion)
    }
}

/// Only the cover and attached badge trail the incoming music page. Expansion
/// geometry still comes from the island's rendered progress, including reversal.
private struct ArtworkPageOffset: AnimatableModifier {
    var position: CGFloat
    let expandedWidth: CGFloat
    let expansion: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        content.animation(nil) { artwork in
            artwork.offset(x: -position * expandedWidth * expansion)
        }
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
