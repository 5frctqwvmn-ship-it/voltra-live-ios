// LiveCaptureView.swift
// v0.4.3 — Live force chart restored inside the session.
//
// What changed in v0.4.3:
//   - Re-added the ForceChartView (the same phase-colored 30s rolling waveform
//     used on DashboardView) below the 2x2 tile grid. Pulls from
//     session.currentSet.samples + peakLb so it stays in sync with the
//     dashboard view of the same set.
//
// What changed in v0.4.2:
//   - Weight nudges (−5/−1/+1/+5) now write to the Voltra device IMMEDIATELY
//     via VoltraWriter.apply(...). Previously this view only updated
//     LoggingStore.pendingPlannedWeightLb, so changing weight mid-rest had
//     no effect on the device until the next ExerciseDetailView visit.
//   - REST tile is now tap-to-reset, mirroring DashboardView. Tapping calls
//     SessionStore.tapRestTile() to restart the rest countdown at 0:00.
//   - "Add weight" chip is renamed "Added plates" and the type picker is gone:
//     the only meaning is "physical plates already on the machine" (e.g. a
//     leg-extension stack starting at 20 lb at the lowest pin). The data
//     field stays addedLoadLb/addedLoadType for storage compatibility, but
//     addedLoadType is locked to "plates" going forward.
//   - Logged-set expanded view shows Voltra / Added plates / Total clearly.
//
// Layout (top→bottom inside a scroll view):
//   1. Header — exercise name + day-type strip + "SET N of M" big counter
//   2. 2×2 tile grid: REPS / PHASE / FORCE / REST
//      REST reads SessionStore.restActive + SessionStore.restFormatted
//      DIRECTLY (kills the v0.3.x bug where RestTimerView.now reset every
//      time LiveCaptureView's body re-evaluated). One source of truth, one
//      timer, owned by SessionStore.
//   3. Upcoming-set card — large weight number with −5/−1/+1/+5 nudges,
//      eccentric (when relevant), mode chips, target reps, and an
//      "Added plates" chip for non-Voltra plate weight already on the rig.
//   4. Logged sets list — tap a row to expand+edit inline,
//      swipe-left to delete with an undo toast.
//   5. Bottom actions — Next exercise / End session.
//
// Auto-log: handleCompletedSetsUpdate in LoggingStore now writes a LoggedSet
// the instant telemetry detects a set boundary. This view never opens
// SetLogView. The user only interacts with rows after the fact.
//
// What's gone vs. v0.3.x:
//   - RestTimerView (replaced by direct SessionStore read)
//   - "Log set manually" CTA (auto-log replaces it)
//   - SetLogView sheet trigger via pendingTelemetrySet
//
// Build visibility: still surfaced via BuildBadgeOverlay applied at the app
// level; this view does not need its own build chip.

import SwiftUI
import SwiftData

struct LiveCaptureView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore

    @State private var showingEndConfirm = false
    @State private var showingExportSheet = false
    @State private var lastEndedSession: WorkoutSession? = nil

    /// Most-recently-deleted set, kept around briefly so the user can undo.
    @State private var pendingUndo: DeletedSetSnapshot? = nil
    @State private var undoCountdownTask: Task<Void, Never>? = nil

    /// Set currently expanded for inline edit. Identified by id.
    @State private var expandedSetID: UUID? = nil

    /// Added-plates chip expansion state.
    @State private var addWeightOpen: Bool = false

    /// VoltraWriter for live mid-session weight changes. v0.4.2: every nudge
    /// fires through this writer so the device updates immediately during
    /// rest. Held in an ObservableObject so the BLE manager can be attached
    /// in onAppear (env objects aren't available in init).
    @StateObject private var writerHolder = LiveWriterHolder()

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    tileGrid
                    forceChart
                    upcomingSetCard
                    loggedSetsSection
                    bottomActions
                    Spacer(minLength: 60)
                }
                .padding(16)
            }

            if let snap = pendingUndo {
                undoToast(for: snap)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pendingUndo != nil)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingEndConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .alert("End session?", isPresented: $showingEndConfirm) {
            Button("Keep going", role: .cancel) { }
            Button("End and export", role: .destructive) {
                if let ended = logging.endSession() {
                    lastEndedSession = ended
                    showingExportSheet = true
                }
            }
        } message: {
            Text("This will save all logged sets and stop recording.")
        }
        .sheet(isPresented: $showingExportSheet, onDismiss: {
            lastEndedSession = nil
            logging.sessionExitTick &+= 1
        }) {
            if let s = lastEndedSession {
                ExportSheet(session: s)
                    .environmentObject(logging)
            }
        }
        .onAppear {
            // Attach BLE to the writer once env is available. Idempotent.
            writerHolder.attach(ble: ble)
        }
    }

    // MARK: - Header

    private var header: some View {
        let exName = logging.activeInstance?.exercise?.name ?? "Exercise"
        let dayLabel = logging.activeSession?.displayLabel ?? ""
        let setNum = logging.setNumberForCurrentInstance
        let plannedTotal = plannedSetCount
        let counterText: String = {
            if let total = plannedTotal {
                return "SET \(setNum) of \(total)"
            }
            return "SET \(setNum)"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text(dayLabel.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundColor(VoltraColor.accent)
            Text(exName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(VoltraColor.text)
            Text(counterText)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// M = previous session's set count for this exercise. Drives "SET N of M".
    private var plannedSetCount: Int? {
        guard let ex = logging.activeInstance?.exercise else { return nil }
        let prev = logging.previousSetSeries(for: ex).count
        return prev > 0 ? prev : nil
    }

    // MARK: - 2×2 tile grid (REPS / PHASE / FORCE / REST)

    private var tileGrid: some View {
        let live = ble.telemetry
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            tile(
                label: "REPS",
                value: "\(live.repCount)",
                color: VoltraColor.text
            )
            tile(
                label: "PHASE",
                value: phaseLabel(live.phase),
                color: VoltraColor.phase(live.phase)
            )
            tile(
                label: "FORCE",
                value: String(format: "%.0f", live.forceLb),
                unit: "lb",
                color: VoltraColor.accent
            )
            // REST tile is tap-to-reset (parity with DashboardView). Tapping
            // restarts the rest countdown via SessionStore.tapRestTile().
            Button {
                session.tapRestTile()
            } label: {
                tile(
                    label: "REST",
                    // Read from SessionStore.restActive — the SAME source-of-truth
                    // DashboardView uses, which works correctly. No second timer,
                    // no Combine sink, no view-recreation reset bug.
                    value: session.restActive ? session.restFormatted : "0:00",
                    color: session.restActive ? VoltraColor.returnPhase : VoltraColor.textFaint,
                    subline: session.restActive ? "tap to restart" : "tap to start"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Live force chart

    /// Same component DashboardView uses, fed from the same SessionStore set.
    /// Keeps the in-session view feature-parity with the dashboard so the user
    /// can see their realtime waveform without leaving LiveCaptureView.
    private var forceChart: some View {
        let samples = session.currentSet?.samples ?? []
        let peak = session.currentSet?.peakLb ?? 0
        return ForceChartView(samples: samples, peakLb: peak)
            .frame(minHeight: 180)
    }

    private func phaseLabel(_ p: VoltraPhase) -> String {
        switch p {
        case .pull:       return "PULL"
        case .return:     return "RETURN"
        case .transition: return "TRANS"
        case .idle:       return "IDLE"
        }
    }

    private func tile(label: String, value: String, unit: String? = nil, color: Color, subline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let u = unit {
                    Text(u)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
            if let sub = subline {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundColor(VoltraColor.textFaint)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Upcoming set card

    private var upcomingSetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("UPCOMING SET")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if let reps = effectiveTargetReps {
                    Text("Target \(reps) reps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VoltraColor.textDim)
                }
            }

            // Big weight nudger
            weightNudgerRow

            // Eccentric (when applicable)
            if showsEccentric {
                eccentricNudgerRow
            }

            // Mode chips
            modeChipsRow

            // Added-weight chip + inline picker
            addedWeightSection
        }
        .padding(16)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VoltraColor.accentDim, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Effective base weight binding — backed by pendingPlannedWeightLb.
    private var weightLb: Double {
        logging.pendingPlannedWeightLb ?? 0
    }

    private var effectiveTargetReps: Int? {
        let r = logging.upcomingTargetReps
        return r > 0 ? r : nil
    }

    private var showsEccentric: Bool {
        logging.upcomingMode == .eccentric || logging.upcomingEccLb > 0
    }

    private var weightNudgerRow: some View {
        HStack(spacing: 8) {
            nudgeButton(label: "−5") { adjustWeight(-5) }
            nudgeButton(label: "−1") { adjustWeight(-1) }
            VStack(spacing: 2) {
                Text("\(Int(weightLb))")
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("lb")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VoltraColor.textFaint)
            }
            .frame(maxWidth: .infinity)
            nudgeButton(label: "+1") { adjustWeight(+1) }
            nudgeButton(label: "+5") { adjustWeight(+5) }
        }
    }

    private var eccentricNudgerRow: some View {
        HStack(spacing: 8) {
            Text("ECC")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundColor(VoltraColor.returnPhase)
                .frame(width: 38, alignment: .leading)
            nudgeButton(label: "−5", small: true) { adjustEcc(-5) }
            nudgeButton(label: "−1", small: true) { adjustEcc(-1) }
            Text("+\(Int(logging.upcomingEccLb))")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.returnPhase)
                .frame(maxWidth: .infinity)
            nudgeButton(label: "+1", small: true) { adjustEcc(+1) }
            nudgeButton(label: "+5", small: true) { adjustEcc(+5) }
        }
    }

    private var modeChipsRow: some View {
        let modes: [SetMode] = [.working, .warmUp, .eccentric, .band, .pause, .dropSet, .isoHold]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modes, id: \.self) { m in
                    Button {
                        logging.upcomingMode = m
                        // v0.4.2: mode change also retargets the device.
                        pushUpcomingStateToDevice()
                    } label: {
                        Text(m.label)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                logging.upcomingMode == m
                                    ? VoltraColor.accent
                                    : VoltraColor.bgElev2
                            )
                            .foregroundColor(
                                logging.upcomingMode == m
                                    ? VoltraColor.bg
                                    : VoltraColor.text
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Added-weight chip

    private var addedWeightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation { addWeightOpen.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: addWeightOpen ? "minus.circle" : "plus.circle")
                        let title = addWeightChipTitle
                        Text(title)
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
            }

            if addWeightOpen {
                addWeightPicker
            }
        }
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

    /// v0.4.2: type picker removed. "Added plates" only ever means physical
    /// plates already loaded on the machine (e.g. leg-extension stack starting
    /// at 20 lb on the lowest pin). The lb count gets added to the Voltra
    /// reading to compute total work. addedLoadType is locked to "plates".
    private var addWeightPicker: some View {
        let currentLb = Int(logging.upcomingAddedLoadLb ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Plates already on the machine (not from Voltra). Added to your set’s logged total.")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                nudgeButton(label: "−5", small: true) { adjustAddedLoad(-5) }
                nudgeButton(label: "−1", small: true) { adjustAddedLoad(-1) }
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

    // MARK: - Nudge helpers

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

    private func adjustWeight(_ delta: Int) {
        let cur = Int(logging.pendingPlannedWeightLb ?? 0)
        let next = max(0, min(500, cur + delta))
        logging.pendingPlannedWeightLb = Double(next)
        // v0.4.2: push the new weight to the Voltra device IMMEDIATELY so the
        // user can adjust mid-rest and the device retargets before the next
        // set begins. VoltraWriter.apply() debounces internally, so even rapid
        // tap sequences only emit one BLE write per debounce window.
        pushUpcomingStateToDevice()
    }

    private func adjustEcc(_ delta: Int) {
        let cur = Int(logging.upcomingEccLb)
        let next = max(0, min(300, cur + delta))
        logging.upcomingEccLb = Double(next)
        if next > 0, logging.upcomingMode != .eccentric {
            // Don't auto-flip mode — just allow eccentric weight on any mode.
        }
        pushUpcomingStateToDevice()
    }

    private func adjustAddedLoad(_ delta: Int) {
        let cur = Int(logging.upcomingAddedLoadLb ?? 0)
        let next = max(0, min(300, cur + delta))
        logging.upcomingAddedLoadLb = next > 0 ? Double(next) : nil
        // v0.4.2: type is locked to "plates" (machine plates already on the rig).
        // We always set it so legacy nil rows don't surface as "chains".
        logging.upcomingAddedLoadType = "plates"
        // "Added plates" is NOT sent to the Voltra — it's a logging-only field
        // representing weight already on the machine. No push to writer.
    }

    /// Build a coherent VoltraDeviceState from the upcoming-set fields and
    /// hand it to the writer. The writer debounces and diffs internally.
    private func pushUpcomingStateToDevice() {
        // Map LoggingStore's SetMode to the VoltraMode the writer expects.
        // Only weight + band + damper are device-relevant; everything else
        // (warmup/working/eccentric/pause/dropset/isohold) is a *logging*
        // mode and runs the device in plain weight mode.
        let voltraMode: VoltraMode = {
            switch logging.upcomingMode {
            case .band:    return .band
            default:       return .weight
            }
        }()
        let baseLb = Int((logging.pendingPlannedWeightLb ?? 0).rounded())
        let eccLb  = Int(logging.upcomingEccLb.rounded())
        let state = VoltraDeviceState(
            mode: voltraMode,
            modifiers: VoltraModifiers(
                eccentric: eccLb > 0,
                chains: false,
                inverse: false
            ),
            weights: VoltraWeights(
                baseLb: baseLb,
                eccentricLb: eccLb,
                chainsLb: 0,
                bandMaxForceLb: 0,
                damperLevel: 0
            )
        )
        writerHolder.writer?.apply(state)
    }

    // MARK: - Logged sets section

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
            Text("Start lifting — sets auto-log after a 4s rest.")
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

    // MARK: - Bottom actions

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
                showingEndConfirm = true
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

// MARK: - Live writer holder

/// Tiny ObservableObject that owns the LiveCapture VoltraWriter. Same pattern
/// as ExerciseDetailView.WriterHolder — SwiftUI views can't reference
/// @EnvironmentObject in init, so we lazily attach the BLE manager onAppear.
@MainActor
private final class LiveWriterHolder: ObservableObject {
    var writer: VoltraWriter?

    func attach(ble: VoltraBLEManager) {
        guard writer == nil else { return }
        writer = VoltraWriter(
            writeFrame: { [weak ble] frame in ble?.writeControlFrame(frame) },
            log:        { [weak ble] msg   in ble?.addLog(msg) }
        )
    }
}

// MARK: - SwipeableSetRow

/// A logged-set row that supports tap-to-expand-edit and swipe-left-to-delete.
/// Implemented as a List-less row using DragGesture for the swipe so it
/// composes inside the parent ScrollView (List would conflict).
private struct SwipeableSetRow: View {
    let set: LoggedSet
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSave: (EditingState) -> Void
    let onDelete: () -> Void

    /// Local copy of editable fields. Reset on expand.
    struct EditingState {
        var weightLb: Double
        var eccentricLb: Double?
        var reps: Int
        var addedLoadLb: Double?
        var addedLoadType: String?
        var mode: SetMode
        var notes: String?
    }

    @State private var editing: EditingState = EditingState(
        weightLb: 0, eccentricLb: nil, reps: 0,
        addedLoadLb: nil, addedLoadType: nil, mode: .working, notes: nil
    )

    @State private var dragOffset: CGFloat = 0
    @State private var revealedDelete: Bool = false

    private let deleteRevealWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background (visible behind on drag)
            HStack {
                Spacer()
                Button(action: onDelete) {
                    VStack(spacing: 2) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Delete")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: deleteRevealWidth)
                    .frame(maxHeight: .infinity)
                    .background(VoltraColor.danger)
                }
                .buttonStyle(.plain)
                .opacity(revealedDelete ? 1 : 0)
            }

            // Foreground row
            VStack(alignment: .leading, spacing: 0) {
                rowSummary
                if isExpanded { editor }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { v in
                        // Left swipe only
                        if v.translation.width < 0 {
                            dragOffset = max(-deleteRevealWidth - 20, v.translation.width)
                        } else if revealedDelete {
                            // Allow swipe-right to dismiss the delete reveal
                            dragOffset = min(0, -deleteRevealWidth + v.translation.width)
                        }
                    }
                    .onEnded { v in
                        let threshold: CGFloat = -deleteRevealWidth / 2
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if v.translation.width < threshold {
                                dragOffset = -deleteRevealWidth
                                revealedDelete = true
                            } else {
                                dragOffset = 0
                                revealedDelete = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if revealedDelete {
                    withAnimation { dragOffset = 0; revealedDelete = false }
                } else {
                    syncEditingFromModel()
                    onToggleExpand()
                }
            }
        }
        .clipped()
    }

    private var rowSummary: some View {
        // v0.4.2: split Voltra weight from "Added plates" so the user can
        // tell at a glance which lbs came from the device vs. machine plates
        // already on the rig.
        let plates = (set.addedLoadLb ?? 0)
        // Display the legacy chains field as plates if a row predates v0.4.2
        // and only has chainsLb set. This keeps imported history readable.
        let legacyPlates = plates == 0 ? (set.chainsLb ?? 0) : 0
        let totalPlates = plates + legacyPlates
        let totalLb = set.weightLb + totalPlates
        return HStack(spacing: 12) {
            Text("\(set.orderIndex)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // Primary: total lifted weight
                    Text("\(formatLb(totalLb)) lb")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    if totalPlates > 0 {
                        // Show breakdown so total isn't ambiguous
                        Text("= \(formatLb(set.weightLb)) Voltra + \(formatLb(totalPlates)) plates")
                            .font(.system(size: 11))
                            .foregroundColor(VoltraColor.textFaint)
                    }
                    if let e = set.eccentricLb, e > 0 {
                        Text("+\(formatLb(e)) ecc")
                            .font(.system(size: 12))
                            .foregroundColor(VoltraColor.returnPhase)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(set.reps) reps")
                        .font(.system(size: 12))
                        .foregroundColor(VoltraColor.textDim)
                    if !set.labelText.isEmpty {
                        Text(set.labelText)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VoltraColor.bgElev2)
                            .clipShape(Capsule())
                            .foregroundColor(VoltraColor.textDim)
                    }
                }
            }
            Spacer()
            Text(String(format: "%.0f lb pk", set.peakForceLb))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(VoltraColor.textFaint)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12))
                .foregroundColor(VoltraColor.textFaint)
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 12) {
            Divider().background(VoltraColor.border).padding(.vertical, 8)
            editorRow(
                label: "Weight",
                value: Int(editing.weightLb),
                unit: "lb",
                onMinus: { editing.weightLb = max(0, editing.weightLb - 5) },
                onPlus: { editing.weightLb = min(500, editing.weightLb + 5) }
            )
            editorRow(
                label: "Reps",
                value: editing.reps,
                unit: "",
                onMinus: { editing.reps = max(0, editing.reps - 1) },
                onPlus: { editing.reps = min(99, editing.reps + 1) }
            )
            editorRow(
                label: "Eccentric",
                value: Int(editing.eccentricLb ?? 0),
                unit: "lb",
                onMinus: {
                    let cur = Int(editing.eccentricLb ?? 0)
                    let next = max(0, cur - 5)
                    editing.eccentricLb = next > 0 ? Double(next) : nil
                },
                onPlus: {
                    let cur = Int(editing.eccentricLb ?? 0)
                    editing.eccentricLb = Double(min(300, cur + 5))
                }
            )
            // v0.4.2: "Added plates" — plates already on the machine, not Voltra weight.
            editorRow(
                label: "Added plates",
                value: Int(editing.addedLoadLb ?? 0),
                unit: "lb",
                onMinus: {
                    let cur = Int(editing.addedLoadLb ?? 0)
                    let next = max(0, cur - 5)
                    editing.addedLoadLb = next > 0 ? Double(next) : nil
                },
                onPlus: {
                    let cur = Int(editing.addedLoadLb ?? 0)
                    editing.addedLoadLb = Double(min(300, cur + 5))
                    editing.addedLoadType = "plates"
                }
            )
            // v0.4.2: explicit Voltra / Added plates / Total summary inside
            // the editor so the breakdown is unambiguous when reviewing.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TOTAL")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text("\(Int(editing.weightLb)) Voltra + \(Int(editing.addedLoadLb ?? 0)) plates")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VoltraColor.textFaint)
                Text("= \(Int(editing.weightLb + (editing.addedLoadLb ?? 0))) lb")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.accent)
            }
            HStack {
                Button("Cancel") {
                    onToggleExpand()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(VoltraColor.textDim)
                Spacer()
                Button("Save") {
                    onSave(editing)
                }
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(VoltraColor.accent)
                .foregroundColor(VoltraColor.bg)
                .clipShape(Capsule())
            }
        }
    }

    private func editorRow(label: String, value: Int, unit: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .kerning(0.8)
                .foregroundColor(VoltraColor.textDim)
                .frame(width: 80, alignment: .leading)
            Button(action: onMinus) {
                Text("−")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 32)
                    .background(VoltraColor.bgElev2)
                    .foregroundColor(VoltraColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                }
            }
            .frame(maxWidth: .infinity)
            Button(action: onPlus) {
                Text("+")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 32)
                    .background(VoltraColor.bgElev2)
                    .foregroundColor(VoltraColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    private func syncEditingFromModel() {
        editing = EditingState(
            weightLb: set.weightLb,
            eccentricLb: set.eccentricLb,
            reps: set.reps,
            addedLoadLb: set.addedLoadLb,
            addedLoadType: set.addedLoadType,
            mode: set.mode,
            notes: set.notes
        )
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }
}

#Preview {
    NavigationStack {
        LiveCaptureView()
            .environmentObject(VoltraBLEManager())
            .environmentObject(SessionStore())
            .environmentObject(LoggingStore())
    }
}
