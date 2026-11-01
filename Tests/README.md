# Media playback regression tests

Run with a full Xcode installation selected:

```sh
bash Tests/run-media-playback-tests.sh
```

These XCTest cases compile the production stream reader and state reducer directly,
without downloading the app's dependencies. They cover fragmented UTF-8 metadata,
large artwork, full snapshots and partial updates (including explicit null values),
playback timestamps, delivery while the pipe writer remains open, EOF,
cancellation, and malformed messages.

NetEase regression cases replay its valid-track/pause/empty-snapshot sequence,
check real pause/resume and termination, correct stale duration/artwork using
playback-queue metadata, and reject late results from a preceding track.

They do not launch a music player or replace a real playback acceptance check.
