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

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            if ble.connectionState.isConnected {
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
    }
}

#Preview {
    ContentView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
        .environmentObject(LoggingStore())
}
