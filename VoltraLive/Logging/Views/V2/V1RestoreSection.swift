// V1RestoreSection.swift
//
// b56 — Ports the V1 LiveCaptureView's "below-the-chart" affordances
// VERBATIM (per user direction: "everything under the force curve looks
// almost identical to how the previous version was") into V2. The V2
// rewrite originally dropped these — b56 restores them.
//
// Restored sections, top-to-bottom:
//
//   1. Pulley chip + Added-plates chip pair (V1 line 1561 addedWeightSection)
//      - "Pulley" / "Pulley ×2" toggle on the trailing edge
//      - "Added plates" chip on the leading edge — taps toggle the
//        embedded ±1/±5 picker. When active, an X chip clears the value.
//      - Picker (V1 line 1648 addWeightPicker) — −5 / −1 / "+N lb plates" / +1 / +5
//
//   2. Logged sets list (V1 line 1781 loggedSetsSection)
//      - Header "LOGGED SETS  N"
//      - Empty hint when no sets
//      - SwipeableSetRow per logged set (tap-to-expand, swipe-to-delete)
//      - Undo toast wired by parent
//
//   3. Bottom actions (V1 line 1935 bottomActions)
//      - "Next exercise" NavigationLink → ExercisePickerView(dayType:)
//      - "End session" red button → calls onEndTapped()
//
// SwipeableSetRow is `private` inside V1 LiveCaptureView. b56 promotes
// it (in a paired edit on that file) by removing `private` so V2 can
// reuse it.
//
// Sacred files NOT touched.

import SwiftUI

struct V1RestoreSection: View {

    // MARK: Environment

    @EnvironmentObject var logging: LoggingStore

    // MARK: Local picker state (matches V1's @State addWeightOpen)

    @State private var addWeightOpen: Bool = false

    /// Currently expanded set row, mirrors V1's `expandedSetID`.
    @State private var expandedSetID: UUID? = nil

    /// Pending undo snapshot, mirrors V1's `pendingUndo`.
    @State private var pendingUndo: DeletedSetSnapshot? = nil

    /// Auto-expiry task for the undo toast.
    @State private var undoCountdownTask: Task<Void, Never>? = nil

    // MARK: Inputs

    /// Called when the user taps "End session" — parent shows the
    /// confirmation dialog. b56 keeps the dialog ownership in
    /// LiveCaptureViewV2 so the export-sheet flow stays in one place.
    let onEndTapped: () -> Void

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addedWeightSection
            loggedSetsSection
            if let snap = pendingUndo {
                undoToast(for: snap)
            }
            bottomActions
        }
    }

    // MARK: - 1. Added-weight + Pulley chip pair (port of V1 addedWeightSection)

    private var addedWeightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation { addWeightOpen.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: addWeightOpen ? "minus.circle" : "plus.circle")
                        Text(addWeightChipTitle)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(addedWeightActive ? VoltraColor.transition.opacity(0.18) : VoltraColor.bgElev2)
                    .foregroundColor(addedWeightActive ? VoltraColor.transition : VoltraColor.text)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if addedWeightActive && !addWeightOpen {
                    Button {
                        logging.upcomingAddedLoadLb = nil
                        logging.upcomingAddedLoadType = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(VoltraColor.textFaint)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                pulleyModeChip
            }

            if addWeightOpen {
                addWeightPicker
            }
        }
    }

    /// Pulley Mode toggle chip. Tap to flip. Mirrors V1 line 1609.
    private var pulleyModeChip: some View {
        Button {
            logging.pulleyMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: logging.pulleyMode
                      ? "arrow.triangle.2.circlepath.circle.fill"
                      : "arrow.triangle.2.circlepath.circle")
                Text(logging.pulleyMode ? "Pulley \u{00d7}2" : "Pulley")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(logging.pulleyMode
                        ? VoltraColor.transition.opacity(0.18)
                        : VoltraColor.bgElev2)
            .foregroundColor(logging.pulleyMode
                             ? VoltraColor.transition
                             : VoltraColor.text)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var addedWeightActive: Bool {
        (logging.upcomingAddedLoadLb ?? 0) > 0
    }

    private var addWeightChipTitle: String {
        if let lb = logging.upcomingAddedLoadLb, lb > 0 {
            return "\(Int(lb)) lb plates"
        }
        return "Added plates"
    }

    /// Picker: −5 / −1 / "+N lb plates" / +1 / +5. V1 line 1648.
    private var addWeightPicker: some View {
        let currentLb = Int(logging.upcomingAddedLoadLb ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Plates already on the machine (not from Voltra). Added to your set\u{2019}s logged total.")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                nudgeButton(label: "\u{2212}5", small: true) { adjustAddedLoad(-5) }
                nudgeButton(label: "\u{2212}1", small: true) { adjustAddedLoad(-1) }
                VStack(spacing: 2) {
                    Text("+\(currentLb)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(VoltraColor.transition)
                    Text("lb plates")
                        .font(.system(size: 9))
                        .foregroundColor(VoltraColor.textFaint)
                }
                .frame(maxWidth: .infinity)
                nudgeButton(label: "+1", small: true) { adjustAddedLoad(+1) }
                nudgeButton(label: "+5", small: true) { adjustAddedLoad(+5) }
            }
        }
        .padding(10)
        .background(VoltraColor.bgElev2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func nudgeButton(label: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: small ? 12 : 14, weight: .bold, design: .monospaced))
                .frame(width: small ? 38 : 48, height: small ? 32 : 44)
                .background(VoltraColor.bgElev2)
                .foregroundColor(VoltraColor.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func adjustAddedLoad(_ delta: Int) {
        let cur = Int(logging.upcomingAddedLoadLb ?? 0)
        let next = max(0, min(300, cur + delta))
        logging.upcomingAddedLoadLb = next > 0 ? Double(next) : nil
        logging.upcomingAddedLoadType = "plates"
    }

    // MARK: - 2. Logged sets section (port of V1 loggedSetsSection)

    private var loggedSetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LOGGED SETS")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if let inst = logging.activeInstance {
                    Text("\(inst.sets?.count ?? 0)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
            let sets = logging.activeInstance?.orderedSets ?? []
            if sets.isEmpty {
                emptyHint
            } else {
                ForEach(sets) { s in
                    SwipeableSetRow(
                        set: s,
                        isExpanded: expandedSetID == s.id,
                        onToggleExpand: {
                            withAnimation { expandedSetID = expandedSetID == s.id ? nil : s.id }
                        },
                        onSave: { editing in
                            logging.updateLoggedSet(
                                s,
                                weightLb: editing.weightLb,
                                eccentricLb: editing.eccentricLb,
                                reps: editing.reps,
                                addedLoadLb: editing.addedLoadLb,
                                addedLoadType: editing.addedLoadType,
                                mode: editing.mode,
                                notes: editing.notes
                            )
                            withAnimation { expandedSetID = nil }
                        },
                        onDelete: {
                            if let snap = logging.deleteLoggedSet(s) {
                                pendingUndo = snap
                                scheduleUndoExpiry()
                            }
                            withAnimation { expandedSetID = nil }
                        }
                    )
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.path")
                .font(.system(size: 24))
                .foregroundColor(VoltraColor.textFaint)
            Text("Start lifting \u{2014} sets auto-log after a 4s rest.")
                .font(.system(size: 13))
                .foregroundColor(VoltraColor.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(VoltraColor.bgElev2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Undo toast

    private func undoToast(for snap: DeletedSetSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .foregroundColor(VoltraColor.text)
            Text("Set deleted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            Spacer()
            Button {
                logging.restoreDeletedSet(snap)
                pendingUndo = nil
                undoCountdownTask?.cancel()
            } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(VoltraColor.accent)
                    .foregroundColor(VoltraColor.bg)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private func scheduleUndoExpiry() {
        undoCountdownTask?.cancel()
        undoCountdownTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                pendingUndo = nil
            }
        }
    }

    // MARK: - 3. Bottom actions (port of V1 bottomActions)

    private var bottomActions: some View {
        HStack(spacing: 10) {
            NavigationLink {
                if let dt = logging.activeSession?.dayType {
                    ExercisePickerView(dayType: dt)
                }
            } label: {
                Label("Next exercise", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VoltraColor.bgElev)
                    .foregroundColor(VoltraColor.text)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(VoltraColor.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                onEndTapped()
            } label: {
                Label("End session", systemImage: "stop.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VoltraColor.danger.opacity(0.15))
                    .foregroundColor(VoltraColor.danger)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(VoltraColor.danger.opacity(0.4), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
