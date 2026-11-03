import AppKit
import Combine
import Defaults
import EventKit
import Foundation

/// Activity source. EventKit owns the data; the island never maintains a second todo database.
@MainActor
final class RemindersActivityManager: ObservableObject {
    static let shared = RemindersActivityManager()
    @Published private(set) var authorized = false
    @Published private(set) var requesting = false
    @Published private(set) var accessDenied = false
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lists: [ReminderList] = []
    private lazy var store = EKEventStore()
    private var fetchRequest: Any?
    private var generation = ReminderFetchGeneration()
    private var loadedSelection = ReminderListSelection()
    private var observers = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.remindersActivityEnabled).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &observers)
        Defaults.publisher(.reminderListIdentifier).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
            .store(in: &observers)
        refresh()
    }

    func connect() async {
        guard !requesting else { return }
        requesting = true
        errorMessage = nil
        defer { requesting = false }
        Defaults[.remindersActivityEnabled] = true
        do { _ = try await store.requestFullAccessToReminders() }
        catch { errorMessage = error.localizedDescription }
        refresh()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        let selection = currentSelection
        if selection != loadedSelection {
            ActivityCoordinator.shared.setReminders([])
            loadedSelection = selection
        }
        let token = generation.invalidate()
        if let fetchRequest { store.cancelFetchRequest(fetchRequest) }
        fetchRequest = nil
        authorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        accessDenied = [.denied, .restricted].contains(EKEventStore.authorizationStatus(for: .reminder))
        guard authorized && Defaults[.remindersActivityEnabled] else {
            loading = false
            lists = []
            ActivityCoordinator.shared.setReminders([])
            return
        }
        let calendars = store.calendars(for: .reminder)
        lists = listDescriptions(calendars)
        let selectedCalendars = calendars.filter { selection.includes(listIdentifier: $0.calendarIdentifier) }
        guard !selectedCalendars.isEmpty else {
            loading = false
            errorMessage = selection.identifier.isEmpty ? String(localized: "No reminders lists are available.") : String(localized: "The selected list is unavailable. Choose another list in settings.")
            ActivityCoordinator.shared.setReminders([])
            return
        }
        loading = true
        errorMessage = nil
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: selectedCalendars)
        fetchRequest = store.fetchReminders(matching: predicate) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation.accepts(token) else { return }
                guard self.currentSelection == selection else { self.refresh(); return }
                guard Defaults[.remindersActivityEnabled], EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                    self.refresh()
                    return
                }
                self.fetchRequest = nil
                self.loading = false
                guard let result else {
                    self.errorMessage = String(localized: "Unable to load reminders.")
                    ActivityCoordinator.shared.setReminders([])
                    return
                }
                self.errorMessage = nil
                let tasks = result.filter { !$0.isCompleted }.map { reminder in
                    ReminderTask(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                 dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                                 listIdentifier: reminder.calendar?.calendarIdentifier ?? "",
                                 creationDate: reminder.creationDate)
                }
                ActivityCoordinator.shared.setReminders(selection.filter(tasks))
            }
        }
    }

    @discardableResult func add(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, canWrite else { return false }
        let selection = currentSelection
        let calendars = store.calendars(for: .reminder)
        let descriptions = listDescriptions(calendars)
        let destination = selection.destination(in: descriptions, defaultIdentifier: store.defaultCalendarForNewReminders()?.calendarIdentifier)
        guard let destination, let calendar = calendars.first(where: { $0.calendarIdentifier == destination.id }) else {
            if selection.identifier.isEmpty { errorMessage = String(localized: "No writable reminders list is available.") }
            else if descriptions.contains(where: { $0.id == selection.identifier }) { errorMessage = String(localized: "This reminders list is read-only.") }
            else { errorMessage = String(localized: "The selected list is unavailable. Choose another list in settings.") }
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        return save(reminder)
    }

    func complete(id: String) {
        guard canWrite else { return }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { refresh(); return }
        guard currentSelection.includes(listIdentifier: reminder.calendar?.calendarIdentifier ?? "") else { refresh(); return }
        guard reminder.calendar.allowsContentModifications else {
            errorMessage = String(localized: "This reminders list is read-only.")
            return
        }
        reminder.isCompleted = true
        _ = save(reminder)
    }

    private var canWrite: Bool {
        guard Defaults[.remindersActivityEnabled], EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            refresh()
            return false
        }
        return true
    }

    private var currentSelection: ReminderListSelection {
        ReminderListSelection(identifier: Defaults[.reminderListIdentifier])
    }

    private func listDescriptions(_ calendars: [EKCalendar]) -> [ReminderList] {
        calendars.map { ReminderList(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "", writable: $0.allowsContentModifications) }
            .sorted { $0.displayTitle == $1.displayTitle ? $0.id < $1.id : $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    private func save(_ reminder: EKReminder) -> Bool {
        do { try store.save(reminder, commit: true); refresh(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
