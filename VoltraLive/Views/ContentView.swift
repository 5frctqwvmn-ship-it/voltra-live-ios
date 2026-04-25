// ContentView.swift
// Root view: shows ConnectView when not connected, DashboardView when connected.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            if ble.connectionState.isConnected {
                DashboardView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else {
                ConnectView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .preferredColorScheme(.dark)
        .tint(VoltraColor.accent)
    }
}

#Preview {
    ContentView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
}
