// VoltraLive/Coaching/Views/CoachingCardButtonRow.swift
// RC-01 — action buttons at the bottom of the coaching card.
//
// Button layout (left → right, mutually exclusive middle slot):
//   [Load X lb]  [Push Y lb | Last Z lb]  [Repeat W lb]
//
// Nothing here writes to BLE directly. Callbacks call adjustWeight
// in LiveCaptureViewV2 which enforces CombinedParity + reanchor.

import SwiftUI

struct CoachingCardButtonRow: View {
    let recommendation: CoachingRecommendation
    let onLoadRecommended: () -> Void
    let onLoadAggressive: () -> Void
    let onLoadAnchor: () -> Void
    let onRepeatCurrent: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Primary — always visible
            Button(action: onLoadRecommended) {
                Text("Load \(fmt(recommendation.recommendedWeightLb)) lb")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(8)
            }
            .accessibilityLabel(
                "Load recommended weight \(fmt(recommendation.recommendedWeightLb)) pounds"
            )

            // Middle — aggressive OR last-session, mutually exclusive
            if recommendation.shouldShowAggressiveOption,
               let agg = recommendation.aggressiveWeightLb {
                Button(action: onLoadAggressive) {
                    Text("Push \(fmt(agg)) lb")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                .accessibilityLabel("Aggressive push weight \(fmt(agg)) pounds")
            } else if let anchor = recommendation.anchorWeightLb,
                      Int(anchor.rounded()) != Int(recommendation.recommendedWeightLb.rounded()) {
                Button(action: onLoadAnchor) {
                    Text("Last \(fmt(anchor)) lb")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
                .accessibilityLabel("Load last session weight \(fmt(anchor)) pounds")
            }

            // Repeat — hidden when safe weight is zero (no current weight)
            if recommendation.safeWeightLb > 0 {
                Button(action: onRepeatCurrent) {
                    Text("Repeat \(fmt(recommendation.safeWeightLb)) lb")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
                .accessibilityLabel(
                    "Repeat current weight \(fmt(recommendation.safeWeightLb)) pounds"
                )
            }
        }
    }

    private func fmt(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
    }
}
