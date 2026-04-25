// TelemetryExtractor.swift
// Swift port of extractTelemetry() from voltra-protocol.js
// Decodes a VoltraPacket into a Telemetry struct with optional fields.

import Foundation

struct Telemetry {
    var batteryPercent: Int?
    var serial: String?

    // Rep / phase
    var setCount: Int?
    var repCount: Int?
    var phase: VoltraPhase?
    var phaseRaw: UInt8?

    // Live force
    var forceLb: Double?
    var tick: UInt32?

    // Per-rep summary
    var lastRepTimeToPeakMs: Int?

    // Final summary
    var peakForceLb: Double?
    var peakPowerWatts: Int?
    var timeToPeakMs: Int?

    var hasAnyField: Bool {
        batteryPercent != nil || serial != nil || setCount != nil ||
        repCount != nil || phase != nil || forceLb != nil || tick != nil ||
        lastRepTimeToPeakMs != nil || peakForceLb != nil ||
        peakPowerWatts != nil || timeToPeakMs != nil
    }
}

/// Extract telemetry from a parsed packet. Returns nil if nothing useful decoded.
func extractTelemetry(_ packet: VoltraPacket) -> Telemetry? {
    var out = Telemetry()
    let p = packet.payload

    // --- Battery from async-state push (cmd 0x10) ---
    if packet.commandId == CMD_ASYNC_STATE && p.count >= 5 {
        // Format: [count=0x01] [paramId LE x2] [value] ...
        // Simplest case: 1 entry, BMS_RSOC, 1-byte uint8 value
        if p[0] == 0x01 && p.count == 5 {
            let paramId = UInt16(p[1]) | (UInt16(p[2]) << 8)
            let val = Int(p[3])
            if (paramId == PARAM_BMS_RSOC_A || paramId == PARAM_BMS_RSOC_B) && val >= 0 && val <= 100 {
                out.batteryPercent = val
            }
        }
    }

    // --- Serial info (cmd 0x19) ---
    if packet.commandId == CMD_SERIAL_INFO {
        let ascii = asciiOf(p)
        if let ascii = ascii,
           let range = ascii.range(of: #"M?B[0-9A-Z]{10,}"#, options: .regularExpression) {
            out.serial = String(ascii[range])
        }
    }

    // Only CMD_TELEMETRY (0xAA) carries rep/force data
    guard packet.commandId == CMD_TELEMETRY else {
        return out.hasAnyField ? out : nil
    }

    // --- Rep telemetry — short form ---
    if p.count >= TELEMETRY_REP_MIN_BYTES &&
       p[0] == TELEMETRY_REP_TYPE &&
       p[1] == TELEMETRY_REP_LENGTH_MARKER {
        let setCount  = Int(p[TELEMETRY_SET_COUNT_OFFSET])
        let repCountU = (UInt16(p[TELEMETRY_REP_COUNT_OFFSET]) << 8) | UInt16(p[TELEMETRY_REP_COUNT_OFFSET + 1])
        let repCount  = Int(repCountU)
        let phaseRaw  = p[TELEMETRY_REP_PHASE_OFFSET]
        if setCount <= MAX_REASONABLE_SET_COUNT && repCount <= MAX_REASONABLE_REP_COUNT {
            out.setCount  = setCount
            out.repCount  = repCount
            out.phase     = VoltraPhase(raw: phaseRaw)
            out.phaseRaw  = phaseRaw
        }
    }

    // --- Power workout live (force + tick) — same first 2 bytes, longer payload ---
    if p.count >= POWER_WORKOUT_LIVE_MIN_BYTES &&
       p[0] == POWER_WORKOUT_LIVE_TYPE &&
       p[1] == POWER_WORKOUT_LIVE_LENGTH_MARKER {
        let forceTenths = Int(UInt16(p[POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET]) |
                             (UInt16(p[POWER_WORKOUT_LIVE_FORCE_TENTHS_LB_OFFSET + 1]) << 8))
        if forceTenths >= 0 && forceTenths <= MAX_REASONABLE_POWER_WORKOUT_FORCE_TENTHS_LB {
            out.forceLb = Double(forceTenths) / POWER_WORKOUT_FORCE_TENTHS_PER_LB
            out.tick    = UInt32(p[POWER_WORKOUT_LIVE_TICK_OFFSET])
                        | (UInt32(p[POWER_WORKOUT_LIVE_TICK_OFFSET + 1]) << 8)
                        | (UInt32(p[POWER_WORKOUT_LIVE_TICK_OFFSET + 2]) << 16)
                        | (UInt32(p[POWER_WORKOUT_LIVE_TICK_OFFSET + 3]) << 24)
        }
    }

    // --- Per-rep summary ---
    if p.count >= POWER_WORKOUT_REP_SUMMARY_MIN_BYTES &&
       p[0] == POWER_WORKOUT_REP_SUMMARY_TYPE &&
       p[1] == POWER_WORKOUT_REP_SUMMARY_LENGTH_MARKER {
        let ttp = Int(UInt16(p[22]) | (UInt16(p[23]) << 8))
        if ttp >= 1 && ttp <= MAX_REASONABLE_POWER_WORKOUT_TIME_TO_PEAK_CENTISECONDS {
            out.lastRepTimeToPeakMs = ttp * 10
        }
    }

    // --- Final summary (peak force + peak power) ---
    if p.count >= POWER_WORKOUT_SUMMARY_MIN_BYTES &&
       p[0] == POWER_WORKOUT_SUMMARY_TYPE &&
       p[1] == POWER_WORKOUT_SUMMARY_LENGTH_MARKER {
        let peakF = Int(UInt16(p[POWER_WORKOUT_SUMMARY_PEAK_FORCE_TENTHS_LB_OFFSET]) |
                       (UInt16(p[POWER_WORKOUT_SUMMARY_PEAK_FORCE_TENTHS_LB_OFFSET + 1]) << 8))
        let peakP = Int(UInt16(p[POWER_WORKOUT_SUMMARY_PEAK_POWER_WATTS_OFFSET]) |
                       (UInt16(p[POWER_WORKOUT_SUMMARY_PEAK_POWER_WATTS_OFFSET + 1]) << 8))
        let ttp   = Int(UInt16(p[POWER_WORKOUT_SUMMARY_TIME_TO_PEAK_CENTISECONDS_OFFSET]) |
                       (UInt16(p[POWER_WORKOUT_SUMMARY_TIME_TO_PEAK_CENTISECONDS_OFFSET + 1]) << 8))
        if peakF >= 0 && peakF <= MAX_REASONABLE_POWER_WORKOUT_FORCE_TENTHS_LB {
            out.peakForceLb = Double(peakF) / POWER_WORKOUT_FORCE_TENTHS_PER_LB
        }
        if peakP >= 0 && peakP <= MAX_REASONABLE_POWER_WORKOUT_WATTS {
            out.peakPowerWatts = peakP
        }
        if ttp >= 1 && ttp <= MAX_REASONABLE_POWER_WORKOUT_TIME_TO_PEAK_CENTISECONDS {
            out.timeToPeakMs = ttp * 10
        }
    }

    return out.hasAnyField ? out : nil
}

// MARK: - ASCII helper (mirrors JS asciiOf)

private func asciiOf(_ bytes: [UInt8]) -> String? {
    var result = ""
    var any = false
    for b in bytes {
        if b >= 32 && b <= 126 {
            result.append(Character(UnicodeScalar(b)))
            any = true
        } else {
            result.append(".")
        }
    }
    return any ? result : nil
}
