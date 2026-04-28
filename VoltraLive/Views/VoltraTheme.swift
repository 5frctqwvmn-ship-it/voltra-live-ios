// VoltraTheme.swift
// Color palette ported from styles.css. Dark theme only.
// Readable from 8 feet away on a rack-mounted iPad.

import SwiftUI

enum VoltraColor {
    // Backgrounds
    static let bg       = Color(hex: "#0a0e0c")
    static let bgElev   = Color(hex: "#11181a")
    static let bgElev2  = Color(hex: "#1a2426")
    static let border   = Color(hex: "#1f2c2e")

    // Text
    static let text      = Color(hex: "#e8f4f1")
    static let textDim   = Color(hex: "#8aa39e")
    static let textFaint = Color(hex: "#4a5f5b")

    // Accent / phase colors
    static let accent     = Color(hex: "#00d4aa")  // pull
    static let accentDim  = Color(hex: "#007a62")
    static let pull       = Color(hex: "#00d4aa")
    static let returnPhase = Color(hex: "#ffb84d")
    static let transition = Color(hex: "#6c8de0")
    static let idle       = Color(hex: "#4a5f5b")
    static let warn       = Color(hex: "#ff7a4d")
    static let danger     = Color(hex: "#ff4d6d")

    // b53: phase washes for the V2 phase tile background tint, and
    // freshness dots for HR/KCAL secondary tiles. Matches
    // design-system/colors_and_type.css exactly.
    static let pullWash    = Color(red: 0,        green: 0.831, blue: 0.667).opacity(0.12)  // rgba(0,212,170,0.12)
    static let returnWash  = Color(red: 1,        green: 0.722, blue: 0.302).opacity(0.12)  // rgba(255,184,77,0.12)
    static let fresh       = Color(red: 0.20,     green: 0.85,  blue: 0.40)                  // rgb(51,217,102)
    static let freshStale  = Color(red: 0.349,    green: 0.349, blue: 0.349)                 // rgb(89,89,89)

    static func phase(_ p: VoltraPhase) -> Color {
        switch p {
        case .pull:       return Self.pull
        case .return:     return Self.returnPhase
        case .transition: return Self.transition
        case .idle:       return Self.idle
        }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        switch h.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

// MARK: - Font helpers

enum VoltraFont {
    /// Big mono number — readable from 8 feet
    static func bigNumber(size: CGFloat = 72) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
    static func label() -> Font {
        .system(size: 11, weight: .bold).uppercaseSmallCaps()
    }
    static func unit() -> Font {
        .system(size: 18, weight: .medium, design: .monospaced)
    }
    static func tileLabel() -> Font {
        .system(size: 11, weight: .bold)
    }
}
