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
    @EnvironmentObject var health: HealthKitStore

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

    /// v0.4.5: Drop-set planner sheet.

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
                    dropSetSection
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
            // v0.4.6: Begin polling HealthKit for HR + active energy from
            // the user's Apple Watch workout. Lazy-prompts for permission.
            health.start()
        }
        .onDisappear {
            health.stop()
        }
    }

    /// Used as the bridge for drop-chain advances — each time SessionStore
    /// reports a drop boundary, LoggingStore calls this with the next
    /// planned weight so the device retargets.
    private func pushWeightToDevice(_ lb: Double) {
        // Update LoggingStore's internal pending weight so the upcoming-set
        // card mirrors what's on the device. We DO NOT modify
        // pendingPlannedWeightLb here — that's bound to drop #1 for the
        // parent set's record. The device target is computed below from
        // the explicit lb argument.
        let baseLb = Int(lb.rounded())
        let eccLb  = Int(logging.upcomingEccLb.rounded())
        let state = VoltraDeviceState(
            mode: .weight,
            modifiers: VoltraModifiers(eccentric: eccLb > 0, chains: false, inverse: false),
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

    // MARK: - 2×3 tile grid (REPS / PHASE / FORCE / RESISTANCE / TOTAL VOL / REST)

    private var tileGrid: some View {
        let live = ble.telemetry
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        // v0.4.6: Pulley mode multiplies user-felt load. Voltra base + ecc
        // overload all run through the same cable, so they all get ×m. Added
        // plates are physical weight on the rig and are NOT multiplied (they
        // don't go through the pulley).
        let m = logging.pulleyMultiplier
        let baseEff = (logging.pendingPlannedWeightLb ?? 0) * m
        let eccEff  = logging.upcomingEccLb * m
        let plates  = logging.upcomingAddedLoadLb ?? 0
        // v0.4.5: Per-rep total weight = Voltra base concentric + eccentric
        // overload + any plates already on the rig. This is what the user is
        // actually pushing each rep.
        let perRepTotalLb = baseEff + eccEff + plates
        // v0.4.5: Total volume = per-rep total × reps so far this set.
        // Falls back to the just-finalized set's reps so the tile stays
        // populated through rest. CompletedSet is value-typed; reps lives
        // on it directly.
        let liveSetReps = session.currentSet?.reps
            ?? session.completedSets.last?.reps
            ?? 0
        let totalVolumeLb = perRepTotalLb * Double(liveSetReps)
        // Build a subline that explains the math in compact form, e.g.
        // "50 +5 ecc ×2" (×2 only when pulley mode active). Hide if ambiguous.
        let resistanceSubline: String? = {
            var pieces: [String] = []
            if baseEff > 0 { pieces.append(formatLbCompact(baseEff)) }
            if eccEff > 0 { pieces.append("+\(formatLbCompact(eccEff)) ecc") }
            if plates > 0 { pieces.append("+\(formatLbCompact(plates)) pl") }
            if logging.pulleyMode { pieces.append("\u{00d7}2 pulley") }
            return pieces.isEmpty ? nil : pieces.joined(separator: " ")
        }()
        return LazyVGrid(columns: cols, spacing: 10) {
            // v0.4.6: REPS tile gets a tiny inline phase pill + an under-tile
            // 4s idle countdown bar so the user can see auto-finalize coming.
            repsTile(live: live)
            // v0.4.6: PHASE tile is gone — force curve already shows that.
            // DROP SET tile replaces it: button when inactive, cascade
            // progress + 4s/10s countdown bars when active.
            dropSetTile(perRepTotalLb: perRepTotalLb)
            tile(
                label: "FORCE",
                value: String(format: "%.0f", live.forceLb * m),
                unit: "lb",
                color: VoltraColor.accent
            )
            // v0.4.5: RESISTANCE = total per-rep load (con + ecc + plates).
            // This is the Vulture-equivalent "how much you're actually
            // pushing each rep" readout.
            tile(
                label: "RESISTANCE",
                value: formatLbCompact(perRepTotalLb),
                unit: "lb",
                color: VoltraColor.text,
                subline: resistanceSubline
            )
            // v0.4.5: TOTAL VOLUME = resistance × reps so far this set.
            tile(
                label: "TOTAL VOL",
                value: formatLbCompact(totalVolumeLb),
                unit: "lb",
                color: VoltraColor.pull,
                subline: liveSetReps > 0
                    ? "\(formatLbCompact(perRepTotalLb)) × \(liveSetReps) reps"
                    : nil
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
            // v0.4.6: HealthKit tiles. Em-dash empty state when nil/zero so
            // the user knows the data isn't flowing yet vs reading 0.
            tile(
                label: "HEART RATE",
                value: health.currentHR.map { String($0) } ?? "\u{2014}",
                unit: health.currentHR != nil ? "BPM" : nil,
                color: VoltraColor.danger,
                freshnessIndicator: .some(health.lastHRSampleAt)
            )
            tile(
                label: "KCAL",
                value: health.sessionKcal > 0 ? String(Int(health.sessionKcal.rounded())) : "\u{2014}",
                unit: health.sessionKcal > 0 ? "kcal" : nil,
                color: VoltraColor.accent,
                freshnessIndicator: .some(health.lastKcalSampleAt)
            )
        }
    }

    /// Compact lb formatter: integer when whole, one decimal otherwise.
    /// Used by the live tiles so 5.0 → "5" and 7.5 → "7.5".
    private func formatLbCompact(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%.1f", d)
    }

    // MARK: - Live force chart

    /// Same component DashboardView uses, fed from the same SessionStore set.
    /// Keeps the in-session view feature-parity with the dashboard so the user
    /// can see their realtime waveform without leaving LiveCaptureView.
    /// v0.4.4: Y-axis is anchored to planned total weight (Voltra base + ecc +
    /// added plates) + 15% headroom so light lifts (e.g. 10 lb total) no longer
    /// look tiny against a 40 lb default floor.
    private var forceChart: some View {
        // v0.4.5: While a set is in flight we use currentSet; once finalize
        // fires (4s of no movement), SessionStore stashes the trace into
        // lastFinalizedSamples so the chart KEEPS displaying the rep pattern
        // through the rest period instead of blanking. Cleared on next set.
        let samples = session.currentSet?.samples
            ?? session.lastFinalizedSamples
        let peak = session.currentSet?.peakLb
            ?? session.lastFinalizedPeakLb
        let m = logging.pulleyMultiplier
        // v0.4.6: planned ceiling is computed in EFFECTIVE space so a
        // 50 lb device under 2× pulley reads as 100 lb on the y-axis,
        // matching the smoothed sample values the chart will plot.
        let planned = ((logging.pendingPlannedWeightLb ?? 0) + logging.upcomingEccLb) * m
            + (logging.upcomingAddedLoadLb ?? 0)
        return ForceChartView(
            samples: samples,
            peakLb: peak,
            plannedCeilingLb: planned > 0 ? planned : nil,
            forceMultiplier: m
        )
        .frame(minHeight: 280)
    }

    // MARK: - v0.4.6: REPS tile with inline phase + idle bar

    /// REPS tile + tiny phase pill + 4s idle countdown bar at the bottom.
    /// The idle bar fills as `SessionStore.idleProgress01` ramps 0→1 over
    /// the 4-second IDLE_GRACE window. Only visible when phase is idle and
    /// the user has at least one rep — otherwise it stays empty.
    private func repsTile(live: LiveTelemetry) -> some View {
        // Re-evaluate every 0.1s so the idle bar smoothly animates without
        // depending on telemetry packets arriving (since idle = no packets).
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            VStack(alignment: .leading, spacing: 4) {
                Text("REPS")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(live.repCount)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(VoltraColor.text)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    // Tiny inline phase pill — takes PHASE tile's old job.
                    Text(phaseLabel(live.phase))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1.0)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VoltraColor.phase(live.phase).opacity(0.18))
                        .foregroundColor(VoltraColor.phase(live.phase))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                // Idle countdown bar — fills 0→1 over 4s when idle.
                idleCountdownBar
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 2pt-tall progress line. When phase is non-idle or no set is active
    /// it renders as a near-invisible faint track so the tile height
    /// doesn't jump when the bar appears/disappears.
    private var idleCountdownBar: some View {
        let progress = session.idleProgress01
        let isActive = progress > 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(VoltraColor.border.opacity(0.4))
                Capsule()
                    .fill(isActive ? VoltraColor.returnPhase : Color.clear)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 2)
    }

    // MARK: - v0.4.6: DROP SET tile (replaces PHASE tile)

    /// DROP SET tile. Two states:
    ///   - INACTIVE: shows a button-style label "DROP SET" with the
    ///     preview of the next two cascade weights underneath.
    ///   - ACTIVE: shows the current device weight, the next two upcoming
    ///     weights, and two countdown bars (4s next-drop, 10s finalize).
    /// Re-evaluates every 0.1s while active so countdown bars animate
    /// smoothly against the wall clock.
    private func dropSetTile(perRepTotalLb: Double) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            Button {
                // Tap behavior:
                //  - inactive → start a cascade at the current planned weight
                //  - active   → bump the cascade tier (5/5% → 10/10% → 15/15%)
                //               PREVIEW ONLY. The weight does not change on
                //               tap; the 4s fuse fires the drop at whatever
                //               tier is current when it elapses. (build 30)
                if logging.dropSetActive {
                    logging.bumpCascadeTier()
                } else {
                    let starting = logging.pendingPlannedWeightLb ?? 0
                    guard starting > 0 else { return }
                    logging.startDropSet(startingLb: starting) { lb in
                        pushWeightToDevice(lb)
                    }
                }
            } label: {
                dropSetTileBody(perRepTotalLb: perRepTotalLb)
            }
            .buttonStyle(.plain)
            // v0.4.6.1: Long-press (0.8s) cancels an active drop chain.
            // simultaneousGesture so the long-press wins over the tap when
            // the press lasts ≥0.8s; a quick tap still bumps the tier.
            // No-op when inactive.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8)
                    .onEnded { _ in
                        if logging.dropSetActive {
                            logging.cancelDropSet()
                            // Light haptic so the user knows the cancel registered.
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                        }
                    }
            )
        }
    }

    @ViewBuilder
    private func dropSetTileBody(perRepTotalLb: Double) -> some View {
        if logging.dropSetActive {
            dropSetTileActive
        } else {
            dropSetTileInactive
        }
    }

    /// Inactive state: "DROP SET" call-to-action + preview of next 2 weights.
    /// Preview is rendered in EFFECTIVE units so the user always sees what
    /// they'll feel — under pulley mode, that's 2× the device setting.
    private var dropSetTileInactive: some View {
        let m = logging.pulleyMultiplier
        let startingEff = (logging.pendingPlannedWeightLb ?? 0) * m
        let preview = startingEff > 0 ? logging.previewNextCascade(from: startingEff, count: 2) : []
        let canStart = preview.count >= 1
        return VStack(alignment: .leading, spacing: 6) {
            Text("DROP SET")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.transition)
            Text("TAP TO START")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(canStart ? VoltraColor.text : VoltraColor.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            if canStart {
                Text("next: \(preview.map { formatLbCompact($0) }.joined(separator: " \u{2192} "))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(VoltraColor.textFaint)
                    .lineLimit(1)
            } else {
                Text("set a weight first")
                    .font(.system(size: 9))
                    .foregroundColor(VoltraColor.textFaint)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(VoltraColor.transition.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.transition.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Active state: current weight, next-2 preview, 4s + 10s countdown bars.
    /// All weights shown EFFECTIVE (× pulley multiplier).
    private var dropSetTileActive: some View {
        let m = logging.pulleyMultiplier
        let current = (logging.pendingPlannedWeightLb ?? 0) * m
        let preview = logging.previewNextCascade(from: current, count: 2)
        let now = Date()
        let nextDropProgress: Double = {
            guard let target = logging.nextDropFiresAt else { return 0 }
            // Fill as we APPROACH the next drop — 0 at start, 1 at fire.
            let total: Double = 4.0
            let remaining = target.timeIntervalSince(now)
            return min(1, max(0, 1 - remaining / total))
        }()
        let finalizeProgress: Double = {
            guard let target = logging.dropFinalizeAt else { return 0 }
            let total: Double = 10.0
            let remaining = target.timeIntervalSince(now)
            return min(1, max(0, 1 - remaining / total))
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("DROP \(logging.currentDropIndex)")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.transition)
                Spacer()
                Text(logging.cascadeStepLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.textFaint)
            }
            // v0.4.6.1: discoverability hint for the long-press-to-cancel.
            Text("hold to cancel")
                .font(.system(size: 8, weight: .semibold))
                .kerning(0.8)
                .foregroundColor(VoltraColor.textFaint.opacity(0.7))
            Text(formatLbCompact(current))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.transition)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !preview.isEmpty {
                Text("\u{2192} \(preview.map { formatLbCompact($0) }.joined(separator: " \u{2192} "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VoltraColor.textFaint)
                    .lineLimit(1)
            } else {
                Text("bottomed out")
                    .font(.system(size: 9))
                    .foregroundColor(VoltraColor.textFaint)
            }
            Spacer(minLength: 0)
            // Two stacked progress bars: top = 4s next-drop fuse,
            // bottom = 10s finalize fuse. Faint label tag.
            VStack(spacing: 3) {
                cascadeBar(progress: nextDropProgress, color: VoltraColor.transition, label: "4s")
                cascadeBar(progress: finalizeProgress, color: VoltraColor.returnPhase, label: "10s")
            }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(VoltraColor.transition.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.transition, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Single horizontal progress line with a small inline label.
    private func cascadeBar(progress: Double, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(VoltraColor.border.opacity(0.4))
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 3)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.textFaint)
                .frame(width: 16, alignment: .trailing)
        }
    }

    private func phaseLabel(_ p: VoltraPhase) -> String {
        switch p {
        case .pull:       return "PULL"
        case .return:     return "RETURN"
        case .transition: return "TRANS"
        case .idle:       return "IDLE"
        }
    }

    /// `freshnessIndicator` (build 30): when set, renders a small PulseDot
    /// next to the label that pulses green while data is fresh and fades
    /// to grey when stale. Used by the HR and kcal tiles to show whether
    /// HealthKit is actively streaming samples from the paired Watch.
    private func tile(label: String, value: String, unit: String? = nil, color: Color, subline: String? = nil, freshnessIndicator: Date?? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                if let last = freshnessIndicator {
                    PulseDot(lastSampleAt: last)
                }
                Spacer(minLength: 0)
            }
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

    /// v0.4.6.1: Effective base weight (what the user actually feels).
    /// Backed by pendingPlannedWeightLb (DEVICE) × pulleyMultiplier. The big
    /// dial and the eccentric dial both render this. Nudge buttons still
    /// adjust the underlying device value by ±5 / ±1; the dial visually
    /// moves by ±10 / ±2 under pulley mode.
    private var weightLb: Double {
        (logging.pendingPlannedWeightLb ?? 0) * logging.pulleyMultiplier
    }

    /// Effective eccentric overload (× pulley multiplier, like base weight).
    private var eccLbEffective: Double {
        logging.upcomingEccLb * logging.pulleyMultiplier
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
                // v0.4.6.1: "lb" baseline; under pulley mode show the device
                // value too so the user can confirm what the Voltra is set to.
                if logging.pulleyMode {
                    Text("lb · device \(Int(logging.pendingPlannedWeightLb ?? 0))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                } else {
                    Text("lb")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                }
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
            // v0.4.6.1: ECC dial also renders effective (× pulley).
            Text("+\(Int(eccLbEffective))")
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
                // v0.4.6: Pulley Mode toggle. Sticky-to-next-set, reset on
                // pickExercise. When on, all user-felt loads are 2× the
                // device setting (force chart, RESISTANCE/TOTAL VOL/FORCE
                // tiles, drop cascade math, persisted weight + peak force).
                pulleyModeChip
            }

            if addWeightOpen {
                addWeightPicker
            }
        }
    }

    /// Pulley Mode toggle chip. Tap to flip. Visual state mirrors the Added
    /// plates chip styling so they read as a coherent pair.
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

    // MARK: - Drop-set section (v0.4.6)

    /// v0.4.6: only shows the small Cancel chip while a cascade is active.
    /// The DROP SET tile in the grid carries everything else (button when
    /// idle; weight, next-2 preview, and 4s/10s countdown bars when active).
    @ViewBuilder
    private var dropSetSection: some View {
        if logging.dropSetActive {
            dropCancelChip
        } else {
            EmptyView()
        }
    }

    private var dropCancelChip: some View {
        HStack {
            Text("Cascade live · step \(logging.cascadeStepLabel)")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textDim)
            Spacer()
            Button {
                logging.cancelDropSet()
            } label: {
                Text("Cancel cascade")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(VoltraColor.bgElev2)
                    .foregroundColor(VoltraColor.textDim)
                    .overlay(
                        Capsule().stroke(VoltraColor.border, lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
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
            .environmentObject(HealthKitStore())
    }
}
