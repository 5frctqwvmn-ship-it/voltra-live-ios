// PhaseIndicator.swift
// Small colored dot + label reflecting the current workout phase.

import SwiftUI

struct PhaseIndicator: View {
    let phase: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.6), radius: 3)
                .animation(.easeInOut(duration: 0.3), value: phase)

            Text(phase.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(dotColor)
                .tracking(1.5)
                .animation(.easeInOut(duration: 0.3), value: phase)
        }
        .frame(maxWidth: .infinity)
        .contentTransition(.identity)
    }

    private var dotColor: Color {
        switch phase {
        case "Pull":       return Color(red: 0.0,   green: 0.831, blue: 0.667) // teal
        case "Return":     return Color(red: 1.0,   green: 0.722, blue: 0.302) // amber
        case "Transition": return Color(red: 0.424, green: 0.553, blue: 0.878) // blue
        default:           return Color(red: 0.290, green: 0.373, blue: 0.357) // dim
        }
    }
}
