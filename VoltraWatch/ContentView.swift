// ContentView.swift (Watch)
// Root view: shows ConnectedView when phone is reachable and VOLTRA is connected,
// otherwise shows WaitingForPhoneView.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: WatchTelemetryStore

    var body: some View {
        if store.isConnected && store.isConnectedToVoltra {
            ConnectedView()
        } else {
            WaitingForPhoneView()
        }
    }
}
