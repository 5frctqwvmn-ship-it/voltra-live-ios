// WriterRouter.swift
//
// Build 45 (v0.4.23): Routes VoltraDeviceState writes to the correct
// destination based on whether MultiDeviceManager has dual Voltras paired.
//
// Background: prior to b45, LiveWriterHolder/WriterHolder held a single
// VoltraWriter bound to the legacy single-device VoltraBLEManager. When the
// user paired two Voltras through the unified Connect sheet (b40), both
// peripherals were owned by MultiDeviceManager — the legacy `ble` was
// disconnected, so all `writerHolder.writer?.apply(state)` calls fired into
// a writer whose BLE characteristic was nil. Result: weights never loaded
// and the device looked "frozen" even though telemetry routing (b41) was
// firing correctly.
//
// Fix: this router decides per-write where the bytes go:
//   • MDM has 2 slots paired AND workoutMode == .combined  → mdm.applyCombined
//   • MDM has 2 slots paired AND workoutMode == .singleLeft → mdm.leftWriter
//   • MDM has 2 slots paired AND workoutMode == .singleRight → mdm.rightWriter
//   • MDM has 2 slots paired AND workoutMode == .independent → BOTH writers
//   • MDM has 1 slot paired                                  → that slot's writer
//   • Otherwise (legacy single-Voltra flow)                  → single VoltraWriter
//
// Owners attach a `ble` once on view appear and pass `mdm` on every write so
// the routing reflects the user's current pairing state.

import Foundation

@MainActor
final class WriterRouter: ObservableObject {

    /// Legacy single-device writer. Constructed lazily on first attach so
    /// the router can be created at @StateObject init time.
    private var singleWriter: VoltraWriter?

    /// Attach the legacy BLE manager. Idempotent — re-attaching is a no-op
    /// so the router survives view re-creation cycles.
    func attach(ble: VoltraBLEManager) {
        guard singleWriter == nil else { return }
        singleWriter = VoltraWriter(
            writeFrame: { [weak ble] frame in ble?.writeControlFrame(frame) },
            log:        { [weak ble] msg   in ble?.addLog(msg) }
        )
    }

    /// Apply a device state, routing through MDM when dual is paired.
    func apply(_ state: VoltraDeviceState, mdm: MultiDeviceManager?) {
        guard let mdm = mdm else {
            singleWriter?.apply(state)
            return
        }
        let leftOn  = mdm.left.connectionState.isConnected
        let rightOn = mdm.right.connectionState.isConnected

        switch (leftOn, rightOn) {
        case (true, true):
            // b50: chain length is the FIRST source of truth. The b49
            // unified flow auto-derives workoutMode = .independent when
            // 2 Voltras are paired, but if the user added a second
            // exercise (chain count >= 2), each side is targeting its
            // OWN exercise's weight — broadcasting both like .independent
            // does would clobber the inactive side's standing weight.
            // Active-slot-only routing is the correct behavior whenever
            // a chain exists, regardless of WorkoutMode.
            //
            // b52: this also fires for a 1-entry chain (the user picked
            // exercise A on slot Left, hasn't added B yet). Prior behavior
            // required count >= 2 (`hasActiveSupersetChain`) and fell
            // through to the `.independent` broadcast below for 1-entry
            // chains, which loaded BOTH Voltras with A's weight even
            // though A was bound to a single slot. The new predicate
            // `hasAnySupersetChainEntry` (count >= 1) routes to the
            // active slot the moment the chain has any entry, matching
            // user expectation that picking exercise A for slot Left
            // does not move the right Voltra.
            if mdm.hasAnySupersetChainEntry {
                switch mdm.supersetActiveSlot {
                case .left:  mdm.leftWriter.apply(state)
                case .right: mdm.rightWriter.apply(state)
                }
                break
            }
            // No chain — fall back to honoring workoutMode. This covers
            // the single-exercise-with-2-Voltras-paired case (.independent
            // means "same weight to both" since the user hasn't added a
            // second exercise) and the explicit Combined / single modes.
            switch mdm.workoutMode {
            case .combined:
                mdm.applyCombined(state)
            case .singleLeft:
                mdm.leftWriter.apply(state)
            case .singleRight:
                mdm.rightWriter.apply(state)
            case .independent:
                // Independent without a chain: same target on both sides
                // (user doing the same exercise unilaterally).
                mdm.leftWriter.apply(state)
                mdm.rightWriter.apply(state)
            case .superset:
                // Legacy path — b49 unified flow no longer routes here
                // since workoutMode is auto-derived. Kept for safety.
                switch mdm.supersetActiveSlot {
                case .left:  mdm.leftWriter.apply(state)
                case .right: mdm.rightWriter.apply(state)
                }
            }
        case (true, false):
            mdm.leftWriter.apply(state)
        case (false, true):
            mdm.rightWriter.apply(state)
        case (false, false):
            // No MDM-owned connection — fall back to the legacy single
            // manager. This is the path used when the user paired one
            // Voltra via the unified sheet but no MDM slot was filled
            // (shouldn't happen post-b40 but kept for safety).
            singleWriter?.apply(state)
        }
    }

    /// Reset the underlying writer's applied-state cache. Called when a
    /// connection drops so the next apply re-sends the full state.
    func resetAppliedState() {
        singleWriter?.resetAppliedState()
    }
}
