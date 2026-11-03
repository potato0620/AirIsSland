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
        private var stamp: TimeInterval = 0
        private var fallbackEnd: DispatchWorkItem?
        init(action: @escaping (Double, Double, NSEvent.Phase) -> Void) { self.action = action }

        func install(on view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, let window = view.window, event.window === window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                if !event.momentumPhase.isEmpty { return self.horizontal == true ? nil : event }
                if event.phase == .began || (event.phase.isEmpty && event.timestamp - self.stamp > 0.22) {
                    self.horizontal = nil
                    self.action(0, 0, .began)
                }
                let dt = max(0.008, event.timestamp - self.stamp)
                self.stamp = event.timestamp
                if event.phase == .ended || event.phase == .cancelled {
                    let consumed = self.horizontal == true
                    if consumed { self.action(0, dt, .ended) }
                    return consumed ? nil : event
                }
                if self.horizontal == nil && max(abs(event.scrollingDeltaX), abs(event.scrollingDeltaY)) > 0.2 {
                    self.horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5
                    if self.horizontal == true { self.action(0, dt, .began) }
                }
                guard self.horizontal == true else { return event }
                let scale = event.hasPreciseScrollingDeltas ? 1.0 : 8.0
                self.action(Double(-event.scrollingDeltaX) * scale, dt, .changed)
                if event.phase.isEmpty {
                    self.fallbackEnd?.cancel()
                    let work = DispatchWorkItem { [weak self] in self?.action(0, 0, .ended) }
                    self.fallbackEnd = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
                }
                return nil
            }
        }
        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            fallbackEnd?.cancel()
        }
    }
}
