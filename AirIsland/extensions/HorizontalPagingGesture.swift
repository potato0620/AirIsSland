import AppKit
import SwiftUI

/// Local trackpad events retain native phase/momentum boundaries. No global event tap or permission.
struct HorizontalPagingGesture: NSViewRepresentable {
    var action: (Double, Double, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor final class Coordinator {
        var action: (Double, Double, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var horizontal: Bool?
        private var gestureActive = false
        private var stamp: TimeInterval = 0
        private var fallbackEnd: DispatchWorkItem?
        init(action: @escaping (Double, Double, NSEvent.Phase) -> Void) { self.action = action }

        func install(on view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, let window = view.window, event.window === window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                return self.handleScrollEvent(event)
            }
        }

        func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
            if !event.momentumPhase.isEmpty { return horizontal == true ? nil : event }
            // Resting fingers can produce mayBegin after the previous return has
            // finished. It carries no drag and must never reuse the old axis/raw distance.
            if event.phase.contains(.mayBegin) { return event }
            if event.phase.contains(.began)
                || (event.phase.isEmpty && (!gestureActive || event.timestamp - stamp > 0.22)) {
                fallbackEnd?.cancel()
                fallbackEnd = nil
                horizontal = nil
                gestureActive = true
            }
            let dt = max(0.008, event.timestamp - stamp)
            stamp = event.timestamp
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                fallbackEnd?.cancel()
                fallbackEnd = nil
                if gestureActive && horizontal == true { action(0, dt, .ended) }
                gestureActive = false
                return horizontal == true ? nil : event
            }
            guard gestureActive else { return event }
            guard event.phase.isEmpty || event.phase.contains(.began) || event.phase.contains(.changed)
                else { return horizontal == true ? nil : event }
            if horizontal == nil && max(abs(event.scrollingDeltaX), abs(event.scrollingDeltaY)) > 0.2 {
                horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5
                if horizontal == true { action(0, dt, .began) }
            }
            guard horizontal == true else { return event }
            let scale = event.hasPreciseScrollingDeltas ? 1.0 : 8.0
            action(Double(-event.scrollingDeltaX) * scale, dt, .changed)
            if event.phase.isEmpty {
                fallbackEnd?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.gestureActive else { return }
                    self.gestureActive = false
                    self.action(0, 0, .ended)
                }
                fallbackEnd = work
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
            }
            return nil
        }
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            fallbackEnd?.cancel()
            fallbackEnd = nil
            gestureActive = false
            horizontal = nil
        }
    }
}
