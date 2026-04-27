// Drop.swift
// v0.4.5 — Drop-set sub-entry model.
//
// A `Drop` is one mini-set inside a drop-set chain. The PARENT LoggedSet's
// existing weight/reps/peak/avg fields represent DROP #1 (so legacy rows
// render as a 1-element chain with no migration). Subsequent drops live as
// `Drop` rows linked back to the parent via `loggedSet`.
//
// CloudKit constraint: every property optional or has a default; relationships
// optional; no @Attribute(.unique). Same conventions as the rest of the
// LoggingModels schema.
//
// PR detection rule (v0.4.5): only the FIRST drop counts toward working-set
// PRs. Subsequent drops record force telemetry but are excluded from PR
// leaderboards. The `order` field (1-based) is what drives that rule —
// PR queries can filter `Drop.order == 1` (or use the parent LoggedSet
// directly, since drop #1 is mirrored on the parent).

import Foundation
import SwiftData

@Model
final class Drop {
    var id: UUID = UUID()
    /// 1-based index within the chain. Drop #1 is mirrored on the parent
    /// LoggedSet's weight/reps/peak/avg fields — kept here too for
    /// query/render symmetry.
    var order: Int = 1

    /// Voltra base weight in lb at this drop.
    var weightLb: Double = 0
    /// Plates already on the machine for this drop. Usually inherited from
    /// the parent set since Voltra weight changes digitally (no plates to
    /// strip), but stored per-drop in case the user manually adjusts.
    var addedPlatesLb: Double? = nil
    /// Eccentric overload at this drop (rare, but supported).
    var eccentricLb: Double? = nil

    var reps: Int = 0
    /// Boundaries inside the chain — reps from `startedAt` to `endedAt`
    /// against this drop's resistance.
    var startedAt: Date? = nil
    var endedAt: Date? = nil

    /// Per-drop peak/avg force from telemetry sliced to this drop's window.
    var peakForceLb: Double = 0
    var avgForceLb: Double? = nil

    /// Parent LoggedSet — optional for CloudKit compatibility.
    var loggedSet: LoggedSet? = nil

    init(
        id: UUID = UUID(),
        order: Int = 1,
        weightLb: Double = 0,
        addedPlatesLb: Double? = nil,
        eccentricLb: Double? = nil,
        reps: Int = 0,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        peakForceLb: Double = 0,
        avgForceLb: Double? = nil,
        loggedSet: LoggedSet? = nil
    ) {
        self.id = id
        self.order = order
        self.weightLb = weightLb
        self.addedPlatesLb = addedPlatesLb
        self.eccentricLb = eccentricLb
        self.reps = reps
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.peakForceLb = peakForceLb
        self.avgForceLb = avgForceLb
        self.loggedSet = loggedSet
    }

    /// Total effective weight at this drop = Voltra base + plates already on rig.
    var totalLb: Double { weightLb + (addedPlatesLb ?? 0) }
}
