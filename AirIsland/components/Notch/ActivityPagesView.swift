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
    let scalesIcon: Bool
    let action: () -> Void

    init(_ title: LocalizedStringKey, icon: String, tint: Color? = nil, scalesIcon: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.scalesIcon = scalesIcon
        self.action = action
    }

    var body: some View {
        Button { action(); IslandHaptics.alignment() } label: {
            ZStack {
                if scalesIcon {
                    Image(systemName: icon)
                        .id(icon)
                        .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                } else {
                    Image(systemName: icon)
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
            }
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

struct TimerActivityPage: View, Equatable {
    var active = true
    /// Supplied by the island's rendered geometry; standalone pages have no collapse.
    var expansion: CGFloat? = nil
    // Paging translation does not change this page's inputs. Observed source,
    // environment and local interaction state still invalidate it independently.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.active == rhs.active && lhs.expansion == rhs.expansion
    }
    @ObservedObject private var activities = ActivityCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDuration: TimeInterval = 1500
    @State private var pickerID = UUID()
    @State private var lastTimer: TimerSession?
    @State private var runProgress: CGFloat = ActivityCoordinator.shared.timer == nil ? 0 : 1
    @State private var transitionID = UUID()
    @State private var retiringFinished: TimerSession?

    var body: some View {
        Group {
            if let timer = retiringFinished ?? activities.timer, timer.phase == .finished {
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        TimerFinishedIcon(isActive: active || retiringFinished != nil)
                        Text("Timer finished").font(.system(size: 28, weight: .light))
                    }.foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        IslandActionButton("Restart timer", icon: "arrow.clockwise", tint: .orange) { dismissFinished(timer, restart: true) }
                        IslandActionButton("Close", icon: "xmark") { dismissFinished(timer, restart: false) }
                    }
                }
                .allowsHitTesting(retiringFinished == nil)
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
            guard retiringFinished == nil else { return }
            // A confirmation in another island window updates this same source.
            // Keep this window's finished page through its own collapse as well.
            if expansion != nil, let previous, previous.phase == .finished,
               next?.phase != .finished {
                retiringFinished = previous
                return
            }
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
        .onChange(of: expansion) { _, progress in
            if let progress, progress <= 0.02 { finishRetirement() }
        }
        .onChange(of: active) { _, active in
            // Reopening during a collapse must show the new real state.
            if active { finishRetirement() }
        }
        .onDisappear { finishRetirement() }
    }

    private func dismissFinished(_ timer: TimerSession, restart: Bool) {
        guard activities.timer?.id == timer.id, activities.timer?.phase == .finished else { return }
        if expansion != nil { retiringFinished = timer }
        if restart { startTimer(timer.duration) }
        else { TimerActivityManager.shared.cancel() }
    }

    private func finishRetirement() {
        guard retiringFinished != nil else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionID = UUID()
            retiringFinished = nil
            lastTimer = activities.timer
            selectedDuration = 1500
            pickerID = UUID()
            runProgress = activities.timer == nil ? 0 : 1
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

// A borderless native field keeps the label's font and origin. Its own editor
// owns the draft; Return submits, Escape cancels, and blur never writes a task.
private final class ReminderEditSession {
    let id = UUID()
    weak var field: ReminderTitleEditor.TextField?

    func end() {
        field?.mayEdit = { false }
        field?.releaseEditor()
    }
}

private struct ReminderTitleEditor: NSViewRepresentable {
    let task: ReminderTask
    let session: ReminderEditSession
    let isCurrentEdit: () -> Bool
    let save: (String) -> Bool
    let cancel: () -> Void

    final class TextField: NSTextField {
        var mayEdit: () -> Bool = { false }
        weak var editingWindow: NSWindow?
        weak var editingFieldEditor: NSTextView?

        func releaseEditor() {
            let window = window ?? editingWindow
            let editor = currentEditor() as? NSTextView ?? editingFieldEditor
            DispatchQueue.main.async { [weak window, weak editor] in
                guard let window, let editor, window.firstResponder === editor,
                      (editor.delegate as? NSTextField) === self else { return }
                // AppKit shares one field editor. Never release a newly selected row.
                window.makeFirstResponder(nil)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let firstAttachment = editingWindow == nil
            editingWindow = window
            requestFocus(activateWindow: firstAttachment)
        }

        func requestFocus(activateWindow: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mayEdit(), let window = self.window, window.isVisible,
                      activateWindow || window.isKeyWindow else { return }
                if activateWindow && !window.isKeyWindow { window.makeKey() }
                window.makeFirstResponder(self)
                if let editor = self.currentEditor() as? NSTextView {
                    self.editingFieldEditor = editor
                    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                }
                if self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
                    NSCursor.iBeam.set()
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let session: ReminderEditSession
        var active = true
        var mayEdit: () -> Bool
        var save: (String) -> Bool
        var cancel: () -> Void

        init(_ view: ReminderTitleEditor) {
            session = view.session
            mayEdit = view.isCurrentEdit
            save = view.save
            cancel = view.cancel
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard active, mayEdit() else { return false }
            if command == #selector(NSResponder.insertNewline(_:)) {
                if !save(textView.string) { session.field?.requestFocus(activateWindow: true) }
                return true
            }
            if command == #selector(NSResponder.cancelOperation(_:)) {
                cancel()
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TextField {
        let field = TextField(frame: .zero)
        field.stringValue = task.title
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .labelColor
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        session.field = field
        field.mayEdit = { [weak coordinator = context.coordinator] in
            coordinator?.active == true && coordinator?.mayEdit() == true
        }
        return field
    }

    func updateNSView(_ field: TextField, context: Context) {
        context.coordinator.mayEdit = isCurrentEdit
        context.coordinator.save = save
        context.coordinator.cancel = cancel
        // Preserve native uncommitted text through source refreshes and failed saves.
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    static func dismantleNSView(_ field: TextField, coordinator: Coordinator) {
        coordinator.active = false
        field.delegate = nil
        field.releaseEditor()
    }
}

private struct ReminderTaskRow: View {
    let task: ReminderTask
    let isEditing: Bool
    let isCurrentEdit: () -> Bool
    let editingSession: ReminderEditSession
    let edit: () -> Void
    let save: (String) -> Bool
    let cancel: () -> Void
    let complete: () -> Bool
    @State private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            Button(action: finish) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(completed ? Color.white : .blue, Color.blue)
                    .contentTransition(.identity)
                    .animation(nil, value: completed)
                    .frame(width: 18, height: 23).contentShape(Rectangle())
            }
            .buttonStyle(ReminderRowButtonStyle())
            .accessibilityLabel(Text("Complete task: \(task.title)"))
            ZStack(alignment: .leading) {
                if isEditing && !completed {
                    ReminderTitleEditor(task: task, session: editingSession, isCurrentEdit: isCurrentEdit, save: save, cancel: cancel)
                        .id(editingSession.id)
                        .transition(.identity)
                } else {
                    Button(action: edit) {
                        Text(task.title).font(.body).lineLimit(1).opacity(completed ? 0.45 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Edit task: \(task.title)"))
                    .transition(.identity)
                }
            }
        }
        .frame(height: 23).allowsHitTesting(!completed)
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

// One persistent primary control moves between plus and check in both directions.
// The auxiliary cross only fades; the same progress drives the entire transition.
private struct ReminderCreationControls: View, Animatable {
    var progress: CGFloat
    let adding: Bool
    let empty: Bool
    let begin: () -> Void
    let save: () -> Void
    let cancel: () -> Void

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let separation = 52 * min(1, max(0, progress))
        // Reveal only after the 44-point circles have two points of clearance.
        let crossOpacity = min(1, max(0, (separation - 46) / 6))
        ZStack(alignment: .trailing) {
            IslandActionButton("Cancel", icon: "xmark", action: cancel)
                .animation(nil) { view in view.opacity(crossOpacity) }
                .allowsHitTesting(adding)
                .accessibilityHidden(!adding)
            IslandActionButton(adding ? "Add" : "Add reminder",
                               icon: adding ? "checkmark" : "plus", tint: .blue, scalesIcon: true) {
                    if adding { save() } else { begin() }
                }
                .animation(nil) { view in view.offset(x: -separation) }
                .disabled(adding && empty)
        }
        .frame(width: 96, height: 44, alignment: .trailing)
    }
}

struct RemindersActivityPage: View, Equatable {
    var active = true
    // Only the explicit parent input participates. Local state, Defaults and
    // observed sources still invalidate this view through their own dependencies.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.active == rhs.active }
    @EnvironmentObject private var vm: IslandViewModel
    @ObservedObject private var activities = ActivityCoordinator.shared
    @ObservedObject private var source = RemindersActivityManager.shared
    @Default(.remindersActivityEnabled) private var enabled
    @Default(.reminderListIdentifier) private var listIdentifier
    @State private var adding = false
    @State private var creationTransition = UUID()
    @State private var title = ""
    @State private var editingID: String?
    @State private var originalTitle = ""
    @State private var editingSession = ReminderEditSession()
    @State private var countHovered = false
    @FocusState private var focused: UUID?
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
                            .foregroundStyle(Color.blue.opacity(countHovered ? 0.82 : 1))
                            .monospacedDigit()
                            .fixedSize()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: activities.reminders.count)
                    }
                    .buttonStyle(.plain)
                    .onHover { countHovered = $0 }
                    .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: countHovered)
                    .accessibilityHint(Text("Open Reminders"))
                }.font(.subheadline).lineLimit(1)
                VStack(alignment: .leading, spacing: 5) {
                    if let error = source.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("Retry") { source.refresh() }.buttonStyle(IslandActionButtonStyle())
                    }
                        ScrollView(.vertical) {
                            // Eager layout keeps the last retiring row alive during its transition.
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(activities.reminders) { task in
                                    ReminderTaskRow(task: task, isEditing: editingID == task.id,
                                        isCurrentEdit: { [session = editingSession.id] in
                                            editingID == task.id && editingSession.id == session && active && vm.isEditingActivity
                                        },
                                        editingSession: editingSession,
                                        edit: { edit(task) },
                                        save: { [session = editingSession.id] title in saveEdit(id: task.id, session: session, title: title) },
                                        cancel: { [session = editingSession.id] in
                                            if editingID == task.id && editingSession.id == session { cancelEdit() }
                                        }) {
                                            let saved = source.complete(id: task.id)
                                            if saved && editingID == task.id { cancelEdit() }
                                            return saved
                                        }
                                }
                            }
                            // Keep a drawing surface for the last row's removal transition.
                            .frame(minHeight: 23, alignment: .top)
                            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: activities.reminders.map(\.id))
                            // Keep rows reachable beside the floating add button, including the last row.
                            .padding(.trailing, adding ? 0 : 56)
                            .padding(.vertical, 2)
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
                .padding(.bottom, adding ? 49 : 0)
                .overlay(alignment: .bottomTrailing) {
                    ZStack(alignment: .trailing) {
                        if adding {
                            let inputSession = creationTransition
                            TextField("Task title", text: $title).textFieldStyle(.roundedBorder).focused($focused, equals: inputSession)
                                .task {
                                    await Task.yield()
                                    guard !Task.isCancelled else { return }
                                    focused = inputSession
                                }
                                .id(inputSession)
                                .onSubmit { add() }
                                .onExitCommand { finishAdding() }
                                .padding(.trailing, 104)
                                .transition(.opacity)
                        }
                        ReminderCreationControls(progress: adding ? 1 : 0, adding: adding,
                            empty: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            begin: beginAdding, save: add, cancel: finishAdding)
                    }
                    .frame(height: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: adding)
        .onChange(of: adding || editingID != nil) { _, editing in
            vm.isEditingActivity = editing
            if !editing { focused = nil }
        }
        .onChange(of: vm.isEditingActivity) { _, editing in
            if !editing && (adding || editingID != nil) { cancelEditing() }
        }
        .onChange(of: active) { _, active in if !active { cancelEditing() } }
        .onChange(of: enabled) { _, enabled in if !enabled { cancelEditing() } }
        .onChange(of: listIdentifier) { _, _ in cancelEditing() }
        .onChange(of: source.authorized) { _, authorized in if !authorized { cancelEditing() } }
        .onChange(of: activities.reminders.map(\.id)) { _, ids in
            if let editingID, !ids.contains(editingID) { cancelEdit() }
        }
        .onDisappear { cancelEditing(); vm.isEditingActivity = false }
    }

    private func edit(_ task: ReminderTask) {
        guard active, let task = activities.reminders.first(where: { $0.id == task.id }) else { return }
        vm.isEditingActivity = true
        creationTransition = UUID()
        adding = false
        focused = nil
        originalTitle = task.title
        editingSession.end()
        editingSession = ReminderEditSession()
        editingID = task.id
    }

    private func saveEdit(id: String, session: UUID, title: String) -> Bool {
        guard editingID == id, editingSession.id == session else { return false }
        guard source.updateTitle(id: id, originalTitle: originalTitle, title: title) else { return false }
        cancelEdit()
        return true
    }

    private func cancelEdit() {
        editingSession.end()
        editingID = nil
        originalTitle = ""
        vm.isEditingActivity = adding
    }

    private func beginAdding() {
        guard active, !adding else { return }
        cancelEdit()
        creationTransition = UUID()
        vm.isEditingActivity = true
        adding = true
    }

    private func finishAdding() {
        guard adding else { return }
        let transition = UUID()
        creationTransition = transition
        withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion), completionCriteria: .removed) {
            adding = false
            focused = nil
        } completion: {
            guard creationTransition == transition, !adding else { return }
            // A reversed/reopened animation must not clear the new input.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                title = ""
            }
        }
    }

    private func cancelEditing() {
        creationTransition = UUID()
        adding = false
        title = ""
        focused = nil
        countHovered = false
        cancelEdit()
    }

    private func add() {
        guard adding else { return }
        if source.add(title: title) { finishAdding() }
    }
}

func timerText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds)))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}
