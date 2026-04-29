// ExerciseDetailView.swift
// The control screen shown after picking an exercise: top-level mode
// (Weight/Band/Damper), modifier toggles (eccentric/chains/inverse — only in
// weight, with chains↔inverse mutex), per-mode parameter steppers, target reps,
// a live "Voltra: ..." confirm strip, and a "Start set" CTA that opens
// LiveCaptureView.
//
// Ported 1:1 from the web prototype's renderDetail() in app.js. Every state
// change pipes through `VoltraWriter.apply(_:)`, which debounces and only
// sends the diff to the device.
//
// Why this is a new file (not edits to ExerciseStartView): the prototype
// detail screen and the smart-start screen are different shapes and different
// flows. Keeping ExerciseStartView intact avoids breaking the smart-start
// behavior anyone has tested in v0.2.x while we ship the new flow.
//
// Hardware note: we use `VoltraWriter` rather than calling
// `bleManager.writeControlFrame` directly so the user can hold +/- on a stepper
// without flooding the BLE characteristic. Writes coalesce within ~80 ms.

import SwiftUI

// MARK: - Top-level mode picker shape

private struct ModeOption: Identifiable {
    let id: VoltraMode
    let label: String
}

private let DETAIL_MODES: [ModeOption] = [
    .init(id: .weight, label: "Weight"),
    .init(id: .band,   label: "Band"),
    .init(id: .damper, label: "Damper"),
]

struct ExerciseDetailView: View {
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var health: HealthKitStore
    /// b67 V4.3 (Bug 07): shared pair-sheet presenter — same coordinator
    /// drives UnifiedConnectSheet from the home screen, here, and live.
    @EnvironmentObject var pairing: PairingCoordinator
    // b45: needed by WriterRouter so writes route through MDM when dual
    // is paired. Without this the legacy single-device manager is used
    // even when both peripherals are owned by MDM — weights never load.
    @EnvironmentObject var mdm: MultiDeviceManager

    /// Captured per-view so the writer's debounce/diff state is scoped to one
    /// detail-screen visit. On dismiss it deinits along with the view.
    // b45: WriterRouter replaces WriterHolder for dual-aware routing.
    @StateObject private var writerRouter: WriterRouter

    // Mode + modifier state — drives both the device and the UI
    @State private var mode: VoltraMode = .weight
    @State private var eccentric: Bool = false
    @State private var chains: Bool = false
    @State private var inverse: Bool = false

    // Weights for each mode (independent so switching modes preserves prior
    // values, matching the prototype's per-exercise state.weights)
    @State private var baseLb: Int = 100
    @State private var eccLb: Int = 0
    @State private var chainsLb: Int = 0
    @State private var bandMaxForceLb: Int = 60
    @State private var damperLevel: Int = 4
    @State private var targetReps: Int = 9

    @State private var navigateToCapture = false
    @State private var didInitialize = false
    /// b48: per-exercise Voltra assignment in superset mode. Default
    /// alternates by chain length so the user can just tap through and
    /// the exercises auto-assign to alternating Voltras.
    @State private var supersetSlot: DeviceSlot = .left

    init() {
        // Build the writer eagerly so the first apply() has a live target.
        // We can't reference @EnvironmentObject in init, so the writer's BLE
        // reference is wired in .onAppear via WriterHolder.attach.
        _writerRouter = StateObject(wrappedValue: WriterRouter())
    }

    /// b49 (was b48 inSupersetMode): True when both Voltras are paired
    /// so the L/R assignment panel + Add-Another + Superset-tag dot
    /// should render. Workout mode is no longer a gate \u2014 the unified
    /// flow puts assignment inside the exercise screen unconditionally
    /// when there's a meaningful choice. With one Voltra paired, there's
    /// no choice and the panel is hidden.
    private var showsDualVoltraPanel: Bool {
        mdm.left.connectionState.isConnected
            && mdm.right.connectionState.isConnected
    }

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // b67 V4.3 (Bug 03/08): single canonical chrome —
                    // VoltraUnitHeader. Per-exercise override scope
                    // (writes mdm.exerciseAssignmentOverride[name]).
                    // Mirror rule 1A applies via exerciseName.
                    VoltraUnitHeader(
                        mdm: mdm,
                        hk: health,
                        exerciseName: logging.activeInstance?.exercise?.name,
                        onPairRequest: { slot in
                            pairing.presentPair(slot: slot)
                        }
                    )

                    if showsDualVoltraPanel {
                        dualVoltraTopPanel
                    }
                    historyStrip
                    progressChart
                    modeSection
                    modifiersAndSteppers
                    targetSection
                    voltraConfirmStrip
                    startButton
                    if showsDualVoltraPanel {
                        addAnotherExerciseButton
                    }
                    Spacer(minLength: 24)
                }
                .padding(20)
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        // b66 V4.2: page-name badge — bottom-leading, faint mint,
        // Swift type name verbatim. Always visible in TestFlight.
        .pageBadge("ExerciseDetailView")
        .navigationDestination(isPresented: $navigateToCapture) {
            // b53: route through the V1/V2 container instead of pinning
            // V1. Container reads @AppStorage("liveCaptureUIVersion")
            // and falls back to V1 for any session V2 cannot render.
            LiveCaptureContainer()
        }
        .onAppear {
            writerRouter.attach(ble: ble)
            // b50: wipe the writer's applied-state cache on first entry
            // so a stale device (powered off between sessions) gets the
            // full re-send of base + ecc on the first pushToVoltra. See
            // LiveCaptureView .onAppear for the full reasoning.
            if !didInitialize {
                writerRouter.resetAppliedState()
                mdm.leftWriter.resetAppliedState()
                mdm.rightWriter.resetAppliedState()
            }
            if !didInitialize {
                seedFromHistory()
                didInitialize = true
            }
            // b48: pre-select the slot for this entry. Even chain length
            // -> left, odd -> right so the user can chain entries by
            // tapping through. They can override before Start/Add.
            if showsDualVoltraPanel {
                supersetSlot = (mdm.supersetChain.count % 2 == 0) ? .left : .right
            }
            pushToVoltra()
        }
        .onDisappear {
            // Don't reset device state on disappear — the user is going into
            // LiveCaptureView with the same loaded weight.
        }
    }

    // MARK: - Sections

    private var navTitle: String {
        logging.activeInstance?.exercise?.name ?? "Exercise"
    }

    // v0.4.0 — Per-exercise progress chart, sample-fallback when empty so a
    // first-time user still sees the shape. Sits between the history strip
    // and the mode picker per research recommendation.
    private var progressChart: some View {
        let history: [LoggedSet]
        if let ex = logging.activeInstance?.exercise {
            history = logging.historicalSets(for: ex)
        } else {
            history = []
        }
        let realPoints = ProgressChartView.points(fromSeries: history)
        return ProgressChartView(series: realPoints)
    }

    private var historyStrip: some View {
        let last = previousSeries.first
        return HStack(spacing: 0) {
            cell(label: "LAST SESSION", value: lastSessionSummary)
            Divider().frame(width: 1, height: 36).background(VoltraColor.border)
            cell(label: "SET \(currentSetIndex + 1)", value: lastMatchingSetSummary(last))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func cell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textFaint)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODE")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            HStack(spacing: 8) {
                ForEach(DETAIL_MODES) { option in
                    Button {
                        selectMode(option.id)
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(mode == option.id ? VoltraColor.accent : VoltraColor.bgElev2)
                            .foregroundColor(mode == option.id ? VoltraColor.bg : VoltraColor.text)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(mode == option.id ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var modifiersAndSteppers: some View {
        switch mode {
        case .weight: weightPanel
        case .band:   bandPanel
        case .damper: damperPanel
        }
    }

    private var weightPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MODIFIERS")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(VoltraColor.textDim)
                    Spacer()
                    Text("stack eccentric with chains or inverse")
                        .font(.system(size: 10))
                        .foregroundColor(VoltraColor.textFaint)
                }
                HStack(spacing: 8) {
                    modToggle(label: "Eccentric", on: eccentric) {
                        eccentric.toggle()
                        if !eccentric { eccLb = 0 }
                        pushToVoltra()
                    }
                    modToggle(label: "Chains", on: chains) {
                        chains.toggle()
                        if chains {
                            inverse = false
                        } else if !inverse {
                            chainsLb = 0
                        }
                        pushToVoltra()
                    }
                    modToggle(label: "Inverse", on: inverse) {
                        inverse.toggle()
                        if inverse {
                            chains = false
                        } else if !chains {
                            chainsLb = 0
                        }
                        pushToVoltra()
                    }
                }
            }

            stepper(label: "Base weight", unit: "lb", value: baseLb, min: 5, max: 200, deltas: [-5, -1, 1, 5]) { newValue in
                baseLb = newValue
                pushToVoltra()
            }

            if eccentric {
                stepper(label: "Eccentric", unit: "lb", value: eccLb, min: 0, max: 200, deltas: [-5, -1, 1, 5], prefix: "+") { newValue in
                    eccLb = newValue
                    pushToVoltra()
                }
            }

            if chains || inverse {
                stepper(label: inverse ? "Inverse chains" : "Chains", unit: "lb", value: chainsLb, min: 0, max: 200, deltas: [-5, -1, 1, 5], prefix: "+") { newValue in
                    chainsLb = newValue
                    pushToVoltra()
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

    private var bandPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepper(label: "Max force", unit: "lb", value: bandMaxForceLb, min: 15, max: 200, deltas: [-5, -1, 1, 5]) { newValue in
                bandMaxForceLb = newValue
                pushToVoltra()
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

    private var damperPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAMPER LEVEL")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            // 9 buttons in a row — they fit comfortably on iPhone widths
            HStack(spacing: 6) {
                ForEach(1...9, id: \.self) { n in
                    Button {
                        damperLevel = n
                        pushToVoltra()
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(damperLevel == n ? VoltraColor.accent : VoltraColor.bgElev2)
                            .foregroundColor(damperLevel == n ? VoltraColor.bg : VoltraColor.text)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(damperLevel == n ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("1 = light cable feel · 9 = heavy resistance")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepper(label: "Target reps", unit: "reps", value: targetReps, min: 1, max: 30, deltas: [-5, -1, 1, 5]) { newValue in
                targetReps = newValue
                // Target reps does NOT call pushToVoltra — it's UI-only
            }
            Text(targetHint)
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var voltraConfirmStrip: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VoltraColor.accent)
                .frame(width: 8, height: 8)
            Text("Voltra:")
                .font(.system(size: 12))
                .foregroundColor(VoltraColor.textDim)
            Text(loadedSummary)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(VoltraColor.bgElev2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VoltraColor.accentDim, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - b49 Dual-Voltra top panel (unified flow)

    /// b49: Single top panel rendered above the history strip whenever
    /// both Voltras are paired. Replaces the b48 "superset slot picker"
    /// (which was workoutMode-gated) with a permanent dual-Voltra UI.
    /// Three controls, all on the exercise screen where they belong:
    ///
    ///   \u2022 L/R slot picker \u2014 binds THIS exercise to a Voltra.
    ///   \u2022 Merge button    \u2014 flips workoutMode to .combined
    ///                            for b47 single-bar two-Voltra math.
    ///   \u2022 Superset tag dot \u2014 toggle that marks the upcoming
    ///                              chain as a superset for end-of-session
    ///                              tagging. Locks at set 1 start so the
    ///                              user can't change the historical
    ///                              record mid-session.
    ///
    /// Rationale: b48 forced the user to commit Combined / Superset / etc.
    /// at the home screen before they had even picked an exercise. The
    /// same two Voltras are a Combined heavy lift on Back Squat and a
    /// Superset pair on Seated Row + Belt Squat \u2014 mode is exercise-
    /// scoped, not session-scoped.
    private var dualVoltraTopPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top label row: counter + superset tag dot on the right.
            HStack {
                Text("ASSIGN TO VOLTRA")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if !mdm.supersetChain.isEmpty {
                    Text("#\(mdm.supersetChain.count + 1) IN CHAIN")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.0)
                        .foregroundColor(VoltraColor.accent)
                }
                supersetTagDot
            }
            // Slot picker + Merge button row.
            HStack(spacing: 8) {
                ForEach(DeviceSlot.allCases) { slot in
                    let selected = (slot == supersetSlot) && mdm.workoutMode != .combined
                    Button {
                        // Picking a slot exits Combined back to Independent
                        // so the assignment has meaning again.
                        if mdm.workoutMode == .combined {
                            mdm.workoutMode = .independent
                        }
                        supersetSlot = slot
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: slot == .left ? "l.circle.fill" : "r.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(selected ? VoltraColor.bg : VoltraColor.accent)
                            Text(slot.label.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .kerning(1.0)
                                .foregroundColor(selected ? VoltraColor.bg : VoltraColor.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? VoltraColor.accent : VoltraColor.bgElev2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                mergeButton
            }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// b49: Merge button. Switches workoutMode to .combined so b47's
    /// virtual-twin math kicks in (weights split, telemetry summed).
    /// Tapping again flips back to .independent. Disabled once a chain
    /// has 2+ entries since Merge math doesn't compose with a chain.
    private var mergeButton: some View {
        let active = mdm.workoutMode == .combined
        let disabled = mdm.supersetChain.count >= 2
        return Button {
            if active {
                mdm.workoutMode = .independent
            } else {
                // b51: snap base + ecc + chains to even pounds the moment
                // Merge engages, so the per-side split (CombinedMath) is
                // exactly equal and the user can't accidentally enter
                // Combined with an odd total (e.g. 65 = 32.5 / 32.5).
                // Going forward, \u00b1 stepper enforces even via
                // CombinedParity.enforce(); this just fixes the entry
                // value.
                let snap: (Double) -> Double = { v in
                    let n = Int(v.rounded())
                    return Double(n.isMultiple(of: 2) ? n : (n + 1))
                }
                if let cur = logging.pendingPlannedWeightLb {
                    logging.pendingPlannedWeightLb = snap(cur)
                }
                if logging.upcomingEccLb > 0 {
                    logging.upcomingEccLb = snap(logging.upcomingEccLb)
                }
                if logging.upcomingChainsLb > 0 {
                    logging.upcomingChainsLb = snap(logging.upcomingChainsLb)
                }
                mdm.workoutMode = .combined
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(active ? VoltraColor.bg : (disabled ? VoltraColor.textFaint : VoltraColor.accent))
                Text("MERGE")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundColor(active ? VoltraColor.bg : (disabled ? VoltraColor.textFaint : VoltraColor.text))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? VoltraColor.accent : VoltraColor.bgElev2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(disabled ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// b49: Superset tag dot \u2014 a small toggle in the top-right of
    /// the dual-Voltra panel. When ON, the upcoming chain is marked as
    /// a superset for post-session display. Locks at set 1 start so
    /// the user can't change the historical record mid-session.
    private var supersetTagDot: some View {
        Button {
            guard !mdm.supersetTagLocked else { return }
            mdm.supersetTag.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(mdm.supersetTag ? VoltraColor.accent : VoltraColor.border)
                    .frame(width: 8, height: 8)
                Text(mdm.supersetTagLocked ? "SUPERSET" : "SUPERSET TAG")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.0)
                    .foregroundColor(mdm.supersetTag ? VoltraColor.accent : VoltraColor.textDim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(mdm.supersetTag ? VoltraColor.accent.opacity(0.15) : Color.clear)
            .overlay(
                Capsule()
                    .stroke(mdm.supersetTag ? VoltraColor.accent.opacity(0.5) : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(Capsule())
            .opacity(mdm.supersetTagLocked ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(mdm.supersetTagLocked)
    }

    /// b49 (was b48 addAnotherSupersetButton): "Add Another Exercise"
    /// CTA. Stamps THIS exercise into the chain and pops back to the
    /// day tiles so the user can pick the next exercise. The chain
    /// becomes a superset only if `mdm.supersetTag` is on at set 1
    /// start \u2014 the chain itself is just "two exercises in flight,
    /// one per Voltra,\" with no implied superset semantics.
    private var addAnotherExerciseButton: some View {
        Button {
            commitChainEntryFromCurrentState()
            mdm.requestSupersetReturnToHome()
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Another Exercise")
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(VoltraColor.accent.opacity(0.15))
            .foregroundColor(VoltraColor.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(VoltraColor.accent.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// b48: persist this exercise into the superset chain. Reads weight
    /// from whichever mode is active; defaults to baseLb in weight mode.
    private func commitChainEntryFromCurrentState() {
        let name = logging.activeInstance?.exercise?.name ?? "Exercise"
        let weight: Double
        switch mode {
        case .weight: weight = Double(baseLb)
        case .band:   weight = Double(bandMaxForceLb)
        case .damper: weight = 0
        }
        mdm.appendSupersetEntry(name: name, slot: supersetSlot, weightLb: weight)
    }

    private var startButton: some View {
        Button {
            // b49 (was b48): when both Voltras are paired, stamp this
            // exercise into the chain before opening live so the banner
            // has the right labels and slot bindings from the first
            // frame. The chain may be only one entry long \u2014 that's
            // fine, it just means "this exercise on this slot."
            if showsDualVoltraPanel {
                commitChainEntryFromCurrentState()
            }
            // v0.4.0 — plumb the FULL upcoming-set context into LoggingStore so
            // when telemetry detects the set boundary, autoLogTelemetrySet()
            // can build a complete LoggedSet without any user prompt.
            switch mode {
            case .weight:
                logging.pendingPlannedWeightLb = Double(baseLb)
                logging.upcomingMode = eccentric ? .eccentric : .working
                logging.upcomingEccLb = eccentric ? Double(eccLb) : 0
            case .band:
                logging.pendingPlannedWeightLb = Double(bandMaxForceLb)
                logging.upcomingMode = .band
                logging.upcomingEccLb = 0
            case .damper:
                logging.pendingPlannedWeightLb = nil
                logging.upcomingMode = .standard
                logging.upcomingEccLb = 0
            }
            logging.upcomingTargetReps = targetReps
            // Chains/inverse from this screen carry into the upcoming set as
            // an added-load entry (chains type, with sign captured by
            // inverseChains via the modifier toggles in LiveCapture).
            if (chains || inverse) && chainsLb > 0 {
                logging.upcomingAddedLoadLb = Double(chainsLb)
                logging.upcomingAddedLoadType = inverse ? "inverse_chains" : "chains"
            }
            // b51: also surface chains as a first-class digital chains-mode
            // overload so the live RESISTANCE tile can render the chains
            // row (with tap-to-toggle motor) separately from the added-
            // plates subline. Inverse keeps using the added-load path only;
            // it isn't a positive overload at the bottom of the lift.
            if chains, chainsLb > 0 {
                logging.upcomingChainsLb = Double(chainsLb)
                logging.upcomingChainsEnabled = true
            } else {
                logging.upcomingChainsLb = 0
            }
            // b51: ecc enable bit follows the eccentric toggle on this
            // screen so a fresh entry doesn't carry over a previously-
            // disabled ecc motor.
            logging.upcomingEccEnabled = true
            navigateToCapture = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Start set \(currentSetIndex + 1)")
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VoltraColor.accent)
            .foregroundColor(VoltraColor.bg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Reusable controls

    private func modToggle(label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(on ? VoltraColor.bg : VoltraColor.text)
                Text(on ? "On" : "Off")
                    .font(.system(size: 10))
                    .foregroundColor(on ? VoltraColor.bg.opacity(0.7) : VoltraColor.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(on ? VoltraColor.accent : VoltraColor.bgElev2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(on ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func stepper(
        label: String,
        unit: String,
        value: Int,
        min: Int,
        max: Int,
        deltas: [Int],
        prefix: String = "",
        onChange: @escaping (Int) -> Void
    ) -> some View {
        let negs = deltas.filter { $0 < 0 }
        let pos  = deltas.filter { $0 > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .kerning(1.0)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(VoltraColor.textFaint)
            }
            HStack(spacing: 6) {
                ForEach(negs, id: \.self) { d in
                    stepBtn(delta: d) {
                        let next = Swift.max(min, Swift.min(max, value + d))
                        if next != value { onChange(next) }
                    }
                }
                Text("\(prefix)\(value)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
                    .frame(maxWidth: .infinity)
                ForEach(pos, id: \.self) { d in
                    stepBtn(delta: d) {
                        let next = Swift.max(min, Swift.min(max, value + d))
                        if next != value { onChange(next) }
                    }
                }
            }
        }
    }

    private func stepBtn(delta: Int, action: @escaping () -> Void) -> some View {
        let big = abs(delta) >= 5
        let sign = delta > 0 ? "+" : "−"
        return Button(action: action) {
            Text("\(sign)\(abs(delta))")
                .font(.system(size: big ? 14 : 13, weight: .bold, design: .monospaced))
                .frame(width: big ? 50 : 42, height: 40)
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

    // MARK: - Behavior

    private var currentSetIndex: Int {
        // 0-based for prototype-style messaging; logging.setNumberForCurrentInstance is 1-based
        Swift.max(0, logging.setNumberForCurrentInstance - 1)
    }

    private var previousSeries: [LoggedSet] {
        guard let ex = logging.activeInstance?.exercise else { return [] }
        return logging.previousSetSeries(for: ex)
    }

    private var lastSessionSummary: String {
        guard let last = previousSeries.first else { return "—" }
        let dateStr: String
        if let started = last.instance?.session?.startedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            dateStr = f.localizedString(for: started, relativeTo: Date())
        } else {
            dateStr = ""
        }
        return "\(formatLb(last.weightLb)) lb × \(last.reps) \(dateStr)"
    }

    private func lastMatchingSetSummary(_ last: LoggedSet?) -> String {
        // Show the matching-slot set from last session
        let series = previousSeries
        let target = currentSetIndex
        if let s = series.first(where: { $0.orderIndex - 1 == target }) {
            return "\(formatLb(s.weightLb)) lb · \(s.reps) reps"
        }
        if let last = last {
            return "Last: \(formatLb(last.weightLb)) × \(last.reps)"
        }
        return "First time"
    }

    private var targetHint: String {
        let series = previousSeries
        let idx = currentSetIndex
        if let s = series.first(where: { $0.orderIndex - 1 == idx }) {
            return "Last time, set \(idx + 1): \(s.reps) reps"
        }
        if !series.isEmpty {
            return "No set \(idx + 1) last time — free entry"
        }
        return "First time — set your own target"
    }

    private var loadedSummary: String {
        switch mode {
        case .weight:
            var s = "\(baseLb) lb"
            if eccentric, eccLb > 0 { s += " + \(eccLb) ecc" }
            if chains, chainsLb > 0 { s += " + \(chainsLb) chain" }
            if inverse, chainsLb > 0 { s += " + \(chainsLb) inv-chain" }
            return s
        case .band:
            return "\(bandMaxForceLb) lb max · Resistance Band"
        case .damper:
            return "Level \(damperLevel) · Damper"
        }
    }

    private func selectMode(_ newMode: VoltraMode) {
        guard mode != newMode else { return }
        mode = newMode
        // Switching modes clears modifiers (matches prototype)
        eccentric = false
        chains = false
        inverse = false
        pushToVoltra()
    }

    /// Seed initial values from the last set on this exercise.
    private func seedFromHistory() {
        guard let last = previousSeries.first else { return }
        baseLb = Int(last.weightLb.rounded())
        if let ecc = last.eccentricLb, ecc > 0 {
            eccentric = true
            eccLb = Int(ecc.rounded())
        }
        if let c = last.chainsLb, c > 0 {
            chainsLb = Int(c.rounded())
            if last.inverseChains {
                inverse = true
            } else {
                chains = true
            }
        }
        if let band = last.bandMaxForceLb, band > 0 {
            bandMaxForceLb = Int(band.rounded())
        }
        if let damper = last.damperLevel, damper > 0 {
            damperLevel = damper
        }
        if last.reps > 0 { targetReps = last.reps }
    }

    private func pushToVoltra() {
        let state = VoltraDeviceState(
            mode: mode,
            modifiers: VoltraModifiers(eccentric: eccentric, chains: chains, inverse: inverse),
            weights: VoltraWeights(
                baseLb: baseLb,
                eccentricLb: eccLb,
                chainsLb: chainsLb,
                bandMaxForceLb: bandMaxForceLb,
                damperLevel: damperLevel
            )
        )
        // b53: route by per-exercise Voltra assignment when available.
        writerRouter.apply(state, mdm: mdm, assignment: logging.activeInstance?.assignedVoltra)
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }
}

// MARK: - Writer holder

/// Why this exists: SwiftUI views can't construct a writer with closures
/// capturing @EnvironmentObject in init (env is not available there). We hold
/// the writer on a tiny ObservableObject and attach the BLE manager in
/// onAppear.
@MainActor
private final class WriterHolder: ObservableObject {
    var writer: VoltraWriter?

    func attach(ble: VoltraBLEManager) {
        guard writer == nil else { return }
        writer = VoltraWriter(
            writeFrame: { [weak ble] frame in ble?.writeControlFrame(frame) },
            log:        { [weak ble] msg   in ble?.addLog(msg) }
        )
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView()
            .environmentObject(LoggingStore())
            .environmentObject(SessionStore())
            .environmentObject(VoltraBLEManager())
            .environmentObject(MultiDeviceManager())
    }
}
