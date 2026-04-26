// SetSuggestionEngine.swift
// Generates the ±5 lb suggestion for the next set the user is about to do.
//
// Two principles:
//   1. The "anchor" is what the engine recommends the user load. It comes from
//      the user's actual current-session sets where possible, projected by the
//      delta the user took at the same slot last session. For set 1, the anchor
//      is just "what did you start with last time".
//   2. The toggle is always Anchor-5 / Anchor / Anchor+5. No reps prompt.
//
// This file has zero SwiftUI imports — it's pure Foundation so it's trivially
// testable. The view passes in:
//   - The set index the user is about to log (1-based)
//   - All sets the user has already logged in the active instance, in order
//   - The previous-session series for this exercise (from HistoryAnalytics)

import Foundation

struct SetSuggestion: Equatable {
    enum Source: Equatable {
        /// First set, anchored to the previous session's first set.
        case previousFirstSet(lb: Double)
        /// Subsequent set, anchored to (current set N-1) + (delta from previous
        /// session's same slot).
        case projectedDelta(lastCurrentLb: Double, deltaFromHistory: Double)
        /// Subsequent set with no usable history delta — just repeat current.
        case repeatCurrent(lastCurrentLb: Double)
        /// No history at all and no current sets — free entry.
        case freeEntry
    }

    let source: Source
    let anchorLb: Double?
    /// e.g. -5, 0, +5
    let offsets: [Double]

    var isFreeEntry: Bool {
        if case .freeEntry = source { return true }
        return false
    }

    /// The three suggested loads, anchor-aware. Empty for freeEntry.
    var options: [Double] {
        guard let a = anchorLb else { return [] }
        return offsets.map { a + $0 }.filter { $0 >= 0 }
    }

    /// Index in `options` whose offset is 0. May be nil if 0 is not present.
    var sameIndex: Int? {
        offsets.firstIndex(of: 0)
    }

    /// Human caption explaining the anchor — "Last time you started here",
    /// "+5 from last set", etc.
    var caption: String {
        switch source {
        case .previousFirstSet(let lb):
            return "Last session you started at \(formatLb(lb)) lb."
        case .projectedDelta(_, let delta):
            if delta == 0 { return "Same weight as the previous set last time." }
            let sign = delta > 0 ? "+" : ""
            return "Last session you went \(sign)\(formatLb(delta)) lb into this set."
        case .repeatCurrent(let lb):
            return "Repeat \(formatLb(lb)) lb (no history for this set)."
        case .freeEntry:
            return "First time through — enter your starting weight."
        }
    }
}

enum SetSuggestionEngine {

    /// Build a suggestion for the next set. `setIndex` is 1-based.
    static func suggestion(
        forSetIndex setIndex: Int,
        currentInstanceSets: [LoggedSet],
        previousSeries: [LoggedSet],
        defaultOffsets: [Double] = [-5, 0, 5]
    ) -> SetSuggestion {
        // SET 1 — anchor to previous session's set 1.
        if setIndex <= 1 {
            if let prev = HistoryAnalytics.previousWeight(atSetIndex: 1, in: previousSeries) {
                return SetSuggestion(
                    source: .previousFirstSet(lb: prev),
                    anchorLb: prev,
                    offsets: defaultOffsets
                )
            }
            return SetSuggestion(source: .freeEntry, anchorLb: nil, offsets: [])
        }

        // SET >=2 — anchor to (last current weight) + (history delta same-slot).
        // 1) Most recent weight the user actually loaded in this session.
        let lastCurrent = currentInstanceSets
            .sorted { $0.orderIndex < $1.orderIndex }
            .last?.weightLb ?? 0

        guard lastCurrent > 0 else {
            // User hasn't logged a real weight yet (maybe a 0-lb warmup?).
            // Fall back to previous session's same slot.
            if let prev = HistoryAnalytics.previousWeight(atSetIndex: setIndex, in: previousSeries) {
                return SetSuggestion(
                    source: .previousFirstSet(lb: prev),
                    anchorLb: prev,
                    offsets: defaultOffsets
                )
            }
            return SetSuggestion(source: .freeEntry, anchorLb: nil, offsets: [])
        }

        if let delta = HistoryAnalytics.previousDelta(toSetIndex: setIndex, in: previousSeries) {
            // Snap delta to the nearest 5 so the toggle stays clean.
            let snapped = snapToFive(delta)
            let anchor = max(0, lastCurrent + snapped)
            return SetSuggestion(
                source: .projectedDelta(lastCurrentLb: lastCurrent, deltaFromHistory: snapped),
                anchorLb: anchor,
                offsets: defaultOffsets
            )
        }

        // No history delta — just repeat current.
        return SetSuggestion(
            source: .repeatCurrent(lastCurrentLb: lastCurrent),
            anchorLb: lastCurrent,
            offsets: defaultOffsets
        )
    }

    private static func snapToFive(_ d: Double) -> Double {
        (d / 5.0).rounded() * 5.0
    }
}

// MARK: - Local formatter (avoid importing the View's helper)

private func formatLb(_ d: Double) -> String {
    if d == d.rounded() { return String(Int(d)) }
    return String(format: "%.1f", d)
}
