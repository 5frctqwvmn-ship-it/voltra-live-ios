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
    @EnvironmentObject private var demo: DemoController
    /// Build 37: HealthKit access for the Settings/Debug status panel so
    /// the user can see at a glance whether HK has been authorized,
    /// whether the paired Watch is streaming HR samples, and re-prompt
    /// from one consistent place.
    @EnvironmentObject private var health: HealthKitStore

    @State private var counts: (sessions: Int, exercises: Int, sets: Int, legTagged: Int) = (0, 0, 0, 0)
    @State private var stubCount: Int = 0
    @State private var statusMessage: String = ""
    @State private var isWorking = false
    @State private var showWipeConfirm = false
    /// Mirrors HistoryImporter.lastImportStats, captured into @State so SwiftUI
    /// re-renders when refreshCounts() reads new values.
    @State private var importStats: HistoryImporter.ImportStats = HistoryImporter.ImportStats()
    @State private var importError: String? = nil

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

                        // v0.3.7: surface the importer's per-session diagnostics
                        // so we can see WHY the import is partially failing.
                        section("LAST IMPORT") {
                            row("Parsed sessions",  "\(importStats.parsedSessionCount)")
                            row("Saved sessions",   "\(importStats.savedSessionCount)")
                            row("Failed sessions",  "\(importStats.failedSessionCount)")
                            row("Exercises created","\(importStats.totalExercisesCreated)")
                            row("Sets created",     "\(importStats.totalSetsCreated)")
                            if let n = importStats.lastErrorAtSession {
                                row("Last error at session", "#\(n)")
                            }
                        }

                        // Red error banner if anything failed.
                        if let err = importError {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("IMPORT ERROR")
                                    .font(.system(size: 11, weight: .bold))
                                    .kerning(1.5)
                                    .foregroundColor(VoltraColor.warn)
                                Text(err)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(VoltraColor.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(VoltraColor.bgElev2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(VoltraColor.warn.opacity(0.5), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // v0.4.6.3: Demo Mode toggle. Persists across
                        // launches in real UserDefaults; flipping it here
                        // either enters or exits the demo session.
                        section("DEMO MODE") {
                            HStack {
                                Text(demo.isActive ? "Demo Mode is active" : "Demo Mode is off")
                                    .font(.system(size: 14))
                                    .foregroundColor(VoltraColor.text)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { demo.isActive },
                                    set: { newVal in
                                        if newVal {
                                            guard let handler = DemoTelemetryBridge.shared.handler else { return }
                                            demo.note(.buttonTap(label: "Demo toggle ON", screen: "Debug"))
                                            demo.enter(source: .settingsRestore, onTelemetry: handler)
                                        } else {
                                            demo.note(.buttonTap(label: "Demo toggle OFF", screen: "Debug"))
                                            _ = demo.exit()
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .tint(VoltraColor.accent)
                            }
                            Text("While active, no logs, sets, or settings are written to disk. The session is captured to a JSON trace you can send to the developer.")
                                .font(.system(size: 12))
                                .foregroundColor(VoltraColor.textDim)
                        }

                        // Build 37: HealthKit / Apple Watch status panel.
                        // Mirrors the home-screen healthPill but with full
                        // text and a 'Request again' button, so anyone
                        // looking for HK state has one obvious place to
                        // check on top of the chip on the home header.
                        section("APPLE WATCH / HEALTHKIT") {
                            row("HealthKit available", health.isAvailable ? "yes" : "no")
                            row("Authorization requested", health.hasRequestedAuthorization ? "yes" : "not yet")
                            if let hr = health.currentHR {
                                row("Current HR (bpm)", "\(hr)")
                            } else {
                                row("Current HR (bpm)", "\u{2014}")
                            }
                            if let last = health.lastHRSampleAt {
                                let secs = Int(Date().timeIntervalSince(last))
                                row("Last HR sample", "\(secs)s ago")
                            } else {
                                row("Last HR sample", "never")
                            }
                            row("Session kcal", String(format: "%.1f", health.sessionKcal))
                            actionButton(
                                title: health.hasRequestedAuthorization
                                    ? "Re-request HealthKit access"
                                    : "Request HealthKit access",
                                systemImage: "heart.text.square",
                                tint: VoltraColor.accent
                            ) {
                                health.requestAuthIfNeeded()
                            }
                            Text("If the system permission sheet didn't appear on first launch, tap the button above. iOS may also require you to enable HealthKit access in Settings -> Privacy & Security -> Health -> VOLTRA Live.")
                                .font(.system(size: 12))
                                .foregroundColor(VoltraColor.textDim)
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
        importStats = HistoryImporter.lastImportStats
        importError = HistoryImporter.lastImportError
        statusMessage = "Refreshed at \(timestamp())"
    }

    private func forceReimport() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Re-importing seed/history.md…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            do {
                try HistoryImporter.forceReimport(context: context)
                refreshCounts()
                statusMessage =
                    "Re-import done at \(timestamp())\n" +
                    "Saved \(importStats.savedSessionCount)/\(importStats.parsedSessionCount) sessions, " +
                    "\(importStats.totalExercisesCreated) ex, \(importStats.totalSetsCreated) sets"
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
                refreshCounts()
                statusMessage =
                    "Wiped \(wiped) sessions at \(timestamp())\n" +
                    "Saved \(importStats.savedSessionCount)/\(importStats.parsedSessionCount) sessions, " +
                    "\(importStats.totalExercisesCreated) ex, \(importStats.totalSetsCreated) sets"
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
        .environmentObject(DemoController())
}
