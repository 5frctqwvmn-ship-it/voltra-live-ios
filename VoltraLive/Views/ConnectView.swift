// ConnectView.swift
// Logo, big Connect button, About section, Bluetooth permission hint.
// Mirrors the connect screen from styles.css / app.js.

import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var demo: DemoController
    @EnvironmentObject var mdm: MultiDeviceManager

    // Build 40: single unified connect sheet replaces both the
    // auto-connect-first-Voltra path and the separate "Pair 2 Voltras"
    // page. Tap Connect -> sheet appears -> user picks 1 or 2 Voltras.
    @State private var showConnectSheet: Bool = false

    private var statusMessage: String {
        switch ble.connectionState {
        case .scanning:    return "Scanning for VOLTRA…"
        case .connecting:  return "Connecting…"
        case .disconnected(let reason):
            return reason.map { "Disconnected: \($0)" } ?? "Disconnected"
        default:           return "Ready to connect"
        }
    }

    private var isConnecting: Bool {
        switch ble.connectionState {
        case .scanning, .connecting: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            content
                .sheet(isPresented: $showConnectSheet) {
                    UnifiedConnectSheet()
                        .environmentObject(ble)
                        .environmentObject(mdm)
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(VoltraColor.accent)
                        .font(.system(size: 18, weight: .bold))
                    Text("VOLTRA")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    Text("Live")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(VoltraColor.textDim)
                }
                Spacer()
                // Status dot
                HStack(spacing: 8) {
                    Circle()
                        .fill(VoltraColor.textFaint)
                        .frame(width: 10, height: 10)
                    Text("Disconnected")
                        .font(.system(size: 13))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(VoltraColor.border)
                    .frame(height: 1)
            }

            Spacer()

            // Connect card
            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(VoltraColor.accent)

                    Text("VOLTRA Live")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(VoltraColor.text)

                    Text("Real-time workout telemetry for your VOLTRA device.\nProp your iPad on the rack and start lifting.")
                        .font(.system(size: 15))
                        .foregroundColor(VoltraColor.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Connect button - opens the unified discovery sheet so
                // the user can see every nearby Voltra and pick one (single
                // mode) or two (dual mode). No more guessing which device
                // the auto-scan grabs first.
                Button {
                    showConnectSheet = true
                } label: {
                    HStack(spacing: 10) {
                        if isConnecting {
                            ProgressView()
                                .tint(Color.black)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(isConnecting ? statusMessage : "Connect to VOLTRA")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 36)
                    .frame(minWidth: 240)
                    .background(VoltraColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isConnecting)
                .scaleEffect(isConnecting ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.1), value: isConnecting)

                // About / device info
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Connects to VOLTRA BLE service")
                        Text("• Read-only — never sends control commands")
                        Text("• Handshake keeps connection alive")
                        Text("• iOS 17+ required")
                        Text("• Install via AltStore (sideload, no Apple ID required beyond free tier)")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("About this app")
                        .font(.system(size: 14))
                        .foregroundColor(VoltraColor.text)
                }
                .tint(VoltraColor.accent)

                // Bluetooth permission hint
                if case .idle = ble.connectionState {
                    Text("Tip: prop the iPad on your rack, then tap Connect.")
                        .font(.system(size: 13))
                        .foregroundColor(VoltraColor.warn)
                        .multilineTextAlignment(.center)
                }

                // Build 40: removed "Pair 2 Voltras" — dual is folded into
                // the unified Connect sheet above (multi-select to pair two).
                //
                // Build 45: restored Demo mode entry on this screen. Removing
                // it in b40 made it impossible to demo the app without a
                // physical Voltra in BLE range (TestFlight reviewers, sales).
                // The button uses the standard DemoModeButton component which
                // boots the synthetic telemetry bridge.
                Divider()
                    .background(VoltraColor.border)
                    .padding(.vertical, 4)

                if !demo.isActive {
                    HStack {
                        Spacer()
                        DemoModeButton(source: .prePair) {
                            guard let handler = DemoTelemetryBridge.shared.handler else { return }
                            demo.note(.buttonTap(label: "Demo Mode (pre-pair)", screen: "Connect"))
                            demo.enter(source: .prePair, onTelemetry: handler)
                        }
                        Spacer()
                    }
                }
            }
            .padding(40)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 32, x: 0, y: 8)
            .padding(.horizontal, 24)
            .frame(maxWidth: 560)

            Spacer()
        }
        .background(VoltraColor.bg)
    }
}

#Preview {
    ConnectView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(DemoController())
        .environmentObject(MultiDeviceManager())
}
