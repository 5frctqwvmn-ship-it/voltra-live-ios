// ContentView.swift
// Root view.
//
// b67 V4.3 (Bug 01) — cold-launch routing flip.
//
//   OLD (b40–b66): ConnectView was the cold-launch landing surface;
//   you only saw LoggingHomeView once a Voltra was paired or Demo
//   was active. That meant a returning user with no Voltra in range
//   (battery, BT off, left at the gym) was forced through a pair
//   wall before they could see their workout history or even pick a
//   day.
//
//   NEW: LoggingHomeView is the unconditional cold-launch screen.
//   Voltra pairing is a foreground gesture surfaced via the
//   PairingCoordinator (greyed L/R pill tap in VoltraUnitHeader →
//   UnifiedConnectSheet). ConnectView is reserved for the legacy
//   onboarding deeplink only and is no longer wired here.

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            LoggingHomeView()
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        }
        .preferredColorScheme(.dark)
        .tint(VoltraColor.accent)
        .buildBadgeOverlay()
        // b66 V4.2: page-name badge.
        .pageBadge("ContentView")
    }
}

#Preview {
    ContentView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
        .environmentObject(LoggingStore())
        .environmentObject(DemoController())
        .environmentObject(MultiDeviceManager())
        .environmentObject(PairingCoordinator())
}
