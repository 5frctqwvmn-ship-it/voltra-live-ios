// VoltraControlFrames+LoadUnload.swift
//
// v0.4.7 build 29: LOAD / UNLOAD control payloads.
//
// These are NEW commands not previously implemented in iOS. Pulled from the
// Beyond-Power-Voltra-Android reference repo (see AndroidVoltraClient.load() /
// unload() and VoltraControlFrames.loadPayload() / unloadPayload()).
//
// Wire format:
//   Both are CMD_PARAM_WRITE writes to PARAM_BP_SET_FITNESS_MODE (0x3E89).
//
//     LOAD   = uint16-LE 0x0005  (FITNESS_MODE_STRENGTH_LOADED)
//     UNLOAD = uint16-LE 0x0004  (FITNESS_MODE_STRENGTH_READY)
//
// Semantics on the device:
//   LOAD   — engages the cable load. Cable can move; weight is felt.
//   UNLOAD — releases the cable. Cable goes slack; safe to step off the rack.
//
// Conservatism: we only add the two byte-payloads here. Higher-level callers
// frame them via VoltraFrameBuilder.build(cmd: .CMD_PARAM_WRITE, payload:, seq:),
// the same way every other control payload in this app is framed. We do not
// touch the four sacred protocol files.
//
// Caller flow (typical):
//   let payload = VoltraControlFrames.loadPayload()
//   let frame   = VoltraFrameBuilder.build(cmd: VoltraControlFrames.CMD_PARAM_WRITE,
//                                          payload: payload, seq: nextSeq())
//   bleManager.writeControlFrame(frame)

import Foundation

extension VoltraControlFrames {

    // MARK: New param ID + values (from Android reference)

    /// PARAM_BP_SET_FITNESS_MODE — 16-bit param ID. Different from the
    /// PARAM_FITNESS_WORKOUT_STATE (0x4FB0) we already use; this one toggles
    /// engaged/ready inside an already-active fitness mode.
    static let PARAM_BP_SET_FITNESS_MODE: UInt16 = 0x3E89

    /// FITNESS_MODE_STRENGTH_READY — cable released, no load. UNLOAD.
    static let FITNESS_MODE_STRENGTH_READY: Int = 0x0004
    /// FITNESS_MODE_STRENGTH_LOADED — cable engaged, load applied. LOAD.
    static let FITNESS_MODE_STRENGTH_LOADED: Int = 0x0005

    // MARK: Payload builders

    /// Build the CMD_PARAM_WRITE payload for LOAD.
    /// Engages the cable load on the device. Caller is responsible for framing
    /// (CRC8 / CRC16 / sequence) via VoltraFrameBuilder.
    static func loadPayload() -> Data {
        return paramWritePayload(PARAM_BP_SET_FITNESS_MODE,
                                 uint16Le(FITNESS_MODE_STRENGTH_LOADED))
    }

    /// Build the CMD_PARAM_WRITE payload for UNLOAD.
    /// Releases the cable load. Safe to call without firmware ack —
    /// fire-and-forget like every other control write in this app.
    static func unloadPayload() -> Data {
        return paramWritePayload(PARAM_BP_SET_FITNESS_MODE,
                                 uint16Le(FITNESS_MODE_STRENGTH_READY))
    }
}
