// PageRegistry.swift
// b70 V4.4 / V4-D18 — stable numeric IDs for every screen that calls
// `.pageBadge("ScreenName")`. Renders as the "NN" prefix in the page-badge
// overlay (`PageBadgeOverlay.swift`).
//
// The user ask (continuation of the b66 page-badge work):
// "Pair each screen with a stable numeric ID I can reference even faster
// than typing a type name."
//
// Numbering rule
// --------------
// Build the table by running:
//
//   rg "\\.pageBadge\\(" VoltraLive --type swift
//
// taking the unique set of arguments, and assigning IDs in **alphabetical
// order** starting at 01. Future screens added to the table get the NEXT
// available ID — no renumbering of existing entries. This keeps the user's
// muscle memory stable across builds: once a screen has a number, that's
// its number forever.
//
// Lookups
// -------
// `PageRegistry.id(for:)` returns the 2-digit zero-padded string "NN" for a
// known screen, or `"--"` for an unknown one. Unknown screens still render
// a badge ("-- · ScreenName") so that's the visible signal to add the new
// screen to this table.
//
// CRITICAL: do not renumber existing entries. If a screen is renamed in
// Swift, update the existing entry in place — keep the same numeric ID.
// If the rename feels like it deserves a different number, leave the old
// key with its old ID and add the new key with a new ID, then delete the
// old key only after one full ship cycle of overlap so the user has time
// to learn the new number.

import Foundation

enum PageRegistry {

    /// Static map from `.pageBadge(...)` argument to numeric ID.
    /// Keys are the verbatim Swift type-name strings each screen passes in.
    /// Values are stable 2-digit IDs assigned in alphabetical order at
    /// the b70 cycle baseline. New screens get the next available ID.
    static let table: [String: Int] = [
        "ConnectView":          1,
        "ContentView":          2,
        "DashboardView":        3,
        "DebugView":            4,
        "ExerciseDetailView":   5,
        "ExercisePickerView":   6,
        "ExerciseStartView":    7,
        "ExportSheet":          8,
        "LiveCaptureContainer": 9,
        "LiveCaptureView":     10,
        "LiveCaptureViewV2":   11,
        "LoggingHomeView":     12,
        "SetLogView":          13,
    ]

    /// Returns the 2-digit zero-padded ID string for a known screen, or
    /// `"--"` for an unknown one. Format is fixed-width so the page badge
    /// renders with a stable visual rhythm even when the registry doesn't
    /// recognize a screen yet.
    static func id(for name: String) -> String {
        guard let n = table[name] else { return "--" }
        return String(format: "%02d", n)
    }
}
