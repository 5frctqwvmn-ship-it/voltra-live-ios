// FrameAssembler.swift
// Swift port of the JS FrameAssembler in voltra-protocol.js
// Handles BLE fragmentation: accumulates partial frames until a complete one arrives.
//
// Frame format:
//   byte[0]  = magic 0x55
//   byte[1]  = declared length
//   byte[2]  = packet type
//   total length = declared, UNLESS type is 0x09 or 0x05 → then total = declared + 0x100

import Foundation

final class FrameAssembler {
    private var pending = Data()

    func clear() {
        pending = Data()
    }

    /// Feed a new BLE notification fragment. Returns zero or more complete frames.
    func accept(_ fragment: Data) -> [Data] {
        guard !fragment.isEmpty else { return [] }

        var buffer = pending + fragment
        pending = Data()

        var frames = [Data]()

        while !buffer.isEmpty {
            // Frame must start with magic byte
            guard buffer[0] == VOLTRA_MAGIC else {
                // Non-magic prefix — emit whatever's left and bail (mirrors JS behavior)
                frames.append(buffer)
                return frames
            }

            // Need at least 3 bytes to read declared length + type
            guard buffer.count >= HEADER_BYTES_FOR_LENGTH else {
                pending = buffer
                return frames
            }

            let declared = Int(buffer[1])
            let type     = buffer[2]
            let expected = (type == EXTENDED_RESPONSE_PACKET_TYPE || type == EXTENDED_APP_WRITE_PACKET_TYPE)
                ? EXTENDED_RESPONSE_LENGTH_OFFSET + declared
                : declared

            // Sanity check
            guard expected >= MIN_FRAME_LENGTH else {
                frames.append(buffer)
                return frames
            }

            // Wait for more data if incomplete
            guard buffer.count >= expected else {
                pending = buffer
                return frames
            }

            // Slice off one complete frame
            frames.append(buffer.prefix(expected))
            buffer = buffer.dropFirst(expected)
        }

        return frames
    }
}
