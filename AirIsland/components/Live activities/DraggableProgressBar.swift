//
//  DraggableProgressBar.swift
//  AirIsland
//

import SwiftUI

struct DraggableProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .fill(.white)
                        .frame(width: max(0, min(geo.size.width * value, geo.size.width)))
                        .opacity(value.isZero ? 0 : 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion)) {
                                isDragging = true
                            }
                            updateValue(gesture: gesture, in: geo)
                        }
                        .onEnded { _ in
                            withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion)) {
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
