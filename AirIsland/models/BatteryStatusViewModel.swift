import Cocoa
import Foundation

/// A view model that manages and monitors the battery status of the device
@MainActor
class BatteryStatusViewModel: ObservableObject {

    @Published private(set) var levelBattery: Float = 0.0
    private var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            Task { @MainActor in self?.handleBatteryEvent(event) }
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            self.isPluggedIn = isPluggedIn
            self.statusText = isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
            self.notifyPowerStatusChange()

        case .batteryLevelChanged(let level):
            self.levelBattery = level

        case .lowPowerModeChanged(let isEnabled):
            self.isInLowPowerMode = isEnabled
            self.statusText = isEnabled ? String(localized: "Low Power: On") : String(localized: "Low Power: Off")
            self.notifyPowerStatusChange()

        case .isChargingChanged(let isCharging):
            self.isCharging = isCharging
            self.statusText =
                isCharging
                ? String(localized: "Charging battery")
                : (self.levelBattery < self.maxCapacity ? String(localized: "Not charging") : String(localized: "Full charge"))
            self.notifyPowerStatusChange()

        case .maxCapacityChanged(let capacity):
            self.maxCapacity = capacity

        case .error:
            break
        }
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        self.levelBattery = batteryInfo.currentCapacity
        self.isPluggedIn = batteryInfo.isPluggedIn
        self.isCharging = batteryInfo.isCharging
        self.isInLowPowerMode = batteryInfo.isInLowPowerMode
        self.maxCapacity = batteryInfo.maxCapacity
        self.statusText = batteryInfo.isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
    }

    /// Submit the event; only the scheduler determines its visibility and lifetime.
    private func notifyPowerStatusChange() {
        ActivityCoordinator.shared.post(.power)
    }

    deinit {
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
