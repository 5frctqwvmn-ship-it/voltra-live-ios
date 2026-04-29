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

    /// b57 V3 §2: DROP toggle idle-fire timer. When the user taps the
    /// DROP tile to arm, we start a 2s countdown — if no further
    /// adjustment lands the planned drop is committed (no-op here, the
    /// sequence is already armed; this just dismisses the stepper UI).
    /// A second tap on the DROP tile cancels & disarms.
    @State private var dropIdleWorkItem: DispatchWorkItem? = nil

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
                    // b57 V3 §4: Pulley + Added-plates bar relocated to
                    // sit directly above the force chart.
                    PulleyAndPlatesBarV3()
                        .padding(.bottom, 8)
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

    /// b57 V3 §7: V2 dial removed entirely. The trailing watermark
    /// previously sat in the toolbar; it now ships only as the small
    /// "V3" label inside the header to claw back vertical space.
    /// Toolbar content is empty so the navigation chrome doesn't push
    /// content down. CI-injected build tag is a known-issue TODO.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { EmptyView() }
    }

    // MARK: - 1. Header strip (b57 V3 §7 — redesigned)

    /// V3 header layout, top-to-bottom:
    ///
    ///   [← End]  [V3]  ·····  [● 118 bpm · 42 kcal]
    ///   <Reverse Hyper Pulley · Set 3>  → marquee scroll if it overflows
    ///
    /// Compared to b56:
    ///   - V2 dial pulled OUT of the toolbar (§7).
    ///   - "Connected" pill is gone in single-Voltra mode — replaced by
    ///     a 6–8 px status dot leading the telemetry cluster, with tap
    ///     popover revealing device + last-seen.
    ///   - Exercise name horizontally marquee-scrolls when it overflows
    ///     (5 s pause → scroll → reset → loop).
    private var headerStrip: some View {
        VStack(spacing: 4) {
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

                v3Watermark

                Spacer()

                HStack(spacing: 6) {
                    statusDot
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

            // Exercise name with marquee fallback — wraps to second row so
            // long names like "Reverse Hyper Pulley" don't fight the
            // telemetry cluster for horizontal space.
            MarqueeText(
                text: exerciseHeaderText,
                font: .system(size: 14, weight: .semibold),
                color: VoltraColor.text,
                pauseSeconds: 5
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 6)
    }

    /// b57 V3 §7: small "V3" build watermark inline in header. CI-
    /// injected build tag is a follow-up (logged in 06_KNOWN_ISSUES).
    private var v3Watermark: some View {
        Text("V3")
            .font(.system(size: 10, weight: .bold))
            .kerning(1.2)
            .foregroundColor(VoltraColor.bg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VoltraColor.accent)
            .clipShape(Capsule())
    }

    /// b57 V3 §7: 6–8 px status dot leading the telemetry cluster.
    /// Replaces the b56 "CONNECTED" pill in single-Voltra mode.
    /// - green = connected
    /// - red = disconnected
    /// - amber pulse = reconnecting (≈ connecting state)
    /// Tap reveals device name / last-seen as a popover.
    private var statusDot: some View {
        let s = connectionStatus
        return Button {
            statusPopoverShown.toggle()
        } label: {
            Circle()
                .fill(s.color)
                .frame(width: 8, height: 8)
                .shadow(color: s.color.opacity(0.7), radius: 3)
                .opacity(s.isReconnecting ? (pulseOn ? 1.0 : 0.45) : 1.0)
                .scaleEffect(s.isReconnecting ? (pulseOn ? 1.0 : 0.78) : 1.0)
                .padding(4)  // bigger tap target
        }
        .buttonStyle(.plain)
        .popover(isPresented: $statusPopoverShown, arrowEdge: .top) {
            statusPopover(s)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Inline status struct. Computed each render from BLE/MDM state.
    private struct ConnectionSummary {
        let label: String         // e.g. "Voltra", "LEFT + RIGHT", "Searching…"
        let color: Color
        let isReconnecting: Bool  // amber pulse
        let lastSeen: Date?
    }

    private var connectionStatus: ConnectionSummary {
        let leftOn  = mdm.left.connectionState.isConnected
        let rightOn = mdm.right.connectionState.isConnected
        let bleOn   = ble.connectionState.isConnected
        if leftOn || rightOn || bleOn {
            let label: String = {
                if leftOn && rightOn { return "LEFT + RIGHT" }
                if leftOn  { return "Voltra (LEFT)" }
                if rightOn { return "Voltra (RIGHT)" }
                return "Voltra"
            }()
            return ConnectionSummary(label: label, color: VoltraColor.accent, isReconnecting: false, lastSeen: Date())
        }
        // Reconnecting heuristic: BLE is in connecting state — amber pulse.
        if case .connecting = ble.connectionState {
            return ConnectionSummary(label: "Reconnecting…", color: VoltraColor.warn, isReconnecting: true, lastSeen: nil)
        }
        return ConnectionSummary(label: "Disconnected", color: VoltraColor.danger, isReconnecting: false, lastSeen: nil)
    }

    @ViewBuilder
    private func statusPopover(_ s: ConnectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            if let seen = s.lastSeen {
                Text("Last seen \(formatRelative(seen))")
                    .font(.system(size: 11))
                    .foregroundColor(VoltraColor.textDim)
            } else {
                Text("No active connection")
                    .font(.system(size: 11))
                    .foregroundColor(VoltraColor.textDim)
            }
        }
        .padding(12)
        .frame(minWidth: 180)
    }

    private func formatRelative(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        let m = secs / 60
        return "\(m) min ago"
    }

    @State private var statusPopoverShown: Bool = false

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
        // b57 V3 §4: WEIGHT card big number shows the EFFECTIVE weight
        // the user feels (device-frame × pulleyMultiplier). BLE write
        // continues to send raw device-frame.
        let pulleyM = logging.pulleyMultiplier
        let weightLb = Int(((logging.pendingPlannedWeightLb ?? 0) * pulleyM).rounded())

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
                    // b57 V3 §2/§3: dropMode=true greys ±1 (micro-drops
                    // are forbidden per spec; only multiples of 5 allowed).
                    ModStepperRowV2(
                        label: "DROP",
                        valueLb: stepLb,
                        valueTint: VoltraColor.warn,
                        dropMode: true
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

    /// b57 V3 §1: y-axis ceiling = max of the four possible peak
    /// configurations × 1.2, with a 60-lb floor so an unloaded screen
    /// still draws sensibly. Pulley-multiplied so the chart reflects
    /// what the user feels (matches LoggedSet storage).
    ///   working                      — concentric only
    ///   working + ECC                — eccentric phase
    ///   working + CHAIN              — top of ROM under chain
    ///   working + ECC + CHAIN        — eccentric AND chain (rare but
    ///                                  happens when both armed)
    /// CHAIN and INV CHAIN are mutually exclusive — INV CHAIN only adds
    /// at mid-ROM, never exceeds working+CHAIN, so it doesn't bump max.
    private func computedYAxisMaxLb() -> Double {
        let m       = logging.pulleyMultiplier
        let working = (logging.pendingPlannedWeightLb ?? 0) * m
        let eccEff  = logging.upcomingEccEnabled    ? (logging.upcomingEccLb    * m) : 0
        let chainEff = logging.upcomingChainsEnabled ? (logging.upcomingChainsLb * m) : 0
        let total = max(
            working,
            working + eccEff,
            working + chainEff,
            working + eccEff + chainEff
        )
        return max(60, total * 1.2)
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

    /// b57 V3 §2: DROP tile is a TOGGLE.
    ///   Tap 1 (off → on):  arm a 5-lb drop, expand the nested DROP row
    ///                       and ±5/±1 stepper. Start a 2s idle timer
    ///                       that auto-fires (commits) the armed drop.
    ///   Tap 2 (on → off):  cancel & disarm — collapses the tile entirely
    ///                       (no nested row, no stepper). manualDropSequence
    ///                       is cleared.
    /// Increments are clamped to multiples of 5 inside `adjustDropStep`
    /// (±1 are no-ops via ModStepperRowV2's dropMode greying).
    private func tapDropTile() {
        // Already armed → second tap disarms.
        if (logging.manualDropSequence?.count ?? 0) >= 2 {
            cancelArmedDrop()
            return
        }
        let head = (logging.pendingPlannedWeightLb ?? 0).rounded()
        guard head > 5 else { return }
        // First tap: arm at −5 lb (device floor 5 lb).
        let nextWeight = max(5.0, head - 5.0)
        logging.manualDropSequence = [head, nextWeight]
        logging.manualDropIndex    = 0
        scheduleDropIdleAutoFire()
    }

    /// Cancel armed drop & collapse the DROP tile UI.
    private func cancelArmedDrop() {
        logging.manualDropSequence = nil
        logging.manualDropIndex    = 0
        dropIdleWorkItem?.cancel()
        dropIdleWorkItem = nil
    }

    /// b57 V3 §2: 2s idle auto-fire. Reschedule on every adjustment.
    /// Auto-fire here is a no-op against the armed sequence (it's already
    /// the source of truth for the next set's planned weight), but the
    /// timer's existence drives the "stop fiddling, this is committed"
    /// affordance the user requested.
    private func scheduleDropIdleAutoFire() {
        dropIdleWorkItem?.cancel()
        let item = DispatchWorkItem {
            // Sequence is already armed; nothing to do — this slot is
            // intentional so future builds can hook commit-side effects
            // (haptic, BLE pre-write, telemetry) without changing the
            // call sites.
        }
        dropIdleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
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

    /// b57 V3 §2/§3: DROP step adjuster — modifies the GAP between head
    /// and next. Clamped to multiples of 5 (per spec); ±1 deltas are
    /// no-ops (the stepper renders ±1 greyed via dropMode=true, but we
    /// defend here too in case a tap slips through). −5 = smaller drop
    /// (next gets HEAVIER), +5 = deeper drop (next gets LIGHTER).
    /// Reschedules the 2s idle auto-fire on every adjustment.
    private func adjustDropStep(_ delta: Int) {
        // Clamp to multiples of 5 — micro-drops are forbidden per spec.
        guard delta == 5 || delta == -5 else { return }
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
        scheduleDropIdleAutoFire()
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
        // b57 V3 §4 BLE math fix: `pendingPlannedWeightLb` (and the
        // upcoming ECC/CHAIN/INV CHAIN values) are stored in DEVICE
        // FRAME — i.e. the actual cable load the hardware applies. The
        // BLE write must NOT be multiplied by pulleyMultiplier; the UI
        // is the only side that displays effective load. Previous
        // implementations multiplied here, which sent doubled values
        // through to the device under 2× pulley. Fixed.
        let baseLb = Int((logging.pendingPlannedWeightLb ?? 0).rounded())
        let eccLb  = logging.upcomingEccEnabled ? Int(logging.upcomingEccLb.rounded()) : 0

        // CHAIN vs INV CHAIN — mutually exclusive (toggle helpers enforce).
        let chainsActive = logging.upcomingChainsEnabled  && logging.upcomingChainsLb  > 0
        let inverseActive = logging.upcomingInverseEnabled && logging.upcomingInverseLb > 0

        let chainsLb: Int = {
            if inverseActive { return Int(logging.upcomingInverseLb.rounded()) }
            if chainsActive  { return Int(logging.upcomingChainsLb.rounded()) }
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
