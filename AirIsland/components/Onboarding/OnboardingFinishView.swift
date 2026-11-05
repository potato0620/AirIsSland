//
//  OnboardingFinishView.swift
//  AirIsland
//
//  Created by Alexander on 2025-06-23.
//


import SwiftUI

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Switch cards")
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 16)

            Text("Expand the island, then swipe left or right with two fingers.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Spacer(minLength: 12)

            CardSwitchingDemo()
                .frame(height: 220)

            Text("You can also click the dots in the top-left corner.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Text("Open Settings from the island's right-click menu or the menu bar icon.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                OnboardingActionButton("Customize in Settings", action: onOpenSettings)

                OnboardingActionButton("Finish", prominent: true, action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, OnboardingLayout.inset)
        }
        .padding(.horizontal, OnboardingLayout.inset)
    }
}

#Preview {
    OnboardingView(step: .finished, onFinish: {}, onOpenSettings: {})
}
