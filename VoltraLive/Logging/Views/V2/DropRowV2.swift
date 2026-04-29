// DropRowV2.swift
//
// b55 (v0.4.33): V2-only DROP sub-row that lives INSIDE the WEIGHT card
// when a manual drop sequence is armed. Distinct from DropSetBannerV2:
//
//   - DropSetBannerV2 sits ABOVE the WEIGHT card (warn-tinted background)
//   - DropRowV2 sits INSIDE the WEIGHT card (sunken bg, neutral border)
//
// Visual spec mirrors the web preview's `.drop-row` rule:
//
//   margin-top: 10                  (parent supplies via .padding(.top, 10))
//   padding: 8 12
//   background: var(--vl-bg)        ← darker than the card's bgElev
//   border:     var(--vl-border)
//   border-radius: 10
//
// Layout: [DROP] ──── [120 → 110] ──── [next: −10 lb pill]
//
// The inner sequence is centered horizontally (preview has flex: 1 +
// text-align: center on .seq); we mirror that with a Spacer/Text/Spacer
// pattern. The next-pill on the trailing edge is the warn-orange step
// callout — same colors as the DropSetBannerV2 pill but smaller.

import SwiftUI

struct DropRowV2: View {

    // MARK: Inputs

    let fromLb: Int
    let toLb:   Int
    let stepLb: Int

    // MARK: Body

    var body: some View {
        HStack(spacing: 10) {
            Text("DROP")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)

            // Centered sequence: from → to
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("\(fromLb)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                Text("\u{2192}")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)
                Text("\(toLb)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
            }
            Spacer(minLength: 0)

            // next: −STEP lb pill (two-line layout per preview)
            VStack(spacing: 0) {
                Text("next: \u{2212}\(stepLb)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.warn)
                Text("lb")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.warn)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(VoltraColor.warn.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(VoltraColor.warn.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VoltraColor.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#if DEBUG
#Preview("Drop row inside WEIGHT card") {
    VStack {
        DropRowV2(fromLb: 120, toLb: 110, stepLb: 10)
            .padding()
        Spacer()
    }
    .background(VoltraColor.bgElev)
}
#endif
