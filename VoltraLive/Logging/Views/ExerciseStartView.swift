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
    @Environment(\.dismiss) private var dismiss

    /// The user's chosen weight from the toggle (or free-entry field).
    /// Pre-populated to the suggestion's anchor; updated by tapping a chip
    /// or typing a number.
    @State private var chosenWeight: Double = 0
    /// Free-entry mirror of chosenWeight as a String for the TextField.
    @State private var freeEntryText: String = ""
    @State private var navigateToCapture = false
    /// Refreshed on appear and after each set is logged.
    @State private var suggestion: SetSuggestion = SetSuggestion(
        source: .freeEntry, anchorLb: nil, offsets: []
    )

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    setHeader
                    lastSessionCard
                    suggestionSection
                    startButton
                    Spacer(minLength: 24)
                }
                .padding(20)
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
            LiveCaptureView()
        }
        .onAppear { refreshSuggestion() }
        // When the user logs a set in the capture flow, setNumber bumps —
        // re-derive the suggestion for the new slot when we come back here.
        .onChange(of: logging.setNumberForCurrentInstance) { _, _ in
            refreshSuggestion()
        }
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

    private var startButton: some View {
        Button {
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
    }
}
