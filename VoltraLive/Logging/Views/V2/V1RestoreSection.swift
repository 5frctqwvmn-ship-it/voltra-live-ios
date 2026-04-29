// V1RestoreSection.swift
//
// b56 — Ports the V1 LiveCaptureView's "below-the-chart" affordances
// VERBATIM (per user direction: "everything under the force curve looks
// almost identical to how the previous version was") into V2.
//
// b57 V3 §4 — The pulley + added-plates pair has been MOVED OUT of this
// view. It now lives in `PulleyAndPlatesBarV3`, mounted directly above
// the force-curve card. This view now only owns the logged-sets list
// and bottom actions.
//
// Remaining sections, top-to-bottom:
//
//   1. Logged sets list (V1 line 1781 loggedSetsSection)
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
            loggedSetsSection
            if let snap = pendingUndo {
                undoToast(for: snap)
            }
            bottomActions
        }
    }

    // MARK: - 1. Logged sets section (port of V1 loggedSetsSection)

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
