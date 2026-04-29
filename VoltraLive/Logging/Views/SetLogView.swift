// SetLogView.swift
// Sheet that pops up when SessionStore detects a finished set OR when the
// user taps "Log set manually". Auto-fills weight/eccentric/reps from
// telemetry + previous set on this exercise; the user can edit anything,
// add chains (manual), and tap Log.

import SwiftUI

struct SetLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var session: SessionStore

    // Editable fields
    @State private var weight: String = ""
    @State private var eccentric: String = ""
    @State private var reps: String = ""
    @State private var chains: String = ""
    @State private var label: String = "Working"
    @State private var mode: SetMode = .working
    @State private var notes: String = ""
    @State private var didPrefill = false

    private let labelOptions = ["Warm-Up", "Working", ""]

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        telemetryStrip
                        labelChips

                        weightRowWithToggle
                        numberRow(title: "Eccentric", text: $eccentric, suffix: "lb", placeholder: "—")
                        numberRow(title: "Reps", text: $reps, suffix: "", placeholder: "0")
                        numberRow(title: "Chains", text: $chains, suffix: "lb", placeholder: "—",
                                  hint: "Manual entry — chains aren't sensed by Voltra.")

                        notesField

                        logButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Log set \(logging.setNumberForCurrentInstance)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        logging.skipPendingSet()
                        dismiss()
                    }
                    .foregroundColor(VoltraColor.textDim)
                }
            }
            .onAppear { prefillIfNeeded() }
        }
        .presentationDetents([.large, .medium])
        .buildBadgeOverlay()
        // b66 V4.2: page-name badge.
        .pageBadge("SetLogView")
        }

    // MARK: - Pieces

    private var telemetryStrip: some View {
        let pending = logging.pendingTelemetrySet
        return HStack(spacing: 10) {
            stripTile(label: "DETECTED REPS",
                      value: pending.map { "\($0.reps)" } ?? "—")
            stripTile(label: "PEAK FORCE",
                      value: pending.map { String(format: "%.0f lb", $0.peakLb) } ?? "—",
                      color: VoltraColor.accent)
            if let last = lastSet {
                stripTile(label: "LAST",
                          value: "\(formatLb(last.weightLb))×\(last.reps)",
                          color: VoltraColor.textDim)
            }
        }
    }

    private func stripTile(label: String, value: String, color: Color = VoltraColor.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var labelChips: some View {
        HStack(spacing: 8) {
            chip(text: "Warm-Up", isSelected: label == "Warm-Up") {
                label = "Warm-Up"; mode = .warmUp
            }
            chip(text: "Working", isSelected: label == "Working") {
                label = "Working"; mode = .working
            }
            chip(text: "Eccentric", isSelected: mode == .eccentric) {
                label = "Working"; mode = .eccentric
            }
            chip(text: "Drop", isSelected: mode == .dropSet) {
                label = "Working"; mode = .dropSet
            }
            Spacer()
        }
    }

    private func chip(text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? VoltraColor.accent : VoltraColor.bgElev)
                .foregroundColor(isSelected ? VoltraColor.bg : VoltraColor.textDim)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func numberRow(title: String,
                           text: Binding<String>,
                           suffix: String,
                           placeholder: String,
                           hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 11))
                        .foregroundColor(VoltraColor.textFaint)
                }
            }
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .padding(14)
                .background(VoltraColor.bgElev2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if let h = hint {
                Text(h)
                    .font(.system(size: 11))
                    .foregroundColor(VoltraColor.textFaint)
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOTES")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textDim)
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(VoltraColor.bgElev2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundColor(VoltraColor.text)
        }
    }

    private var logButton: some View {
        Button {
            commit()
        } label: {
            Text("Log set")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canLog ? VoltraColor.accent : VoltraColor.bgElev2)
                .foregroundColor(canLog ? VoltraColor.bg : VoltraColor.textDim)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canLog)
        .padding(.top, 6)
    }

    // MARK: - Behavior

    private var canLog: Bool {
        (Int(reps) ?? 0) > 0
    }

    private var lastSet: LoggedSet? {
        if let ex = logging.activeInstance?.exercise {
            return logging.lastSet(for: ex)
        }
        return nil
    }

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true

        // v0.4.8 / build 30 — Warmup auto-detect.
        // When the user is logging the FIRST set of a new exercise this
        // session (set #1 with no completed sets yet), pre-select Warm-Up
        // mode. Weight prefers the last warmup logged for this exercise; if
        // the user has never logged a warmup, fall back to 50% of the most
        // recent working set (rounded to nearest 5 lb).
        let autoWarmup: Bool = {
            guard logging.isFirstSetOfActiveInstance,
                  logging.activeInstance?.exercise != nil else { return false }
            return true
        }()
        if autoWarmup {
            label = "Warm-Up"
            mode = .warmUp
        }

        // 1) Reps from telemetry when available.
        if let pending = logging.pendingTelemetrySet {
            reps = "\(pending.reps)"
        }

        // 2) Weight — priority order:
        //    a) Telemetry-detected peak force (the rep actually happened at
        //       this weight — always trust it most).
        //    b) Auto-warmup default: last warmup on this exercise, else 50%
        //       of the most recent working set, rounded to nearest 5 lb.
        //    c) User's planned weight from the smart-start toggle.
        //    d) Last set on this exercise.
        if weight.isEmpty {
            if let pending = logging.pendingTelemetrySet, pending.peakLb > 0 {
                weight = formatLb((pending.peakLb / 5).rounded() * 5)
            } else if autoWarmup, let ex = logging.activeInstance?.exercise {
                if let lw = logging.lastWarmup(for: ex), lw.weightLb > 0 {
                    weight = formatLb(lw.weightLb)
                } else if let lws = logging.lastWorkingSet(for: ex), lws.weightLb > 0 {
                    let half = (lws.weightLb * 0.5 / 5).rounded() * 5
                    weight = formatLb(half)
                } else if let planned = logging.pendingPlannedWeightLb, planned > 0 {
                    // No history at all — fall back to planned weight so the
                    // field isn't empty.
                    weight = formatLb(planned)
                }
            } else if let planned = logging.pendingPlannedWeightLb, planned > 0 {
                weight = formatLb(planned)
            } else if let last = lastSet {
                weight = formatLb(last.weightLb)
            }
        }

        // 3) Other defaults from previous set on this exercise.
        //    NOTE: when autoWarmup is true we keep our chosen mode/label and
        //    skip the "copy mode from last set" branch — otherwise the user
        //    would get "Working" carried over from yesterday's last set.
        if let last = lastSet {
            if eccentric.isEmpty, let e = last.eccentricLb, e > 0 {
                eccentric = formatLb(e)
            }
            if reps.isEmpty { reps = "\(last.reps)" }
            if chains.isEmpty, let c = last.chainsLb, c > 0 {
                chains = formatLb(c)
            }
            if !autoWarmup, !last.labelText.isEmpty {
                label = last.labelText
                mode = last.mode
            }
        }
    }

    // MARK: - Weight + smart toggle row

    private var weightRowWithToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WEIGHT")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text("lb")
                    .font(.system(size: 11))
                    .foregroundColor(VoltraColor.textFaint)
            }
            TextField("0", text: $weight)
                .keyboardType(.decimalPad)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .padding(14)
                .background(VoltraColor.bgElev2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Inline smart toggle so the user can re-anchor between sets.
            inlineSmartToggle
        }
    }

    private var inlineSmartToggle: some View {
        let suggestion = logging.nextSetSuggestion()
        return Group {
            if !suggestion.isFreeEntry, !suggestion.options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.caption.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(VoltraColor.textFaint)
                    HStack(spacing: 8) {
                        ForEach(Array(suggestion.options.enumerated()), id: \.offset) { idx, value in
                            let offset = suggestion.offsets[idx]
                            Button {
                                weight = formatLb(value)
                            } label: {
                                Text(toggleLabel(value: value, offset: offset))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(VoltraColor.bgElev)
                                    .foregroundColor(VoltraColor.text)
                                    .overlay(
                                        Capsule()
                                            .stroke(VoltraColor.accent.opacity(0.5), lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                EmptyView()
            }
        }
    }

    private func toggleLabel(value: Double, offset: Double) -> String {
        if offset == 0 { return "Same: \(formatLb(value))" }
        let sign = offset > 0 ? "+" : "−"
        return "\(sign)\(formatLb(abs(offset))) → \(formatLb(value))"
    }

    private func commit() {
        let w = Double(weight) ?? 0
        let e = Double(eccentric)
        let r = Int(reps) ?? 0
        let c = Double(chains)
        let pending = logging.pendingTelemetrySet

        logging.logSet(
            weightLb: w,
            eccentricLb: (e ?? 0) > 0 ? e : nil,
            reps: r,
            chainsLb: (c ?? 0) > 0 ? c : nil,
            peakForceLb: pending?.peakLb ?? 0,
            startedAt: pending?.startedAt,
            endedAt: pending?.endedAt,
            mode: mode,
            labelText: label,
            notes: notes.isEmpty ? nil : notes,
            autofilledFromTelemetry: pending != nil
        )
        dismiss()
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }
}

#Preview {
    SetLogView()
        .environmentObject(LoggingStore())
        .environmentObject(SessionStore())
}
