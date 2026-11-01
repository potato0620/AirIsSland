//
//  IslandHeader.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct IslandHeader: View {
    @EnvironmentObject var vm: IslandViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = IslandWindowCoordinator.shared
    @ObservedObject private var activities = ActivityCoordinator.shared
    private var presentation: IslandPresentation { IslandPresentation(activity: activities.current) }
    @Default(.shelfEnabled) private var shelfEnabled
    @StateObject var tvm = ShelfStateViewModel.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if shelfEnabled && (!tvm.isEmpty || coordinator.currentView == .shelf) {
                    TabSelectionView()
                } else if shelfEnabled && vm.notchState == .open {
                    Button {
                        withAnimation(.smooth) { coordinator.currentView = .shelf }
                    } label: {
                        Image(systemName: "tray").frame(width: 30, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("Shelf")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            // Reserve space for the camera without painting a separate notch-shaped patch.
            Color.clear.frame(width: vm.closedNotchSize.width)

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if let feedback = presentation.feedback {
                        OpenNotchHUD(type: feedback.kind, value: Binding(get: { activities.current?.value ?? 0 }, set: { activities.updateFeedbackValue($0) }), icon: feedback.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            IslandBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }


}

#Preview {
    IslandHeader().environmentObject(IslandViewModel())
}
