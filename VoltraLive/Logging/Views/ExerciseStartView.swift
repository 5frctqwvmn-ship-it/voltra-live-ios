// ExerciseStartView.swift
// Smart-start screen shown after the user picks an exercise. Surfaces:
//  * a "Last session" summary card
//  * a ±5 toggle with three options anchored on history
//  * a Start CTA that opens the live capture screen
//
// On set 1, the anchor is last session's set 1. On set 2+, the anchor is
// (last current weight) + (history delta into this slot). After a set is
// logged the screen automatically refreshes the suggestion for the next set.

import SwiftUI

struct ExerciseStartView: View {
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var session: SessionStore
    /// b48: reads `workoutMode == .superset` to surface the per-exercise
    /// Voltra picker + the "Add Another Superset" CTA. Also writes new
    /// chain entries via `appendSupersetEntry(...)`.
    @EnvironmentObject var mdm: MultiDeviceManager
    @Environment(\.dismiss) private var dismiss

    /// The user's chosen weight from the toggle (or free-entry field).
    /// Pre-populated to the suggestion's anchor; updated by tapping a chip
    /// or typing a number.
    @State private var chosenWeight: Double = 0
    /// Free-entry mirror of chosenWeight as a String for the TextField.
    @State private var freeEntryText: String = ""
    @State private var navigateToCapture = false
    /// b53: per-exercise Voltra assignment. Default follows the existing
    /// chain length (entry 0 -> left, entry 1 -> right, entry 2 -> left,
    /// ...) so the user can just tap through. Replaces the b48
    /// `DeviceSlot`-typed state — b53 lets the user pick BOTH so a
    /// single exercise can drive both Voltras with the same target.
    @State private var supersetSlot: DeviceSlotAssignment = .left
    /// Refreshed on appear and after each set is logged.
    @State private var suggestion: SetSuggestion = SetSuggestion(
        source: .freeEntry, anchorLb: nil, offsets: []
    )

    /// b49 (was b48): True when both Voltras are paired so the L/R
    /// assignment + Add-Another panel should render. Workout mode is
    /// no longer a gate \u2014 b49's unified flow puts assignment
    /// inside the exercise screen unconditionally when the user has
    /// a meaningful choice.
    private var inSupersetMode: Bool {
        mdm.left.connectionState.isConnected
            && mdm.right.connectionState.isConnected
    }

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    setHeader
                    if inSupersetMode {
                        supersetSlotPicker
                    }
                    lastSessionCard
                    suggestionSection
                    startButton
                    if inSupersetMode {
                        addAnotherSupersetButton
                    }
                    Spacer(minLength: 24)
                }
                .padding(20)
                // b74 V4-D24: attach content-space debug grid layer (scrolls with content).
                .debugGridContentLayer()
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Open live") {
                    navigateToCapture = true
                }
                .foregroundColor(VoltraColor.accent)
            }
        }
        .navigationDestination(isPresented: $navigateToCapture) {
            // b53: V1/V2 container \u2014 see ExerciseDetailView for the
            // full reasoning. V1 stays the default; V2 is opted into on
            // first launch via the picker sheet.
            LiveCaptureContainer()
        }
        .onAppear {
            refreshSuggestion()
            // b48: pre-select the slot for this entry. Even chain-length
            // -> left (so entry 0 = left, entry 2 = left), odd -> right.
            // The user can override before tapping Start / Add Another.
            if inSupersetMode {
                // b53: default to the per-instance assignment if this
                // instance was already assigned (e.g. user navigated
                // back into the Start screen). Otherwise fall back to
                // the chain-length default introduced in b48.
                if let prior = logging.activeInstance?.assignedVoltra {
                    supersetSlot = prior
                } else {
                    supersetSlot = (mdm.supersetChain.count % 2 == 0) ? .left : .right
                }
            }
        }
        // When the user logs a set in the capture flow, setNumber bumps —
        // re-derive the suggestion for the new slot when we come back here.
        .onChange(of: logging.setNumberForCurrentInstance) { _, _ in
            refreshSuggestion()
        }
        // b66 V4.2: page-name badge.
        .pageBadge("ExerciseStartView")
        // B74-F11: recorder screen tag.
        .recorderScreen("ExerciseStartView")
        }

    // MARK: - Pieces

    private var navTitle: String {
        logging.activeInstance?.exercise?.name ?? "Exercise"
    }

    private var setHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SET \(logging.setNumberForCurrentInstance)")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            Text(suggestion.caption)
                .font(.system(size: 14))
                .foregroundColor(VoltraColor.textDim)
        }
    }

    private var lastSessionCard: some View {
        let series = previousSeries
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LAST SESSION")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if let date = lastSessionDate {
                    Text(relativeDate(date))
                        .font(.system(size: 11))
                        .foregroundColor(VoltraColor.textFaint)
                }
            }

            if series.isEmpty {
                Text("No history yet.")
                    .font(.system(size: 14))
                    .foregroundColor(VoltraColor.textFaint)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(series, id: \.id) { s in
                        lastSessionRow(s)
                    }
                }
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

    private func lastSessionRow(_ s: LoggedSet) -> some View {
        HStack(spacing: 12) {
            Text("Set \(s.orderIndex)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.textDim)
                .frame(width: 50, alignment: .leading)
            Text("\(formatLb(s.weightLb)) lb")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .frame(width: 90, alignment: .leading)
            Text("\(s.reps) reps")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(VoltraColor.textDim)
            Spacer()
            // Highlight the slot that matches this upcoming set.
            if s.orderIndex == logging.setNumberForCurrentInstance {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(VoltraColor.accent)
            }
        }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("START WITH")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)

            if suggestion.isFreeEntry {
                freeEntryField
            } else {
                toggleChips
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

    private var toggleChips: some View {
        HStack(spacing: 10) {
            ForEach(Array(suggestion.options.enumerated()), id: \.offset) { idx, value in
                let isSelected = abs(value - chosenWeight) < 0.01
                let offsetLabel = offsetLabel(for: suggestion.offsets[idx])
                Button {
                    chosenWeight = value
                } label: {
                    VStack(spacing: 4) {
                        Text(offsetLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isSelected ? VoltraColor.bg.opacity(0.7) : VoltraColor.textFaint)
                        Text("\(formatLb(value))")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? VoltraColor.bg : VoltraColor.text)
                        Text("lb")
                            .font(.system(size: 10))
                            .foregroundColor(isSelected ? VoltraColor.bg.opacity(0.7) : VoltraColor.textFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isSelected ? VoltraColor.accent : VoltraColor.bgElev2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var freeEntryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("0", text: $freeEntryText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
                    .padding(14)
                    .background(VoltraColor.bgElev2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(VoltraColor.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: freeEntryText) { _, new in
                        chosenWeight = Double(new) ?? 0
                    }
                Text("lb")
                    .font(.system(size: 14))
                    .foregroundColor(VoltraColor.textFaint)
            }
        }
    }

    // MARK: - b48 Superset chain UI

    /// b48: Voltra picker shown right under the set header in Superset
    /// mode. The user picks LEFT or RIGHT to bind THIS exercise to a
    /// specific Voltra. This is the assignment that shows up on the
    /// live banner during the actual set, and that LOAD/UNLOAD targets.
    private var supersetSlotPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASSIGN TO VOLTRA")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            HStack(spacing: 10) {
                // b53: three-way picker. BOTH means this single exercise
                // drives both Voltras (e.g. a bilateral movement where
                // the user wants identical targets on each side).
                ForEach(DeviceSlotAssignment.allCases) { assignment in
                    let selected = (assignment == supersetSlot)
                    Button {
                        supersetSlot = assignment
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: iconName(for: assignment))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(selected ? VoltraColor.bg : VoltraColor.accent)
                            Text(assignment.label.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .kerning(1.0)
                                .foregroundColor(selected ? VoltraColor.bg : VoltraColor.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected ? VoltraColor.accent : VoltraColor.bgElev2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// b48: "Add Another Superset" CTA. Appends THIS exercise to the
    /// chain and pops the navigation back to the day-tile screen so the
    /// user can pick the next exercise. Does NOT start the live session.
    private var addAnotherSupersetButton: some View {
        Button {
            commitSupersetEntry()
            mdm.requestSupersetReturnToHome()
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Another Exercise")
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(VoltraColor.accent.opacity(0.15))
            .foregroundColor(VoltraColor.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(VoltraColor.accent.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canStart)
    }

    /// b48: persist this exercise into the superset chain. Called from
    /// both the Start CTA (which then opens live capture) and the Add
    /// Another CTA (which then pops home).
    ///
    /// b53: ALSO stamps the per-exercise assignment onto the active
    /// `ExerciseInstance.assignedVoltra` so WriterRouter can route by
    /// it directly — the source of truth for routing moves from
    /// MDM.supersetChain to the instance itself.
    private func commitSupersetEntry() {
        let name = logging.activeInstance?.exercise?.name ?? "Exercise"
        let weight = chosenWeight > 0 ? chosenWeight : (logging.pendingPlannedWeightLb ?? 0)
        // b53: persist the assignment on the instance.
        logging.activeInstance?.assignedVoltra = supersetSlot
        // Mirror onto the MDM chain. `.both` projects to a single slot
        // here for legacy banner / chain-mirror compatibility — the
        // routing path already broadcasts to both writers when the
        // instance assignment is `.both`, so the projection only
        // affects which side of the banner shows the active dot.
        mdm.appendSupersetEntry(
            name: name,
            slot: supersetSlot.projectedSlot,
            weightLb: weight
        )
    }

    /// b53: SF Symbol for each assignment option.
    private func iconName(for assignment: DeviceSlotAssignment) -> String {
        switch assignment {
        case .left:  return "l.circle.fill"
        case .right: return "r.circle.fill"
        case .both:  return "square.split.2x1.fill"
        }
    }

    private var startButton: some View {
        Button {
            // b48: in superset mode, also stamp this exercise into the
            // chain before opening live so the banner has the right
            // labels and slot bindings from the first frame.
            if inSupersetMode {
                commitSupersetEntry()
            }
            // Stash the user's chosen starting weight so SetLogView prefills
            // it instead of the previous-set fallback.
            logging.pendingPlannedWeightLb = chosenWeight > 0 ? chosenWeight : nil
            navigateToCapture = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(buttonLabel)
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canStart ? VoltraColor.accent : VoltraColor.bgElev2)
            .foregroundColor(canStart ? VoltraColor.bg : VoltraColor.textDim)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canStart)
    }

    private var canStart: Bool {
        // Free entry requires a positive weight; toggle is fine even with 0.
        if suggestion.isFreeEntry { return chosenWeight > 0 }
        return true
    }

    private var buttonLabel: String {
        if suggestion.isFreeEntry, chosenWeight <= 0 {
            return "Enter a starting weight"
        }
        return "Start set \(logging.setNumberForCurrentInstance) — \(formatLb(chosenWeight)) lb"
    }

    // MARK: - Behavior

    private var previousSeries: [LoggedSet] {
        guard let ex = logging.activeInstance?.exercise else { return [] }
        return logging.previousSetSeries(for: ex)
    }

    private var lastSessionDate: Date? {
        previousSeries.first?.instance?.session?.startedAt
    }

    private func refreshSuggestion() {
        suggestion = logging.nextSetSuggestion()
        // Default the chip selection to the "Same" anchor.
        if let anchor = suggestion.anchorLb {
            chosenWeight = anchor
            freeEntryText = formatLb(anchor)
        } else {
            chosenWeight = 0
            freeEntryText = ""
        }
    }

    private func offsetLabel(for offset: Double) -> String {
        if offset == 0 { return "SAME" }
        if offset > 0 { return "+\(formatLb(offset))" }
        return "\(formatLb(offset))"
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        ExerciseStartView()
            .environmentObject(LoggingStore())
            .environmentObject(SessionStore())
            .environmentObject(MultiDeviceManager())
    }
}
