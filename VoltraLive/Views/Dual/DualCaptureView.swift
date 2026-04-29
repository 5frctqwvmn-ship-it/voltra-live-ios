// DualCaptureView.swift
//
// Minimal post-pair view for the dual-Voltra flow. Shows:
//
//   • Mode toggle: Independent (default) | Combined
//   • Two stat cards: Left + Right with live force, reps, phase, RSSI
//   • In Combined mode: a third "Combined" card showing the merged
//     virtual-twin reading
//   • LOAD / UNLOAD action row (broadcast in Combined, per-side in
//     Independent — this build just routes both buttons to MDM.load /
//     MDM.unload with no target, which means "both" in Combined and
//     a no-op selector in Independent. The selector UI for Independent
//     mode lands in build 31.)
//
// This view does NOT yet wire telemetry into LoggingStore. That is a
// build 31 task — single-device LoggingStore writes still work because
// the existing single-Voltra connect flow is unchanged.
//
// Build 30 / dual-Voltra.

import SwiftUI

@MainActor
final class DualCaptureViewModel: ObservableObject {
    @Published var leftTelem:  Telemetry? = nil
    @Published var rightTelem: Telemetry? = nil
    @Published var combined:   CombinedTelemetry? = nil
}

struct DualCaptureView: View {
    @EnvironmentObject var mdm: MultiDeviceManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = DualCaptureViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    modeToggle
                    deviceCard(label: "Left",  manager: mdm.left,  telem: vm.leftTelem)
                    deviceCard(label: "Right", manager: mdm.right, telem: vm.rightTelem)
                    if mdm.mode == .combined, let c = vm.combined {
                        combinedCard(c)
                    }
                    actionRow
                }
                .padding(20)
            }
        }
        .background(VoltraColor.bg)
        .preferredColorScheme(.dark)
        .onAppear { wireTelemetry() }
        // b66 V4.2: page-name badge.
        .pageBadge("DualCaptureView")
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
            Text("Dual Capture")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            Spacer()
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 8) {
            ForEach(DualMode.allCases, id: \.self) { m in
                Button {
                    mdm.mode = m
                } label: {
                    Text(m.label)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(mdm.mode == m ? .black : VoltraColor.text)
                        .background(mdm.mode == m ? VoltraColor.accent : VoltraColor.bgElev)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deviceCard(label: String,
                            manager: VoltraBLEManager,
                            telem: Telemetry?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(manager.connectionState.isConnected ? VoltraColor.accent : VoltraColor.textFaint)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(VoltraColor.text)
                Spacer()
                Text(connStatus(manager))
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }
            HStack(spacing: 16) {
                statTile(title: "Force", value: forceText(telem?.forceLb), unit: "lb")
                statTile(title: "Reps",  value: telem?.repCount.map { "\($0)" } ?? "—", unit: "")
                statTile(title: "Phase", value: phaseText(telem?.phase), unit: "")
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

    private func combinedCard(_ c: CombinedTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "rectangle.connected.to.line.below")
                    .foregroundColor(VoltraColor.accent)
                Text("Combined")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(VoltraColor.text)
                Spacer()
                Text("virtual twin")
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }
            HStack(spacing: 16) {
                statTile(title: "Force", value: forceText(c.forceLb), unit: "lb")
                statTile(title: "Reps",  value: "\(c.repCount)", unit: "")
                statTile(title: "Peak",  value: c.peakPower.map { "\($0)" } ?? "—", unit: "W")
            }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.accent.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statTile(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(VoltraColor.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(VoltraColor.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { mdm.load() } label: {
                actionLabel(text: "LOAD", icon: "arrow.down.to.line", primary: true)
            }
            Button { mdm.unload() } label: {
                actionLabel(text: "UNLOAD", icon: "arrow.up.to.line", primary: false)
            }
        }
    }

    private func actionLabel(text: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.system(size: 14, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundColor(primary ? .black : VoltraColor.text)
        .background(primary ? VoltraColor.accent : VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(primary ? Color.clear : VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Wiring

    private func wireTelemetry() {
        let vm = self.vm
        mdm.onLeftTelemetry  = { t in
            Task { @MainActor in vm.leftTelem = t }
        }
        mdm.onRightTelemetry = { t in
            Task { @MainActor in vm.rightTelem = t }
        }
        mdm.onCombinedTelemetry = { c in
            Task { @MainActor in vm.combined = c }
        }
    }

    // MARK: - Formatters

    private func forceText(_ lb: Double?) -> String {
        guard let v = lb else { return "—" }
        return String(format: "%.0f", v)
    }

    private func phaseText(_ p: VoltraPhase?) -> String {
        guard let p = p else { return "—" }
        switch p {
        case .idle:       return "Idle"
        case .pull:       return "Pull"
        case .transition: return "Hold"
        case .return:     return "Return"
        }
    }

    private func connStatus(_ m: VoltraBLEManager) -> String {
        switch m.connectionState {
        case .scanning:    return "Scanning"
        case .connecting:  return "Connecting"
        case .connected:   return "Connected"
        case .disconnected(let reason): return reason ?? "Disconnected"
        case .idle:        return "Idle"
        }
    }
}

#Preview {
    NavigationStack {
        DualCaptureView()
            .environmentObject(MultiDeviceManager())
    }
}
