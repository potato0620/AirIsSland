//
//  WelcomeView.swift
//  AirIsland
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            Image("logo2")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("Welcome to AirIsland")
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 24)

            Text("Music, reminders, and timers, right in your island.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 32)

            Spacer(minLength: 32)

            HStack {
                Image("UpstreamAttribution")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 164, height: 16)
                Spacer(minLength: 20)
                OnboardingActionButton("Get started", prominent: true) { onGetStarted?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, OnboardingLayout.inset)
        .padding(.top, 24)
        .padding(.bottom, OnboardingLayout.inset)
    }
}

#Preview {
    OnboardingView(onFinish: {}, onOpenSettings: {})
}
