// LiveCaptureViewV2.swift
//
// b56 (v0.4.34): full rewrite of the V2 capture screen per the b56 design
// drop. Locks the layout to the screenshot-driven spec:
//
//   1. Header strip                — End/back, CONNECTED pill + "Bench Press · Set 2"
//                                    centered, HR + KCAL pulse pills right
//   2. Phase strip OR RestTimerBarV2 — phase strip while active; rest bar
//                                    replaces it 2s after idle (HSL sweep,
//                                    blink on overtime).
//   3. WEIGHT card                 — WEIGHT label, big number (TAP toggles
//                                    hardware LOAD/UNLOAD; goes green when
//                                    deviceLoaded), nested mod rows (only
//                                    armed mods rendered), 4-up mod tile
//                                    grid (ALL selectable), per-engaged-mod
//                                    stepper rows (ECC clamps 5–400).
//   4. REPS / TOTAL VOLUME tiles
//   5. ForceChartV2                — y-axis = max(workingLb, eccEffective) × 1.3
//   6. V1RestoreSection            — pulley chip + added-plates picker +
//                                    LOGGED SETS list + Next-exercise / End
//                                    bottom actions (verbatim port from V1)
//
// DROP behavior (b56):
//   - First tap: arms a drop of −5 lb from current working weight.
//   - Each subsequent tap deepens the step: −10 → −15 → −20 …
//     (clamped at 5 lb floor).
//   - Long-press: cancels the armed drop (sets manualDropSequence = nil).
//   - Idle fires: when the user finalizes the set (telemetry rest detect),
//     the queued next weight is pushed to the device on the next set start.
//     This is finalize-driven, not timer-driven — distinct from V1's 2s
//     time-cascade (`startDropSet`) which b56 explicitly does not use.
//
// LOAD behavior (b56):
//   - Tapping the big WEIGHT NUMBER toggles hardware LOAD / UNLOAD via
//     ble.sendLoad() / ble.sendUnload() (or mdm.load/unload if paired).
//     Mirrors V1's deviceLoaded toggle (LiveCaptureView.swift:716).
//   - Number turns VoltraColor.accent (green) when loaded; the small
//     "✓ LOADED" / "UNLOADED" pill on the WEIGHT card label row matches.
//
// Container (LiveCaptureContainer) only routes here when V2 is opted in,
// no chains, single Voltra. Sacred files NOT modified.

import SwiftUI

struct LiveCaptureViewV2: View {

    // MARK: Environment

    @EnvironmentObject var ble:     VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var health:  HealthKitStore
    @EnvironmentObject var mdm:     MultiDeviceManager

    @Environment(\.dismiss) private var dismiss

    // MARK: Local state

    @State private var showingEndConfirm  = false
    @State private var showingExportSheet = false
    @State private var lastEndedSession: WorkoutSession? = nil

    /// Drives the 1Hz pulse-dot animation on HR / KCAL pills.
    @State private var pulseOn: Bool = false

    /// Drives the rest-over blink. Toggled at 1Hz while we're over preset.
    @State private var blinkOn: Bool = false

    /// Hardware LOAD state. Same semantics as V1's @State deviceLoaded.
    /// b56: toggled by tapping the big WEIGHT NUMBER.
    @State private var deviceLoaded: Bool = false

    /// Owns its own writer router — same pattern as V1.
    @StateObject private var writerRouter = WriterRouter()

    // MARK: Body

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    headerStrip
                    phaseOrRestBar
                    weightCard
                    smallTileRow
                    forceChartCard
                    V1RestoreSection(onEndTapped: { showingEndConfirm = true })
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
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
                    lastEndedSession  = ended
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
                ExportSheet(session: s).environmentObject(logging)
            }
        }
        .onAppear {
            health.start()
            writerRouter.attach(ble: ble)
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
            // Independent 1Hz blink driver for rest-over UI elements.
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in self.blinkOn.toggle() }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { EmptyView() }
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

    // MARK: - 1. Header strip

    private var headerStrip: some View {
        HStack(spacing: 8) {
            Button { showingEndConfirm = true } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("End")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(VoltraColor.text)
            }
            .buttonStyle(.plain)

            VStack(spacing: 3) {
                connectionPill
                Text(exerciseHeaderText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VoltraColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                healthPill(
                    color: VoltraColor.danger,
                    value: health.currentHR.map(String.init) ?? "\u{2014}",
                    unit:  "bpm"
                )
                healthPill(
                    color: VoltraColor.warn,
                    value: health.sessionKcal > 0 ? String(format: "%.0f", health.sessionKcal) : "\u{2014}",
                    unit:  "kcal"
                )
            }
        }
        .padding(.vertical, 10)
    }

    private var connectionPill: some View {
        let connected = ble.connectionState.isConnected || mdm.left.connectionState.isConnected || mdm.right.connectionState.isConnected
        let label: String = {
            if mdm.left.connectionState.isConnected, !mdm.right.connectionState.isConnected { return "LEFT CONNECTED" }
            if mdm.right.connectionState.isConnected, !mdm.left.connectionState.isConnected { return "RIGHT CONNECTED" }
            if ble.connectionState.isConnected { return "CONNECTED" }
            return "DISCONNECTED"
        }()
        let color = connected ? VoltraColor.accent : VoltraColor.textFaint
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: connected ? color.opacity(0.7) : .clear, radius: 3)
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .kerning(1.0)
                .foregroundColor(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(0.10))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
    }

    private func healthPill(color: Color, value: String, unit: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: 3)
                .opacity(pulseOn ? 1.0 : 0.55)
                .scaleEffect(pulseOn ? 1.0 : 0.85)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(VoltraColor.text)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(VoltraColor.textDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(VoltraColor.bgElev2)
        .overlay(Capsule().stroke(VoltraColor.border, lineWidth: 1))
        .clipShape(Capsule())
    }

    // MARK: - 2. Phase strip OR Rest Timer Bar

    /// b56: replaces b55's TopBannerV2. Active → small phase-color strip;
    /// resting → RestTimerBarV2 with HSL sweep & blink. Boundary is 2s
    /// idle on push or pull, observed via `session.restElapsedSeconds`.
    @ViewBuilder
    private var phaseOrRestBar: some View {
        let phase = ble.telemetry.phase
        let restElapsed = Int(session.restElapsedSeconds.rounded())
        if restElapsed > 0 {
            RestTimerBarV2(
                restElapsedSec: restElapsed,
                restPresetSec:  restPresetSeconds,
                blinkOn:        blinkOn
            )
            .padding(.bottom, 10)
        } else {
            // Compact phase strip when active.
            VStack(spacing: 6) {
                HStack {
                    Text(phase.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .kerning(1.6)
                        .foregroundColor(VoltraColor.phase(phase))
                    Spacer()
                    Text("SET \(setNumber)")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(1.6)
                        .foregroundColor(VoltraColor.textDim)
                }
                Capsule(style: .continuous)
                    .fill(VoltraColor.phase(phase))
                    .frame(height: 4)
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: - 3. WEIGHT card (with hardware-load tap + nested mod rows)

    private var weightCard: some View {
        let weightLb = Int((logging.pendingPlannedWeightLb ?? 0).rounded())

        return VStack(spacing: 10) {
            // Top row: WEIGHT label + LOADED/UNLOADED pill
            HStack {
                Text("WEIGHT")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.6)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                loadedPill
            }

            // Big number row + steppers. b56: tapping the number toggles
            // hardware LOAD/UNLOAD. Number is green when deviceLoaded.
            HStack(spacing: 10) {
                Button(action: toggleHardwareLoad) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(weightLb)")
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(deviceLoaded ? VoltraColor.accent : VoltraColor.text)
                        Text("lb")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(VoltraColor.textDim)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                stepperButton("\u{2212}5") { adjustWeight(-5) }
                stepperButton("\u{2212}1") { adjustWeight(-1) }
                stepperButton("+1")        { adjustWeight(+1) }
                stepperButton("+5")        { adjustWeight(+5) }
            }

            // Nested mod rows — render only ARMED rows in fixed order.
            VStack(spacing: 4) {
                if eccArmed {
                    NestedModRowV2.ecc(
                        workingLb: weightLb,
                        eccLb: Int(logging.upcomingEccLb.rounded())
                    )
                }
                if chainArmed {
                    NestedModRowV2.chain(
                        workingLb: weightLb,
                        chainsLb: Int(logging.upcomingChainsLb.rounded())
                    )
                }
                if invArmed {
                    NestedModRowV2.invChain(
                        workingLb: weightLb,
                        inverseLb: Int(logging.upcomingInverseLb.rounded())
                    )
                }
                if dropArmed,
                   let seq = logging.manualDropSequence,
                   let head = seq.first,
                   let next = seq.dropFirst().first {
                    NestedModRowV2.drop(
                        currentLb: Int(head.rounded()),
                        nextLb:    Int(next.rounded())
                    )
                }
            }

            // 4-up mod tile grid. b56: ALL FOUR are selectable (V1 bug fix).
            modTileRow

            // Per-mod stepper rows — render only for engaged mods.
            VStack(spacing: 4) {
                if eccArmed {
                    ModStepperRowV2(
                        label: "ECC",
                        valueLb: Int(logging.upcomingEccLb.rounded())
                    ) { delta in adjustEcc(delta) }
                }
                if chainArmed {
                    ModStepperRowV2(
                        label: "CHAIN",
                        valueLb: Int(logging.upcomingChainsLb.rounded())
                    ) { delta in adjustChain(delta) }
                }
                if invArmed {
                    ModStepperRowV2(
                        label: "INV CHAIN",
                        valueLb: Int(logging.upcomingInverseLb.rounded())
                    ) { delta in adjustInverse(delta) }
                }
                if dropArmed,
                   let seq = logging.manualDropSequence,
                   let head = seq.first,
                   let next = seq.dropFirst().first {
                    let stepLb = Int((head - next).rounded())
                    ModStepperRowV2(
                        label: "DROP",
                        valueLb: stepLb,
                        valueTint: VoltraColor.warn
                    ) { delta in adjustDropStep(delta) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 8)
    }

    /// "✓ LOADED" / "UNLOADED" pill — mirrors deviceLoaded.
    @ViewBuilder
    private var loadedPill: some View {
        let tint = deviceLoaded ? VoltraColor.accent : VoltraColor.textDim
        HStack(spacing: 5) {
            if deviceLoaded {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(deviceLoaded ? "LOADED" : "UNLOADED")
                .font(.system(size: 9, weight: .bold))
                .kerning(1.4)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10))
        .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
    }

    private func stepperButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .frame(minWidth: 38, minHeight: 32)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(VoltraColor.bgElev2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 4. Mod tile row (ALL selectable per b56 bug fix)

    private var modTileRow: some View {
        HStack(spacing: 8) {
            modTile(systemImage: "arrow.down.to.line",
                    label: "ECC",
                    active: eccArmed,
                    onTap:  toggleEcc)
            modTile(systemImage: "link",
                    label: "CHAIN",
                    active: chainArmed,
                    onTap:  toggleChain)
            modTile(systemImage: "arrow.uturn.left",
                    label: "INV CHAIN",
                    active: invArmed,
                    onTap:  toggleInverse)
            modTile(systemImage: "chart.bar.fill",
                    label: "DROP",
                    active: dropArmed,
                    onTap:       tapDropTile,
                    onLongPress: cancelArmedDrop,
                    activeTint:  VoltraColor.warn)
        }
        .padding(.top, 2)
    }

    private func modTile(
        systemImage: String,
        label: String,
        active: Bool,
        onTap: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil,
        activeTint: Color = VoltraColor.accent
    ) -> some View {
        let tint = active ? activeTint : VoltraColor.textDim
        let view = VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .kerning(1.3)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(active ? activeTint.opacity(0.45) : VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())

        return Group {
            if let lp = onLongPress {
                view
                    .onTapGesture { onTap() }
                    .onLongPressGesture(minimumDuration: 0.5) { lp() }
            } else {
                view
                    .onTapGesture { onTap() }
            }
        }
    }

    // MARK: - 5. Small tile row (REPS / TOTAL VOLUME)

    private var smallTileRow: some View {
        HStack(spacing: 8) {
            smallTile(label: "REPS",         value: "\(session.currentSet?.reps ?? 0)",      unit: nil)
            smallTile(label: "TOTAL VOLUME", value: formattedTotalVolume(),                  unit: "lb", smallNumber: true)
        }
        .padding(.bottom, 8)
    }

    private func smallTile(label: String, value: String, unit: String?, smallNumber: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.6)
                .foregroundColor(VoltraColor.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: smallNumber ? 24 : 32, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                if let u = unit {
                    Text(u)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 6. Force chart card

    private var forceChartCard: some View {
        let phase   = ble.telemetry.phase
        let force   = ble.telemetry.forceLb
        let resting = session.restElapsedSeconds > 0
        let samples = session.currentSet?.samples ?? session.lastFinalizedSamples
        let peak    = session.currentSet?.peakLb ?? session.lastFinalizedPeakLb
        let yMax    = computedYAxisMaxLb()

        let displayForce: String = {
            if resting { return "0" }
            if force > 0 { return String(format: "%.0f", force) }
            return "\u{2014}"
        }()
        let forceColor: Color = resting ? VoltraColor.textFaint : VoltraColor.phase(phase)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FORCE \u{00B7} 30 S")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.6)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayForce)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(forceColor)
                    Text("lb")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
            ForceChartV2(
                samples:    samples,
                peakLb:     peak,
                resting:    resting,
                idlePhase:  phase,
                yAxisMaxLb: yMax
            )
            .frame(maxWidth: .infinity, minHeight: 175)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// b56: y-axis ceiling = max(workingWeight, eccEffective) × 1.3.
    /// Uses pulley-multiplied effective weights so the chart reflects what
    /// the user feels (matches LoggedSet.weightLb / peakForceLb storage).
    /// Defensive 60-lb floor so an unloaded screen still draws sensibly.
    private func computedYAxisMaxLb() -> Double {
        let m = logging.pulleyMultiplier
        let working = (logging.pendingPlannedWeightLb ?? 0) * m
        let eccEff  = logging.upcomingEccEnabled ? (logging.upcomingEccLb * m) : 0
        let total   = max(working, working + eccEff)  // ECC adds on top during eccentric phase
        return max(60, total * 1.3)
    }

    // MARK: - Helpers

    private var exerciseHeaderText: String {
        let name = logging.activeInstance?.exercise?.name ?? "\u{2014}"
        return "\(name) \u{00B7} Set \(setNumber)"
    }

    private var setNumber: Int { logging.setNumberForCurrentInstance }

    /// Default rest preset = 120s (2 min).
    private var restPresetSeconds: Int { 120 }

    private func formattedTotalVolume() -> String {
        let v = sessionTotalVolumeLb()
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }

    private func sessionTotalVolumeLb() -> Double {
        guard let s = logging.activeSession,
              let insts = s.instances else { return 0 }
        var total: Double = 0
        for inst in insts {
            guard let sets = inst.sets else { continue }
            for set in sets {
                total += set.weightLb * Double(set.reps)
            }
        }
        return total
    }

    // MARK: - Mod-armed flags (drive nested-row + stepper-row visibility)

    private var eccArmed:    Bool { logging.upcomingEccEnabled    && logging.upcomingEccLb     > 0 }
    private var chainArmed:  Bool { logging.upcomingChainsEnabled && logging.upcomingChainsLb  > 0 }
    private var invArmed:    Bool { logging.upcomingInverseEnabled && logging.upcomingInverseLb > 0 }
    private var dropArmed:   Bool { (logging.manualDropSequence?.count ?? 0) >= 2 }

    // MARK: - Mod toggles (b56 bug fix: tapping any tile arms/disarms)

    /// ECC toggle. If currently 0, seed with 30 lb default (matches V1's
    /// "first tap arms" feel). Otherwise just flip the enabled flag.
    /// b56: ECC range 5–400 lb — `adjustEcc` enforces.
    private func toggleEcc() {
        if logging.upcomingEccLb <= 0 {
            logging.upcomingEccLb = 30
            logging.upcomingEccEnabled = true
        } else {
            logging.upcomingEccEnabled.toggle()
        }
        pushUpcomingStateToDevice()
    }

    private func toggleChain() {
        // CHAIN and INV CHAIN are mutually exclusive — you can't lighten
        // and add through the ROM at the same time.
        if logging.upcomingInverseEnabled, logging.upcomingInverseLb > 0 {
            logging.upcomingInverseEnabled = false
        }
        if logging.upcomingChainsLb <= 0 {
            logging.upcomingChainsLb = 30
            logging.upcomingChainsEnabled = true
        } else {
            logging.upcomingChainsEnabled.toggle()
        }
        pushUpcomingStateToDevice()
    }

    private func toggleInverse() {
        // Mutually exclusive with CHAIN.
        if logging.upcomingChainsEnabled, logging.upcomingChainsLb > 0 {
            logging.upcomingChainsEnabled = false
        }
        if logging.upcomingInverseLb <= 0 {
            logging.upcomingInverseLb = 30
            logging.upcomingInverseEnabled = true
        } else {
            logging.upcomingInverseEnabled.toggle()
        }
        pushUpcomingStateToDevice()
    }

    /// b56 DROP tile tap: arms a single planned next-weight, deepening
    /// each subsequent tap by 5 lb (−5 → −10 → −15 → −20 …). The next
    /// weight is clamped at 5 lb (device floor).
    private func tapDropTile() {
        let head = (logging.pendingPlannedWeightLb ?? 0).rounded()
        guard head > 5 else { return }

        let curStepLb: Int = {
            if let seq = logging.manualDropSequence,
               let h = seq.first,
               let n = seq.dropFirst().first {
                return Int((h - n).rounded())
            }
            return 0
        }()
        let nextStepLb = max(5, curStepLb + 5)
        let nextWeight = max(5.0, head - Double(nextStepLb))
        // Refresh head to current working weight in case user adjusted
        // weight after the prior tap.
        logging.manualDropSequence = [head, nextWeight]
        logging.manualDropIndex    = 0
    }

    /// b56 DROP tile long-press: cancel armed drop.
    private func cancelArmedDrop() {
        logging.manualDropSequence = nil
        logging.manualDropIndex    = 0
    }

    // MARK: - Stepper actions

    private func adjustWeight(_ delta: Int) {
        let cur  = Int((logging.pendingPlannedWeightLb ?? 0).rounded())
        let raw  = max(0, min(500, cur + delta))
        let next = CombinedParity.enforce(raw, mode: mdm.workoutMode)
        logging.pendingPlannedWeightLb = Double(next)
        logging.reanchorCascadeIfActive(toLb: Double(next))
        // If a drop is armed, slide the head to the new working weight
        // and re-derive the next-weight using the existing step.
        if let seq = logging.manualDropSequence,
           seq.count >= 2 {
            let stepLb = (seq[0] - seq[1]).rounded()
            let nextW = max(5, Double(next) - stepLb)
            logging.manualDropSequence = [Double(next), nextW]
        }
        pushUpcomingStateToDevice()
    }

    /// b56 ECC range: 5–400 lb working. Clamp via ModStepperRowV2.clampedECC.
    private func adjustEcc(_ delta: Int) {
        let cur  = Int(logging.upcomingEccLb.rounded())
        let next = ModStepperRowV2.clampedECC(current: cur, delta: delta)
        logging.upcomingEccLb = Double(next)
        if next > 0 { logging.upcomingEccEnabled = true }
        pushUpcomingStateToDevice()
    }

    private func adjustChain(_ delta: Int) {
        let cur  = Int(logging.upcomingChainsLb.rounded())
        let next = ModStepperRowV2.clampedChain(current: cur, delta: delta)
        logging.upcomingChainsLb = Double(next)
        if next > 0 { logging.upcomingChainsEnabled = true }
        pushUpcomingStateToDevice()
    }

    private func adjustInverse(_ delta: Int) {
        let cur  = Int(logging.upcomingInverseLb.rounded())
        let next = ModStepperRowV2.clampedChain(current: cur, delta: delta)
        logging.upcomingInverseLb = Double(next)
        if next > 0 { logging.upcomingInverseEnabled = true }
        pushUpcomingStateToDevice()
    }

    /// DROP step adjuster — modifies the GAP between head and next.
    /// −5 here means "next weight gets 5 lb HEAVIER" (smaller drop), +5
    /// means "next weight gets 5 lb LIGHTER" (deeper drop). The label
    /// shows the current drop magnitude in lb.
    private func adjustDropStep(_ delta: Int) {
        guard let seq = logging.manualDropSequence,
              seq.count >= 2 else { return }
        let head    = seq[0]
        let curStep = Int((head - seq[1]).rounded())
        let headLb  = Int(head.rounded())
        let newStep = ModStepperRowV2.clampedDropNext(
            current: curStep,
            delta: delta,
            headLb: headLb - 5  // next-weight floor is 5 lb, so max step is head-5
        )
        let nextW = max(5, head - Double(newStep))
        logging.manualDropSequence = [head, nextW]
    }

    // MARK: - Hardware LOAD/UNLOAD

    /// b56: tap on the big WEIGHT NUMBER toggles hardware LOAD/UNLOAD,
    /// reusing the same opcode path V1 uses (sendLoad/sendUnload). When
    /// any MDM slot is paired we route through MDM; otherwise legacy ble.
    private func toggleHardwareLoad() {
        if deviceLoaded {
            if mdm.state != .idle { mdm.unload() } else { ble.sendUnload() }
            deviceLoaded = false
        } else {
            // Re-push the planned state first so the device matches what
            // the user sees on screen, THEN issue LOAD.
            pushUpcomingStateToDevice()
            if mdm.state != .idle { mdm.load() } else { ble.sendLoad() }
            deviceLoaded = true
        }
    }

    // MARK: - Device state push

    /// Build a coherent VoltraDeviceState and hand it to the writer.
    /// b56: honors INV CHAIN — sets `inverse: true` and writes the inverse
    /// weight to chainsLb (per protocol, there's no separate inverseLb
    /// field; VoltraModifiers.inverse repurposes chainsLb for the
    /// thru-ROM offset).
    private func pushUpcomingStateToDevice() {
        let m = logging.pulleyMultiplier
        let baseLb = Int(((logging.pendingPlannedWeightLb ?? 0) * m).rounded())
        let eccLb  = logging.upcomingEccEnabled ? Int((logging.upcomingEccLb * m).rounded()) : 0

        // CHAIN vs INV CHAIN — mutually exclusive (toggle helpers enforce).
        let chainsActive = logging.upcomingChainsEnabled  && logging.upcomingChainsLb  > 0
        let inverseActive = logging.upcomingInverseEnabled && logging.upcomingInverseLb > 0

        let chainsLb: Int = {
            if inverseActive { return Int((logging.upcomingInverseLb * m).rounded()) }
            if chainsActive  { return Int((logging.upcomingChainsLb  * m).rounded()) }
            return 0
        }()

        let voltraMode: VoltraMode = (logging.upcomingMode == .band) ? .band : .weight
        let state = VoltraDeviceState(
            mode: voltraMode,
            modifiers: VoltraModifiers(
                eccentric: eccLb > 0,
                chains:    chainsActive,
                inverse:   inverseActive
            ),
            weights: VoltraWeights(
                baseLb: baseLb,
                eccentricLb: eccLb,
                chainsLb: chainsLb,
                bandMaxForceLb: 0,
                damperLevel: 0
            )
        )
        writerRouter.apply(state, mdm: mdm, assignment: logging.activeInstance?.assignedVoltra)
    }
}
