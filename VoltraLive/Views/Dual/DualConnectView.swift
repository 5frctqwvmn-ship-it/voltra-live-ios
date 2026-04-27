// DualConnectView.swift
//
// Pairing UI for two Voltras at once. Owns a VoltraDiscoveryScanner,
// renders the discovered list, and offers three actions:
//
//   • Connect Left   — tap a discovered row, then tap "Connect Left"
//   • Connect Right  — tap a discovered row, then tap "Connect Right"
//   • Auto-Pair Both — picks the two strongest RSSI hits and assigns
//                      Left = strongest, Right = second-strongest
//
// This view is REACHED from ConnectView via a "Pair 2 Voltras" link.
// It is NOT the default — single-device pairing flow stays untouched.
//
// Once the user has paired both (or one + cancels), DualCaptureView
// becomes available via a "Open Dual Capture" button at the bottom.
//
// Build 30 / dual-Voltra. Reads MultiDeviceManager from the environment.

import SwiftUI

struct DualConnectView: View {
    @EnvironmentObject var mdm: MultiDeviceManager
    @StateObject private var scanner = VoltraDiscoveryScanner()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID? = nil
    @State private var showCapture: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    actionRow
                    Divider().background(VoltraColor.border)
                    discoveredList
                }
                .padding(20)
            }

            Spacer(minLength: 0)

            footer
        }
        .background(VoltraColor.bg)
        .preferredColorScheme(.dark)
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
        .navigationDestination(isPresented: $showCapture) {
            DualCaptureView()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(VoltraColor.accent)
            }
            Spacer()
            Text("Pair 2 Voltras")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            Spacer()
            // Symmetry spacer — keeps the title centered.
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            slotRow(label: "Left",  manager: mdm.left,  slot: .left)
            slotRow(label: "Right", manager: mdm.right, slot: .right)

            if case .errorReconnecting(_, let msg) = mdm.state {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.warn)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func slotRow(label: String, manager: VoltraBLEManager, slot: DeviceSlot) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(manager.connectionState.isConnected ? VoltraColor.accent : VoltraColor.textFaint)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(VoltraColor.text)
                .frame(width: 50, alignment: .leading)
            Text(slotStatus(manager: manager))
                .font(.system(size: 13))
                .foregroundColor(VoltraColor.textDim)
                .lineLimit(1)
            Spacer()
            if manager.connectionState.isConnected {
                Button("Disconnect") { mdm.disconnect(slot: slot) }
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.warn)
            }
        }
    }

    private func slotStatus(manager: VoltraBLEManager) -> String {
        switch manager.connectionState {
        case .scanning:    return "Scanning…"
        case .connecting:  return "Connecting…"
        case .connected:   return "Connected"
        case .disconnected(let reason):
            return reason ?? "Disconnected"
        case .idle:        return "Idle"
        }
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            // Auto-pair: pick the two strongest discoveries.
            // Build 39: shortened label so it fits comfortably; the
            // "top 2 by RSSI" detail moves to the help line below.
            Button {
                autoPairBoth()
            } label: {
                buttonLabel(text: "Auto-Pair Both",
                            icon: "antenna.radiowaves.left.and.right",
                            primary: true)
            }
            .disabled(scanner.discovered.count < 2 || (mdm.left.connectionState.isConnected && mdm.right.connectionState.isConnected))

            HStack(spacing: 10) {
                Button {
                    if let d = currentSelection { mdm.connect(slot: .left, discovered: d) }
                } label: {
                    buttonLabel(text: "Connect Left", icon: "1.circle.fill", primary: false)
                }
                .disabled(currentSelection == nil)

                Button {
                    if let d = currentSelection { mdm.connect(slot: .right, discovered: d) }
                } label: {
                    buttonLabel(text: "Connect Right", icon: "2.circle.fill", primary: false)
                }
                .disabled(currentSelection == nil)
            }

            Text(currentSelection == nil
                 ? "Tap a device below, then choose a side."
                 : "Selected: \(currentSelection?.name ?? "—")")
                .font(.system(size: 12))
                .foregroundColor(VoltraColor.textDim)
        }
    }

    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Discovered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text(scanStateLabel)
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }

            if scanner.discovered.isEmpty {
                Text("Scanning for VOLTRA devices…")
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(scanner.discovered) { d in
                    discoveredRow(d)
                }
            }
        }
    }

    private func discoveredRow(_ d: VoltraDiscoveryScanner.Discovered) -> some View {
        let isSelected = (selectedID == d.id)
        let leftPaired  = (mdm.left.connectionState.isConnected)
        let rightPaired = (mdm.right.connectionState.isConnected)
        let inUse: String? = {
            // Best-effort: we don't currently expose the connected peripheral
            // identifier from VoltraBLEManager, so we can only flag generic
            // "in use" status here. Later refinement: pull connected ID.
            _ = leftPaired; _ = rightPaired
            return nil
        }()

        return Button {
            selectedID = d.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? VoltraColor.accent : VoltraColor.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    Text("\(d.rssi) dBm" + (inUse.map { " • \($0)" } ?? ""))
                        .font(.system(size: 11))
                        .foregroundColor(VoltraColor.textDim)
                }
                Spacer()
                rssiPill(d.rssi)
            }
            .padding(12)
            .background(isSelected ? VoltraColor.bgElev : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? VoltraColor.accent : VoltraColor.border,
                            lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func rssiPill(_ rssi: Int) -> some View {
        // -50 dBm -> excellent; -80 dBm -> weak.
        let color: Color = {
            if rssi > -60 { return VoltraColor.accent }
            if rssi > -75 { return VoltraColor.warn }
            return VoltraColor.textFaint
        }()
        return Image(systemName: "wifi")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
    }

    /// Build 39: pinned to a fixed minHeight so all three action buttons
    /// (Auto-Pair, Connect Left, Connect Right) match in height regardless
    /// of label length. User noted in b30 testing that the buttons looked
    /// uneven — the side-by-side pair was a couple of pixels shorter than
    /// the primary above them when text auto-sized.
    private func buttonLabel(text: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 8)
        .foregroundColor(primary ? .black : VoltraColor.text)
        .background(primary ? VoltraColor.accent : VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(primary ? Color.clear : VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(primary ? 1.0 : 0.95)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if mdm.left.connectionState.isConnected || mdm.right.connectionState.isConnected {
                Button {
                    showCapture = true
                } label: {
                    Text("Open Dual Capture")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(VoltraColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private var currentSelection: VoltraDiscoveryScanner.Discovered? {
        guard let id = selectedID else { return nil }
        return scanner.discovered.first(where: { $0.id == id })
    }

    private var scanStateLabel: String {
        switch scanner.state {
        case .idle:         return "Idle"
        case .scanning:     return "Scanning"
        case .stopped:      return "Stopped"
        case .bluetoothOff: return "Bluetooth off"
        case .unauthorized: return "Permission denied"
        case .unsupported:  return "Unsupported"
        }
    }

    private func autoPairBoth() {
        // Sort by RSSI (strongest first), pick top 2 distinct.
        let sorted = scanner.discovered.sorted { $0.rssi > $1.rssi }
        guard sorted.count >= 2 else { return }
        mdm.connectBoth(left: sorted[0], right: sorted[1])
    }
}

#Preview {
    NavigationStack {
        DualConnectView()
            .environmentObject(MultiDeviceManager())
    }
}
