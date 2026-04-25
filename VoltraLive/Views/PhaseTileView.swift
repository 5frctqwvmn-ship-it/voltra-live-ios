// PhaseTileView.swift
// Phase tile that color-shifts border and background on phase change.
// Mirrors the CSS data-phase rules in styles.css.

import SwiftUI

struct PhaseTileView: View {
    let phase: VoltraPhase

    private var borderColor: Color { VoltraColor.phase(phase) }
    private var accentBackground: Color {
        switch phase {
        case .pull:       return Color(hex: "#00d4aa").opacity(0.12)
        case .return:     return Color(hex: "#ffb84d").opacity(0.12)
        case .transition: return Color(hex: "#6c8de0").opacity(0.08)
        case .idle:       return .clear
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PHASE")
                .font(.system(size: 11, weight: .bold))
                .kerning(2.0)
                .foregroundColor(VoltraColor.textDim)
                .textCase(.uppercase)

            Spacer()

            Text(phase.rawValue)
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(VoltraColor.phase(phase))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.identity)
                .animation(.easeInOut(duration: 0.2), value: phase)

            // Phase indicator bar at bottom
            Rectangle()
                .fill(VoltraColor.phase(phase))
                .frame(height: 4)
                .animation(.easeInOut(duration: 0.2), value: phase)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                VoltraColor.bgElev
                LinearGradient(
                    colors: [VoltraColor.bgElev, accentBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .animation(.easeInOut(duration: 0.2), value: phase)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
                .animation(.easeInOut(duration: 0.2), value: phase)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    HStack {
        PhaseTileView(phase: .pull)
        PhaseTileView(phase: .return)
        PhaseTileView(phase: .idle)
    }
    .frame(height: 170)
    .padding()
    .background(VoltraColor.bg)
}
