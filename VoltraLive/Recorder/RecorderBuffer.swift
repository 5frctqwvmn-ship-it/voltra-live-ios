// RecorderBuffer.swift
// B74-F11 Session Recorder — thread-safe FIFO ring buffer.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Persistence" — 10,000-event
// FIFO ring buffer. Emit sites are arbitrary threads (BLE delegate, HK
// callback, MainActor); the buffer must accept concurrent writes without
// data races. Implemented as an `actor` so the runtime serializes access
// for us with no manual locking.
//
// Storage uses a fixed-size array with head/size cursors so wrap is O(1)
// per append (vs `removeFirst()` on a normal Array which is O(N)).

import Foundation

actor RecorderBuffer {
    /// Maximum events retained. Older events are dropped FIFO when full.
    let capacity: Int

    private var storage: [RecorderEvent?]
    private var head: Int = 0
    private var size: Int = 0

    init(capacity: Int = 10_000) {
        precondition(capacity > 0, "RecorderBuffer capacity must be positive")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    var count: Int { size }

    /// Append one event. When the buffer is at capacity the oldest event
    /// is dropped to make room.
    func append(_ event: RecorderEvent) {
        let slot = (head + size) % capacity
        storage[slot] = event
        if size < capacity {
            size += 1
        } else {
            head = (head + 1) % capacity
        }
    }

    /// Snapshot of all retained events in chronological order. Returns a
    /// fresh array; safe to hand to non-actor consumers.
    func snapshot() -> [RecorderEvent] {
        var result: [RecorderEvent] = []
        result.reserveCapacity(size)
        for i in 0..<size {
            if let e = storage[(head + i) % capacity] {
                result.append(e)
            }
        }
        return result
    }

    /// Drop all retained events. Used at session start so the buffer
    /// represents only the current session.
    func clear() {
        for i in 0..<capacity { storage[i] = nil }
        head = 0
        size = 0
    }
}
