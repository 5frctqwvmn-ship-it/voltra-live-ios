// DebugView.swift
// Hidden behind the gear icon on LoggingHomeView. Shows store counts and
// exposes a manual "Re-import history" button so the user can recover from a
// bad seed state without needing to delete the app.
//
// Bumping HistoryImporter.importVersion in code will also trigger the import
// on next launch automatically; this view is purely for ad-hoc debugging.

import SwiftUI
import SwiftData

struct DebugView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var counts: (sessions: Int, exercises: Int, sets: Int, legTagged: Int) = (0, 0, 0, 0)
    @State private var stubCount: Int = 0
    @State private var statusMessage: String = ""
    @State private var isWorking = false
    @State private var showWipeConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {

                        section("STORE") {
                            row("Sessions",   "\(counts.sessions)")
                            row("Exercises",  "\(counts.exercises)")
                            row("Logged sets", "\(counts.sets)")
                            row("Leg-tagged exercises", "\(counts.legTagged)")
                            row("Stub imported sessions", "\(stubCount)")
                        }

                        section("ACTIONS") {
                            actionButton(
                                title: "Refresh counts",
                                systemImage: "arrow.clockwise",
                                tint: VoltraColor.text
                            ) {
                                refreshCounts()
                            }

                            actionButton(
                                title: "Re-import history.md",
                                systemImage: "tray.and.arrow.down",
                                tint: VoltraColor.accent
                            ) {
                                forceReimport()
                            }

                            actionButton(
                                title: "Wipe & re-import history",
                                systemImage: "trash.slash",
                                tint: VoltraColor.warn
                            ) {
                                showWipeConfirm = true
                            }
                        }

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(VoltraColor.textDim)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(VoltraColor.bgElev)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Text("Build \(buildString) · iCloud: \(iCloudHint)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(VoltraColor.textFaint)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(VoltraColor.accent)
                }
            }
            .onAppear { refreshCounts() }
            .alert("Wipe imported history?", isPresented: $showWipeConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Wipe & re-import", role: .destructive) { wipeAndReimport() }
            } message: {
                Text("Deletes every session that came from history.md (live workouts you logged in the app are kept), then re-runs the importer from scratch. Use this if your history shows fewer sessions than you expect.")
            }
        }
        .buildBadgeOverlay()
    }

    // MARK: - Actions

    private func refreshCounts() {
        counts = HistoryImporter.storeCounts(context: context)
        stubCount = HistoryImporter.stubImportedSessionCount(context: context)
        statusMessage = "Refreshed at \(timestamp())"
    }

    private func forceReimport() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Re-importing seed/history.md…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            do {
                try HistoryImporter.forceReimport(context: context)
                let after = HistoryImporter.storeCounts(context: context)
                counts = after
                stubCount = HistoryImporter.stubImportedSessionCount(context: context)
                statusMessage =
                    "Re-import done at \(timestamp())\n" +
                    "Sessions: \(after.sessions)  Exercises: \(after.exercises)\n" +
                    "Sets: \(after.sets)  Leg-tagged: \(after.legTagged)\n" +
                    "Stubs: \(stubCount)"
            } catch {
                statusMessage = "Re-import FAILED: \(error)"
            }
            isWorking = false
        }
    }

    private func wipeAndReimport() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Wiping imported rows and re-running importer…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            do {
                let wiped = try HistoryImporter.wipeAndReimport(context: context)
                let after = HistoryImporter.storeCounts(context: context)
                counts = after
                stubCount = HistoryImporter.stubImportedSessionCount(context: context)
                statusMessage =
                    "Wiped \(wiped) imported sessions, re-imported at \(timestamp())\n" +
                    "Sessions: \(after.sessions)  Exercises: \(after.exercises)\n" +
                    "Sets: \(after.sets)  Leg-tagged: \(after.legTagged)\n" +
                    "Stubs: \(stubCount)"
            } catch {
                statusMessage = "Wipe FAILED: \(error)"
            }
            isWorking = false
        }
    }

    // MARK: - UI helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
            VStack(spacing: 1) { content() }
                .background(VoltraColor.bgElev)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(VoltraColor.text)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(VoltraColor.bgElev)
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if isWorking {
                    ProgressView().tint(VoltraColor.textDim)
                }
            }
            .foregroundColor(tint)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private var buildString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var iCloudHint: String {
        FileManager.default.ubiquityIdentityToken != nil ? "signed-in" : "not-signed-in"
    }
}

#Preview {
    DebugView()
}
