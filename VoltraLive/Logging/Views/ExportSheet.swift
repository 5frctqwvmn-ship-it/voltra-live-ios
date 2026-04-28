// ExportSheet.swift
// Shown after End Session — the post-workout summary screen.
//
// v0.4.4: Replaced the bare 4-stat header with a richer recap showing start
// time, end time, total elapsed, time-under-tension (sum of per-set
// startedAt→endedAt durations), total rest, and counts. The markdown export
// stays below for sharing into Notes/Notion.

import SwiftUI
import SwiftData

struct ExportSheet: View {
    let session: WorkoutSession
    @EnvironmentObject var logging: LoggingStore
    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var context

    @State private var markdown: String = ""
    @State private var showingCopiedToast = false

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        timingCard
                        countsRow
                        // b52: per-exercise summary cards — each chain entry
                        // gets its own card with set list + rollups (totals,
                        // peak, avg peak, HR, kcal) so the user can review
                        // progression without parsing the markdown blob.
                        ForEach(orderedInstances, id: \.id) { inst in
                            instanceCard(inst)
                        }
                        Text(markdown.isEmpty ? "Generating…" : markdown)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(VoltraColor.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(VoltraColor.bgElev2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .textSelection(.enabled)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Session saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(VoltraColor.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    if !markdown.isEmpty {
                        ShareLink(item: markdown) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(VoltraColor.accent)
                        }
                    }
                }
            }
            .onAppear {
                markdown = logging.markdownExport(
                    for: session,
                    sessionNumber: estimatedSessionNumber(context: context)
                )
            }
        }
        .presentationDetents([.large])
        .buildBadgeOverlay()
    }

    // MARK: - v0.4.4 summary cards

    /// Top-of-summary card: when, how long, time-under-tension, rest.
    private var timingCard: some View {
        let stats = sessionStats
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("WORKOUT")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text(stats.dateString)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(VoltraColor.textDim)
            }
            HStack(spacing: 16) {
                timeColumn(label: "START", value: stats.startString)
                Divider()
                    .frame(width: 1, height: 28)
                    .overlay(VoltraColor.border)
                timeColumn(label: "END", value: stats.endString)
                Divider()
                    .frame(width: 1, height: 28)
                    .overlay(VoltraColor.border)
                timeColumn(label: "TOTAL",
                           value: stats.totalDurationString,
                           valueColor: VoltraColor.accent)
            }
            HStack(spacing: 16) {
                miniStat(label: "TIME UNDER TENSION",
                         value: stats.tutString,
                         color: VoltraColor.pull)
                miniStat(label: "REST",
                         value: stats.restString,
                         color: VoltraColor.returnPhase)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 4-up tile row with exercise/set/rep/peak counts.
    private var countsRow: some View {
        let sets = session.allSets
        let totalReps = sets.reduce(0) { $0 + $1.reps }
        let peak = sets.map(\.peakForceLb).max() ?? 0
        let exCount = (session.instances ?? []).count
        return HStack(spacing: 10) {
            stat(label: "EXERCISES", value: "\(exCount)")
            stat(label: "SETS",      value: "\(sets.count)")
            stat(label: "REPS",      value: "\(totalReps)")
            stat(label: "PEAK",      value: String(format: "%.0f lb", peak),
                 color: VoltraColor.accent)
        }
    }

    private func timeColumn(label: String, value: String, valueColor: Color = VoltraColor.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textDim)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textDim)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Computed timing stats for the summary header.
    private struct SessionStats {
        let dateString: String
        let startString: String
        let endString: String
        let totalDurationString: String
        let tutString: String
        let restString: String
    }

    private var sessionStats: SessionStats {
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let total = end.timeIntervalSince(start)

        // Time-under-tension: sum of per-set startedAt→endedAt durations.
        // Falls back to a 4-second-per-set heuristic for legacy rows that
        // don't carry per-set timestamps yet (early auto-log builds).
        let tut: TimeInterval = session.allSets.reduce(0) { acc, set in
            if let s = set.startedAt, let e = set.endedAt, e > s {
                return acc + e.timeIntervalSince(s)
            }
            // Heuristic: ~3 seconds per rep when no telemetry timestamps.
            return acc + Double(max(set.reps, 1)) * 3.0
        }
        let rest = max(0, total - tut)

        let dayDF = DateFormatter()
        dayDF.dateFormat = "EEE, MMM d"
        let timeDF = DateFormatter()
        timeDF.dateFormat = "h:mm a"

        return SessionStats(
            dateString:          dayDF.string(from: start),
            startString:         timeDF.string(from: start),
            endString:           timeDF.string(from: end),
            totalDurationString: Self.formatDuration(total),
            tutString:           Self.formatDuration(tut),
            restString:          Self.formatDuration(rest)
        )
    }

    /// Compact H:MM:SS / M:SS / S formatter for durations on the summary.
    private static func formatDuration(_ secs: TimeInterval) -> String {
        let s = Int(secs.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private func stat(label: String, value: String, color: Color = VoltraColor.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
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

    /// Best-effort numbering for the markdown header. Counts how many
    /// sessions (imported + user-logged) started on or before this one and
    /// uses that as the session ordinal. Falls back to total count if the
    /// fetch fails.
    private func estimatedSessionNumber(context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let earlierOrSame = all.filter { $0.startedAt <= session.startedAt }.count
        return max(earlierOrSame, 1)
    }

    // MARK: - b52 per-exercise cards

    private var orderedInstances: [ExerciseInstance] {
        (session.instances ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Per-exercise card: header (order + name + equipment), set list with
    /// per-set weight × reps + peak force, totals + HR/kcal rollups.
    private func instanceCard(_ inst: ExerciseInstance) -> some View {
        let exerciseName = inst.exercise?.name ?? "Exercise"
        let sets = inst.orderedSets
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(inst.orderIndex). \(exerciseName.uppercased())")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.accent)
                Spacer()
                if !inst.equipment.isEmpty {
                    Text(inst.equipment)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
            if sets.isEmpty {
                Text("No sets logged")
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textFaint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sets, id: \.id) { s in
                        instanceSetRow(s, exerciseName: exerciseName)
                    }
                }
            }
            Divider().overlay(VoltraColor.border)
            instanceRollups(inst)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// One set row inside an instance card. b52: each row carries the
    /// exercise name as a leading mini-tag so when the user reviews the
    /// summary later the attribution is unambiguous (Issue E2).
    private func instanceSetRow(_ s: LoggedSet, exerciseName: String) -> some View {
        HStack(spacing: 10) {
            Text("Set \(s.orderIndex)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.textDim)
                .frame(width: 50, alignment: .leading)
            Text("\(formatLbInt(s.weightLb)) \u{00D7} \(s.reps)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
            if s.peakForceLb > 0 {
                Text("peak \(formatLbInt(s.peakForceLb)) lb")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VoltraColor.accent)
            }
            Spacer()
            // Compact label tag so chain summary scanning is fast.
            Text(exerciseName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(VoltraColor.textFaint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Rollups row: total reps + volume + peak + avg peak + duration
    /// (top), HR + kcal (bottom, if HK captured them).
    private func instanceRollups(_ inst: ExerciseInstance) -> some View {
        let totalReps = inst.totalReps
        let totalVol = inst.totalVolumeLb
        let peak = inst.peakForceLb
        let avgPeak = inst.avgPeakForceLb
        let dur = inst.duration
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                rollupCell(label: "REPS", value: "\(totalReps)")
                rollupCell(label: "VOL", value: "\(formatLbInt(totalVol)) lb")
                rollupCell(label: "PEAK", value: "\(formatLbInt(peak)) lb",
                           color: VoltraColor.accent)
                rollupCell(label: "AVG PK", value: "\(formatLbInt(avgPeak)) lb")
                rollupCell(label: "DUR", value: Self.formatDuration(dur))
            }
            if inst.avgHRDuringInstance != nil || inst.kcalDuringInstance != nil {
                HStack(spacing: 12) {
                    if let hr = inst.avgHRDuringInstance, hr > 0 {
                        rollupCell(label: "AVG HR",
                                   value: "\(Int(hr.rounded())) bpm",
                                   color: VoltraColor.pull)
                    }
                    if let kcal = inst.kcalDuringInstance, kcal > 0 {
                        rollupCell(label: "KCAL",
                                   value: "\(Int(kcal.rounded()))",
                                   color: VoltraColor.returnPhase)
                    }
                    Spacer()
                }
            }
        }
    }

    private func rollupCell(label: String, value: String,
                            color: Color = VoltraColor.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textDim)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formatLbInt(_ d: Double) -> String {
        if d == 0 { return "0" }
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%.1f", d)
    }
}
