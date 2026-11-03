//
//  InlineHUDs.swift
//  AirIsland
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI

struct InlineHUD: View {
    @EnvironmentObject var vm: IslandViewModel
    let type: IslandActivityKind
    @Binding var value: Double
    let icon: String
    @Binding var hoverAnimation: Bool
    private var hudHeight: CGFloat { max(24, vm.closedNotchSize.height) }
    private var sideWidth: CGFloat {
        let budget = (vm.expandedNotchSize.width - 2 * cornerRadiusInsets.closed.bottom - vm.closedNotchSize.width - 16) / 2
        return min(100 - (hoverAnimation ? 0 : 12), max(0, budget))
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Group {
                    switch (type) {
                        case .volume:
                            if icon.isEmpty {
                                Image(systemName: SpeakerSymbol(CGFloat(value)))
                                    .contentTransition(.interpolate)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            } else {
                                Image(systemName: icon)
                                    .contentTransition(.interpolate)
                                    .opacity(value.isZero ? 0.6 : 1)
                                    .scaleEffect(value.isZero ? 0.85 : 1)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            }
                        case .brightness:
                            Image(systemName: BrightnessSymbol(CGFloat(value)))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .leading)
                        case .backlight:
                            Image(systemName: value > 0.5 ? "light.max" : "light.min")
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .leading)
                        case .mic:
                            Image(systemName: "mic")
                                .symbolRenderingMode(.hierarchical)
                                .symbolVariant(value > 0 ? .none : .slash)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .leading)
                        case .music, .musicChange, .power, .timer, .timerFinished, .reminders:
                            EmptyView()
                    }
                }
                .foregroundStyle(.white)
                .symbolVariant(.fill)
                
                Text(Type2Name(type))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
            }
            .frame(width: sideWidth, height: max(0, hudHeight - (hoverAnimation ? 0 : 12)), alignment: .leading)
            
            Color.clear
                .frame(width: max(0, vm.closedNotchSize.width))
            
            HStack {
                if (type == .mic) {
                    Text(value.isZero ? "muted" : "unmuted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else {
                        HStack {
                        DraggableProgressBar(value: Binding(get: { CGFloat(value) }, set: { value = Double($0) }), onChange: { v in
                            if type == .volume {
                                VolumeManager.shared.setAbsolute(Float32(v))
                            } else if type == .brightness {
                                BrightnessManager.shared.setAbsolute(value: Float32(v))
                            } else if type == .backlight {
                                KeyboardBacklightManager.shared.setAbsolute(value: Float32(v))
                            }
                        })
                        if (type == .volume && value.isZero) {
                            Text("muted")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text("\(Int(value * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .frame(width: sideWidth, height: max(0, hudHeight - (hoverAnimation ? 0 : 12)), alignment: .trailing)
        }
        .frame(height: max(0, hudHeight + (hoverAnimation ? 8 : 0)), alignment: .center)
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0...0.6:
                return "sun.min"
            case 0.6...1:
                return "sun.max"
            default:
                return "sun.min"
        }
    }
    
    func Type2Name(_ type: IslandActivityKind) -> LocalizedStringKey {
        switch(type) {
            case .volume:
                return "Volume"
            case .brightness:
                return "Brightness"
            case .backlight:
                return "Backlight"
            case .mic:
                return "Mic"
            case .music, .musicChange, .power, .timer, .timerFinished, .reminders:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .brightness, value: .constant(0.4), icon: "", hoverAnimation: .constant(false))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(IslandViewModel())
}
