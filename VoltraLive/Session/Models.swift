// Models.swift
// SwiftData @Model classes for persistent session storage.
// In-memory structs for current live session tracking.

import Foundation
import SwiftData

// MARK: - SwiftData persistent models

@Model
final class PastSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    @Relationship(deleteRule: .cascade) var sets: [PastSet]

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, sets: [PastSet] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    var peakForceLb: Double { sets.map(\.peakLb).max() ?? 0 }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: startedAt)
    }
}

@Model
final class PastSet {
    @Attribute(.unique) var id: UUID
    var reps: Int
    var peakLb: Double
    var startedAt: Date
    var endedAt: Date

    init(id: UUID = UUID(), reps: Int, peakLb: Double, startedAt: Date, endedAt: Date) {
        self.id = id
        self.reps = reps
        self.peakLb = peakLb
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

// MARK: - In-memory current-session structs

struct ForceSample {
    let timestamp: Date
    let forceLb: Double
    let phase: VoltraPhase
}

struct CurrentSet {
    var startedAt: Date
    var endedAt: Date?
    var reps: Int = 0
    var peakLb: Double = 0
    /// Rolling buffer sized for a long set: ~3 min at ~20Hz = 3600 samples.
    /// v0.4.5: bumped from 600 (30s) so the chart can show the entire set —
    /// a hard set with long eccentrics + rest-pauses can easily exceed 30s.
    var samples: [ForceSample] = []

    static let maxSamples = 3600

    mutating func addSample(_ sample: ForceSample) {
        samples.append(sample)
        if samples.count > CurrentSet.maxSamples {
            samples.removeFirst()
        }
        if sample.forceLb > peakLb { peakLb = sample.forceLb }
    }
}

struct CompletedSet {
    let reps: Int
    let peakLb: Double
    let startedAt: Date
    let endedAt: Date
}
