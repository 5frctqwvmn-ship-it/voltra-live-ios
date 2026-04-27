// ConnectView.swift
// Logo, big Connect button, About section, Bluetooth permission hint.
// Mirrors the connect screen from styles.css / app.js.

import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var demo: DemoController

    // v0.4.8 build 30: optional dual-Voltra entry. Off by default.
    @State private var showDualConnect: Bool = false

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
                .navigationDestination(isPresented: $showDualConnect) {
                    DualConnectView()
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

                // Connect button
                Button {
                    ble.startScan()
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

                // Build 31: Demo Mode is now a primary, full-width call to
                // action under Connect. User reported the previous secondary
                // text-styled button was missable and "Demo mode does
                // nothing" \u2014 actually it was working but never visibly
                // routed away from this screen (ContentView didn't honor
                // demo.isActive). Both fixed now.
                Button {
                    guard let handler = DemoTelemetryBridge.shared.handler else { return }
                    demo.note(.buttonTap(label: "Skip - Try Demo", screen: "Connect"))
                    demo.enter(source: .prePair, onTelemetry: handler)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle")
                        Text("Skip - Try Demo")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(VoltraColor.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VoltraColor.accent, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .opacity(demo.isActive ? 0.4 : 1.0)
                .disabled(demo.isActive)
                .accessibilityLabel("Skip pairing and enter Demo Mode")

                // v0.4.8 build 30: dual-Voltra opt-in. Tiny tertiary link
                // — single-device flow above is unchanged.
                Button {
                    showDualConnect = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.split.2x1")
                        Text("Pair 2 Voltras (beta)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VoltraColor.textDim)
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
