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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iconOnly ? 18 : 13, weight: .medium))
            .padding(.horizontal, iconOnly ? 0 : 14)
            .frame(width: iconOnly ? 44 : nil, height: 44)
            .foregroundStyle(tint ?? .white)
            .background((tint ?? .white).opacity(tint == nil ? 0.12 : 0.18), in: Capsule())
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.65 : 1)
    }
}

struct IslandActionButton: View {
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
        Button { action(); IslandHaptics.alignment() } label: { Image(systemName: icon) }
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
    @Default(.timerActivityEnabled) private var enabled

    var body: some View {
        Group {
            if !enabled {
                Button("Enable timer") { enabled = true }
                    .buttonStyle(IslandActionButtonStyle(tint: .orange))
            } else if let timer = activities.timer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            if timer.phase != .finished {
                                Text("Timer").font(.subheadline).foregroundStyle(.secondary)
                            }
                            if timer.phase == .finished {
                                HStack(spacing: 10) {
                                    TimerFinishedIcon(isActive: active)
                                    Text("Timer finished").font(.system(size: 28, weight: .light))
                                }.foregroundStyle(.orange)
                            } else {
                                Text(timerText(timer.remaining(at: context.date)))
                                    .font(.system(size: 50, weight: .light))
                                    .monospacedDigit().foregroundStyle(.orange)
                            }
                            if timer.phase != .finished {
                                Text(timer.phase == .running ? LocalizedStringKey("Running") : LocalizedStringKey("Paused"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if timer.phase == .finished {
                            HStack(spacing: 12) {
                                IslandActionButton("Restart timer", icon: "arrow.clockwise", tint: .orange) { startTimer(timer.duration) }
                                IslandActionButton("Close", icon: "xmark") { TimerActivityManager.shared.cancel() }
                            }
                        } else {
                            HStack(spacing: 12) {
                                IslandActionButton("Reset timer", icon: "xmark") { TimerActivityManager.shared.cancel() }
                                IslandActionButton(timer.phase == .running ? "Pause timer" : "Resume timer",
                                                   icon: timer.phase == .running ? "pause.fill" : "play.fill", tint: .orange) {
                                    TimerActivityManager.shared.togglePause()
                                }
                            }
                        }
                    }
                }
            } else {
                TimerDurationForm(start: startTimer)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startTimer(_ duration: TimeInterval) {
        TimerActivityManager.shared.start(duration: duration)
        activities.prefer(.timer)
    }
}

struct TimerDurationForm: View {
    let start: (TimeInterval) -> Void
    @State private var hours = 0
    @State private var minutes = 25
    @State private var seconds = 0

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                DurationColumn(value: $hours, count: 24, label: "Hours")
                DurationColumn(value: $minutes, count: 60, label: "Minutes")
                DurationColumn(value: $seconds, count: 60, label: "Seconds")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Preserve the original centered picker above the 44-point action and 4-point gap.
        .padding(.bottom, 48)
        .overlay(alignment: .bottomTrailing) {
            IslandActionButton("Start", icon: "play.fill", tint: .orange) { start(TimeInterval(hours * 3600 + minutes * 60 + seconds)) }
                .disabled(hours + minutes + seconds == 0)
        }
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
                }.font(.subheadline).lineLimit(1)
                VStack(alignment: .leading, spacing: 5) {
                    if let error = source.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("Retry") { source.refresh() }.buttonStyle(IslandActionButtonStyle())
                    } else if activities.reminders.isEmpty {
                        Text(source.loading ? LocalizedStringKey("Loading reminders…") : LocalizedStringKey("No incomplete tasks"))
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 5) {
                                ForEach(activities.reminders) { task in
                                    Button { source.complete(id: task.id); IslandHaptics.alignment() } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: "circle").foregroundStyle(.blue)
                                            Text(task.title).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }.frame(minHeight: 23).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("Complete task: \(task.title)"))
                                }
                            }
                            // Keep rows reachable beside the floating add button, including the last row.
                            .padding(.trailing, adding ? 0 : 56)
                        }.scrollIndicators(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottomTrailing) {
                    if !adding {
                        IslandActionButton("Add reminder", icon: "plus", tint: .blue) { adding = true }
                    }
                }
                if adding {
                    HStack(spacing: 8) {
                        TextField("Task title", text: $title).textFieldStyle(.roundedBorder).focused($focused)
                            .task { focused = true }
                            .onSubmit { add() }
                        IslandActionButton("Add", icon: "checkmark", tint: .blue) { add() }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        IslandActionButton("Cancel", icon: "xmark") { adding = false }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
