import XCTest

final class ActivitySchedulerTests: XCTestCase {
    func testIdleHasNoContentOrTimer() {
        let scheduler = ActivityScheduler()
        XCTAssertNil(scheduler.current(at: 0))
        XCTAssertNil(scheduler.nextExpiry)
        XCTAssertEqual(IslandPresentation(activity: nil), .idle)
    }

    func testMusicPersistsUntilExplicitlyEnded() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        XCTAssertEqual(scheduler.current(at: 10000)?.kind, .music)
        XCTAssertNil(scheduler.nextExpiry)
        scheduler.end(.music)
        XCTAssertNil(scheduler.current(at: 10000))
    }

    func testVolumeTemporarilyPreemptsMusicThenRestoresIt() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .volume, value: 0.7), at: 1)
        XCTAssertEqual(scheduler.current(at: 1)?.value, 0.7)
        XCTAssertEqual(scheduler.current(at: 2.499)?.kind, .volume)
        XCTAssertEqual(scheduler.current(at: 2.5)?.kind, .music)
    }

    func testRepeatedKeyPressCoalescesAndExtendsDeadline() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .volume, value: 0.2), at: 0)
        scheduler.submit(IslandActivity(kind: .volume, value: 0.8), at: 1)
        XCTAssertEqual(scheduler.nextExpiry, 2.5)
        XCTAssertEqual(scheduler.current(at: 2)?.value, 0.8)
        XCTAssertNil(scheduler.current(at: 2.5))
    }

    func testLatestSystemControlReplacesPreviousControlWithoutReplay() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .volume), at: 0)
        scheduler.submit(IslandActivity(kind: .brightness), at: 0.1)
        XCTAssertEqual(scheduler.current(at: 0.1)?.kind, .brightness)
        scheduler.end(.brightness)
        XCTAssertNil(scheduler.current(at: 0.2))
    }

    func testSongChangeAndUserFeedbackPreemptPowerWithLatestUpdateWinningTies() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .musicChange), at: 0)
        scheduler.submit(IslandActivity(kind: .power), at: 0.1)
        XCTAssertEqual(scheduler.current(at: 0.2)?.kind, .musicChange)
        scheduler.submit(IslandActivity(kind: .backlight), at: 0.2)
        XCTAssertEqual(scheduler.current(at: 0.3)?.kind, .backlight)
        scheduler.submit(IslandActivity(kind: .musicChange), at: 0.4)
        XCTAssertEqual(scheduler.current(at: 0.4)?.kind, .musicChange)
        XCTAssertEqual(scheduler.current(at: 1.7)?.kind, .musicChange)
        XCTAssertNil(scheduler.current(at: 3.4))
    }

    func testDefaultResidentPriorityIsUnchangedUntilManualSelection() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .reminders), at: 0)
        scheduler.submit(IslandActivity(kind: .music), at: 1)
        scheduler.submit(IslandActivity(kind: .timer), at: 2)
        XCTAssertEqual(scheduler.current(at: 2)?.kind, .timer)
        scheduler.prefer(.music, at: 2)
        XCTAssertEqual(scheduler.current(at: 2)?.kind, .music)
        scheduler.submit(IslandActivity(kind: .timer), at: 3)
        scheduler.submit(IslandActivity(kind: .reminders), at: 4)
        XCTAssertEqual(scheduler.current(at: 4)?.kind, .music)
        scheduler.prefer(.timer, at: 4)
        XCTAssertEqual(scheduler.current(at: 4)?.kind, .timer)
        scheduler.prefer(.reminders, at: 4)
        XCTAssertEqual(scheduler.current(at: 4)?.kind, .reminders)
    }

    func testEveryTransientPreemptsManualResidentThenRestoresIt() {
        for kind in [IslandActivityKind.musicChange, .volume, .brightness, .backlight, .mic, .power] {
            var scheduler = ActivityScheduler()
            scheduler.submit(IslandActivity(kind: .timer), at: 0)
            scheduler.submit(IslandActivity(kind: .music), at: 0)
            scheduler.prefer(.music, at: 0)
            scheduler.submit(IslandActivity(kind: kind), at: 1)
            XCTAssertEqual(scheduler.current(at: 1)?.kind, kind)
            scheduler.expire(at: 4)
            XCTAssertEqual(scheduler.current(at: 4)?.kind, .music)
        }
    }

    func testSongPeekRestoresSelectedTimerAndKeepsItsOriginalDeadline() {
        var scheduler = ActivityScheduler()
        let timer = TimerSession(duration: 1500, now: Date(timeIntervalSince1970: 0))!
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .timer, timer: timer), at: 0)
        scheduler.prefer(.timer, at: 0)
        scheduler.submit(IslandActivity(kind: .musicChange), at: 1)
        XCTAssertEqual(IslandPresentation(activity: scheduler.current(at: 1)), .music(peek: true))
        scheduler.prefer(.music, at: 2)
        scheduler.prefer(.timer, at: 3)
        XCTAssertEqual(scheduler.nextExpiry, 4)
        XCTAssertEqual(scheduler.current(at: 3.999)?.kind, .musicChange)
        XCTAssertEqual(scheduler.current(at: 4)?.timer?.deadline, timer.deadline)
        XCTAssertEqual(scheduler.current(at: 4)?.kind, .timer)
    }

    func testEmptyOrTransientPageCannotReplaceResidentPreference() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .timer), at: 0)
        scheduler.prefer(.music, at: 0)
        scheduler.prefer(.reminders, at: 1)
        XCTAssertEqual(scheduler.current(at: 1)?.kind, .music)
        scheduler.submit(IslandActivity(kind: .volume), at: 1)
        scheduler.prefer(.volume, at: 1)
        scheduler.expire(at: 3)
        XCTAssertEqual(scheduler.current(at: 3)?.kind, .music)
    }

    func testEndingSelectedActivityClearsPreferenceWithoutRevivingItLater() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .timer), at: 0)
        scheduler.prefer(.music, at: 0)
        scheduler.end(.music)
        XCTAssertEqual(scheduler.current(at: 1)?.kind, .timer)
        scheduler.submit(IslandActivity(kind: .music), at: 2)
        XCTAssertEqual(scheduler.current(at: 2)?.kind, .timer)
        scheduler.end(.timer)
        scheduler.end(.music)
        XCTAssertNil(scheduler.current(at: 3))
    }

    func testResidentUpdatesUseLatestPayloadAndEndingDuringPeekFallsBack() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .reminders), at: 0)
        scheduler.submit(IslandActivity(kind: .timer), at: 0)
        scheduler.prefer(.reminders, at: 0)
        let tasks = [ReminderTask(id: "task", title: "Updated", dueDate: nil)]
        scheduler.submit(IslandActivity(kind: .reminders, reminders: tasks), at: 1)
        XCTAssertEqual(scheduler.current(at: 1)?.reminders, tasks)
        scheduler.submit(IslandActivity(kind: .musicChange), at: 2)
        scheduler.end(.reminders)
        XCTAssertEqual(scheduler.current(at: 2)?.kind, .musicChange)
        scheduler.expire(at: 5)
        XCTAssertEqual(scheduler.current(at: 5)?.kind, .timer)
    }

    func testTimerCompletionOverridesSelectionAndTransientsUntilAcknowledged() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .timer), at: 0)
        scheduler.prefer(.music, at: 0)
        scheduler.end(.timer)
        scheduler.submit(IslandActivity(kind: .timerFinished), at: 1)
        scheduler.submit(IslandActivity(kind: .musicChange), at: 2)
        scheduler.submit(IslandActivity(kind: .volume), at: 3)
        scheduler.prefer(.music, at: 3)
        XCTAssertEqual(scheduler.current(at: 3)?.kind, .timerFinished)
        scheduler.expire(at: 100)
        XCTAssertEqual(scheduler.current(at: 100)?.kind, .timerFinished)
        scheduler.end(.timerFinished)
        XCTAssertEqual(scheduler.current(at: 100)?.kind, .music)
    }

    func testExpiredSongChangeDoesNotReplayAfterFeedback() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .musicChange), at: 1)
        scheduler.submit(IslandActivity(kind: .volume), at: 3)
        XCTAssertEqual(scheduler.current(at: 4)?.kind, .volume)
        XCTAssertEqual(scheduler.current(at: 5)?.kind, .music)
        scheduler.expire(at: 5)
        XCTAssertNil(scheduler.nextExpiry)
    }

    func testEndingBackgroundMusicDoesNotDismissForegroundFeedback() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .mic, value: 0), at: 1)
        scheduler.end(.music)
        XCTAssertEqual(scheduler.current(at: 1)?.kind, .mic)
        XCTAssertNil(scheduler.current(at: 3))
    }

    func testRepeatedSongChangesKeepOnlyLatestEmphasis() {
        var scheduler = ActivityScheduler()
        for index in 0..<100 {
            scheduler.submit(IslandActivity(kind: .musicChange), at: Double(index) / 10)
        }
        XCTAssertEqual(scheduler.current(at: 10)?.kind, .musicChange)
        XCTAssertNil(scheduler.current(at: 13))
        scheduler.expire(at: 13)
        XCTAssertNil(scheduler.nextExpiry)
    }

    func testEarliestExpiryIncludesHiddenActivities() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .musicChange), at: 0)
        scheduler.submit(IslandActivity(kind: .volume), at: 2)
        XCTAssertEqual(scheduler.nextExpiry, 3)
        scheduler.expire(at: 3)
        XCTAssertEqual(scheduler.nextExpiry, 3.5)
        XCTAssertEqual(scheduler.current(at: 3)?.kind, .volume)
    }

    func testEverySupportedKindHasOnePresentation() {
        for kind in IslandActivityKind.allCases {
            let activity = IslandActivity(kind: kind, value: 0.5, icon: "speaker")
            let presentation = IslandPresentation(activity: activity)
            XCTAssertEqual(presentation.requiresExpandedTimer, kind == .timerFinished)
            if kind.isSystemFeedback {
                XCTAssertEqual(presentation.feedback, activity)
                XCTAssertFalse(presentation.showsMusic)
            } else if kind == .power {
                XCTAssertEqual(presentation, .power)
            } else if kind == .timer || kind == .timerFinished {
                XCTAssertEqual(presentation, .timer(finished: kind == .timerFinished))
            } else if kind == .reminders {
                XCTAssertEqual(presentation, .reminders)
            } else {
                XCTAssertTrue(presentation.showsMusic)
                XCTAssertEqual(presentation.showsMusicPeek, kind == .musicChange)
            }
        }
    }
}

@main
enum ActivityTestRunner {
    static func main() {
        let suite = ActivitySchedulerTests.defaultTestSuite
        suite.addTest(PersonalActivityTests.defaultTestSuite)
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0 else {
            fputs("No activity tests ran\n", stderr)
            exit(1)
        }
        exit(result.hasSucceeded ? 0 : 1)
    }
}
