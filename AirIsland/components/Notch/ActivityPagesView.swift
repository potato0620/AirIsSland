import Defaults
import SwiftUI

extension IslandPage {
    var title: LocalizedStringKey {
        switch self {
        case .music: return "Media"
        case .reminders: return "Reminders"
        case .timer: return "Timer"
        }
    }
}

/// Shared island controls: circles for icons, matching capsules for text actions.
struct IslandActionButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var iconOnly = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iconOnly ? 18 : 13, weight: .medium))
            .padding(.horizontal, iconOnly ? 0 : 14)
            .frame(width: iconOnly ? 44 : nil, height: 44)
            .foregroundStyle(tint ?? .white)
            .background((tint ?? .white).opacity(tint == nil ? 0.12 : 0.18), in: Capsule())
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.94 : 1)
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.65 : 1)
            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct IslandActionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: LocalizedStringKey
    let icon: String
    let tint: Color?
    let action: () -> Void

    init(_ title: LocalizedStringKey, icon: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button { action(); IslandHaptics.alignment() } label: {
            Image(systemName: icon)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: icon)
        }
            .buttonStyle(IslandActionButtonStyle(tint: tint, iconOnly: true))
            .accessibilityLabel(Text(title))
            .help(Text(title))
    }
}

/// Presentation-only ringing. Explicit keyframes avoid relying on symbol-layer
/// animation support; hidden pages and Reduce Motion keep the initial angle.
struct TimerFinishedIcon: View {
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "alarm.fill")
            .font(.system(size: 30, weight: .medium))
            .keyframeAnimator(initialValue: 0.0, repeating: isActive && !reduceMotion) { symbol, angle in
                symbol.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                LinearKeyframe(-12, duration: 0.10)
                LinearKeyframe(12, duration: 0.12)
                LinearKeyframe(-10, duration: 0.12)
                LinearKeyframe(8, duration: 0.12)
                LinearKeyframe(-5, duration: 0.12)
                LinearKeyframe(0, duration: 0.10)
                LinearKeyframe(0, duration: 0.80)
            }
            .foregroundStyle(.orange)
            .frame(width: 36, height: 38)
            .accessibilityHidden(true)
    }
}

struct TimerActivityPage: View {
    var active = true
    @ObservedObject private var activities = ActivityCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDuration: TimeInterval = 1500
    @State private var pickerID = UUID()
    @State private var lastTimer: TimerSession?
    @State private var runProgress: CGFloat = ActivityCoordinator.shared.timer == nil ? 0 : 1
    @State private var transitionID = UUID()

    var body: some View {
        Group {
            if let timer = activities.timer, timer.phase == .finished {
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        TimerFinishedIcon(isActive: active)
                        Text("Timer finished").font(.system(size: 28, weight: .light))
                    }.foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        IslandActionButton("Restart timer", icon: "arrow.clockwise", tint: .orange) { startTimer(timer.duration) }
                        IslandActionButton("Close", icon: "xmark") { TimerActivityManager.shared.cancel() }
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1, paused: !active || activities.timer?.phase != .running)) { context in
                    TimerInteractionSurface(progress: runProgress,
                        duration: $selectedDuration, pickerID: pickerID,
                        timer: activities.timer ?? lastTimer, date: context.date,
                        hasTimer: activities.timer != nil, start: startTimer)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: activities.timer, initial: true) { previous, next in
            if let next { lastTimer = next }
            else if previous != nil { selectedDuration = 1500; pickerID = UUID() }
            let target: CGFloat = next == nil ? 0 : 1
            guard runProgress != target else { return }
            let id = UUID()
            transitionID = id
            withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion), completionCriteria: .removed) {
                runProgress = target
            } completion: {
                guard transitionID == id, activities.timer == nil else { return }
                lastTimer = nil
            }
        }
    }

    private func startTimer(_ duration: TimeInterval) {
        TimerActivityManager.shared.start(duration: duration)
        activities.prefer(.timer)
    }
}

/// A persistent primary control and one rendered progress own setup/run geometry.
/// Business time and cancellation are never delayed to match this transition.
private struct TimerInteractionSurface: View, Animatable {
    var progress: CGFloat
    @Binding var duration: TimeInterval
    let pickerID: UUID
    let timer: TimerSession?
    let date: Date
    let hasTimer: Bool
    let start: (TimeInterval) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let p = min(1, max(0, progress))
            ZStack(alignment: .topLeading) {
                picker(progress: p, size: geometry.size)
                readout(progress: p, size: geometry.size)
                cancelControl(progress: p, size: geometry.size)
                primaryControl(progress: p, size: geometry.size)
            }
        }
    }

    @ViewBuilder private func picker(progress p: CGFloat, size: CGSize) -> some View {
        if p < 0.99 {
            TimerDurationForm(duration: $duration).id(pickerID)
                .frame(width: size.width, height: size.height)
                .animation(nil) { view in view.opacity(Double(max(0, 1 - 2.5 * p))).offset(x: -18 * p) }
                .allowsHitTesting(!hasTimer).accessibilityHidden(hasTimer)
        }
    }

    private func readout(progress p: CGFloat, size: CGSize) -> some View {
        let labelWidth: CGFloat = max(0, size.width - 126)
        let remaining: TimeInterval = timer?.remaining(at: date) ?? duration
        let textWidth = (timerText(remaining) as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 23 + 27 * p, weight: .light)
        ]).width
        let x: CGFloat = size.width / 2 + (labelWidth / 2 - size.width / 2) * p
        let y: CGFloat = (size.height - 48) / 2 + 24 * p
        let offset: CGFloat = max(0, (labelWidth - textWidth) / 2) * (1 - p)
        let label = VStack(alignment: .leading, spacing: 3) {
            Text("Timer").font(.subheadline).foregroundStyle(.secondary).opacity(Double(p))
            countdown(remaining: remaining, progress: p)
            status(progress: p)
        }
        return label
        .frame(width: labelWidth, alignment: .leading)
        .accessibilityHidden(!hasTimer)
        .animation(nil) { view in
            view.opacity(Double(min(1, 1.4 * p))).offset(x: offset).position(x: x, y: y)
        }
    }

    private func countdown(remaining: TimeInterval, progress p: CGFloat) -> some View {
        Text(timerText(remaining))
            .font(.system(size: 23 + 27 * p, weight: .light))
            .monospacedDigit().foregroundStyle(.orange)
            .lineLimit(1).minimumScaleFactor(0.85)
            .contentTransition(.numericText(countsDown: true))
            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: max(0, Int(ceil(remaining))))
            // Keep rolling digits in local coordinates while their page moves.
            .geometryGroup()
    }

    private func status(progress p: CGFloat) -> some View {
        Text(timer?.phase == .paused ? LocalizedStringKey("Paused") : LocalizedStringKey("Running"))
            .font(.subheadline).foregroundStyle(.secondary)
            .contentTransition(.opacity).opacity(Double(p))
            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: timer?.phase)
    }

    private func cancelControl(progress p: CGFloat, size: CGSize) -> some View {
        IslandActionButton("Reset timer", icon: "xmark") { TimerActivityManager.shared.cancel() }
            .allowsHitTesting(hasTimer).accessibilityHidden(!hasTimer)
            .animation(nil) { view in
                view.opacity(p).position(x: size.width - 78,
                                         y: size.height - 22 + (22 - size.height / 2) * p)
            }
    }

    private var primaryTitle: LocalizedStringKey {
        if !hasTimer { return "Start" }
        return timer?.phase == .paused ? "Resume timer" : "Pause timer"
    }

    private func primaryControl(progress p: CGFloat, size: CGSize) -> some View {
        IslandActionButton(primaryTitle,
                          icon: hasTimer && timer?.phase == .running ? "pause.fill" : "play.fill", tint: .orange) {
            if ActivityCoordinator.shared.timer != nil { TimerActivityManager.shared.togglePause() }
            else { start(duration) }
        }
        .disabled(!hasTimer && duration <= 0)
        .animation(nil) { view in
            view.position(x: size.width - 22,
                          y: size.height - 22 + (22 - size.height / 2) * p)
        }
    }
}

struct TimerDurationForm: View {
    @Binding var duration: TimeInterval

    private func component(_ unit: Int, modulus: Int) -> Binding<Int> {
        Binding(get: { Int(duration) / unit % modulus }, set: { value in
            let old = Int(duration) / unit % modulus
            duration += TimeInterval((value - old) * unit)
        })
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                DurationColumn(value: component(3600, modulus: 24), count: 24, label: "Hours")
                DurationColumn(value: component(60, modulus: 60), count: 60, label: "Minutes")
                DurationColumn(value: component(1, modulus: 60), count: 60, label: "Seconds")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Preserve the original centered picker above the 44-point action and 4-point gap.
        .padding(.bottom, 48)
    }
}

struct DurationColumn: View {
    @Binding var value: Int
    let count: Int
    let label: LocalizedStringKey
    @Namespace private var coordinateSpace
    @State private var initialized = false

    var body: some View {
        HStack(spacing: 5) {
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { number in
                            Text(String(format: "%02d", number)).monospacedDigit()
                                .font(.system(size: 23, weight: .medium))
                                .frame(width: 48, height: 26).id(number)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: DurationRowCenters.self,
                                            value: [number: geometry.frame(in: .named(coordinateSpace)).midY])
                                    }
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.vertical, 26, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .frame(width: 48, height: 78)
                .coordinateSpace(name: coordinateSpace)
                .background { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)).frame(height: 26) }
                .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom))
                .task {
                    reader.scrollTo(value, anchor: .center)
                    // Initial layout is not a user selection and must not tick or overwrite the value.
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                    initialized = true
                }
                .onPreferenceChange(DurationRowCenters.self) { centers in
                    guard initialized, let selected = centers.min(by: { abs($0.value - 39) < abs($1.value - 39) })?.key,
                          selected != value else { return }
                    value = selected
                    IslandHaptics.alignment()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text("\(value)"))
                .accessibilityAdjustableAction { direction in
                    let next = min(count - 1, max(0, value + (direction == .increment ? 1 : -1)))
                    if next != value { value = next; reader.scrollTo(next, anchor: .center); IslandHaptics.alignment() }
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DurationRowCenters: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ReminderCompletionExit: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(1 - progress).offset(y: -3 * progress)
            .frame(height: max(0, 23 * (1 - progress)), alignment: .top)
    }
}

private struct ReminderTaskRow: View {
    let task: ReminderTask
    let complete: () -> Bool
    @State private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: finish) {
            HStack(spacing: 9) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(completed ? Color.white : .blue, Color.blue)
                    .contentTransition(.identity)
                    .animation(nil, value: completed)
                Text(task.title).lineLimit(1).opacity(completed ? 0.45 : 1)
                Spacer(minLength: 0)
            }.frame(height: 23).contentShape(Rectangle())
        }
        .buttonStyle(ReminderRowButtonStyle()).allowsHitTesting(!completed)
        .accessibilityLabel(Text("Complete task: \(task.title)"))
        .transition(reduceMotion ? .opacity : .modifier(active: ReminderCompletionExit(progress: 1), identity: ReminderCompletionExit(progress: 0)))
    }

    private func finish() {
        guard !completed else { return }
        if complete() {
            withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion)) { completed = true }
        }
        IslandHaptics.alignment()
    }
}

private struct ReminderRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1, anchor: .leading)
            .contentShape(Rectangle())
            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct RemindersActivityPage: View {
    var active = true
    @EnvironmentObject private var vm: IslandViewModel
    @ObservedObject private var activities = ActivityCoordinator.shared
    @ObservedObject private var source = RemindersActivityManager.shared
    @Default(.remindersActivityEnabled) private var enabled
    @Default(.reminderListIdentifier) private var listIdentifier
    @State private var adding = false
    @State private var title = ""
    @FocusState private var focused: Bool
    @Namespace private var actionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !source.authorized || !enabled {
                VStack(spacing: 5) {
                    Text("Connect Apple Reminders to sync your tasks.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(source.accessDenied ? LocalizedStringKey("Open Privacy Settings") : LocalizedStringKey("Connect Reminders")) {
                        if source.accessDenied { source.openPrivacySettings() }
                        else { Task { await source.connect() } }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .disabled(source.requesting)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: 8) {
                    Text("Reminders").foregroundStyle(.white.opacity(0.8))
                    Group {
                        if listIdentifier.isEmpty { Text("All tasks") }
                        else { Text(source.lists.first(where: { $0.id == listIdentifier })?.title ?? String(localized: "Selected list unavailable")) }
                    }.foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength: 8)
                    Button { source.openReminders() } label: {
                        Text("\(activities.reminders.count) tasks")
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                            .fixedSize()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: activities.reminders.count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Open Reminders"))
                }.font(.subheadline).lineLimit(1)
                VStack(alignment: .leading, spacing: 5) {
                    if let error = source.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("Retry") { source.refresh() }.buttonStyle(IslandActionButtonStyle())
                    }
                        ScrollView(.vertical) {
                            // Eager layout keeps the last retiring row alive during its transition.
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(activities.reminders) { task in
                                    ReminderTaskRow(task: task) { source.complete(id: task.id) }
                                }
                            }
                            // Keep a drawing surface for the last row's removal transition.
                            .frame(minHeight: 23, alignment: .top)
                            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: activities.reminders.map(\.id))
                            // Keep rows reachable beside the floating add button, including the last row.
                            .padding(.trailing, adding ? 0 : 56)
                        }.scrollIndicators(.hidden)
                        .overlay {
                            if activities.reminders.isEmpty {
                                Text(source.loading ? LocalizedStringKey("Loading reminders…") : LocalizedStringKey("No incomplete tasks"))
                                    .font(.callout).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false).transition(.opacity)
                            }
                        }
                        .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: activities.reminders.map(\.id))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottomTrailing) {
                    if !adding {
                        IslandActionButton("Add reminder", icon: "plus", tint: .blue) { adding = true }
                            .matchedGeometryEffect(id: "reminder-primary", in: actionNamespace)
                            .transition(.identity)
                    }
                }
                if adding {
                    HStack(spacing: 8) {
                        TextField("Task title", text: $title).textFieldStyle(.roundedBorder).focused($focused)
                            .task { focused = true }
                            .onSubmit { add() }
                            .transition(.opacity)
                        IslandActionButton("Add", icon: "checkmark", tint: .blue) { add() }
                            .matchedGeometryEffect(id: "reminder-primary", in: actionNamespace)
                            .transition(.identity)
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        IslandActionButton("Cancel", icon: "xmark") { adding = false }
                            .transition(.opacity)
                    }
                    .transition(.identity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: adding)
        .onChange(of: adding) { _, editing in
            vm.isEditingActivity = editing
            if !editing { focused = false }
        }
        .onChange(of: active) { _, active in if !active { adding = false; focused = false } }
        .onDisappear { vm.isEditingActivity = false }
    }

    private func add() {
        if source.add(title: title) { title = ""; adding = false }
    }
}

func timerText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds)))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}
