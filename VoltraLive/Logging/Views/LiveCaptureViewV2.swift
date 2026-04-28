// LiveCaptureViewV2.swift
//
// b53: V2 preview of the live-capture screen. Single-Voltra only.
// This is a 1:1 port of the design-system spec at:
//   design-system/ui-kit.html
//   design-system/preview/index.html (principle 06: REPS PHASE FORCE REST)
// from the design-studio branch (HEAD 74d0d3b9). The first cut of V2
// I shipped did NOT match that spec \u2014 it had REPS / PEAK / HR / REST
// with no phase-tinted PHASE tile, no HR+KCAL paired strip, and no
// CompareStripView. This rewrite fixes that.
//
// Layout (top \u2192 bottom inside a scroll view):
//   1. Header strip       \u2014 LIVE kicker + exercise name + day pill
//   2. PRIMARY 2x2 GRID   \u2014 REPS / PHASE (wash tint) / FORCE / REST
//   3. HR / KCAL pair     \u2014 secondary strip with pulse dots
//   4. CompareStripView   \u2014 LAST REPS / BEST FORCE / TARGET
//   5. ForceChartView     \u2014 30s rolling, phase-segmented (reused)
//   6. PLAN + LOG SET CTA \u2014 single primary button
//
// Hard rules from design-system/SKILL.md, enforced here:
//   - Dark canvas only, single accent color (no gradients).
//   - All live numbers mono + tabular.
//   - At most 4 primary tiles (REPS / PHASE / FORCE / REST).
//   - HR + KCAL are SECONDARY (smaller value, pulse dot indicator).
//   - Tile radius 18px, button radius 12px, 1px hairline borders.
//   - No emoji, no exclamation marks, operator voice.
//
// Container (LiveCaptureContainer) routes here only when V2 is opted
// in AND only one Voltra is paired AND chain<2 \u2014 so we can ignore
// dual / chain UX entirely in this file.

import SwiftUI

struct LiveCaptureViewV2: View {

    // MARK: Environment

    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var health: HealthKitStore
    @EnvironmentObject var mdm: MultiDeviceManager

    @Environment(\.dismiss) private var dismiss

    // MARK: Local state

    @State private var showingEndConfirm = false
    @State private var showingExportSheet = false
    @State private var lastEndedSession: WorkoutSession? = nil

    // Drives the pulse-dot animation on the HR / KCAL secondary tiles.
    @State private var pulseOn: Bool = false

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    headerStrip
                    primaryTileGrid
                    secondaryHRKcalRow
                    compareStrip
                    forceChartCard
                    planCard
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
        }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("V2")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.bg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VoltraColor.accent)
                    .clipShape(Capsule())
            }
        }
        .confirmationDialog(
            "What do you want to do?",
            isPresented: $showingEndConfirm,
            titleVisibility: .visible
        ) {
            Button("Just go back (keep session running)") { dismiss() }
            Button("End and export", role: .destructive) {
                if let active = logging.activeSession {
                    active.supersetTag = mdm.supersetTag
                }
                if let ended = logging.endSession() {
                    lastEndedSession = ended
                    showingExportSheet = true
                }
            }
            Button("Keep going (stay here)", role: .cancel) { }
        } message: {
            Text("End and export saves and stops recording. Just go back lets you peek at the home screen \u{2014} your session keeps running in the background.")
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
            health.start()
            // Kick the pulse-dot animation. 1 Hz, design-system spec.
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        }
    }

    // MARK: - 1. Header strip

    /// b53 V2: minimal header. LIVE kicker, exercise name, day pill.
    /// No superset kicker because V2 is gated single-Voltra.
    private var headerStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundColor(VoltraColor.accent)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(exerciseName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(VoltraColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let day = logging.activeSession?.dayTypeRaw, !day.isEmpty {
                    Text(day.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(VoltraColor.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().stroke(VoltraColor.accent.opacity(0.5), lineWidth: 1))
                }
                Text("SET \(setNumber)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(VoltraColor.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - 2. Primary 2x2 grid (REPS / PHASE / FORCE / REST)

    /// b53 V2: the canonical 4 primary tiles per design-system principle
    /// 06. PHASE tile uses a phase-tinted wash background that follows
    /// the live BLE phase. All numerals are mono + tabular at 72px.
    private var primaryTileGrid: some View {
        let live = ble.telemetry
        let reps = session.currentSet?.reps ?? 0
        let force = live.forceLb
        let rest = Int(session.restElapsedSeconds.rounded())
        let phase = live.phase

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                bigTile(
                    label: "REPS",
                    value: "\(reps)",
                    unit: nil,
                    valueColor: VoltraColor.text
                )
                phaseTile(phase: phase)
            }
            HStack(spacing: 12) {
                bigTile(
                    label: "FORCE",
                    value: force > 0 ? String(format: "%.0f", force) : "\u{2014}",
                    unit: force > 0 ? "lb" : nil,
                    valueColor: VoltraColor.phase(phase)
                )
                bigTile(
                    label: "REST",
                    value: formatRest(rest),
                    unit: nil,
                    valueColor: VoltraColor.text,
                    valueSize: 52  // smaller than 72 because MM:SS has more chars
                )
            }
        }
    }

    /// Spec-correct primary tile: 18px padding, 18px radius, 1px hairline,
    /// 11px UPPERCASE label +2 tracked, 72px mono tabular value.
    private func bigTile(
        label: String,
        value: String,
        unit: String?,
        valueColor: Color,
        valueSize: CGFloat = 72
    ) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundColor(VoltraColor.textDim)
            Spacer(minLength: 8)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let u = unit {
                    Text(u)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Phase tile with wash-tinted background. Spec from ui-kit.html:
    ///   .phase-pull   { background: rgba(0,212,170,.12); border: rgba(0,212,170,.35); }
    ///   .phase-return { background: rgba(255,184,77,.12); border: rgba(255,184,77,.35); }
    ///   .phase-idle   { plain bg-elev }
    private func phaseTile(phase: VoltraPhase) -> some View {
        let color = VoltraColor.phase(phase)
        let washBg: Color
        let borderColor: Color
        switch phase {
        case .pull:
            washBg = VoltraColor.pullWash
            borderColor = VoltraColor.pull.opacity(0.35)
        case .return:
            washBg = VoltraColor.returnWash
            borderColor = VoltraColor.returnPhase.opacity(0.35)
        case .transition, .idle:
            washBg = Color.clear
            borderColor = VoltraColor.border
        }

        return VStack(alignment: .leading) {
            Text("PHASE")
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundColor(color)
            Spacer(minLength: 8)
            Text(phaseLabel(phase))
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(VoltraColor.bgElev)
        .background(washBg)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.18), value: phase)
    }

    // MARK: - 3. HR / KCAL secondary pair

    /// b53 V2: secondary HR + KCAL tile pair with pulse-dot freshness
    /// indicator. Pulse dot blinks at 1 Hz when the most recent HK
    /// sample is < 5 s old, goes flat-grey when stale. Spec from
    /// ui-kit.html "HR / KCAL pair".
    private var secondaryHRKcalRow: some View {
        let now = Date()
        let hrFresh = (health.lastHRSampleAt.map { now.timeIntervalSince($0) } ?? .infinity) < 5
        let kcalFresh = (health.lastKcalSampleAt.map { now.timeIntervalSince($0) } ?? .infinity) < 5

        return HStack(spacing: 12) {
            secondaryTile(
                label: "HR",
                iconColor: VoltraColor.danger,
                iconSystemName: "heart.fill",
                value: health.currentHR.map(String.init) ?? "\u{2014}",
                unit: "bpm",
                isFresh: hrFresh
            )
            secondaryTile(
                label: "KCAL",
                iconColor: VoltraColor.warn,
                iconSystemName: "flame.fill",
                value: health.sessionKcal > 0 ? String(format: "%.0f", health.sessionKcal) : "\u{2014}",
                unit: "kcal",
                isFresh: kcalFresh
            )
        }
    }

    private func secondaryTile(
        label: String,
        iconColor: Color,
        iconSystemName: String,
        value: String,
        unit: String,
        isFresh: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(2)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                pulseDot(isFresh: isFresh)
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// 8px circle. Fresh: green with glow + 1Hz blink. Stale: flat grey.
    private func pulseDot(isFresh: Bool) -> some View {
        Circle()
            .fill(isFresh ? VoltraColor.fresh : VoltraColor.freshStale)
            .frame(width: 8, height: 8)
            .shadow(color: isFresh ? VoltraColor.fresh.opacity(0.7) : .clear, radius: 4)
            .opacity(isFresh ? (pulseOn ? 1.0 : 0.45) : 1.0)
    }

    // MARK: - 4. CompareStripView (LAST REPS / BEST FORCE / TARGET)

    /// b53 V2: 3-cell horizontal strip showing context relative to past
    /// performance. Spec from ui-kit.html "CompareStripView". When we
    /// don't have a prior set yet, cells render \u2014 placeholders.
    private var compareStrip: some View {
        let priorSet = mostRecentPriorLoggedSet()
        let bestForce = bestForceForActiveExercise()
        let target = logging.pendingPlannedWeightLb ?? 0
        let liveReps = session.currentSet?.reps ?? 0
        let liveForce = ble.telemetry.forceLb

        return HStack(spacing: 0) {
            compareCell(
                label: "LAST · REPS",
                value: priorSet.map { "\($0.reps)" } ?? "\u{2014}",
                unit: nil,
                delta: priorSet.map { p in
                    let d = liveReps - p.reps
                    return (text: d == 0 ? "= last" : (d > 0 ? "+\(d) vs last" : "\(d) vs last"),
                            color: d > 0 ? VoltraColor.pull : (d < 0 ? VoltraColor.returnPhase : VoltraColor.textDim))
                },
                showDivider: true
            )
            compareCell(
                label: "BEST · FORCE",
                value: bestForce > 0 ? String(format: "%.0f", bestForce) : "\u{2014}",
                unit: bestForce > 0 ? "lb" : nil,
                delta: bestForce > 0 ? {
                    let d = liveForce - bestForce
                    if d >= 0 {
                        return (text: String(format: "+%.0f vs best", d), color: VoltraColor.pull)
                    } else {
                        return (text: String(format: "%.0f vs best", d), color: VoltraColor.returnPhase)
                    }
                }() : nil,
                showDivider: true
            )
            compareCell(
                label: "TARGET",
                value: target > 0 ? "\(Int(target))" : "\u{2014}",
                unit: target > 0 ? "lb" : nil,
                delta: target > 0 ? (text: "on track", color: VoltraColor.textDim) : nil,
                showDivider: false
            )
        }
        .padding(.vertical, 14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func compareCell(
        label: String,
        value: String,
        unit: String?,
        delta: (text: String, color: Color)?,
        showDivider: Bool
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(VoltraColor.text)
                    if let u = unit {
                        Text(u)
                            .font(.system(size: 13))
                            .foregroundColor(VoltraColor.textDim)
                    }
                }
                Text(delta?.text ?? " ")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(delta?.color ?? VoltraColor.textFaint)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showDivider {
                Rectangle()
                    .fill(VoltraColor.border)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - 5. Force chart card

    /// b53 V2: same `ForceChartView` the dashboard uses. Wrapped in a
    /// chart card per ui-kit.html "ForceChartView".
    private var forceChartCard: some View {
        let samples = session.currentSet?.samples ?? session.lastFinalizedSamples
        let peak = session.currentSet?.peakLb ?? session.lastFinalizedPeakLb
        return VStack(alignment: .leading, spacing: 10) {
            Text("FORCE \u{00B7} 30s")
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundColor(VoltraColor.textDim)
                .padding(.horizontal, 4)
            ForceChartView(samples: samples, peakLb: peak)
                .frame(height: 140)
                .padding(16)
                .background(VoltraColor.bgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - 6. Plan + LOG SET CTA

    /// b53 V2: plan target + single primary CTA. CTA height is 50px
    /// per design-system principle 05 (primary CTAs 50px). Disabled
    /// state uses opacity 0.4 per spec.
    private var planCard: some View {
        let planned = logging.pendingPlannedWeightLb ?? 0
        return VStack(spacing: 12) {
            HStack {
                Text("PLAN")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(2)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(planned > 0 ? "\(Int(planned))" : "\u{2014}")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(VoltraColor.text)
                    if planned > 0 {
                        Text("lb")
                            .font(.system(size: 13))
                            .foregroundColor(VoltraColor.textDim)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Button(action: logSetTapped) {
                HStack {
                    Spacer()
                    Text("LOG SET")
                        .font(.system(size: 15, weight: .semibold))
                        .kerning(0.5)
                        .foregroundColor(Color(red: 0, green: 0.168, blue: 0.133)) // #002b22
                    Spacer()
                }
                .frame(height: 50)
                .background(VoltraColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(canLogSet ? 1.0 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canLogSet)
        }
    }

    // MARK: - Helpers

    private var exerciseName: String {
        logging.activeInstance?.exercise?.name ?? "\u{2014}"
    }

    private var setNumber: Int {
        logging.setNumberForCurrentInstance
    }

    private var canLogSet: Bool {
        if let cs = session.currentSet, cs.reps > 0 { return true }
        if logging.pendingTelemetrySet != nil { return true }
        return false
    }

    private func phaseLabel(_ p: VoltraPhase) -> String {
        switch p {
        case .pull:       return "PULL"
        case .return:     return "RETURN"
        case .transition: return "TRANS"
        case .idle:       return "IDLE"
        }
    }

    private func formatRest(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Most recent LoggedSet for the active exercise across the active
    /// session. Used for the LAST cell of the compare strip.
    private func mostRecentPriorLoggedSet() -> LoggedSet? {
        guard let inst = logging.activeInstance,
              let sets = inst.sets,
              !sets.isEmpty else { return nil }
        return sets.sorted { $0.orderIndex > $1.orderIndex }.first
    }

    /// Best peak force for the active exercise across all sessions in
    /// this instance. Used for the BEST cell of the compare strip.
    private func bestForceForActiveExercise() -> Double {
        guard let inst = logging.activeInstance,
              let sets = inst.sets else { return 0 }
        return sets.map(\.peakForceLb).max() ?? 0
    }

    private func logSetTapped() {
        let pending: CompletedSet? = logging.pendingTelemetrySet ?? session.currentSet.map { cs in
            CompletedSet(
                reps: cs.reps,
                peakLb: cs.peakLb,
                startedAt: cs.startedAt,
                endedAt: cs.endedAt ?? Date()
            )
        }
        let weight = logging.pendingPlannedWeightLb ?? 0
        logging.logSet(
            weightLb: weight,
            eccentricLb: nil,
            reps: pending?.reps ?? 0,
            chainsLb: nil,
            peakForceLb: pending?.peakLb ?? 0,
            startedAt: pending?.startedAt,
            endedAt: pending?.endedAt,
            mode: .working,
            labelText: "",
            notes: nil,
            autofilledFromTelemetry: pending != nil
        )
    }
}
