// VoltraLive/Coaching/Views/FatigueIndicatorView.swift
// RC-01 — small colored dot showing current fatigue gate.

import SwiftUI

struct FatigueIndicatorView: View {
    let gate: FatigueGate

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch gate {
        case .green:   return .green
        case .yellow:  return .yellow
        case .red:     return .red
        case .unknown: return .gray
        }
    }

    private var label: String {
        switch gate {
        case .green:   return "Low fatigue"
        case .yellow:  return "Moderate fatigue"
        case .red:     return "High fatigue"
        case .unknown: return "Fatigue unknown"
        }
    }
}
