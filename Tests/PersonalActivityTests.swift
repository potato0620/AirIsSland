import XCTest

final class PersonalActivityTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 10000)

    func testTimerPauseResumeAndSleepCompletionAreRealDeadlines() throws {
        var timer = try XCTUnwrap(TimerSession(duration: 60, now: start))
        timer.pause(at: start.addingTimeInterval(12))
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(3600)), 48)
        timer.resume(at: start.addingTimeInterval(3600))
        XCTAssertFalse(timer.finishIfDue(at: start.addingTimeInterval(3647)))
        XCTAssertTrue(timer.finishIfDue(at: start.addingTimeInterval(7200)))
        XCTAssertFalse(timer.finishIfDue(at: start.addingTimeInterval(7201)))
        XCTAssertEqual(timer.phase, .finished)
    }

    func testOverduePauseCannotResurrectTimer() throws {
        var timer = try XCTUnwrap(TimerSession(duration: 1, now: start))
        timer.pause(at: start.addingTimeInterval(2))
        timer.resume(at: start.addingTimeInterval(3))
        XCTAssertEqual(timer.phase, .finished)
    }

    func testTimerRoundTripAndValidation() throws {
        XCTAssertNil(TimerSession(duration: 0))
        XCTAssertNil(TimerSession(duration: .infinity))
        XCTAssertNil(TimerSession(duration: 86400))
        let timer = try XCTUnwrap(TimerSession(duration: 90, now: start))
        let restored = try JSONDecoder().decode(TimerSession.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(restored, timer)
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(30)), 60)
    }

    func testFinishedTimerWaitsForAcknowledgementThenRestoresCurrentActivity() throws {
        var timer = try XCTUnwrap(TimerSession(duration: 1, now: start))
        timer.finishIfDue(at: start.addingTimeInterval(2))
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .volume), at: 0)
        scheduler.submit(IslandActivity(kind: .timerFinished, timer: timer), at: 0)
        XCTAssertEqual(scheduler.current(at: 1)?.kind, .timerFinished)
        XCTAssertEqual(scheduler.current(at: 2.999)?.kind, .timerFinished)
        XCTAssertEqual(scheduler.current(at: 3)?.kind, .timerFinished)
        scheduler.expire(at: 3)
        XCTAssertNil(scheduler.nextExpiry)
        XCTAssertEqual(scheduler.current(at: 100000)?.kind, .timerFinished)
        scheduler.end(.timerFinished)
        XCTAssertEqual(scheduler.current(at: 100000)?.kind, .music)
    }

    func testAcknowledgingFinishedTimerWithoutMusicRestoresIdleWithPanelOnlyReminders() throws {
        var timer = try XCTUnwrap(TimerSession(duration: 1, now: start))
        timer.finishIfDue(at: start.addingTimeInterval(2))
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .reminders, reminders: [.init(id: "task", title: "Task", dueDate: nil)]), at: 0)
        scheduler.submit(IslandActivity(kind: .timerFinished, timer: timer), at: 0)
        XCTAssertEqual(scheduler.current(at: 2)?.kind, .timerFinished)
        scheduler.expire(at: 100000)
        XCTAssertEqual(scheduler.current(at: 100000)?.kind, .timerFinished)
        scheduler.end(.timerFinished)
        XCTAssertNil(scheduler.current(at: 100000))
        XCTAssertEqual(scheduler.activity(.reminders, at: 100000)?.reminders.count, 1)
        scheduler.end(.reminders)
        XCTAssertNil(scheduler.current(at: 100000))
    }

    func testReminderWithdrawalDoesNotCancelOtherActivity() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .reminders, reminders: [.init(id: "real-id", title: "Task", dueDate: start)]), at: 0)
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        XCTAssertEqual(scheduler.current(at: 0)?.kind, .music)
        scheduler.end(.reminders)
        XCTAssertNil(scheduler.activity(.reminders, at: 0))
        XCTAssertEqual(scheduler.current(at: 0)?.kind, .music)
    }

    func testLateReminderFetchCannotRestoreRevokedOrOlderData() {
        var generation = ReminderFetchGeneration()
        let old = generation.invalidate()
        let current = generation.invalidate()
        XCTAssertFalse(generation.accepts(old))
        XCTAssertTrue(generation.accepts(current))
        _ = generation.invalidate()
        XCTAssertFalse(generation.accepts(current))
    }

    func testAllListsIncludesUndatedAndFutureIncompleteTasksByDefault() {
        let tasks = [
            ReminderTask(id: "undated", title: "Undated", dueDate: nil, listIdentifier: "personal"),
            ReminderTask(id: "future", title: "Future", dueDate: start.addingTimeInterval(86400), listIdentifier: "work"),
            ReminderTask(id: "overdue", title: "Overdue", dueDate: start.addingTimeInterval(-86400), listIdentifier: "work")
        ]
        XCTAssertEqual(Set(ReminderListSelection().filter(tasks).map(\.id)), Set(["overdue", "future", "undated"]))
    }

    func testNewReminderAppendsAfterExistingTasksRegardlessOfDeadlineOrIdentifier() {
        let older = ReminderTask(id: "z-older", title: "Older", dueDate: start.addingTimeInterval(86400),
                                 listIdentifier: "personal", creationDate: start)
        let newer = ReminderTask(id: "m-newer", title: "Newer", dueDate: nil,
                                 listIdentifier: "work", creationDate: start.addingTimeInterval(1))
        let added = ReminderTask(id: "a-added", title: "Added", dueDate: start.addingTimeInterval(-86400),
                                 listIdentifier: "personal", creationDate: start.addingTimeInterval(2))
        let selection = ReminderListSelection()
        XCTAssertEqual(selection.filter([newer, older]).map(\.id), [older.id, newer.id])
        XCTAssertEqual(selection.filter([added, newer, older]).map(\.id), [older.id, newer.id, added.id])
        XCTAssertEqual(ReminderListSelection(identifier: "personal").filter([added, newer, older]).map(\.id),
                       [older.id, added.id])
    }

    func testReminderOrderSurvivesRefetchAndTitleOrDeadlineEdits() {
        let older = ReminderTask(id: "z-older", title: "Renamed", dueDate: start.addingTimeInterval(86400),
                                 creationDate: start)
        let newer = ReminderTask(id: "a-newer", title: "New", dueDate: start.addingTimeInterval(-86400),
                                 creationDate: start.addingTimeInterval(1))
        let selection = ReminderListSelection()
        XCTAssertEqual(selection.filter([older, newer]), selection.filter([newer, older]))
        XCTAssertEqual(selection.filter([newer, older]).map(\.id), [older.id, newer.id])
        XCTAssertEqual(selection.filter([newer]).map(\.id), [newer.id])
    }

    func testLegacyMissingCreationDatesAndEqualDatesHaveStableOrder() {
        let legacy = ReminderTask(id: "z-legacy", title: "Legacy", dueDate: nil)
        let first = ReminderTask(id: "a", title: "First", dueDate: nil, creationDate: start)
        let second = ReminderTask(id: "b", title: "Second", dueDate: nil, creationDate: start)
        let added = ReminderTask(id: "0-new", title: "Added", dueDate: nil, creationDate: start.addingTimeInterval(1))
        let selection = ReminderListSelection()
        XCTAssertEqual(selection.filter([added, second, legacy, first]).map(\.id), [legacy.id, first.id, second.id, added.id])
        XCTAssertEqual(selection.filter([first, legacy, second, added]).map(\.id), [legacy.id, first.id, second.id, added.id])
    }

    func testSelectedListDoesNotIncludeOtherListsWithTheSameTitle() {
        let tasks = [
            ReminderTask(id: "work-task", title: "Same title", dueDate: nil, listIdentifier: "work"),
            ReminderTask(id: "personal-task", title: "Same title", dueDate: nil, listIdentifier: "personal")
        ]
        XCTAssertEqual(ReminderListSelection(identifier: "work").filter(tasks).map(\.id), ["work-task"])
    }

    func testNewTasksUseSelectedListOrSystemDefaultForAllLists() {
        let lists = [
            ReminderList(id: "work", title: "Tasks", account: "Work", writable: true),
            ReminderList(id: "personal", title: "Tasks", account: "Personal", writable: true)
        ]
        XCTAssertEqual(ReminderListSelection().destination(in: lists, defaultIdentifier: "personal")?.id, "personal")
        XCTAssertEqual(ReminderListSelection(identifier: "work").destination(in: lists, defaultIdentifier: "personal")?.id, "work")
        XCTAssertNil(ReminderListSelection().destination(in: lists, defaultIdentifier: nil))
    }

    func testDeletedOrReadOnlySelectionNeverWritesIntoAnotherList() {
        let lists = [
            ReminderList(id: "readonly", title: "Shared", account: "", writable: false),
            ReminderList(id: "personal", title: "Tasks", account: "", writable: true)
        ]
        XCTAssertNil(ReminderListSelection(identifier: "deleted").destination(in: lists, defaultIdentifier: "personal"))
        let readOnly = ReminderListSelection(identifier: "readonly")
        XCTAssertNil(readOnly.destination(in: lists, defaultIdentifier: "personal"))
        let task = ReminderTask(id: "shared-task", title: "Shared task", dueDate: nil, listIdentifier: "readonly")
        XCTAssertEqual(readOnly.filter([task]), [task])
    }

    func testSwitchingListsInvalidatesPreviousFetchAndMembership() {
        var generation = ReminderFetchGeneration()
        let oldSelection = ReminderListSelection(identifier: "work")
        let oldFetch = generation.invalidate()
        let newSelection = ReminderListSelection(identifier: "personal")
        let newFetch = generation.invalidate()
        XCTAssertNotEqual(oldSelection, newSelection)
        XCTAssertFalse(generation.accepts(oldFetch))
        XCTAssertTrue(generation.accepts(newFetch))
        XCTAssertFalse(newSelection.includes(listIdentifier: "work"))
        XCTAssertTrue(newSelection.includes(listIdentifier: "personal"))
    }

    func testPagerResistsBeforeThresholdAndReturnsWithoutFling() {
        var pager = IslandPager()
        pager.begin()
        XCTAssertNil(pager.drag(delta: 0.08, seconds: 0.008))
        XCTAssertEqual(pager.selection, .music)
        XCTAssertGreaterThan(pager.position, 0)
        pager.end()
        XCTAssertEqual(pager.position, 0)
    }

    func testPagerCommitsOnceBeforeReleaseAndCannotOvershoot() {
        var pager = IslandPager()
        pager.begin()
        XCTAssertEqual(pager.drag(delta: 0.4, seconds: 0.02), .reminders)
        for delta in [0.5, 10, -20, 30] {
            XCTAssertNil(pager.drag(delta: delta, seconds: 0.01))
            XCTAssertEqual(pager.position, 1)
        }
        pager.end()
        XCTAssertEqual(pager.selection, .reminders)
        pager.begin()
        XCTAssertEqual(pager.drag(delta: 0.4, seconds: 0.02), .timer)
        pager.end()
        pager.begin()
        XCTAssertNil(pager.drag(delta: 10, seconds: 0.02))
        pager.end()
        XCTAssertEqual(pager.position, 2)
    }

    func testSlowDragHasMoreResistanceThanFastDrag() {
        var slow = IslandPager(), fast = IslandPager()
        slow.begin(); fast.begin()
        _ = slow.drag(delta: 0.08, seconds: 0.4)
        _ = fast.drag(delta: 0.08, seconds: 0.008)
        XCTAssertGreaterThan(fast.position, slow.position)
    }

    func testPagerSkipsDisabledMiddlePage() {
        var pager = IslandPager()
        pager.updatePages([.music, .timer])
        pager.begin()
        XCTAssertEqual(pager.drag(delta: 0.4, seconds: 0.02), .timer)
        XCTAssertEqual(pager.position, 1)
        pager.end()
        pager.begin()
        XCTAssertEqual(pager.drag(delta: -0.4, seconds: 0.02), .music)
        XCTAssertEqual(pager.position, 0)
        pager.select(.reminders)
        XCTAssertEqual(pager.selection, .music)
    }

    func testPagerKeepsSelectionWhenEarlierPageIsRemoved() {
        var pager = IslandPager()
        pager.select(.timer)
        pager.updatePages([.music, .timer])
        XCTAssertEqual(pager.selection, .timer)
        XCTAssertEqual(pager.position, 1)
        pager.updatePages(IslandPage.allCases)
        XCTAssertEqual(pager.selection, .timer)
        XCTAssertEqual(pager.position, 2)
    }

    func testRemovingSelectedPageCancelsDragAndFallsBackToMusic() {
        var pager = IslandPager()
        pager.select(.reminders)
        pager.begin()
        XCTAssertNil(pager.drag(delta: 0.08, seconds: 0.1))
        pager.updatePages([.music, .timer])
        XCTAssertEqual(pager.selection, .music)
        XCTAssertEqual(pager.position, 0)
        XCTAssertNil(pager.drag(delta: 10, seconds: 0.01))
        pager.end()
        XCTAssertEqual(pager.position, 0)
    }

    func testSinglePageDoesNotMoveOrRespondToSwipes() {
        var pager = IslandPager()
        pager.updatePages([.music])
        for delta in [-10.0, 10.0] {
            pager.begin()
            XCTAssertNil(pager.drag(delta: delta, seconds: 0.01))
            pager.end()
            XCTAssertEqual(pager.position, 0)
            XCTAssertEqual(pager.selection, .music)
        }
        pager.updatePages([])
        XCTAssertEqual(pager.pages, [.music])
    }
}
