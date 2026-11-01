//
//  DraggableProgressBar.swift
//  AirIsland
//

import SwiftUI
import Defaults

struct DraggableProgressBar: View {
    @Binding var value: CGFloat
    var onChange: ((CGFloat) -> Void)? = nil
    
    @State private var isDragging = false
    
    var body: some View {
        VStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.tertiary)
                    Capsule()
                        .fill(
                            Defaults[.enableGradient] ?
                                AnyShapeStyle(LinearGradient(
                                    colors: Defaults[.systemEventIndicatorUseAccent] ?
                                        [Color.effectiveAccent, Color.effectiveAccent.ensureMinimumBrightness(factor: 0.2)] :
                                        [Color.white, Color.white.opacity(0.2)],
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )) :
                                AnyShapeStyle(Defaults[.systemEventIndicatorUseAccent] ? Color.effectiveAccent : Color.white)
                        )
                        .frame(width: max(0, min(geo.size.width * value, geo.size.width)))
                        .shadow(color: Defaults[.systemEventIndicatorShadow] ?
                            (Defaults[.systemEventIndicatorUseAccent] ?
                                Color.effectiveAccent.ensureMinimumBrightness(factor: 0.7) :
                                Color.white) :
                            Color.clear,
                            radius: 8, x: 3)
                        .opacity(value.isZero ? 0 : 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = true
                                updateValue(gesture: gesture, in: geo)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: isDragging ? 8 : 5)
        }
    }
    
    private func updateValue(gesture: DragGesture.Value, in geometry: GeometryProxy) {
        guard geometry.size.width > 0 else { return }
        let dragPosition = gesture.location.x
        let newValue = dragPosition / geometry.size.width
        
        value = max(0, min(newValue, 1))
        onChange?(value)
    }
}
