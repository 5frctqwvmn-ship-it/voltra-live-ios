// VoltraLive/Coaching/Views/CoachingCardView.swift
// RC-01 — rest-state coaching card shown in LiveCaptureViewV2
// when the device is unloaded and a session cursor is available.
//
// minHeight matches CoachingConstants.cardMinHeight so the panel
// switch from ForceChartView does not cause a layout shift.
//
// Callbacks (onLoadRecommended, onLoadAggressive, onLoadAnchor,
// onRepeatCurrent) must route through adjustWeight(_:) in the
// parent view — never write to pendingPlannedWeightLb directly.

import SwiftUI

struct CoachingCardView: View {
    let recommendation: CoachingRecommendation
    let onLoadRecommended: () -> Void
    let onLoadAggressive: () -> Void
    let onLoadAnchor: () -> Void
    let onRepeatCurrent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: headline + fatigue dot
            HStack {
                Text(recommendation.headline)
                    .font(.headline)
                Spacer()
                FatigueIndicatorView(gate: recommendation.fatigueGate)
            }

            // History context
            Text(recommendation.historyLine)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Today vs last session delta
            if let delta = recommendation.deltaLine {
                Text(delta)
                    .font(.subheadline)
            }

            // Fatigue warning (yellow/red only)
            if let fatigue = recommendation.fatigueLine {
                Text(fatigue)
                    .font(.footnote)
                    .foregroundColor(.orange)
            }

            // Recommended weight (or prompt when unknown)
            if recommendation.recommendedWeightLb > 0 {
                Text("Recommended: \(fmt(recommendation.recommendedWeightLb)) lb")
                    .font(.title3.bold())
                    .padding(.top, 4)
            } else {
                Text("Pick a starting weight")
                    .font(.title3.bold())
                    .padding(.top, 4)
            }

            // Reason string — always present, always explainable
            Text(recommendation.reasonLine)
                .font(.footnote)
                .foregroundColor(.secondary)

            // Action buttons
            CoachingCardButtonRow(
                recommendation: recommendation,
                onLoadRecommended: onLoadRecommended,
                onLoadAggressive: onLoadAggressive,
                onLoadAnchor: onLoadAnchor,
                onRepeatCurrent: onRepeatCurrent
            )
            .padding(.top, 6)
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: CoachingConstants.cardMinHeight,
            alignment: .topLeading
        )
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    private func fmt(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
    }
}
