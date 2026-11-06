import AppKit

@main enum HorizontalPagingGestureTests {
    @MainActor static func main() async {
        var phases: [NSEvent.Phase] = []
        var deltas: [Double] = []
        let input = HorizontalPagingGesture.Coordinator { delta, _, phase in
            phases.append(phase)
            if phase == .changed { deltas.append(delta) }
        }
        func require(_ condition: Bool, _ message: String) {
            guard condition else { print("FAIL: \(message)"); exit(1) }
        }
        func event(_ phase: CGScrollPhase?, x: Int32 = 0, y: Int32 = 0,
                   time: Double, momentum: Int64 = 0) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                             wheel1: y, wheel2: x, wheel3: 0)!
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            cg.timestamp = UInt64(time * 1_000_000_000)
            return NSEvent(cgEvent: cg)!
        }
        _ = input.handleScrollEvent(event(.began, time: 100))
        _ = input.handleScrollEvent(event(.changed, x: 180, time: 100.05))
        _ = input.handleScrollEvent(event(.ended, time: 100.1))
        let completed = phases.count
        _ = input.handleScrollEvent(event(.mayBegin, time: 100.6))
        require(phases.count == completed, "Native mayBegin re-entered the completed drag")
        _ = input.handleScrollEvent(event(.changed, x: -2, time: 100.61))
        _ = input.handleScrollEvent(event(nil, x: -90, time: 100.62, momentum: 1))
        require(phases.count == completed, "Late changed/momentum continued a completed drag")
        _ = input.handleScrollEvent(event(.began, time: 100.7))
        _ = input.handleScrollEvent(event(.changed, x: -4, time: 100.75))
        _ = input.handleScrollEvent(event(.cancelled, time: 100.8))
        require(phases == [.began, .changed, .ended, .began, .changed, .ended],
                "A gesture did not produce exactly one begin/change/end: \(phases)")
        require(deltas == [-180, 4], "Preparation or momentum injected a drag delta")
        let beforeVertical = phases.count
        _ = input.handleScrollEvent(event(.began, time: 101))
        _ = input.handleScrollEvent(event(.changed, x: 1, y: 30, time: 101.05))
        _ = input.handleScrollEvent(event(.ended, time: 101.1))
        require(phases.count == beforeVertical, "Vertical scrolling entered horizontal paging")

        // A legacy wheel timeout must not end a subsequent native gesture.
        _ = input.handleScrollEvent(event(nil, x: 4, time: 102))
        _ = input.handleScrollEvent(event(.began, time: 102.02))
        _ = input.handleScrollEvent(event(.changed, x: -4, time: 102.04))
        let beforeWait = phases.count
        try? await Task.sleep(for: .milliseconds(150))
        require(phases.count == beforeWait, "A stale wheel timeout ended a newer native gesture")
        _ = input.handleScrollEvent(event(.ended, time: 102.2))
        input.remove()
        print("PASS: native preparation, end/cancel, momentum, axis selection, one begin per gesture and wheel-timeout isolation")
    }
}
