// LiveCaptureViewV2.swift
//
// b58 (v0.4.36): V4 spec — dropsets ported back to time-driven cascade,
// Tonal-style force curve, weight-cell auto-fit, L/R + MERGE header strip
// when 2 Voltras are connected, pulley grey-out in Twin Mode.
//
// V4 DROP behavior (b58, ports the b48 / aff322f time-cascade verbatim):
//   - First tap arms the cascade — IMMEDIATELY fires drop #2 to the device
//     (−5 lb / −5% via cascadeAnchoredDeviceWeight at tier 1) and starts a
//     4 s recurring fuse + 10 s no-movement watchdog.
//   - Subsequent taps WHILE ACTIVE bump the tier (5→10→15→5, mod 3) and
//     fire an immediate drop at the new tier.
//   - Telemetry activity (forceLb > 3 lb) resets BOTH the 4 s fuse and the
//     10 s watchdog so the cable doesn't auto-drop mid-rep.
//   - 10 s of no rep increment finalizes the chain and transitions the
//     SessionStore to its normal rest-timer flow. Idle handler in
//     SessionStore checks the dropset boundary callback BEFORE finalizing
//     to a normal set — ordering is correct in SessionStore (line 146).
//   - Long-press (0.8 s) cancels the cascade without finalizing the parent
//     set (1.5 s arm-cooldown prevents the same gesture from re-arming).
//   - DROP step buttons are clamped to multiples of 5 (±5 only; ±1 greyed)
//     and bump the cascade tier rather than mutating a manual sequence.
//
// b56 originally introduced a `manualDropSequence` UI sequence that is
// FINALIZE-driven (commits the queued next weight on rest-timer entry).
// V4 deprecates that path entirely — it never actually dropped the device
// weight mid-set, which is what the user wanted.
//
// V4 dual-Voltra: when MultiDeviceManager reports both .left and .right
// connected, the header strip swaps to the L ⋆ MERGE ⋆ R unit selector.
// Independent mode binds the screen's mod controls to the focused unit;
// MERGE / Twin Mode mirrors every adjustment to BOTH units (auto twin sync)
// and greys the pulley toggle (shared attachment doesn't allow pulley).
// In single-Voltra sessions the header is unchanged from b57.
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
//   5. ForceChartView (V1)         — b71 (V4-D20, supersedes V4-D13):
//                                    V1's raw-sample phase-colored
//                                    polyline is canonical for V2; the
//                                    b58/b67 ForceChartV2 sine renderer
//                                    is retained on disk only for rollback.
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
    /// b67 V4.3 (Bug 07): shared pair-sheet presenter — lets the user
    /// re-pair a slot mid-session by tapping a greyed L/R pill in the
    /// VoltraUnitHeader (subject to the live-set isReadOnly lock).
    @EnvironmentObject var pairing: PairingCoordinator
    /// b68 (B68-01): demo controller env-injected so the LIVE screen can
    /// auto-engage demo mode when the user loads weight with no Voltra
    /// connected, and auto-exit when a real device pairs mid-session.
    /// Replaces the deprecated `ConnectView` `DemoModeButton(.prePair)`
    /// path that B67-01 orphaned (cold launch goes straight to
    /// `LoggingHomeView` now, so the prePair button is unreachable from
    /// the root flow).
    @EnvironmentObject var demo: DemoController

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

    /// b57 V3 §2: DROP toggle idle-fire timer. b58 V4 retired this in favor
    /// of LoggingStore's time-driven cascade (`startDropSet`). Kept declared
    /// only to avoid a churn-y diff if a future build wants finalize-driven
    /// DROP back; unused at runtime in V4.
    @State private var dropIdleWorkItem: DispatchWorkItem? = nil

    /// b58 V4: which Voltra the screen's mod controls are currently driving.
    /// Defaults to `.left`; only matters when both `mdm.left` and `mdm.right`
    /// are connected AND `mdm.workoutMode == .independent`. In `.combined`
    /// (Twin Mode) every adjustment mirrors to both regardless of focus. In
    /// single-Voltra sessions this is ignored.
    @State private var focusedSlot: DeviceSlot = .left

    /// Owns its own writer router — same pattern as V1.
    @StateObject private var writerRouter = WriterRouter()

    // MARK: - b66 V4.2: live-set lock helpers

    /// True while the lift is above the cascade idle force floor (3 lb).
    /// Mirrors the gate `LoggingStore.noteTelemetryActivity(forceLb:)`
    /// uses so the V4.2 ASSIGN TO VOLTRA panel locks pills at exactly the
    /// same moment the engine considers the lift "engaged". Locked via MC
    /// answer 2A: pills lock during live set.
    ///
    /// 3 lb is the engine constant `cascadeIdleForceFloorLb` — hard-coded
    /// here because the constant is private to LoggingStore. If the
    /// engine's floor changes, update this in lockstep.
    private var isLiveSetInProgress: Bool {
        ble.telemetry.forceLb > 3.0
    }

    // MARK: Body

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // b67 V4.3 (Bug 03/08): single canonical chrome —
                    // VoltraUnitHeader on the live screen. Per-exercise
                    // override scope (exerciseName) + live-set lock
                    // (isReadOnly locks every pill mid-set). Mirror
                    // rules 1A + 2A.
                    VoltraUnitHeader(
                        mdm: mdm,
                        hk: health,
                        exerciseName: logging.activeInstance?.exercise?.name,
                        isReadOnly: isLiveSetInProgress,
                        onPairRequest: { slot in
                            pairing.presentPair(slot: slot)
                        }
                    )
                    .padding(.bottom, 8)

                    // b66 V4.2: V1 supersetBanner verbatim port +
                    // breathing-ring delta on ACTIVE side. Self-hides
                    // when supersetTag is false or both Voltras are
                    // not paired.
                    //
                    // b71 (V4-D21 part 2): pass `session` so the banner's
                    // SWAP can call `forceFinalizeCurrentSet()` directly
                    // (V1's safety contract: no telemetry-orphaned set on
                    // mid-set chain advance), and pass `onAfterSwap` so
                    // the host's writer-cache-aware `pushUpcomingStateToDevice`
                    // is the single source of device-side state, identical
                    // to V1.
                    SupersetSwitcherBanner(
                        mdm: mdm,
                        logging: logging,
                        session: session,
                        onAfterSwap: { pushUpcomingStateToDevice() }
                    )
                        .padding(.bottom, 8)

                    headerStrip
                    phaseOrRestBar
                    weightCard
                    smallTileRow
                    // b57 V3 §4: Pulley + Added-plates bar relocated to
                    // sit directly above the force chart.
                    PulleyAndPlatesBarV3()
                        .padding(.bottom, 8)
                    forceChartCard
                    // b71 (V4-D21): visible drop cascade cancel chip,
                    // ported from V1's dropSetSection. Self-hides when
                    // no cascade is active.
                    dropCancelChipV2
                    V1RestoreSection(onEndTapped: { showingEndConfirm = true })
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 22)
                // b73 V4-D23: report content metrics so debug grid row
                // labels track the user's scroll position.
                .debugGridContent()
            }
        }
        .navigationBarBackButtonHidden(true)
        // b68 (B68-01) Q2: hand off from prePair demo to real telemetry
        // the moment any of the three connection paths flips to
        // .connected. Wired to all three @Published states; Equatable
        // associated values mean redundant fires are harmless because
        // `handleConnectionChange()` is guarded by `demo.isActive` +
        // `entrySource == .prePair`.
        .onChange(of: ble.connectionState)        { _, _ in handleConnectionChange() }
        .onChange(of: mdm.left.connectionState)   { _, _ in handleConnectionChange() }
        .onChange(of: mdm.right.connectionState)  { _, _ in handleConnectionChange() }
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
            // b71 (V4-D21): mirror V1's onAppear writer-cache wipe.
            // V1 LiveCaptureView.swift:213 clears writerRouter +
            // mdm.left/rightWriter applied-state on every entry to
            // the live screen. Without it the writer's cached
            // baseLb may equal the new target after a device
            // power-cycle, no-op'ing the first LOAD. V2 only wiped
            // writerRouter; the dual-side writers were leaked.
            writerRouter.resetAppliedState()
            mdm.leftWriter.resetAppliedState()
            mdm.rightWriter.resetAppliedState()
            // b71 (V4-D21): mirror V1 LiveCaptureView.swift:223 —
            // push current workoutMode into LoggingStore so the
            // drop-set cascade math knows whether to use even (-6 lb)
            // or odd (-5 lb) steps, and round the standing pending
            // weight to even on Combined entry.
            logging.applyWorkoutMode(mdm.workoutMode)
            enforceCombinedParityOnEntry()
            // b71 (V4-D21 part 2): mirror V1 LiveCaptureView.swift:242-248
            // verbatim — when arriving at the live screen with an active
            // chain (>=2 entries), restore the active entry's exercise
            // and planned weight, re-anchor the cascade, and push the
            // resulting state to the device. The picker / chain-builder
            // does not know about LoggingStore (separate module) and the
            // user is briefly on the home screen between
            // appendSupersetEntry and entering the live view, so onAppear
            // is the canonical "about to start lifting" hook. SWAP keeps
            // doing its own restore work for in-flight chain advances;
            // this onAppear path is idempotent with it.
            if let entry = mdm.activeSupersetEntry,
               mdm.supersetChain.count >= 2 {
                logging.switchActiveInstanceByExerciseName(entry.exerciseName)
                logging.pendingPlannedWeightLb = entry.plannedWeightLb
                logging.reanchorCascadeIfActive(toLb: entry.plannedWeightLb)
                pushUpcomingStateToDevice()
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
            // Independent 1Hz blink driver for rest-over UI elements.
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in self.blinkOn.toggle() }
            }
        }
        // b71 (V4-D21): mirror V1 LiveCaptureView.swift:250 — keep
        // cascade math + Combined parity in sync if the user
        // switches mode mid-session (back out to picker, re-enter).
        .onChange(of: mdm.workoutMode) { _, newMode in
            logging.applyWorkoutMode(newMode)
            enforceCombinedParityOnEntry()
        }
        // b71 (V4-D21 part 2): mirror V1 LiveCaptureView.swift:264-268
        // verbatim. Lock the superset tag the instant set 1 begins.
        // session.currentSet flips nil -> non-nil on the first Pull
        // or rep bump, which is the canonical "set 1 has started" event.
        // After this the user can no longer toggle mdm.supersetTag — the
        // historical record is sealed. Subsequent set starts are no-ops
        // because lockSupersetTag() is idempotent.
        .onChange(of: session.currentSet != nil) { _, started in
            if started && mdm.supersetTag {
                mdm.lockSupersetTag()
            }
        }
        // b71 (V4-D21 part 2): mirror V1 LiveCaptureView.swift:283-288
        // verbatim. Keep LoggingStore.activeInstance in sync with the
        // active chain slot. Pre-b52 (V1) the only resync path was
        // SWAP's call to switchActiveInstanceByExerciseName, so any
        // other route that flipped supersetActiveSlot (chain advance,
        // navigation back into a chain entry, etc.) left activeInstance
        // pointing at the wrong exercise — sets committed against the
        // wrong instance. Resyncing here on every slot change closes
        // that gap.
        //
        // Guard: only run while no set is in flight. If a slot flip
        // races a live set boundary, SWAP itself force-finalizes the
        // current set BEFORE flipping (see SupersetSwitcherBanner.swap),
        // so this observer is a NO-OP during that window. The guard
        // catches any future code path that flips the slot without
        // finalizing.
        .onChange(of: mdm.supersetActiveSlot) { _, _ in
            guard session.currentSet == nil else { return }
            if let entry = mdm.activeSupersetEntry {
                logging.switchActiveInstanceByExerciseName(entry.exerciseName)
            }
        }
        // b71 (V4-D21): mirror V1 LiveCaptureView.swift:289 — stop
        // HealthKit polling when the live screen vanishes so HR /
        // kcal observers don't leak across navigation.
        .onDisappear {
            health.stop()
        }
        // b66 V4.2: page-name badge — bottom-leading, faint mint,
        // Swift type name verbatim. Always visible in TestFlight.
        .pageBadge("LiveCaptureViewV2")
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

                // b58 V4 §4: header telemetry cluster. When both Voltras are
                // connected, swap to the L ⋆ MERGE ⋆ R unit selector with
                // the kcal pill trailing. In Independent mode the focused
                // side's status dot tints accent / the unfocused side dims.
                // In Twin (combined) mode the [⇄ MERGE] tile lights up and
                // the two side pills fuse into [● L+R total · max bpm].
                if bothVoltrasConnected {
                    dualHeaderCluster
                } else {
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

    // MARK: - b58 V4 §4: dual-Voltra header cluster

    /// `[● L bpm] [⇄ MERGE] [● R bpm] kcal`
    /// Tapping a side dot focuses that unit (Independent only — Twin
    /// always mirrors writes to both). Tapping MERGE flips between
    /// `.independent` and `.combined`. The kcal pill trails unchanged.
    /// In Twin mode the side dots fuse into a single [● L+R total · max]
    /// pill before MERGE.
    @ViewBuilder
    private var dualHeaderCluster: some View {
        if twinModeActive {
            HStack(spacing: 6) {
                fusedTwinPill
                mergeButton
                healthPill(
                    color: VoltraColor.warn,
                    value: health.sessionKcal > 0 ? String(format: "%.0f", health.sessionKcal) : "\u{2014}",
                    unit:  "kcal"
                )
            }
        } else {
            HStack(spacing: 6) {
                sideDot(slot: .left)
                mergeButton
                sideDot(slot: .right)
                healthPill(
                    color: VoltraColor.warn,
                    value: health.sessionKcal > 0 ? String(format: "%.0f", health.sessionKcal) : "\u{2014}",
                    unit:  "kcal"
                )
            }
        }
    }

    /// Per-side dot + bpm pill. When `focusedSlot == slot` the dot tints
    /// accent and the pill border highlights. Tap focuses this slot.
    @ViewBuilder
    private func sideDot(slot: DeviceSlot) -> some View {
        let isFocused = (focusedSlot == slot)
        let label = (slot == .left) ? "L" : "R"
        Button {
            // Switch focus only when Independent. Tapping a side in Twin
            // is a no-op (writes already mirror) but we still allow it to
            // bias which side's bpm reads in the fused pill, by storing
            // focus regardless. WriterRouter routing is decided via
            // focusOverrideAssignment which respects mdm.workoutMode.
            focusedSlot = slot
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isFocused ? VoltraColor.accent : VoltraColor.textDim)
                    .frame(width: 7, height: 7)
                    .shadow(
                        color: isFocused ? VoltraColor.accent.opacity(0.7) : .clear,
                        radius: isFocused ? 3 : 0
                    )
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isFocused ? VoltraColor.text : VoltraColor.textDim)
                Text(health.currentHR.map(String.init) ?? "\u{2014}")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                Text("bpm")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(VoltraColor.textDim)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(VoltraColor.bgElev2)
            .overlay(
                Capsule().stroke(
                    isFocused ? VoltraColor.accent.opacity(0.55) : VoltraColor.border,
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// `[⇄ MERGE]` button. Tap toggles between `.independent` and
    /// `.combined`. Reads pressed when `twinModeActive`.
    @ViewBuilder
    private var mergeButton: some View {
        Button {
            // Toggle. Both modes assume both sides connected (we only show
            // this cluster under bothVoltrasConnected).
            mdm.workoutMode = (mdm.workoutMode == .combined) ? .independent : .combined
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("MERGE")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.4)
            }
            .foregroundColor(twinModeActive ? VoltraColor.bg : VoltraColor.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(twinModeActive ? VoltraColor.accent : VoltraColor.bgElev2)
            .overlay(
                Capsule().stroke(
                    twinModeActive ? VoltraColor.accent : VoltraColor.border,
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Fused L+R pill shown in Twin mode. Single dot, single bpm reading
    /// (the screen still shows one HealthKit stream regardless of unit
    /// count), but the label disambiguates so it doesn't read like a
    /// single-Voltra session.
    @ViewBuilder
    private var fusedTwinPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(VoltraColor.accent)
                .frame(width: 7, height: 7)
                .shadow(color: VoltraColor.accent.opacity(0.7), radius: 3)
            Text("L+R")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
            Text(health.currentHR.map(String.init) ?? "\u{2014}")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(VoltraColor.text)
            Text("bpm")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(VoltraColor.textDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(VoltraColor.bgElev2)
        .overlay(Capsule().stroke(VoltraColor.accent.opacity(0.55), lineWidth: 1))
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

    // MARK: - 2. Phase strip OR Rest Timer Bar OR Dropset Progress Bar

    /// b56 / b60 (KI-8): single progress bar that morphs across three
    /// states without ever swapping component identities:
    ///
    ///   1. Rest timer (post-finalize): preset countdown w/ HSL sweep
    ///      and over-time blink. Highest priority — if the rest clock
    ///      is ticking, the user is between sets.
    ///   2. Dropset progress (DROP tile armed or active): two
    ///      sub-states:
    ///        a. Armed + lift idle → 2 s ARM countdown to first drop.
    ///        b. Active + cascade running → 2 s tier-to-tier countdown.
    ///      Bottoming out at the 5 lb floor surfaces "BOTTOM" instead
    ///      of an empty bar so the user knows the cascade ended.
    ///   3. Active phase strip: PUSH/PULL/IDLE color band, default.
    ///
    /// Why one bar across all three: pre-b60 the dropset countdown was
    /// invisible — the user could only see weight changes mid-cascade,
    /// not WHEN the next change would come. KI-8 surfaces that timing
    /// by reusing the same bar the user is already reading for rest.
    @ViewBuilder
    private var phaseOrRestBar: some View {
        let phase = ble.telemetry.phase
        // P1-2 (b66): key on `session.restActive` rather than the
        // rounded elapsed seconds. The previous predicate
        // (`Int(restElapsedSeconds.rounded()) > 0`) made the rest bar
        // miss the very first set finalize after launch, because
        // `restElapsedSeconds` is 0 until the 0.25s ticker next fires
        // — the bar would silently fail to mount on engage. Sourcing
        // mount state from `restActive` (which is set synchronously
        // inside `finalizeSet()` and `tapRestTile()`) is honest to
        // intent and removes the race.
        let restElapsed = max(0, Int(session.restElapsedSeconds.rounded()))
        if session.restActive {
            RestTimerBarV2(
                restElapsedSec: restElapsed,
                restPresetSec:  restPresetSeconds,
                blinkOn:        blinkOn
            )
            .padding(.bottom, 10)
        } else if logging.dropSetArmed || logging.dropSetActive {
            dropProgressBar
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

    /// b60 (KI-8): dropset progress bar. Renders one of four labels +
    /// a sweep that fills as the next-fire wall-clock deadline
    /// approaches. The fill animates via the ambient `blinkOn` 2 Hz
    /// republish (same source the rest bar uses for its over-time
    /// blink) so we don't spin a second timer here.
    ///
    ///   - "DROP · ARM"    — armed, lift still active. Empty bar.
    ///   - "DROP · IN"     — armed, lift idle. 2 s countdown to first drop.
    ///   - "DROP · NEXT"   — active cascade. 2 s tier-to-tier countdown.
    ///   - "DROP · BOTTOM" — active cascade hit the 5 lb floor. Full bar.
    private var dropProgressBar: some View {
        let armed   = logging.dropSetArmed
        let active  = logging.dropSetActive
        let atFloor = logging.cascadeAtFloor
        let armSec  = logging.cascadeArmIdleSecondsForUI
        let tickSec = logging.cascadeIntervalSecondsForUI
        _ = blinkOn // republish driver; we read `Date()` below
        let now = Date()
        let progress: Double = {
            if active && atFloor { return 1.0 }
            if active, let deadline = logging.nextDropFiresAt {
                let remaining = max(0, deadline.timeIntervalSince(now))
                return min(1.0, max(0.0, 1.0 - (remaining / tickSec)))
            }
            if armed, let deadline = logging.dropArmedFiresAt {
                let remaining = max(0, deadline.timeIntervalSince(now))
                return min(1.0, max(0.0, 1.0 - (remaining / armSec)))
            }
            return 0.0
        }()
        let label: String = {
            if active && atFloor { return "DROP \u{00B7} BOTTOM" }
            if active            { return "DROP \u{00B7} NEXT" }
            if armed && logging.dropArmedFiresAt != nil { return "DROP \u{00B7} IN" }
            return "DROP \u{00B7} ARM"
        }()
        let secondsRemaining: Int = {
            if active && !atFloor, let d = logging.nextDropFiresAt {
                return max(0, Int(d.timeIntervalSince(now).rounded(.up)))
            }
            if armed, let d = logging.dropArmedFiresAt {
                return max(0, Int(d.timeIntervalSince(now).rounded(.up)))
            }
            return 0
        }()
        return VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.6)
                    .foregroundColor(VoltraColor.accent)
                Spacer()
                if secondsRemaining > 0 {
                    Text("\(secondsRemaining)s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(VoltraColor.text)
                }
            }
            GeometryReader { geo in
                let fillW = geo.size.width * CGFloat(progress)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(VoltraColor.bgElev2)
                        .frame(height: 4)
                    Capsule(style: .continuous)
                        .fill(VoltraColor.accent)
                        .frame(width: fillW, height: 4)
                        .animation(.linear(duration: 0.5), value: fillW)
                }
                .frame(height: 4)
            }
            .frame(height: 4)
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
            // Top row: WEIGHT label + Target chip + LOADED/UNLOADED pill
            HStack(spacing: 8) {
                Text("WEIGHT")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.6)
                    .foregroundColor(VoltraColor.textDim)
                // b71 (V4-D21): port V1 effectiveTargetReps display.
                // Renders the "Target N reps" hint that V1 surfaced on
                // upcomingSetCard so users can see their reps target on
                // the V2 live screen too. Hidden when no target is set.
                if let reps = effectiveTargetReps {
                    Text("Target \(reps) reps")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(VoltraColor.textDim)
                }
                Spacer()
                loadedPill
            }

            // Big number row + steppers. b56: tapping the number toggles
            // hardware LOAD/UNLOAD. Number is green when deviceLoaded.
            //
            // b66 V4.2 P1-1 fix: 3-digit weight + TWIN badge overlap.
            // Pre-b66 the TWIN capsule shared an HStack with the
            // shrink-to-fit weight number; on "4xx lb TWIN" the gradient
            // fade-out mask leaked over the lb suffix and visually
            // crashed into the badge. Fix: TWIN now lives in the OUTER
            // HStack as a fixed-size sibling AFTER the steppers spacer,
            // and the weight `Text` is wrapped in a `frame(maxWidth:
            // .infinity, alignment: .leading)` so it owns its own slot
            // and can compress without dragging the lb suffix or TWIN
            // along with it. The fade-out mask now applies ONLY to the
            // number (not the trailing label cluster).
            HStack(spacing: 10) {
                Button(action: toggleHardwareLoad) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(weightLb)")
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(deviceLoaded ? VoltraColor.accent : VoltraColor.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .black,            location: 0.0),
                                        .init(color: .black,            location: 0.92),
                                        .init(color: .black.opacity(0), location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint:   .trailing
                                )
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("lb")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(VoltraColor.textDim)
                            .layoutPriority(2)
                            .fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .layoutPriority(1)

                // b66 V4.2 P1-1: TWIN badge promoted out of the weight
                // button so it can never be visually clipped by the
                // weight gradient mask. Sits between the weight cluster
                // and the steppers; only renders when MERGE is active.
                if twinModeActive {
                    Text("TWIN")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(VoltraColor.bg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VoltraColor.accent)
                        .clipShape(Capsule())
                        .fixedSize()
                        .layoutPriority(2)
                }

                Spacer(minLength: 4)
                // b71 (V4-D21): mode-aware step sizes via CombinedParity,
                // matching V1's weightNudgerRow. Combined mode advertises
                // \u00B12 / \u00B16 so totals stay even per b47 parity rule;
                // every other mode keeps the legacy \u00B11 / \u00B15 steps.
                let small = CombinedParity.smallStepLb(for: mdm.workoutMode)
                let large = CombinedParity.largeStepLb(for: mdm.workoutMode)
                stepperButton("\u{2212}\(large)") { adjustWeight(-large) }
                stepperButton("\u{2212}\(small)") { adjustWeight(-small) }
                stepperButton("+\(small)")        { adjustWeight(+small) }
                stepperButton("+\(large)")        { adjustWeight(+large) }
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
                if dropArmed {
                    // b58 V4: cascade head = last anchored device-frame weight
                    // pushed (or current planned weight if no drop has fired
                    // yet). The next preview weight comes from the LoggingStore
                    // anchor-relative preview helper, which honors current
                    // tier + combined-mode rounding rules. previewNextCascade
                    // takes EFFECTIVE (user-felt) lb, so we multiply head by
                    // pulleyMultiplier on the way in.
                    let pulleyM = logging.pulleyMultiplier
                    let headDeviceLb = logging.dropChainPlannedLb.last
                        ?? (logging.pendingPlannedWeightLb ?? 0)
                    let headEffLb = Int((headDeviceLb * pulleyM).rounded())
                    let preview = logging.previewNextCascade(
                        from: headDeviceLb * pulleyM,
                        count: 1
                    )
                    let nextEffLb = Int((preview.first ?? Double(headEffLb)).rounded())
                    NestedModRowV2.drop(
                        currentLb: headEffLb,
                        nextLb:    max(5, nextEffLb)
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
                if dropArmed {
                    // b58 V4: stepper value = current cascade tier step in lb
                    // (5/10/15). ±1 buttons are greyed (dropMode=true);
                    // ±5 cycles the tier forward / backward.
                    let stepLb: Int = {
                        switch logging.cascadeTier {
                        case 1: return 5
                        case 2: return 10
                        case 3: return 15
                        default: return 5
                        }
                    }()
                    ModStepperRowV2(
                        label: "DROP",
                        valueLb: stepLb,
                        valueTint: VoltraColor.warn,
                        dropMode: true
                    ) { delta in adjustDropStep(delta) }
                }
            }

            // b71 (V4-D21): port V1 modeChipsRow. SetMode picker for
            // working / warmUp / eccentric / band / pause / dropSet /
            // isoHold. V2 previously had no surface for these tags so
            // warmUp / pause / isoHold sets could not be tagged at all.
            // Selecting a mode mirrors V1's behavior: write to
            // logging.upcomingMode and re-push device state (band
            // toggles VoltraMode.band on the BLE write).
            modeChipsRow
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

    /// b71 (V4-D21): port of V1 effectiveTargetReps. Returns the
    /// upcoming target reps when > 0, otherwise nil so the chip
    /// hides. Mirrors V1 LiveCaptureView.swift:1480.
    private var effectiveTargetReps: Int? {
        let r = logging.upcomingTargetReps
        return r > 0 ? r : nil
    }

    /// b71 (V4-D21): port of V1 modeChipsRow (LiveCaptureView.swift:
    /// 1588). Horizontal scroll of seven SetMode chips. Selected chip
    /// fills with accent; tapping re-pushes device state so the
    /// VoltraMode.band branch fires on band selection.
    private var modeChipsRow: some View {
        let modes: [SetMode] = [.working, .warmUp, .eccentric, .band, .pause, .dropSet, .isoHold]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modes, id: \.self) { m in
                    Button {
                        logging.upcomingMode = m
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

    /// b71 (V4-D21): visible drop cascade cancel chip, ported from V1
    /// dropSetSection / dropCancelChip. V2 previously only allowed
    /// cancellation via long-press on the DROP tile, which the user
    /// reported was not discoverable. The chip self-hides unless
    /// `logging.dropSetActive` is true.
    @ViewBuilder
    private var dropCancelChipV2: some View {
        if logging.dropSetActive {
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
            .padding(.bottom, 6)
        }
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
    //
    // b71 (V4-D20 — supersedes V4-D13 / b67-10): V1's `ForceChartView` is
    // now the canonical force-curve renderer for V2. The previous V2-only
    // `ForceChartV2` (parametric `sin(π·t)` lobes) is retained on disk for
    // rollback safety but is NO LONGER MOUNTED — see
    // `VoltraLive/Logging/Views/V2/ForceChartV2.swift` for the SUPERSEDED
    // banner. User-facing rationale (verbatim, 2026-04-30):
    //   "the V1 ForceChartView is the one that displays the force curve
    //    correctly in practice. Replace or wrap V2's force panel so
    //    LiveCaptureViewV2 uses the V1 ForceChartView behavior/data path."
    //
    // This helper is now a thin V1-input adapter: it reproduces the same
    // builder block V1 uses in `LiveCaptureView.forceChart` (samples / peak
    // / pulley multiplier / planned ceiling / superset secondary trace) and
    // returns `ForceChartView` directly. We deliberately do NOT wrap it in
    // V2-only chrome — `ForceChartView` paints its own header, legend, peak
    // readout, padding, bgElev, border, and rounded-corner clip. Stacking
    // V2's old card chrome on top would produce double headers / double
    // borders / nested cards.

    private var forceChartCard: some View {
        // Sample source — V1-verbatim:
        //   currentSet.samples while a set is in flight, then
        //   lastFinalizedSamples after finalize so the chart KEEPS
        //   displaying the rep pattern through the rest period instead
        //   of blanking. Cleared on next set.
        let samples = session.currentSet?.samples
            ?? session.lastFinalizedSamples
        let peak = session.currentSet?.peakLb
            ?? session.lastFinalizedPeakLb
        let m = logging.pulleyMultiplier
        // Planned ceiling computed in EFFECTIVE space (pulley-multiplied)
        // so a 50 lb device under 2× pulley reads as 100 lb on the y-axis,
        // matching the smoothed sample values the chart will plot. Verbatim
        // from `LiveCaptureView.forceChart` (V1 line ~1052).
        let planned = ((logging.pendingPlannedWeightLb ?? 0) + logging.upcomingEccLb) * m
            + (logging.upcomingAddedLoadLb ?? 0)

        // b49 superset secondary trace — V1-verbatim. When a 2+ exercise
        // chain is active, pull the OTHER exercise's most-recent finalized
        // force trace out of `SessionStore.lastFinalizedByExercise` and
        // pass it as a secondary (dashed, dimmed) trace so the user can
        // compare both exercises in one chart. Labels come from the chain
        // entries.
        var secondarySamples: [ForceSample]? = nil
        var primaryLabel: String? = nil
        var secondaryLabel: String? = nil
        if mdm.hasActiveSupersetChain,
           let active = mdm.activeSupersetEntry,
           let other  = mdm.nextSupersetEntry,
           active.exerciseName != other.exerciseName {
            primaryLabel   = active.exerciseName
            secondaryLabel = other.exerciseName
            if let trace = session.lastFinalizedByExercise[other.exerciseName], !trace.isEmpty {
                secondarySamples = trace
            }
        }

        return ForceChartView(
            samples: samples,
            peakLb: peak,
            plannedCeilingLb: planned > 0 ? planned : nil,
            forceMultiplier: m,
            secondarySamples: secondarySamples,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel
        )
        .frame(minHeight: 280)
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
    /// b58 V4 / b60 (KI-9): DROP tile is "armed" whenever the cascade is
    /// either tap-armed (waiting for the lift to go idle) OR actively
    /// running. Tile visuals + nested-row visibility don't distinguish
    /// the two states; the unified progress bar (KI-8) does.
    private var dropArmed:   Bool { logging.dropSetActive || logging.dropSetArmed }

    // MARK: - b58 V4: dual-Voltra helpers

    /// True only when BOTH MDM slots report a live connection. Single-
    /// Voltra sessions stay on the b57 header.
    private var bothVoltrasConnected: Bool {
        mdm.left.connectionState.isConnected &&
        mdm.right.connectionState.isConnected
    }

    /// True when the user has merged both Voltras into a single virtual
    /// twin (`mdm.workoutMode == .combined`). Drives the TWIN badge, the
    /// pulley grey-out, and the fused HR pill.
    private var twinModeActive: Bool {
        bothVoltrasConnected && mdm.workoutMode == .combined
    }

    /// b58 V4: BLE manager for whichever side currently owns the screen's
    /// mod controls. In Twin mode this is read-only — writes broadcast to
    /// both via `mdm.applyCombined`. In Independent mode this returns the
    /// focused unit. In single-Voltra sessions this returns the legacy
    /// `ble` so existing logic keeps working unchanged.
    private var focusedBle: VoltraBLEManager {
        if !bothVoltrasConnected { return ble }
        switch focusedSlot {
        case .left:  return mdm.left
        case .right: return mdm.right
        }
    }

    /// b58 V4 §5: per-write assignment override.
    /// In Independent + dual-connected sessions, force the writer to the
    /// focused unit so weight / ECC / CHAIN / INV CHAIN / DROP edits only
    /// hit the side the user is looking at. In Twin mode return nil so
    /// the WriterRouter falls through to its `.combined` branch and
    /// mirrors writes via `mdm.applyCombined`. In single-Voltra sessions
    /// return the instance's stored assignment unchanged.
    private var focusOverrideAssignment: DeviceSlotAssignment? {
        if bothVoltrasConnected && mdm.workoutMode == .independent {
            return DeviceSlotAssignment(slot: focusedSlot)
        }
        if twinModeActive {
            return nil
        }
        return logging.activeInstance?.assignedVoltra
    }

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

    /// b58 V4 / b60 (KI-9): DROP tile state machine.
    ///   Tap inactive: armDropSet — captures anchor + writer bridge,
    ///     flips `dropSetArmed = true`, but DOES NOT touch the cable.
    ///     The first cascade drop fires only after the lift has been
    ///     idle (force ≤ 3 lb) for `cascadeArmIdleSec` (= 2 s).
    ///   Tap while armed (not yet engaged): cancelArmedDropSet — clears
    ///     arm state with a 1.5 s cooldown so a long-press cancel + tap
    ///     don't fight.
    ///   Tap while active: bumpCascadeTier — 5→10→15→5, fires immediate
    ///     drop at the new tier, resets the 2 s fuse.
    ///   Long-press: cancelDropSet (active) or cancelArmedDropSet (armed).
    /// Telemetry activity (forceLb > 3 lb) is forwarded into
    /// `LoggingStore.noteTelemetryActivity` from `VoltraLiveApp`'s BLE
    /// telemetry pipe — that is the engine that engages the armed
    /// cascade once the lift has been idle for 2 s.
    private func tapDropTile() {
        if logging.dropSetActive {
            // Tap-while-active: bump the tier & fire immediately.
            logging.bumpCascadeTier()
            return
        }
        if logging.dropSetArmed {
            // Tap-to-disarm before the first drop has fired.
            logging.cancelArmedDropSet()
            return
        }
        let starting = (logging.pendingPlannedWeightLb ?? 0)
        guard starting > 0 else { return }
        // Capture writerRouter + mdm so the cascade can re-target the device
        // ONCE the arm-idle gate elapses and the engine engages the chain.
        // armDropSet is a no-op weight write — the cable holds the working
        // weight until the user finishes the rep and the lift goes idle.
        logging.armDropSet(startingLb: starting) { [weak ble = ble] lb in
            // Re-build the upcoming state with the new device-frame base
            // weight. ECC / CHAIN / INV CHAIN flags are preserved from the
            // current upcoming state so the chain inherits the parent set's
            // mods.
            let baseLb = Int(lb.rounded())
            let eccLb = logging.upcomingEccEnabled
                ? Int(logging.upcomingEccLb.rounded()) : 0
            let chainsActive = logging.upcomingChainsEnabled
                && logging.upcomingChainsLb > 0
            let inverseActive = logging.upcomingInverseEnabled
                && logging.upcomingInverseLb > 0
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
                    chains: chainsActive,
                    inverse: inverseActive
                ),
                weights: VoltraWeights(
                    baseLb: baseLb,
                    eccentricLb: eccLb,
                    chainsLb: chainsLb,
                    bandMaxForceLb: 0,
                    damperLevel: 0
                )
            )
            // b58 V4 §5: cascade writes also respect focus / Twin mode.
            writerRouter.apply(
                state,
                mdm: mdm,
                assignment: focusOverrideAssignment
            )
            _ = ble  // silences capture warning when unused
        }
    }

    /// Long-press cancel for the DROP tile. Branches on cascade state:
    ///   - active: cancelDropSet (restores anchor weight on device,
    ///     1.5 s re-arm cooldown).
    ///   - armed (b60 / KI-9): cancelArmedDropSet (no device write
    ///     needed — the cable was never moved off the working weight).
    private func cancelArmedDrop() {
        if logging.dropSetActive {
            logging.cancelDropSet()
        } else if logging.dropSetArmed {
            logging.cancelArmedDropSet()
        }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    // MARK: - Stepper actions

    /// b71 (V4-D21): port of V1 enforceCombinedParityOnEntry
    /// (LiveCaptureView.swift:300). When entering Combined mode,
    /// round the standing pendingPlannedWeightLb DOWN to the nearest
    /// even pound. No-op in any other mode. Per b47 Q1 = A: round
    /// down so we never silently add weight the user didn't request.
    private func enforceCombinedParityOnEntry() {
        guard mdm.workoutMode.requiresEvenWeight else { return }
        let cur = Int((logging.pendingPlannedWeightLb ?? 0).rounded())
        let even = CombinedParity.roundDownToEven(cur)
        if even != cur {
            logging.pendingPlannedWeightLb = Double(even)
            logging.reanchorCascadeIfActive(toLb: Double(even))
            pushUpcomingStateToDevice()
        }
    }

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

    /// b58 V4 §2/§3: DROP step adjuster.
    /// In V4 the step is no longer a freeform value — it's the cascade
    /// `tier` (1→3, mapping to 5/10/15 lb base steps). ±5 buttons cycle the
    /// tier forward/backward; ±1 buttons are no-ops (greyed via dropMode).
    /// Cycling tier mid-cascade fires an immediate drop at the new tier
    /// (LoggingStore.bumpCascadeTier) so the user sees the device respond.
    private func adjustDropStep(_ delta: Int) {
        // Clamp to multiples of 5 — micro-drops are forbidden per spec.
        guard delta == 5 || delta == -5 else { return }
        guard logging.dropSetActive else { return }
        // bumpCascadeTier rolls 1→2→3→1. For −5 we want the previous tier;
        // since the cycle is 3-wide, two forward bumps == one backward.
        if delta == 5 {
            logging.bumpCascadeTier()
        } else {
            logging.bumpCascadeTier()
            logging.bumpCascadeTier()
        }
    }

    // MARK: - Hardware LOAD/UNLOAD

    /// b56: tap on the big WEIGHT NUMBER toggles hardware LOAD/UNLOAD,
    /// reusing the same opcode path V1 uses (sendLoad/sendUnload). When
    /// any MDM slot is paired we route through MDM; otherwise legacy ble.
    private func toggleHardwareLoad() {
        // b68 (B68-01): if no Voltra is connected and demo isn't already
        // active, auto-engage prePair demo so the force chart + rep
        // counter respond to synthetic telemetry. Replaces the orphaned
        // ConnectView prePair entry. User decision (Apr 29 2026 PDT):
        //   Q1 = any weight tap, no device → fire here.
        //   Q4 = silent (no banner/toast); existing DemoModeOverlay is
        //        the only signal.
        // Q2 (auto-exit on real-device connect mid-session) is handled
        // by the .onChange observer on connection state in body.
        autoEngageDemoIfNeeded()

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

    /// b68 (B68-01): true when no Voltra is paired & connected on any
    /// path (legacy single `ble`, MDM left, or MDM right).
    private var anyDeviceConnected: Bool {
        ble.connectionState.isConnected
            || mdm.left.connectionState.isConnected
            || mdm.right.connectionState.isConnected
    }

    /// b68 (B68-01): auto-engage prePair demo when the user interacts
    /// with weight controls but no Voltra is connected. Idempotent —
    /// `DemoController.enter` early-returns when already active.
    private func autoEngageDemoIfNeeded() {
        guard !anyDeviceConnected, !demo.isActive else { return }
        guard let handler = DemoTelemetryBridge.shared.handler else { return }
        demo.note(.buttonTap(
            label: "Auto-engage (no device, weight tapped)",
            screen: "LiveCaptureViewV2"
        ))
        demo.enter(source: .prePair, onTelemetry: handler)
    }

    /// b68 (B68-01) / Q2: when a real Voltra connects mid-session while
    /// prePair demo is active, exit demo so subsequent reps consume real
    /// telemetry. postPair demo (manually engaged from home with a
    /// device already paired) is left alone — that path is intentional.
    private func handleConnectionChange() {
        guard demo.isActive,
              demo.entrySource == .prePair,
              anyDeviceConnected else { return }
        _ = demo.exit()
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
        // b58 V4 §5: focus-aware routing. Independent + both connected =
        // writes go to the focused side only; Twin mode returns nil so
        // WriterRouter falls into the `.combined` mirror branch.
        writerRouter.apply(state, mdm: mdm, assignment: focusOverrideAssignment)
    }
}
