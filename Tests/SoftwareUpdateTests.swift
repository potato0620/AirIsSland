import AppKit
import Sparkle

@main
struct SoftwareUpdateTests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let manager = SoftwareUpdateManager()
        // Creating either settings/menu entry must not start an update session.
        precondition(manager.canCheckForUpdates)
        precondition(manager.startupError == nil)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        try manager.updater(controller.updater, mayPerform: .updates)
        for check in [SPUUpdateCheck.updatesInBackground, .updateInformation] {
            do {
                try manager.updater(controller.updater, mayPerform: check)
                fatalError("An unsolicited update check was allowed")
            } catch {
                precondition((error as NSError).domain == "AirIsland.SoftwareUpdate")
            }
        }
        precondition(!controller.updater.sessionInProgress)
        print("Software update policy passed: manual checks allowed; background checks rejected.")
    }
}
