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

    func testPowerPreemptsSongChangeButNotUserFeedback() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .musicChange), at: 0)
        scheduler.submit(IslandActivity(kind: .power), at: 0.1)
        XCTAssertEqual(scheduler.current(at: 0.2)?.kind, .power)
        scheduler.submit(IslandActivity(kind: .backlight), at: 0.2)
        XCTAssertEqual(scheduler.current(at: 0.3)?.kind, .backlight)
        XCTAssertEqual(scheduler.current(at: 1.7)?.kind, .power)
    }

    func testExpiredSongChangeDoesNotReplayAfterPower() {
        var scheduler = ActivityScheduler()
        scheduler.submit(IslandActivity(kind: .music), at: 0)
        scheduler.submit(IslandActivity(kind: .musicChange), at: 1)
        scheduler.submit(IslandActivity(kind: .power), at: 2)
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
            if kind.isSystemFeedback {
                XCTAssertEqual(presentation.feedback, activity)
                XCTAssertFalse(presentation.showsMusic)
            } else if kind == .power {
                XCTAssertEqual(presentation, .power)
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
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0 else {
            fputs("No activity tests ran\n", stderr)
            exit(1)
        }
        exit(result.hasSucceeded ? 0 : 1)
    }
}
