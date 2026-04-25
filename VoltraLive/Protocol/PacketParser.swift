// PacketParser.swift
// Swift port of parsePacket() from voltra-protocol.js
//
// Header layout (mirrors JS exactly):
//   [0]      magic 0x55
//   [1]      declared length
//   [2]      packet type
//   [3]      header checksum
//   [4]      sender id
//   [5]      receiver id
//   [6]      sequence
//   [7]      channel
//   [8..9]   protocol u16-le
//   [10]     commandId
//   [11..N-3] payload
//   [N-2..N-1] crc16 u16-le

import Foundation

struct VoltraPacket {
    let declaredLength: Int
    let totalLength: Int
    let packetType: UInt8
    let headerChecksum: UInt8
    let senderId: UInt8
    let receiverId: UInt8
    let sequence: UInt8
    let channel: UInt8
    let protocolId: UInt16      // u16-le at bytes 8-9
    let commandId: UInt8
    let payload: [UInt8]
    let crc16: UInt16
    let lengthMatches: Bool
}

func parsePacket(_ data: Data) -> VoltraPacket? {
    guard data.count >= MIN_FRAME_LENGTH else { return nil }
    let bytes = [UInt8](data)
    guard bytes[0] == VOLTRA_MAGIC else { return nil }

    let declared = Int(bytes[1])
    let type     = bytes[2]
    let totalLength = (type == EXTENDED_RESPONSE_PACKET_TYPE || type == EXTENDED_APP_WRITE_PACKET_TYPE)
        ? EXTENDED_RESPONSE_LENGTH_OFFSET + declared
        : declared

    let protocolId = UInt16(bytes[8]) | (UInt16(bytes[9]) << 8)
    let crc16 = UInt16(bytes[bytes.count - 2]) | (UInt16(bytes[bytes.count - 1]) << 8)
    let payload = Array(bytes[11..<max(11, bytes.count - 2)])

    return VoltraPacket(
        declaredLength:  declared,
        totalLength:     totalLength,
        packetType:      type,
        headerChecksum:  bytes[3],
        senderId:        bytes[4],
        receiverId:      bytes[5],
        sequence:        bytes[6],
        channel:         bytes[7],
        protocolId:      protocolId,
        commandId:       bytes[10],
        payload:         payload,
        crc16:           crc16,
        lengthMatches:   bytes.count == totalLength
    )
}
