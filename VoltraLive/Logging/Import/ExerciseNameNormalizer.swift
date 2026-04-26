// ExerciseNameNormalizer.swift
// v0.3.9 — collapse the 30+ name variants in the seed history into a small
// number of canonical "movement + equipment family" buckets so the picker
// shows one row per real exercise instead of one row per session-naming
// variant.
//
// Strategy ("Moderate" per user):
//   - Strip leading "Voltra " / "Bulletproof " brand words.
//   - Pluralize → singular form for grouping ("Squats" → "Squat").
//   - Normalize whitespace + casing.
//   - Look at parenthetical equipment hints to decide an EQUIPMENT FAMILY:
//       smith / belt / free-bar / lever-arm / pulley / harness / cable / none
//   - Pick a canonical display name from {base movement, equipment family}.
//
// This file is intentionally NOT in the sacred-file list. It is brand-new code
// and modifies no protocol code.

import Foundation

enum ExerciseNameNormalizer {

    /// Public entry point. Given a raw header like
    /// "Belt Squats (Voltra Harness)" or "Voltra Belt Squat" or
    /// "Squats (Voltra Smith, Solid Bar)" returns a canonical name and
    /// equipment family that should be used as the dedup key.
    ///
    /// - Returns:
    ///   - canonicalName: human-readable display name, e.g. "Belt Squats" /
    ///                    "Smith Machine Squats" / "Squats (Free Bar)"
    ///   - equipmentFamily: short tag used as the secondary dedup key, e.g.
    ///                    "belt" / "smith" / "free-bar" / "lever-arm" / ""
    static func canonical(name rawName: String, equipment rawEquipment: String) -> (canonicalName: String, equipmentFamily: String) {
        // Combine name + equipment hint into one searchable string for
        // family detection. The "equipment" we receive from the parser is
        // already what was inside the parens; the name part has parens
        // stripped. So we re-join for inspection.
        let combined = "\(rawName) \(rawEquipment)".lowercased()

        let base = baseMovement(of: rawName)
        let family = equipmentFamily(in: combined, base: base)

        let canonical = canonicalDisplayName(base: base, family: family, raw: rawName)
        return (canonical, family)
    }

    // MARK: - Movement extraction

    /// Strip brand words and pluralization to find the bare movement noun.
    /// "Voltra Belt Squats" → "belt squat"
    /// "Smith Machine Squats" → "smith machine squat"
    /// "Pull-Ups" → "pull-up"
    private static func baseMovement(of raw: String) -> String {
        var s = raw.lowercased()

        // Strip leading brand words.
        let brands = ["voltra ", "bulletproof "]
        var changed = true
        while changed {
            changed = false
            for b in brands {
                if s.hasPrefix(b) {
                    s = String(s.dropFirst(b.count))
                    changed = true
                }
            }
        }

        // Drop any parenthetical and trim.
        if let openParen = s.firstIndex(of: "(") {
            s = String(s[..<openParen])
        }
        s = s.trimmingCharacters(in: .whitespaces)

        // Naive depluralize: strip a trailing "s" from the LAST word ONLY
        // if the word is longer than 3 chars. "Squats" → "Squat",
        // "Pulldowns" → "Pulldown", "Press" stays "Press".
        var words = s.split(separator: " ").map(String.init)
        if let last = words.last,
           last.hasSuffix("s"),
           !last.hasSuffix("ss"),
           last.count > 3 {
            words[words.count - 1] = String(last.dropLast())
        }
        return words.joined(separator: " ")
    }

    // MARK: - Equipment family detection

    /// Looks at the FULL raw text (name + equipment hint, lowercased) to
    /// decide which equipment family this exercise belongs to.
    private static func equipmentFamily(in text: String, base: String) -> String {
        // Order matters: more specific tests first.
        if text.contains("belt") || text.contains("harness") {
            return "belt"
        }
        if text.contains("smith") {
            return "smith"
        }
        if text.contains("lever arm") || text.contains("lever-arm") || text.contains("isoarm") {
            return "lever-arm"
        }
        if text.contains("pulley") {
            return "pulley"
        }
        if text.contains("free bar") || text.contains("free-bar") || text.contains("straight bar") || text.contains("straight-bar") || text.contains("closed-grip bar") || text.contains("long bar") {
            return "free-bar"
        }
        if text.contains("cable") {
            return "cable"
        }
        if text.contains("dual voltra") {
            return "free-bar"  // dual Voltras + long bar
        }
        // For movements where equipment family is intrinsic to the name
        // (e.g. "Pull-Up", "Dip", "GHD Sit-Up") we leave family blank.
        return ""
    }

    // MARK: - Canonical display name

    /// Build a clean human-readable display name for the picker.
    private static func canonicalDisplayName(base: String, family: String, raw: String) -> String {
        let titledBase = titleCase(base)

        // Handle squat-family explicitly — it has the most variants.
        if base.hasSuffix("squat") {
            switch family {
            case "belt":
                return "Belt Squats"
            case "smith":
                return "Smith Machine Squats"
            case "lever-arm":
                return "Squats (Lever Arms)"
            case "pulley":
                return "Squats (Pulley)"
            case "free-bar":
                return "Squats (Free Bar)"
            case "cable":
                return "Squats (Cable)"
            default:
                // Generic "Squat" / "Squats" with no equipment hint.
                return "Squats"
            }
        }

        // Deadlift family.
        if base.hasSuffix("deadlift") {
            switch family {
            case "smith":
                return "Smith Machine Deadlifts"
            case "free-bar":
                return "Deadlifts (Free Bar)"
            default:
                return "Deadlifts"
            }
        }

        // Press family — bench / incline / decline / overhead — these are
        // already pretty distinct in the seed so we mostly just clean them up.
        if base.contains("press") || base.contains("bench") {
            // Family suffix only if it adds info.
            if family == "smith" { return "\(titledBase) (Smith)" }
            if family == "cable" { return "\(titledBase) (Cable)" }
            if family == "free-bar" { return "\(titledBase) (Free Bar)" }
            return titledBase
        }

        // Row family.
        if base.contains("row") {
            if family == "cable" { return "\(titledBase) (Cable)" }
            if family == "free-bar" { return "\(titledBase) (Free Bar)" }
            return titledBase
        }

        // Default fallback: Title-Cased base, optional family suffix when
        // the family adds disambiguation beyond an obviously bodyweight or
        // single-equipment movement.
        if family.isEmpty {
            return titledBase.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : titledBase
        }
        return "\(titledBase) (\(familyDisplay(family)))"
    }

    private static func familyDisplay(_ family: String) -> String {
        switch family {
        case "smith": return "Smith"
        case "belt": return "Belt"
        case "free-bar": return "Free Bar"
        case "lever-arm": return "Lever Arms"
        case "pulley": return "Pulley"
        case "cable": return "Cable"
        default: return family.capitalized
        }
    }

    /// Title-cases each space-separated word, preserving hyphens.
    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ")
            .map { word -> String in
                word.split(separator: "-")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: "-")
            }
            .joined(separator: " ")
    }
}
