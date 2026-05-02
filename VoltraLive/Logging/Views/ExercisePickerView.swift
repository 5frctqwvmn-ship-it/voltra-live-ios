// ExercisePickerView.swift
// Exercises filtered to the chosen day type, sorted by recency. Top of list
// is "+ New exercise". Tapping any row creates an ExerciseInstance and
// navigates to the live capture view.

import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @EnvironmentObject var logging: LoggingStore
    let dayType: DayType

    // We query via @Query for live updates when the user adds new exercises
    // and also @Query sessions so the sequence ordering stays fresh.
    @Query private var allExercises: [Exercise]
    @Query private var allSessions: [WorkoutSession]

    @State private var search: String = ""
    @State private var showingNewExercise = false
    @State private var navigateToStart = false

    init(dayType: DayType) {
        self.dayType = dayType
    }

    /// Exercises filtered to the chosen day type, ordered by typical sequence
    /// (set 1 first), then by search query.
    var filteredExercises: [Exercise] {
        let pool: [Exercise] = {
            if dayType == .custom { return allExercises }
            return allExercises.filter { $0.dayTypeTags.contains(dayType) }
        }()
        let sorted = HistoryAnalytics.exercisesOrderedBySequence(
            candidates: pool,
            sessions: allSessions,
            dayType: dayType
        )
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(q) || $0.equipment.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 10) {
                    newExerciseRow

                    if filteredExercises.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredExercises) { ex in
                            exerciseRow(ex)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                // b74 V4-D24: attach content-space debug grid layer (scrolls with content).
                .debugGridContentLayer()
            }
        }
        .navigationTitle(dayType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search exercises")
        .sheet(isPresented: $showingNewExercise) {
            NewExerciseSheet(dayType: dayType) { newExercise in
                logging.pickExercise(newExercise)
                showingNewExercise = false
                navigateToStart = true
            }
        }
        .navigationDestination(isPresented: $navigateToStart) {
            ExerciseDetailView()
        }
        // b66 V4.2: page-name badge.
        .pageBadge("ExercisePickerView")
        // B74-F11: recorder screen tag.
        .recorderScreen("ExercisePickerView")
        }

    // MARK: - Rows

    private var newExerciseRow: some View {
        Button {
            showingNewExercise = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(VoltraColor.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(VoltraColor.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New exercise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    Text("Add to \(dayType.displayName)")
                        .font(.system(size: 12))
                        .foregroundColor(VoltraColor.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(VoltraColor.textDim)
            }
            .padding(14)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(VoltraColor.accent.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func exerciseRow(_ ex: Exercise) -> some View {
        let summary = previousSummary(for: ex)
        return Button {
            logging.pickExercise(ex)
            navigateToStart = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if !ex.equipment.isEmpty {
                            Text(ex.equipment)
                                .font(.system(size: 12))
                                .foregroundColor(VoltraColor.textDim)
                        }
                        if let last = ex.lastUsedAt {
                            if !ex.equipment.isEmpty {
                                Text("·").foregroundColor(VoltraColor.textFaint)
                            }
                            Text(relativeDate(last))
                                .font(.system(size: 12))
                                .foregroundColor(VoltraColor.textFaint)
                        }
                    }
                    if !summary.isEmpty {
                        Text("Last: \(summary)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(VoltraColor.accent.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(VoltraColor.textFaint)
            }
            .padding(14)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Compact "30 lb × 10 / 8 / 6" summary for the most recent prior session.
    private func previousSummary(for ex: Exercise) -> String {
        let series = HistoryAnalytics.previousSetSeries(for: ex, excluding: logging.activeSession)
        guard !series.isEmpty else { return "" }
        // Detect uniform weight or first-set weight as the headline.
        let weights = series.map(\.weightLb)
        let reps = series.map(\.reps)
        let allSame = weights.allSatisfy { $0 == weights.first }
        let weightStr: String = {
            if allSame, let w = weights.first { return "\(formatLb(w)) lb" }
            let mn = weights.min() ?? 0
            let mx = weights.max() ?? 0
            return "\(formatLb(mn))\u{2013}\(formatLb(mx)) lb"
        }()
        let repsStr = reps.map(String.init).joined(separator: "/")
        return "\(weightStr) × \(repsStr)"
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(VoltraColor.textFaint)
            Text("No exercises yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(VoltraColor.textDim)
            Text("Tap “New exercise” above to add one.")
                .font(.system(size: 13))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(40)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - New exercise sheet

struct NewExerciseSheet: View {
    let dayType: DayType
    let onCreate: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var logging: LoggingStore

    @State private var name: String = ""
    @State private var equipment: String = ""

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    field(title: "Name", text: $name, placeholder: "e.g. Belt Squats")
                    field(title: "Equipment", text: $equipment, placeholder: "e.g. Voltra")
                    Text("Adds to: \(dayType.displayName)")
                        .font(.system(size: 13))
                        .foregroundColor(VoltraColor.textDim)
                    Spacer()
                    Button {
                        let ex = logging.createNewExercise(name: name, equipment: equipment, dayType: dayType)
                        onCreate(ex)
                    } label: {
                        Text("Add and start")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? VoltraColor.accent : VoltraColor.bgElev2)
                            .foregroundColor(canSave ? VoltraColor.bg : VoltraColor.textDim)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSave)
                }
                .padding(20)
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textDim)
            TextField(placeholder, text: text)
                .padding(14)
                .background(VoltraColor.bgElev2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundColor(VoltraColor.text)
        }
    }
}

#Preview {
    NavigationStack {
        ExercisePickerView(dayType: .leg)
            .environmentObject(LoggingStore())
    }
}
