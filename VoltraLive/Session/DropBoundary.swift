// DropBoundary.swift
// v0.4.5 — Shared types for the SessionStore ↔ LoggingStore drop-set
// boundary handshake. Lives in Session/ so SessionStore can reference the
// types without depending on the logging layer.

import Foundation

/// Snapshot of a single drop's telemetry, handed from SessionStore to the
/// LoggingStore boundary callback at the moment the idle-grace heuristic
/// would normally finalize a set.
struct DropBoundarySnapshot {
    /// 1-based drop index within the chain (1 == first drop, before any
    /// auto-advance).
    let order: Int
    /// Reps performed *during this drop only*, excluding reps from earlier
    /// drops in the chain.
    let reps: Int
    /// Peak force in lb observed during this drop's window.
    let peakLb: Double
    let startedAt: Date
    let endedAt: Date
}

/// Decision returned by the drop-boundary callback. Tells SessionStore
/// whether to keep the chain alive (no finalize, no rest timer) or to fall
/// through to normal finalize.
enum DropDecision {
    /// More drops in the planned chain — keep `currentSet` open, reset
    /// per-drop counters, no rest timer.
    case advance
    /// Last drop. Fall through to normal finalize: archive the set and
    /// start the rest timer.
    case finalize
}
