// LiveCaptureViewV2.swift
//
// b55 (v0.4.33): Rewrite of the V2 single-Voltra capture screen so it
// MATCHES THE DESIGN-HANDOFF SCREENSHOTS. The b53/b54 V2 was a 2x2
// REPS/PHASE/FORCE/REST tile grid + HR/KCAL pair + CompareStrip — it
// did not match the actual A1 spec the design team handed us
// (screenshots/A1-states.png and A1-drop2.png). The user signed off
// on a web preview render before this rewrite — that render is the
// source of truth for the layout below.
//
// Layout (top → bottom):
//   1. Header strip       — End/back, LEFT CONNECTED pill + "Bench Press · Set 2"
//                           centered, HR + KCAL pulse pills right
//   2. Top banner         — Phase strip line (PULL teal / RETURN orange /
//                           IDLE dim half-fill / WARN full orange when rest
//                           preset exceeded) + label row; PLUS a second
//                           rest row beneath when rest is engaged
//   3. DROP-SET banner    — Visible only when a manual drop sequence is
//                           armed; shows "DROP-SET 120lb → 110lb [-10 lb]"
//   4. WEIGHT card        — WEIGHT label + LOADED chip, big mono number,
//                           ±5/±1 stepper pair; embedded DROP row when armed
//   5. Mod tile row       — ECC / CHAIN / INV / DROP (4-up grid). DROP tile
//                           taps open the drop-set configure sheet.
//   6. Small tiles row    — REPS, TOTAL VOLUME
//   7. Force chart card   — FORCE · 30s chart with phase-segmented line.
//                           Sparse single up-tick during idle states (matches
//                           reference); empty when resting (BOTTOM marker only).
//
// Container (LiveCaptureContainer) routes here only when the user opted
// into V2, no chain entries exist, and only one Voltra is paired — so we
// can safely ignore dual-Voltra and chain UX in this file.
//
// Sacred files NOT modified: VoltraProtocol.swift, TelemetryExtractor.swift,
// PacketParser.swift, FrameAssembler.swift. This view reads BLE telemetry
// and writes weight changes via WriterRouter — the same path V1 uses.

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

    /// Drop-set configure sheet — opened from the DROP mod tile.
    @State private var showingDropSetConfigure: Bool = false

    /// Owns its own writer router — same pattern as V1. The router survives
    /// view re-creation cycles via @StateObject.
    @StateObject private var writerRouter = WriterRouter()

    // MARK: Body

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerStrip
                topBannerSection
                dropSetBannerIfArmed
                weightCard
                modTileRow
                smallTileRow
                forceChartCard
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 22)
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
        .sheet(isPresented: $showingDropSetConfigure) {
            DropSetConfigureSheet(
                startingLb: Int((logging.pendingPlannedWeightLb ?? 0).rounded()),
                onConfirm:  { steps in startManualDropSequence(steps: steps) },
                onCancel:   { showingDropSetConfigure = false }
            )
            .environmentObject(logging)
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

    /// Match the reference layout: [< End]  [LEFT CONNECTED pill / Bench Press · Set 2]  [118 bpm] [42 kcal]
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

    // MARK: - 2. Top banner (phase strip + optional rest row)

    /// The phase strip is always visible. The rest row only appears when
    /// `restElapsedSeconds > 0` (i.e. the user has finalized a set and is
    /// in the rest window). Over-preset state turns the strip warn orange
    /// and adds a blink to the rest row.
    private var topBannerSection: some View {
        let phase = ble.telemetry.phase
        let restElapsed = Int(session.restElapsedSeconds.rounded())
        let restPreset  = restPresetSeconds
        let isResting   = restElapsed > 0
        let over        = isResting && restElapsed > restPreset

        return TopBannerV2(
            phase:        phase,
            isResting:    isResting,
            restElapsed:  restElapsed,
            restPreset:   restPreset,
            over:         over,
            blinkOn:      blinkOn,
            setNumber:    setNumber,
            onTapToStart: { /* tap-to-start is wired by SessionStore via the existing rest UI */ }
        )
        .padding(.bottom, 6)
    }

    // MARK: - 3. DROP-SET banner

    /// Visible when a manual drop sequence is armed (V2-only: configured by
    /// tapping the DROP mod tile). Mirrors the auto-cascade banner style
    /// but uses the user's explicit step list.
    @ViewBuilder
    private var dropSetBannerIfArmed: some View {
        if let seq = logging.manualDropSequence,
           seq.count >= 2,
           let head = seq.first,
           let next = seq.dropFirst().first {
            DropSetBannerV2(
                fromLb: Int(head.rounded()),
                toLb:   Int(next.rounded()),
                stepLb: Int((head - next).rounded()),
                blinkOn: false  // banner does NOT blink — only rest-over strip does
            )
            .padding(.bottom, 6)
        }
    }

    // MARK: - 4. WEIGHT card

    private var weightCard: some View {
        let weightLb = Int((logging.pendingPlannedWeightLb ?? 0).rounded())
        let isLoaded = ble.connectionState.isConnected || mdm.left.connectionState.isConnected || mdm.right.connectionState.isConnected
        let dropArmed = (logging.manualDropSequence?.count ?? 0) >= 2

        return VStack(spacing: 0) {
            // Top row: WEIGHT label + LOADED chip
            HStack {
                Text("WEIGHT")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.6)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if isLoaded {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("LOADED")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(1.4)
                    }
                    .foregroundColor(VoltraColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VoltraColor.accent.opacity(0.10))
                    .overlay(Capsule().stroke(VoltraColor.accent.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())
                }
            }
            .padding(.bottom, 6)

            // Big number row + steppers
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(weightLb)")
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(VoltraColor.text)
                    Text("lb")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                }
                Spacer()
                stepperButton("\u{2212}5") { adjustWeight(-5) }
                stepperButton("\u{2212}1") { adjustWeight(-1) }
                stepperButton("+1")        { adjustWeight(+1) }
                stepperButton("+5")        { adjustWeight(+5) }
            }

            // Embedded DROP row — only when an explicit drop sequence is armed
            if dropArmed,
               let seq = logging.manualDropSequence,
               let head = seq.first,
               let next = seq.dropFirst().first {
                DropRowV2(
                    fromLb: Int(head.rounded()),
                    toLb:   Int(next.rounded()),
                    stepLb: Int((head - next).rounded())
                )
                .padding(.top, 10)
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

    // MARK: - 5. Mod tile row (ECC / CHAIN / INV / DROP)

    private var modTileRow: some View {
        HStack(spacing: 8) {
            modTile(systemImage: "arrow.down.to.line", label: "ECC",   active: logging.upcomingEccEnabled && logging.upcomingEccLb > 0)
            modTile(systemImage: "link",               label: "CHAIN", active: logging.upcomingChainsEnabled && logging.upcomingChainsLb > 0)
            modTile(systemImage: "arrow.uturn.left",   label: "INV",   active: false /* INV not surfaced in V2 yet */)
            modTile(systemImage: "chart.bar.fill",     label: "DROP",
                    active: (logging.manualDropSequence?.count ?? 0) >= 2,
                    onTap:  { showingDropSetConfigure = true })
        }
        .padding(.bottom, 8)
    }

    private func modTile(systemImage: String, label: String, active: Bool, onTap: (() -> Void)? = nil) -> some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(active ? VoltraColor.accent : VoltraColor.textDim)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(active ? VoltraColor.accent : VoltraColor.textDim)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(active ? VoltraColor.accent.opacity(0.4) : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    // MARK: - 6. Small tile row (REPS / TOTAL VOLUME)

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

    // MARK: - 7. Force chart card

    private var forceChartCard: some View {
        let phase   = ble.telemetry.phase
        let force   = ble.telemetry.forceLb
        let resting = session.restElapsedSeconds > 0
        let samples = session.currentSet?.samples ?? session.lastFinalizedSamples
        let peak    = session.currentSet?.peakLb ?? session.lastFinalizedPeakLb

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
                samples:  samples,
                peakLb:   peak,
                resting:  resting,
                idlePhase: phase
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

    // MARK: - Helpers

    private var exerciseHeaderText: String {
        let name = logging.activeInstance?.exercise?.name ?? "\u{2014}"
        return "\(name) \u{00B7} Set \(setNumber)"
    }

    private var setNumber: Int { logging.setNumberForCurrentInstance }

    /// Default rest preset = 120s (2 min). The session viewmodel doesn't
    /// expose a per-exercise preset yet; using 120 matches the reference
    /// screenshots' "01:23 of 02:00" timing.
    private var restPresetSeconds: Int { 120 }

    private func formattedTotalVolume() -> String {
        let v = sessionTotalVolumeLb()
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }

    /// Sum of `weightLb × reps` across logged sets in the active session.
    /// Read-only convenience — no mutation.
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

    // MARK: - Stepper actions (mirror V1's adjustWeight + push)

    private func adjustWeight(_ delta: Int) {
        let cur  = Int((logging.pendingPlannedWeightLb ?? 0).rounded())
        let raw  = max(0, min(500, cur + delta))
        let next = CombinedParity.enforce(raw, mode: mdm.workoutMode)
        logging.pendingPlannedWeightLb = Double(next)
        logging.reanchorCascadeIfActive(toLb: Double(next))
        pushWeightToDevice()
    }

    private func pushWeightToDevice() {
        let m = logging.pulleyMultiplier
        let baseLb     = Int(((logging.pendingPlannedWeightLb ?? 0) * m).rounded())
        let eccLb      = logging.upcomingEccEnabled    ? Int((logging.upcomingEccLb    * m).rounded()) : 0
        let chainsLb   = logging.upcomingChainsEnabled ? Int((logging.upcomingChainsLb * m).rounded()) : 0
        let voltraMode: VoltraMode = (logging.upcomingMode == .band) ? .band : .weight
        let state = VoltraDeviceState(
            mode: voltraMode,
            modifiers: VoltraModifiers(eccentric: eccLb > 0, chains: chainsLb > 0, inverse: false),
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

    // MARK: - Manual drop sequence (V2-only)

    private func startManualDropSequence(steps: [Int]) {
        showingDropSetConfigure = false
        let stepsD = steps.map(Double.init)
        guard stepsD.count >= 2 else { return }
        logging.manualDropSequence = stepsD
        logging.manualDropIndex    = 0
        // Push the head weight to the device so the user is on it.
        if let head = stepsD.first {
            logging.pendingPlannedWeightLb = head
            pushWeightToDevice()
        }
    }
}
