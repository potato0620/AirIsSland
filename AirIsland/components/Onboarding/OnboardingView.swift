//
//  OnboardingView.swift
//  AirIsland
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingLayout {
    static let size = CGSize(width: 560, height: 560)
    static let inset: CGFloat = 32
}

enum OnboardingStep {
    case welcome
    case finished
}


struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        IslandWindowCoordinator.shared.firstLaunch = false
                        step = .finished
                    }
                }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: OnboardingLayout.size.width)
        .frame(maxHeight: .infinity)
        .background {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }

}

/// Use system controls so their material and interaction follow the running macOS.
struct OnboardingActionButton: View {
    let title: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    init(_ title: LocalizedStringKey, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    private var button: some View {
        Button(action: action) {
            Text(title).frame(minWidth: prominent ? 88 : 0)
        }
        .controlSize(.large)
    }

    var body: some View {
        if #available(macOS 26, *) {
            if prominent { button.buttonStyle(.glassProminent) }
            else { button.buttonStyle(.glass) }
        } else {
            if prominent { button.buttonStyle(.borderedProminent) }
            else { button.buttonStyle(.bordered) }
        }
    }
}
