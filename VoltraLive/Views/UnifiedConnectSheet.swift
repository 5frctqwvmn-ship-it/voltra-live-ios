// UnifiedConnectSheet.swift
//
// Build 40 "Connect unify".
//
// Single discovery+selection sheet that replaces the old split flow:
//
//   OLD: ConnectView had a big "Connect to VOLTRA" button (auto-connect to
//        first Voltra found) AND a separate "Pair 2 Voltras (beta)" link
//        that pushed to DualConnectView. The user couldn't choose WHICH
//        Voltra was used in single-device mode \u2014 they had to guess which
//        one the auto-scan would grab first.
//
//   NEW: Tap "Connect to VOLTRA" \u2192 this sheet opens, scans, lists every
//        Voltra it sees. Tap one to select; tap a second to multi-select
//        for dual mode. Bottom button reads:
//          \u2022 "Connect" when 1 selected     \u2192 single-device path (ble.connectKnown)
//          \u2022 "Connect Both" when 2 selected \u2192 dual path (mdm.connectBoth)
//        Selecting a third row replaces the oldest selection.
//
// Once the sheet kicks off the connect, it dismisses immediately. The
// connection state itself is observed by ContentView, which flips to
// LoggingHomeView as soon as either the legacy single-device manager OR
// MultiDeviceManager has at least one slot connected.
//
// Sacred files (VoltraProtocol, TelemetryExtractor, PacketParser,
// FrameAssembler) are NOT touched by this build.

import SwiftUI
import CoreBluetooth

struct UnifiedConnectSheet: View {

    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var mdm: MultiDeviceManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scanner = VoltraDiscoveryScanner()

    /// Selection order matters: first tap becomes Left, second tap Right.
    /// If the user taps a third row, we drop the OLDEST selection (FIFO)
    /// so the newest tap is always honored.
    @State private var selectedIDs: [UUID] = []

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    instructions
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Cancel")
                }
                .foregroundColor(VoltraColor.accent)
            }
            Spacer()
            Text("Select VOLTRA")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            Spacer()
            // Symmetry spacer to keep the title visually centered.
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }

    // MARK: - Instructions / scan-state line

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(instructionText)
                .font(.system(size: 14))
                .foregroundColor(VoltraColor.text)
            HStack(spacing: 8) {
                Circle()
                    .fill(scannerDotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: scannerDotColor.opacity(0.5), radius: 4)
                Text(scanStateLabel)
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }
        }
    }

    private var instructionText: String {
        switch selectedIDs.count {
        case 0: return "Tap a Voltra to use it. Tap a second to use both at once."
        case 1: return "Tap Connect to use this one, or tap a second Voltra for dual mode."
        default: return "Two Voltras selected. They'll be paired as Left + Right."
        }
    }

    private var scannerDotColor: Color {
        switch scanner.state {
        case .scanning: return VoltraColor.accent
        case .bluetoothOff, .unauthorized, .unsupported: return VoltraColor.warn
        default: return VoltraColor.textFaint
        }
    }

    private var scanStateLabel: String {
        switch scanner.state {
        case .idle:         return "Idle"
        case .scanning:     return "Scanning for Voltras\u{2026}"
        case .stopped:      return "Stopped"
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission required"
        case .unsupported:  return "Bluetooth not supported on this device"
        }
    }

    // MARK: - Discovered list

    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if scanner.discovered.isEmpty {
                emptyState
            } else {
                ForEach(Array(scanner.discovered.enumerated()), id: \.element.id) { idx, d in
                    discoveredRow(d, index: idx)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundColor(VoltraColor.textFaint)
            Text("Looking for nearby Voltras\u{2026}")
                .font(.system(size: 14))
                .foregroundColor(VoltraColor.textDim)
            Text("Make sure the device is powered on and within range.")
                .font(.system(size: 12))
                .foregroundColor(VoltraColor.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func discoveredRow(_ d: VoltraDiscoveryScanner.Discovered, index: Int) -> some View {
        let selectionIndex = selectedIDs.firstIndex(of: d.id)
        let isSelected = selectionIndex != nil
        // Slot tag: first selection = Left, second = Right.
        let slotTag: String? = {
            guard let i = selectionIndex else { return nil }
            return i == 0 ? "LEFT" : "RIGHT"
        }()

        return Button {
            toggleSelection(d.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? VoltraColor.accent : VoltraColor.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(d.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(VoltraColor.text)
                        if let tag = slotTag {
                            Text(tag)
                                .font(.system(size: 10, weight: .heavy))
                                .kerning(0.6)
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(VoltraColor.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(d.rssi) dBm")
                        .font(.system(size: 11))
                        .foregroundColor(VoltraColor.textDim)
                }
                Spacer()
                rssiPill(d.rssi)
            }
            .padding(14)
            .background(isSelected ? VoltraColor.bgElev : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? VoltraColor.accent : VoltraColor.border,
                            lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func rssiPill(_ rssi: Int) -> some View {
        let color: Color = {
            if rssi > -60 { return VoltraColor.accent }
            if rssi > -75 { return VoltraColor.warn }
            return VoltraColor.textFaint
        }()
        return Image(systemName: "wifi")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(color)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                performConnect()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(connectButtonText)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(connectButtonEnabled ? VoltraColor.accent : VoltraColor.textFaint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(connectButtonEnabled ? 1.0 : 0.6)
            }
            .disabled(!connectButtonEnabled)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }

    private var connectButtonEnabled: Bool {
        !selectedIDs.isEmpty
    }

    private var connectButtonText: String {
        switch selectedIDs.count {
        case 2:  return "Connect Both"
        case 1:  return "Connect"
        default: return "Select a Voltra"
        }
    }

    // MARK: - Actions

    /// FIFO: tapping an already-selected row unselects it; tapping a new row
    /// appends, and if we'd exceed 2 we drop the oldest first.
    private func toggleSelection(_ id: UUID) {
        if let i = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: i)
            return
        }
        selectedIDs.append(id)
        if selectedIDs.count > 2 {
            selectedIDs.removeFirst(selectedIDs.count - 2)
        }
    }

    private func performConnect() {
        let picks = selectedIDs.compactMap { id -> VoltraDiscoveryScanner.Discovered? in
            scanner.discovered.first(where: { $0.id == id })
        }
        guard !picks.isEmpty else { return }

        if picks.count >= 2 {
            // Dual: assign first tap = Left, second tap = Right.
            mdm.connectBoth(left: picks[0], right: picks[1])
        } else {
            // Single: route through the legacy single-device manager so the
            // existing telemetry pipeline (LoggingStore wiring in
            // VoltraLiveApp) keeps working unchanged. Stop the scanner first
            // so its CBCentral stops competing for the radio while
            // VoltraBLEManager.connectKnown brings up its own connection.
            scanner.stop()
            ble.connectKnown(identifier: picks[0].id, fallback: picks[0].peripheral)
        }
        dismiss()
    }
}

#Preview {
    UnifiedConnectSheet()
        .environmentObject(VoltraBLEManager())
        .environmentObject(MultiDeviceManager())
}
