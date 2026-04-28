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
            // Both paired — honor the user's chosen workoutMode.
            switch mdm.workoutMode {
            case .combined:
                mdm.applyCombined(state)
            case .singleLeft:
                mdm.leftWriter.apply(state)
            case .singleRight:
                mdm.rightWriter.apply(state)
            case .independent:
                // Independent: each side is the same target weight; user
                // is doing the same exercise on both unilaterally.
                mdm.leftWriter.apply(state)
                mdm.rightWriter.apply(state)
            case .superset:
                // b48 Superset: route writes to the ACTIVE side only.
                // The active side flips on every set finalize. The view
                // owns the flip and reads `mdm.supersetActiveSlot` to
                // decide which writer to drive. State writes to the
                // inactive side would clobber its standing weight.
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
