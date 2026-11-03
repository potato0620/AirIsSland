import AppKit
import Defaults

/// Shared presentation feedback. This is the only application-owned haptic entry point.
@MainActor enum IslandHaptics {
    static func alignment() {
        guard Defaults[.enableHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
