import Foundation
import XCTest

final class MediaPlaybackTests: XCTestCase {
    private let snapshot = #"{"diff":false,"payload":{"bundleIdentifier":"com.netease.163music","title":"七点醒来🎵","artist":"歌手","duration":240,"elapsedTime":12,"playing":true,"artworkData":"AQID"}}"#

    private func update(_ json: String) throws -> NowPlayingUpdate {
        try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8))
    }

    func testEveryUTF8SplitPreservesTrackSnapshot() throws {
        let bytes = Data((snapshot + "\n").utf8)
        for split in 0...bytes.count {
            var buffer = JSONLineBuffer()
            let lines = buffer.append(Data(bytes.prefix(split))) + buffer.append(Data(bytes.dropFirst(split)))
            XCTAssertEqual(lines.count, 1, "Failed at byte \(split)")
            let state = try JSONDecoder().decode(NowPlayingUpdate.self, from: XCTUnwrap(lines.first))
                .applying(to: PlaybackState(bundleIdentifier: ""))
            XCTAssertEqual(state.title, "七点醒来🎵")
            XCTAssertEqual(state.duration, 240)
            XCTAssertTrue(state.isPlaying)
        }
    }

    func testProgressDiffPreservesArtworkAndMetadata() throws {
        let initial = try update(snapshot).applying(to: PlaybackState(bundleIdentifier: ""))
        let state = try update(#"{"diff":true,"payload":{"elapsedTime":20}}"#).applying(to: initial)
        XCTAssertEqual(state.title, initial.title)
        XCTAssertEqual(state.artwork, Data([1, 2, 3]))
        XCTAssertEqual(state.duration, 240)
        XCTAssertEqual(state.currentTime, 20)
        XCTAssertTrue(state.isPlaying)
    }

    func testExplicitNullClearsFieldsWithoutClearingUnchangedFields() throws {
        let initial = try update(snapshot).applying(to: PlaybackState(bundleIdentifier: ""))
        let state = try update(#"{"diff":true,"payload":{"artworkData":null,"artist":null,"duration":null}}"#)
            .applying(to: initial)
        XCTAssertNil(state.artwork)
        XCTAssertEqual(state.artist, "")
        XCTAssertEqual(state.duration, 0)
        XCTAssertEqual(state.title, initial.title)
        XCTAssertTrue(state.isPlaying)
    }

    func testEmptySnapshotReallyClearsPlayback() throws {
        let initial = try update(snapshot).applying(to: PlaybackState(bundleIdentifier: ""))
        let state = try update(#"{"diff":false,"payload":{}}"#).applying(to: initial)
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.bundleIdentifier, "")
        XCTAssertEqual(state.duration, 0)
        XCTAssertNil(state.artwork)
        XCTAssertFalse(state.isPlaying)
    }

    func testTrackSwitchRecoversAfterEmptySnapshotAndFragmentedChinese() throws {
        let next = #"{"diff":false,"payload":{"bundleIdentifier":"com.netease.163music","title":"下一首中文歌","duration":180,"playing":true,"artworkData":"BAUG"}}"#
        let wire = Data((snapshot + "\n{\"diff\":false,\"payload\":{}}\n" + next + "\n").utf8)
        var buffer = JSONLineBuffer()
        var state = PlaybackState(bundleIdentifier: "")
        for byte in wire {
            for line in buffer.append(Data([byte])) {
                state = try JSONDecoder().decode(NowPlayingUpdate.self, from: line).applying(to: state)
            }
        }
        XCTAssertEqual(state.title, "下一首中文歌")
        XCTAssertEqual(state.duration, 180)
        XCTAssertEqual(state.artwork, Data([4, 5, 6]))
        XCTAssertTrue(state.isPlaying)
    }

    func testLargeArtworkAcrossPipeSizedChunks() throws {
        let artwork = Data(repeating: 0xAB, count: 150_000)
        let wire = Data(("{\"diff\":false,\"payload\":{\"title\":\"大封面中文歌\",\"artworkData\":\"" + artwork.base64EncodedString() + "\"}}\n").utf8)
        var buffer = JSONLineBuffer()
        var lines: [Data] = []
        for start in stride(from: 0, to: wire.count, by: 65_536) {
            lines += buffer.append(Data(wire[start..<min(start + 65_536, wire.count)]))
        }
        XCTAssertEqual(lines.count, 1)
        let state = try JSONDecoder().decode(NowPlayingUpdate.self, from: XCTUnwrap(lines.first))
            .applying(to: PlaybackState(bundleIdentifier: ""))
        XCTAssertEqual(state.artwork, artwork)
        XCTAssertEqual(state.title, "大封面中文歌")
    }

    func testFractionalTimestampAndPausePosition() throws {
        let initial = try update(#"{"diff":false,"payload":{"title":"Song","duration":240,"elapsedTime":10,"playing":true,"timestamp":"2026-11-01T08:00:00.500Z"}}"#)
            .applying(to: PlaybackState(bundleIdentifier: ""))
        let state = try update(#"{"diff":true,"payload":{"playing":false,"timestamp":"2026-11-01T08:00:02.500Z"}}"#)
            .applying(to: initial)
        XCTAssertEqual(state.currentTime, 12, accuracy: 0.001)
        XCTAssertFalse(state.isPlaying)
    }

    func testElapsedTimeWithoutTimestampReanchorsProgress() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let initial = try update(snapshot).applying(to: PlaybackState(bundleIdentifier: ""), now: now)
        let state = try update(#"{"diff":true,"payload":{"elapsedTime":25}}"#)
            .applying(to: initial, now: now.addingTimeInterval(10))
        XCTAssertEqual(state.currentTime, 25)
        XCTAssertEqual(state.lastUpdated, now.addingTimeInterval(10))
    }

    func testSnapshotsAndDiffsArriveBeforeWriterCloses() throws {
        let snapshotReceived = expectation(description: "Snapshot arrives while writer stays open")
        let diffReceived = expectation(description: "Progress update arrives while writer stays open")
        let finished = expectation(description: "Reader finishes after writer closes")
        let pipe = Pipe()
        let handler = JSONLinesPipeHandler(pipe: pipe)
        let reader = Task.detached {
            do {
                try await handler.readJSONLines(as: NowPlayingUpdate.self) { update in
                    if update.diff == false {
                        XCTAssertEqual(update.payload.title, "七点醒来🎵")
                        snapshotReceived.fulfill()
                    } else {
                        XCTAssertEqual(update.payload.elapsedTime, 24)
                        diffReceived.fulfill()
                    }
                }
            } catch { XCTFail("Live pipe read failed: \(error)") }
            await handler.close()
            finished.fulfill()
        }
        defer { reader.cancel() }
        try pipe.fileHandleForWriting.write(contentsOf: Data((snapshot + "\n").utf8))
        wait(for: [snapshotReceived], timeout: 1)
        try pipe.fileHandleForWriting.write(contentsOf: Data("{\"diff\":true,\"payload\":{\"elapsedTime\":24}}\n".utf8))
        wait(for: [diffReceived], timeout: 1)
        try pipe.fileHandleForWriting.close()
        wait(for: [finished], timeout: 3)
    }

    func testRealPipeFinishesAtEOFIncludingLastUnterminatedLine() {
        let finished = expectation(description: "Pipe reader finishes at EOF")
        let wire = Data((snapshot + "\n{\"diff\":true,\"payload\":{\"elapsedTime\":24}}").utf8)
        let task = Task.detached {
            let handler = JSONLinesPipeHandler()
            let pipe = await handler.getPipe()
            do {
                try pipe.fileHandleForWriting.write(contentsOf: wire)
                try pipe.fileHandleForWriting.close()
                let received = ReceivedUpdates()
                try await handler.readJSONLines(as: NowPlayingUpdate.self) { await received.append($0) }
                let values = await received.values
                XCTAssertEqual(values.count, 2)
                XCTAssertEqual(values.last?.payload.elapsedTime, 24)
            } catch { XCTFail("Pipe read failed: \(error)") }
            await handler.close()
            finished.fulfill()
        }
        defer { task.cancel() }
        wait(for: [finished], timeout: 3)
    }

    func testCancellingAnIdlePipeReaderFinishesPromptly() {
        let finished = expectation(description: "Cancelled idle reader finishes")
        let task = Task.detached {
            let handler = JSONLinesPipeHandler()
            let reader = Task {
                try await handler.readJSONLines(as: NowPlayingUpdate.self) { _ in }
            }
            reader.cancel()
            do {
                try await reader.value
                XCTFail("Expected cancellation")
            } catch is CancellationError { }
            catch { XCTFail("Unexpected error: \(error)") }
            await handler.close()
            finished.fulfill()
        }
        defer { task.cancel() }
        wait(for: [finished], timeout: 3)
    }

    func testMalformedJSONIsReportedSoControllerCanReconnect() {
        let finished = expectation(description: "Malformed data reports an error")
        let task = Task.detached {
            let handler = JSONLinesPipeHandler()
            let pipe = await handler.getPipe()
            do {
                try pipe.fileHandleForWriting.write(contentsOf: Data("{broken JSON}\n".utf8))
                try pipe.fileHandleForWriting.close()
                try await handler.readJSONLines(as: NowPlayingUpdate.self) { _ in XCTFail("Invalid update delivered") }
                XCTFail("Expected decoding failure")
            } catch is DecodingError { }
            catch { XCTFail("Unexpected error: \(error)") }
            await handler.close()
            finished.fulfill()
        }
        defer { task.cancel() }
        wait(for: [finished], timeout: 3)
    }

    private func neteaseTrack(_ title: String = "Witches", playing: Bool = true, elapsed: Double = 0, rate: Double = 1) throws -> NowPlayingUpdate {
        let value: [String: Any] = ["diff": false, "payload": [
            "bundleIdentifier": "com.netease.163music", "title": title,
            "artist": "Artist", "album": "Album", "duration": 195,
            "elapsedTime": elapsed, "playing": playing, "playbackRate": rate,
            "artworkData": "AQID",
        ]]
        return try JSONDecoder().decode(NowPlayingUpdate.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testRequestedTrackLoadDoesNotBecomeVisualPauseOrFakePlayback() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        XCTAssertTrue(session.beginTrackChange(now: start).isChangingTrack)
        let loading = session.receive(try neteaseTrack("Next", playing: false, rate: 0), neteaseIsRunning: true, now: start.addingTimeInterval(1))
        XCTAssertFalse(loading.isPlaying)
        XCTAssertEqual(loading.playbackRate, 0)
        XCTAssertTrue(loading.isChangingTrack)
        XCTAssertTrue(session.confirmPendingPause(now: start.addingTimeInterval(6)).isChangingTrack)
        let resumed = session.receive(try neteaseTrack("Next"), neteaseIsRunning: true, now: start.addingTimeInterval(7))
        XCTAssertTrue(resumed.isPlaying)
        XCTAssertFalse(resumed.isChangingTrack)
        XCTAssertNil(session.trackChangeDeadline)
    }

    func testNetEaseObservedLoadSequenceWaitsThroughTemporaryIDsAndZeroRatePlaying() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        _ = session.beginTrackChange(now: start)
        let packets = [
            #"{"diff":true,"payload":{"playing":false}}"#,
            #"{"diff":true,"payload":{"playbackRate":0,"elapsedTime":130,"contentItemIdentifier":"temporary-old"}}"#,
            #"{"diff":true,"payload":{"playing":true}}"#,
            #"{"diff":false,"payload":{"bundleIdentifier":"com.netease.163music","title":"Next","artist":"Artist","album":"Album","playing":true,"playbackRate":0,"contentItemIdentifier":"destination"}}"#,
            #"{"diff":true,"payload":{"artworkData":"BAUG"}}"#,
            #"{"diff":true,"payload":{"playing":false}}"#,
            #"{"diff":true,"payload":{"playing":true}}"#,
        ]
        for (index, packet) in packets.enumerated() {
            let state = session.receive(try update(packet), neteaseIsRunning: true,
                                        now: start.addingTimeInterval(Double(index + 1) * 0.1))
            XCTAssertTrue(state.isChangingTrack, "Load ended prematurely at packet \(index)")
            if index >= 2 { XCTAssertEqual(state.playbackRate, 0, "Loading must not advance the timeline") }
        }
        let ready = session.receive(try update(#"{"diff":true,"payload":{"playbackRate":1,"elapsedTime":0.18,"contentItemIdentifier":"temporary-progress"}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(1))
        XCTAssertFalse(ready.isChangingTrack)
        XCTAssertTrue(ready.isPlaying)
        XCTAssertEqual(ready.sourceTrackIdentifier, "destination")
        XCTAssertEqual(ready.artwork, Data([4, 5, 6]))
    }

    func testTitleOnlySwitchDoesNotReusePreviousTracksArtwork() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true)
        _ = session.beginTrackChange()
        let loading = session.receive(try update(#"{"diff":true,"payload":{"title":"Next","playbackRate":0}}"#), neteaseIsRunning: true)
        XCTAssertNil(loading.artwork)
        XCTAssertTrue(loading.isChangingTrack)
        let covered = session.receive(try update(#"{"diff":true,"payload":{"artworkData":"BAUG"}}"#), neteaseIsRunning: true)
        XCTAssertEqual(covered.artwork, Data([4, 5, 6]))
        XCTAssertTrue(covered.isChangingTrack)
    }

    func testTrackChangeSurvivesTransientOldTrackPauseAndProgress() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        _ = session.beginTrackChange(now: start)
        _ = session.receive(try update(#"{"diff":true,"payload":{"playing":false}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.1))
        let stopped = session.confirmPendingPause(now: start.addingTimeInterval(0.5))
        XCTAssertFalse(stopped.isPlaying)
        XCTAssertTrue(stopped.isChangingTrack)
        let oldProgress = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start.addingTimeInterval(1))
        XCTAssertTrue(oldProgress.isChangingTrack)
        let next = session.receive(try neteaseTrack("Next"), neteaseIsRunning: true, now: start.addingTimeInterval(2))
        XCTAssertFalse(next.isChangingTrack)
    }

    func testFailedTrackChangeExpiresWithoutAnotherProviderEvent() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        _ = session.beginTrackChange(now: start)
        _ = session.receive(try neteaseTrack("Unavailable", playing: false, rate: 0), neteaseIsRunning: true, now: start.addingTimeInterval(1))
        let expired = session.confirmPendingPause(now: start.addingTimeInterval(8))
        XCTAssertFalse(expired.isChangingTrack)
        XCTAssertFalse(expired.isPlaying)
        XCTAssertNil(session.trackChangeDeadline)
    }

    func testManualPauseCancelsTrackChangeAndPausedSkipStaysPaused() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        _ = session.beginTrackChange(now: start)
        XCTAssertFalse(session.cancelTrackChange().isChangingTrack)
        let paused = session.receive(try neteaseTrack(playing: false, rate: 0), neteaseIsRunning: true, now: start.addingTimeInterval(1))
        XCTAssertFalse(paused.isPlaying)
        XCTAssertFalse(paused.isChangingTrack)
        XCTAssertFalse(session.beginTrackChange(now: start.addingTimeInterval(2)).isChangingTrack)
    }

    func testRapidTrackRequestsReplaceDeadlineAndOldConfirmationCannotEndLatest() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        _ = session.beginTrackChange(now: start)
        _ = session.receive(try neteaseTrack("Slow", playing: false, rate: 0), neteaseIsRunning: true, now: start.addingTimeInterval(1))
        _ = session.beginTrackChange(now: start.addingTimeInterval(6))
        XCTAssertTrue(session.confirmPendingPause(now: start.addingTimeInterval(8)).isChangingTrack)
        XCTAssertFalse(session.confirmPendingPause(now: start.addingTimeInterval(14)).isChangingTrack)
    }

    func testTrackChangeEndsWhenPlayerTerminatesOrSourceChanges() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true)
        _ = session.beginTrackChange()
        XCTAssertFalse(session.sourceDidTerminate(bundleIdentifier: "com.netease.163music").isChangingTrack)
        XCTAssertNil(session.trackChangeDeadline)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true)
        _ = session.beginTrackChange()
        let other = session.receive(try update(#"{"diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"Other","playing":false}}"#), neteaseIsRunning: true)
        XCTAssertFalse(other.isChangingTrack)
        XCTAssertNil(session.trackChangeDeadline)
    }

    func testTrackChangeStateIsPublishedEvenIfPlaybackFieldsAreUnchanged() {
        let original = PlaybackState(bundleIdentifier: "player")
        var loading = original
        loading.isChangingTrack = true
        XCTAssertNotEqual(original, loading)
    }

    func testNetEaseRealPauseThenEmptySequencePreservesPlayingTrack() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        let transientPause = session.receive(try update(#"{"diff":true,"payload":{"playing":false}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.4))
        XCTAssertTrue(transientPause.isPlaying)
        let retained = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.5))
        XCTAssertEqual(retained.title, "Witches")
        XCTAssertEqual(retained.duration, 195)
        XCTAssertEqual(retained.artwork, Data([1, 2, 3]))
        XCTAssertTrue(retained.isPlaying)
        XCTAssertNil(session.pauseDeadline)
        XCTAssertTrue(session.confirmPendingPause(now: start.addingTimeInterval(2)).isPlaying)
    }

    func testNetEaseArtworkDuringTransientPauseDoesNotConfirmPause() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        _ = session.receive(try update(#"{"diff":true,"payload":{"playing":false}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.1))
        _ = session.receive(try update(#"{"diff":true,"payload":{"artworkData":"BAUG"}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.2))
        let state = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.25))
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.title, "Witches")
    }

    func testNetEaseGenuinePauseIsConfirmedAndResumeAdvances() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(elapsed: 10), neteaseIsRunning: true, now: start)
        _ = session.receive(try update(#"{"diff":true,"payload":{"playing":false}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(2))
        let paused = session.confirmPendingPause(now: start.addingTimeInterval(2.4))
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.currentTime, 12, accuracy: 0.001)
        let resumed = session.receive(try update(#"{"diff":true,"payload":{"playing":true}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(5))
        XCTAssertTrue(resumed.isPlaying)
        XCTAssertEqual(resumed.currentTime, 12, accuracy: 0.001)
        XCTAssertEqual(resumed.lastUpdated, start.addingTimeInterval(5))
    }

    func testNetEasePauseWhileMetadataMissingDoesNotRestartPlayback() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true)
        _ = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true)
        let paused = session.receive(try neteaseTrack(playing: false, elapsed: 20, rate: 0), neteaseIsRunning: true)
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.currentTime, 20)
        XCTAssertNil(session.pauseDeadline)
    }

    func testNetEaseRapidTrackChangesKeepNewestTrackThroughEmptyPackets() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        for i in 0..<50 {
            let now = start.addingTimeInterval(Double(i))
            _ = session.receive(try neteaseTrack("Track \(i)"), neteaseIsRunning: true, now: now)
            _ = session.receive(try update(#"{"diff":true,"payload":{"playing":false}}"#), neteaseIsRunning: true, now: now.addingTimeInterval(0.1))
            let state = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true, now: now.addingTimeInterval(0.15))
            XCTAssertEqual(state.title, "Track \(i)")
            XCTAssertTrue(state.isPlaying)
            XCTAssertEqual(state.duration, 195)
        }
    }

    func testNetEasePlayingOnlyDiffFixesZeroPlaybackRate() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(playing: false, rate: 0), neteaseIsRunning: true, now: start)
        let state = session.receive(try update(#"{"diff":true,"payload":{"playing":true}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(0.1))
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.playbackRate, 1)
        XCTAssertEqual(state.lastUpdated, start.addingTimeInterval(0.1))
    }

    func testNetEaseTerminationClearsRetainedMetadata() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true)
        _ = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true)
        let state = session.sourceDidTerminate(bundleIdentifier: "com.netease.163music")
        XCTAssertEqual(state.title, "")
        XCTAssertFalse(state.isPlaying)
        XCTAssertNil(state.artwork)
    }

    func testNetEaseNoLongerRunningDoesNotRetainEmptySnapshot() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true)
        let state = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: false)
        XCTAssertEqual(state.title, "")
        XCTAssertFalse(state.isPlaying)
    }

    func testOtherPlayersStillClearAndPauseImmediately() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try update(#"{"diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"Song","playing":true}}"#), neteaseIsRunning: true)
        let paused = session.receive(try update(#"{"diff":true,"payload":{"playing":false}}"#), neteaseIsRunning: true)
        XCTAssertFalse(paused.isPlaying)
        XCTAssertNil(session.pauseDeadline)
        let cleared = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true)
        XCTAssertEqual(cleared.title, "")
    }

    func testRetainedTrackStopsAtKnownEnd() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack(), neteaseIsRunning: true, now: start)
        let state = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(196))
        XCTAssertEqual(state.title, "Witches")
        XCTAssertEqual(state.currentTime, 195)
        XCTAssertFalse(state.isPlaying)
    }

    func testQueueCatalogExtractsOnlyTrackMetadataAndSecuresArtworkURL() throws {
        let data = Data(#"{"list":[{"track":{"id":"123","name":"Song","duration":233000,"artists":[{"name":"Artist"}],"album":{"name":"Album","picUrl":"http://p3.music.126.net/cover.jpg"}}}]}"#.utf8)
        let tracks = NetEaseQueueCatalog.tracks(in: data)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.id, "123")
        XCTAssertEqual(track.duration, 233)
        XCTAssertEqual(track.artist, "Artist")
        XCTAssertEqual(track.artworkURL?.absoluteString, "https://p3.music.126.net/cover.jpg?param=300y300")
    }

    func testQueueCatalogRejectsUntrustedArtworkHosts() throws {
        let data = Data(#"{"list":[{"track":{"id":"1","name":"Song","dt":200000,"ar":[{"name":"Artist"}],"al":{"name":"Album","picUrl":"https://example.com/cover"}}}]}"#.utf8)
        let track = try XCTUnwrap(NetEaseQueueCatalog.tracks(in: data).first)
        XCTAssertEqual(track.duration, 200)
        XCTAssertNil(track.artworkURL)
    }

    func testQueueCatalogUsesUniqueTitleWhenPreviousArtistLeaksIntoSnapshot() throws {
        let track = NetEaseTrackMetadata(id: "1", title: "Song", artist: "New Artist", album: "Album", duration: 200, artworkURL: nil)
        XCTAssertEqual(NetEaseQueueCatalog.match(in: [track, track], title: "Song", artist: "Old Artist"), track)
    }

    func testQueueCatalogDoesNotGuessBetweenAmbiguousTitles() throws {
        let first = NetEaseTrackMetadata(id: "1", title: "Song", artist: "First Artist", album: "Album", duration: 200, artworkURL: nil)
        let second = NetEaseTrackMetadata(id: "2", title: "Song", artist: "Second Artist", album: "Album", duration: 250, artworkURL: nil)
        XCTAssertNil(NetEaseQueueCatalog.match(in: [first, second], title: "Song", artist: "Unknown"))
        XCTAssertEqual(NetEaseQueueCatalog.match(in: [first, second], title: "Song", artist: "Second Artist"), second)
        XCTAssertTrue(NetEaseQueueCatalog.tracks(in: Data("invalid".utf8)).isEmpty)
    }

    func testQueueReconciliationCorrectsOldDurationAndArtworkDuringSwitch() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack("Terranova"), neteaseIsRunning: true)
        let metadata = NetEaseTrackMetadata(id: "1", title: "Terranova", artist: "Janina", album: "A Piece of Paradise", duration: 233, artworkURL: nil)
        let reconciled = session.reconcile(metadata, artwork: Data([4, 5, 6]))
        XCTAssertEqual(reconciled.duration, 233)
        XCTAssertEqual(reconciled.artist, "Janina")
        XCTAssertEqual(reconciled.artwork, Data([4, 5, 6]))
        let retained = session.receive(try update(#"{"diff":false,"payload":{}}"#), neteaseIsRunning: true)
        XCTAssertEqual(retained.duration, 233)
        XCTAssertEqual(retained.album, metadata.album)
        XCTAssertEqual(retained.artwork, Data([4, 5, 6]))
    }

    func testLateQueueResultCannotOverwriteNewTrack() throws {
        var session = NowPlayingPlaybackSession()
        _ = session.receive(try neteaseTrack("First"), neteaseIsRunning: true)
        _ = session.receive(try neteaseTrack("Second"), neteaseIsRunning: true)
        let old = NetEaseTrackMetadata(id: "1", title: "First", artist: "Old Artist", album: "Old Album", duration: 300, artworkURL: nil)
        let state = session.reconcile(old, artwork: Data([9]))
        XCTAssertEqual(state.title, "Second")
        XCTAssertEqual(state.duration, 195)
        XCTAssertEqual(state.artwork, Data([1, 2, 3]))
    }

    func testNetEaseNewTitleDoesNotInheritPreviousElapsedTime() throws {
        var session = NowPlayingPlaybackSession()
        let start = Date(timeIntervalSince1970: 1000)
        _ = session.receive(try neteaseTrack("First", elapsed: 46), neteaseIsRunning: true, now: start)
        let switched = session.receive(try neteaseTrack("Second", elapsed: 46), neteaseIsRunning: true, now: start.addingTimeInterval(2))
        XCTAssertEqual(switched.currentTime, 0)
        XCTAssertEqual(switched.lastUpdated, start.addingTimeInterval(2))
        let seek = session.receive(try update(#"{"diff":true,"payload":{"elapsedTime":60}}"#), neteaseIsRunning: true, now: start.addingTimeInterval(3))
        XCTAssertEqual(seek.currentTime, 60)
    }

    func testNetEaseInitialSnapshotPreservesAlreadyPlayingPosition() throws {
        var session = NowPlayingPlaybackSession()
        let state = session.receive(try neteaseTrack("Already playing", elapsed: 46), neteaseIsRunning: true)
        XCTAssertEqual(state.currentTime, 46)
    }
    func testArtworkUpgradeAfterCompletedFlipDoesNotFlipAgain() {
        let oldTrack = UUID(), nextTrack = UUID()
        var transition = AlbumArtworkTransition<String>(.init(artwork: "old", trackIdentifier: oldTrack, direction: .next))
        guard case .flip("thumbnail", .next)? = transition.receive(.init(artwork: "thumbnail", trackIdentifier: nextTrack, direction: .next)) else {
            return XCTFail("A new song must flip")
        }
        XCTAssertNil(transition.complete())
        guard case .replace("high-resolution")? = transition.receive(.init(artwork: "high-resolution", trackIdentifier: nextTrack, direction: .next)) else {
            return XCTFail("The same song's sharper cover must replace in place")
        }
        XCTAssertFalse(transition.isAnimating)
        XCTAssertNil(transition.complete())
    }

    func testArtworkUpgradeDuringFlipUpdatesDestinationWithoutAnotherTurn() {
        let nextTrack = UUID()
        var transition = AlbumArtworkTransition<String>(.init(artwork: "old", trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: "thumbnail", trackIdentifier: nextTrack, direction: .previous))
        guard case .replace("sharp")? = transition.receive(.init(artwork: "sharp", trackIdentifier: nextTrack, direction: .previous)) else {
            return XCTFail("Refinement during a flip must update its destination")
        }
        XCTAssertTrue(transition.isAnimating)
        XCTAssertEqual(transition.target.artwork, "sharp")
        XCTAssertNil(transition.complete())
        XCTAssertFalse(transition.isAnimating)
    }

    func testPendingArtworkRefinementsCoalesceToLatestCoverAndDirection() {
        var transition = AlbumArtworkTransition<String>(.init(artwork: "old", trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: "first", trackIdentifier: UUID(), direction: .next))
        let latest = UUID()
        XCTAssertNil(transition.receive(.init(artwork: "thumbnail", trackIdentifier: latest, direction: .previous)))
        XCTAssertNil(transition.receive(.init(artwork: "sharp", trackIdentifier: latest, direction: .previous)))
        guard case .flip("sharp", .previous)? = transition.complete() else {
            return XCTFail("Only the newest queued cover should flip, keeping its direction")
        }
        XCTAssertNil(transition.complete())
        XCTAssertEqual(transition.target.artwork, "sharp")
    }

    func testRapidTrackSwitchesDiscardIntermediateArtwork() {
        var transition = AlbumArtworkTransition<Int>(.init(artwork: 0, trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: 1, trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: 2, trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: 3, trackIdentifier: UUID(), direction: .previous))
        guard case .flip(3, .previous)? = transition.complete() else { return XCTFail("Stale queued artwork must be discarded") }
        XCTAssertNil(transition.complete())
        XCTAssertEqual(AlbumArtFlipDirection.next.rotation, -180)
        XCTAssertEqual(AlbumArtFlipDirection.previous.rotation, 180)
    }

    func testArtworkResetCancelsPendingFlip() {
        let latest = UUID()
        var transition = AlbumArtworkTransition<Int>(.init(artwork: 0, trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: 1, trackIdentifier: UUID(), direction: .next))
        _ = transition.receive(.init(artwork: 2, trackIdentifier: latest, direction: .previous))
        transition.reset(.init(artwork: 2, trackIdentifier: latest, direction: .previous))
        XCTAssertFalse(transition.isAnimating)
        XCTAssertNil(transition.complete())
        guard case .replace(3)? = transition.receive(.init(artwork: 3, trackIdentifier: latest, direction: .next)) else {
            return XCTFail("Returning to the view must not replay an old flip")
        }
    }

    func testLateTrackIdentifierDoesNotTurnArtworkRefinementIntoNewSong() {
        var tracker = AlbumArtworkTrackTracker()
        let initial = tracker.update(bundleIdentifier: "player", title: "Song", sourceTrackIdentifier: nil)
        let identified = tracker.update(bundleIdentifier: "player", title: "Song", sourceTrackIdentifier: "42")
        XCTAssertEqual(initial, identified)
        XCTAssertEqual(identified, tracker.update(bundleIdentifier: "player", title: " Song ", sourceTrackIdentifier: nil))
        XCTAssertNotEqual(identified, tracker.update(bundleIdentifier: "player", title: "Song", sourceTrackIdentifier: "43"))
    }

    func testSourceIdentifierArrivingBeforeTitleKeepsOneSongTransition() {
        var tracker = AlbumArtworkTrackTracker()
        let old = tracker.update(bundleIdentifier: "player", title: "Old title", sourceTrackIdentifier: "1")
        let next = tracker.update(bundleIdentifier: "player", title: "Old title", sourceTrackIdentifier: "2")
        XCTAssertNotEqual(old, next)
        XCTAssertEqual(next, tracker.update(bundleIdentifier: "player", title: "New title", sourceTrackIdentifier: "2"))
    }

    func testArtworkTrackIdentityChangesOnNewTitleAndPlayer() {
        var tracker = AlbumArtworkTrackTracker()
        let first = tracker.update(bundleIdentifier: "player", title: "First", sourceTrackIdentifier: nil)
        let second = tracker.update(bundleIdentifier: "player", title: "Second", sourceTrackIdentifier: nil)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second, tracker.update(bundleIdentifier: "player", title: "Second", sourceTrackIdentifier: "id"))
        XCTAssertNotEqual(second, tracker.update(bundleIdentifier: "other-player", title: "Second", sourceTrackIdentifier: "id"))
    }

    func testNetEaseThumbnailThenQueueCoverProducesOneFlip() throws {
        var session = NowPlayingPlaybackSession()
        var tracker = AlbumArtworkTrackTracker()
        let first = session.receive(try neteaseTrack("First"), neteaseIsRunning: true)
        let initialID = tracker.update(bundleIdentifier: first.bundleIdentifier, title: first.title, sourceTrackIdentifier: first.sourceTrackIdentifier)
        var transition = AlbumArtworkTransition<Data?>(.init(artwork: first.artwork, trackIdentifier: initialID, direction: .next))
        let second = session.receive(try neteaseTrack("Second"), neteaseIsRunning: true)
        let nextID = tracker.update(bundleIdentifier: second.bundleIdentifier, title: second.title, sourceTrackIdentifier: second.sourceTrackIdentifier)
        guard case .flip? = transition.receive(.init(artwork: second.artwork, trackIdentifier: nextID, direction: .next)) else { return XCTFail("New track must flip") }
        XCTAssertNil(transition.complete())
        let metadata = NetEaseTrackMetadata(id: "2", title: "Second", artist: "Corrected Artist", album: "Corrected Album", duration: 200, artworkURL: nil)
        let refined = session.reconcile(metadata, artwork: Data([9, 8, 7, 6]))
        let refinedID = tracker.update(bundleIdentifier: refined.bundleIdentifier, title: refined.title, sourceTrackIdentifier: refined.sourceTrackIdentifier)
        XCTAssertEqual(nextID, refinedID)
        guard case .replace(let artwork)? = transition.receive(.init(artwork: refined.artwork, trackIdentifier: refinedID, direction: .next)) else { return XCTFail("NetEase metadata enrichment must not cause a second flip") }
        XCTAssertEqual(artwork, Data([9, 8, 7, 6]))
        XCTAssertFalse(transition.isAnimating)
    }

}

private actor ReceivedUpdates {
    var values: [NowPlayingUpdate] = []
    func append(_ update: NowPlayingUpdate) { values.append(update) }
}

@main
enum MediaPlaybackTestRunner {
    static func main() {
        let suite = MediaPlaybackTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0 else {
            fputs("No playback tests ran\n", stderr)
            exit(1)
        }
        exit(result.hasSucceeded ? 0 : 1)
    }
}
