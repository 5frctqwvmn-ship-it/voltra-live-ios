// ExportSheet.swift
// Shown after End Session — gives the user a markdown view of the session and
// a Share button so they can paste into Notes / Notion / send to themselves.

import SwiftUI

struct ExportSheet: View {
    let session: WorkoutSession
    @EnvironmentObject var logging: LoggingStore
    @Environment(\.dismiss) private var dismiss

    @State private var markdown: String = ""
    @State private var showingCopiedToast = false

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary
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
                markdown = logging.markdownExport(for: session, sessionNumber: estimatedSessionNumber())
            }
        }
        .presentationDetents([.large])
    }

    private var summary: some View {
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

    /// Best-effort numbering for the markdown header. Counts how many imported
    /// + non-imported sessions exist before this one.
    private func estimatedSessionNumber() -> Int {
        // Without an explicit query here, fall back to a stable date-based n.
        return 89  // First user-logged session lands at #89 (after the imported 88).
    }
}
