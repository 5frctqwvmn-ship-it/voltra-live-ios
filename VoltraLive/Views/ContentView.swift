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

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            // Build 31 fix: also route into the home screen when Demo Mode
            // is active. Previously only `ble.connectionState.isConnected`
            // gated the transition, so tapping the "Demo Mode" button on
            // ConnectView flipped demo.isActive=true but the user stayed
            // stuck on the connect screen \u2014 user reported this as
            // "Demo mode does nothing, I expected it to take me into the
            // app so I can show people what it does without a Voltra."
            if ble.connectionState.isConnected || demo.isActive {
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
