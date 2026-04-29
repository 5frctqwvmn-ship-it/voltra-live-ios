// ContentView.swift
// Root view: ConnectView when not connected, LoggingHomeView when connected.
// The v0.1 DashboardView is still reachable from within LoggingHomeView via
// "Open live dashboard" — we just don't make it the post-connect default
// anymore now that v0.2 introduces the logging flow.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var demo: DemoController
    /// Build 40: also gate routing on MultiDeviceManager so dual-pair
    /// connections also transition into LoggingHomeView (no separate
    /// Dual Capture screen anymore).
    @EnvironmentObject var mdm: MultiDeviceManager

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            // Build 31 fix: also route into the home screen when Demo Mode
            // is active. Previously only `ble.connectionState.isConnected`
            // gated the transition.
            // Build 40: also route when MultiDeviceManager has any slot
            // connected (single or dual via the unified Connect sheet).
            if shouldShowHome {
                LoggingHomeView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else {
                ConnectView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .preferredColorScheme(.dark)
        .tint(VoltraColor.accent)
        .buildBadgeOverlay()
        // b66 V4.2: page-name badge.
        .pageBadge("ContentView")
        }

    private var shouldShowHome: Bool {
        if ble.connectionState.isConnected { return true }
        if demo.isActive { return true }
        if mdm.left.connectionState.isConnected { return true }
        if mdm.right.connectionState.isConnected { return true }
        return false
    }
}

#Preview {
    ContentView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
        .environmentObject(LoggingStore())
        .environmentObject(DemoController())
        .environmentObject(MultiDeviceManager())
}
