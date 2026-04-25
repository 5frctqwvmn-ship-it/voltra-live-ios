// WaitingForPhoneView.swift
// Shown when WCSession is unreachable or the phone isn't connected to VOLTRA.
// Does not crash — just displays a clear placeholder.

import SwiftUI

struct WaitingForPhoneView: View {
    @EnvironmentObject var store: WatchTelemetryStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: store.isConnected ? "antenna.radiowaves.left.and.right.slash"
                                                : "iphone.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(store.isConnected ? "VOLTRA Offline" : "Phone Disconnected")
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(store.isConnected
                    ? "Open VOLTRA Live\non your iPhone"
                    : "Open VOLTRA Live\non your iPhone")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color(red: 0.039, green: 0.055, blue: 0.047), for: .navigation)
    }
}
