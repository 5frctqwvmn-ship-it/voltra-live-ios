// VoltraBLEManager+LoadUnload.swift
//
// Build 36: surface LOAD / UNLOAD on the single-device VoltraBLEManager.
//
// Background: build 29 added VoltraControlFrames+LoadUnload.swift with the
// PARAM_BP_SET_FITNESS_MODE = 0x0005 (LOAD) / 0x0004 (UNLOAD) payload
// builders, and MultiDeviceManager exposed `load(target:)` / `unload(target:)`
// for the dual-Voltra flow. The single-device flow had NO public method to
// fire these — so the Live capture screen couldn't ask the rig to engage or
// release the cable between sets.
//
// User-reported (b30 testing): "no load/unload button on sets". This file
// adds the API; the UI lives in LiveCaptureView.
//
// Conservatism:
//   - Lives in its own file so VoltraBLEManager.swift stays small.
//   - Reuses the same VoltraFrameBuilder + writeControlFrame plumbing as
//     every other control write (bootstrap, weight apply, etc.).
//   - Uses a per-instance ad-hoc seq starting at 0xC000 to stay clear of
//     VoltraWriter's 0..N counter. Device doesn't enforce uniqueness across
//     cmds so collisions are harmless, but separation makes the BLE log
//     easier to read.

import Foundation

extension VoltraBLEManager {

    /// Send LOAD to the connected device. Engages the cable load — weight
    /// becomes felt. Fire-and-forget; safe to call even if disconnected
    /// (writeControlFrame logs a warning and no-ops).
    func sendLoad() {
        let payload = VoltraControlFrames.loadPayload()
        sendAdHocControl(payload, label: "LOAD")
    }

    /// Send UNLOAD to the connected device. Releases the cable — safe to
    /// step off the rack. Fire-and-forget.
    func sendUnload() {
        let payload = VoltraControlFrames.unloadPayload()
        sendAdHocControl(payload, label: "UNLOAD")
    }

    /// Internal: frame an ad-hoc control payload with a per-instance seq
    /// and route to writeControlFrame. Mirrors MultiDeviceManager's
    /// sendControlPayload helper.
    private func sendAdHocControl(_ payload: Data, label: String) {
        let frame = VoltraFrameBuilder.build(
            cmd: VoltraControlFrames.CMD_PARAM_WRITE,
            payload: payload,
            seq: Self.nextAdHocSeq()
        )
        writeControlFrame(frame)
        addLog("\u{2192} \(label)")
    }

    // Static seq counter so all instances share one monotonically-increasing
    // ad-hoc sequence. The device doesn't care about per-source uniqueness
    // and we never have more than one VoltraBLEManager alive at a time in
    // the single-device flow anyway.
    private static var _adHocSeq: UInt16 = 0xC000
    private static let _adHocSeqLock = NSLock()
    static func nextAdHocSeq() -> UInt16 {
        _adHocSeqLock.lock()
        defer { _adHocSeqLock.unlock() }
        _adHocSeq = (_adHocSeq &+ 1) & 0xFFFF
        return _adHocSeq
    }
}
