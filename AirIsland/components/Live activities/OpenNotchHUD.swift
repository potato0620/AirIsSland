//
//  OpenNotchHUD.swift
//  AirIsland
//
//  Created by Alexander on 2024-11-23.
//

import SwiftUI
import Defaults

struct OpenNotchHUD: View {
    @EnvironmentObject var vm: IslandViewModel
    let type: IslandActivityKind
    @Binding var value: Double
    let icon: String
    @Default(.showHUDPercentage) var showPercentage
    
    var body: some View {
        HStack(spacing: 4) {
            // Icon
            Group {
                switch type {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: SpeakerSymbol(CGFloat(value)))
                            .contentTransition(.interpolate)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                    }
                case .brightness:
                    Image(systemName: "sun.max.fill")
                        .contentTransition(.symbolEffect)
                case .backlight:
                    Image(systemName: value > 0.5 ? "light.max" : "light.min")
                        .contentTransition(.interpolate)
                case .mic:
                    Image(systemName: "mic")
                        .symbolVariant(value > 0 ? .none : .slash)
                        .contentTransition(.interpolate)
                default:
                    EmptyView()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 16, alignment: .center)
            
            // Slider or Status Text
            if type != .mic {
                DraggableProgressBar(value: Binding(get: { CGFloat(value) }, set: { value = Double($0) }), onChange: { newVal in
                     updateSystemValue(newVal)
                })
                .frame(width: showPercentage ? 36 : 68) // Fixed width for consistency
            } else {
                Text(value > 0 ? "Unmuted" : "Muted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            
            // Percentage Text
            if type != .mic && showPercentage {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0: return "speaker.slash"
            case 0...0.33: return "speaker.wave.1"
            case 0.33...0.66: return "speaker.wave.2"
            default: return "speaker.wave.3"
        }
    }
    
    func updateSystemValue(_ newVal: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newVal))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newVal))
        case .backlight:
            KeyboardBacklightManager.shared.setAbsolute(value: Float32(newVal))
        default:
            break
        }
    }
}

#Preview {
    OpenNotchHUD(type: .volume, value: .constant(0.5), icon: "")
        .environmentObject(IslandViewModel())
        .padding()
        .background(Color.gray)
}
