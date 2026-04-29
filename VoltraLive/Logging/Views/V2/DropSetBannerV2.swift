// DropSetBannerV2.swift
//
// b55 (v0.4.33): V2-only drop-set armed banner. Sits between the header
// and the WEIGHT card whenever a manual drop sequence is armed (i.e.
// the user tapped the DROP mod tile and confirmed a from/to/step list).
//
// Visual spec mirrors the web preview's `.dropset-banner` rule:
//
//   margin: 0 16 8         (we let the parent supply the bottom padding)
//   padding: 8 12
//   background: rgba(255,184,77,0.08)   ← warn opacity 8%
//   border:    rgba(255,184,77,0.35)    ← warn opacity 35%
//   border-radius: 12
//
// Layout: [DROP-SET label]   ........   [120 lb → 110 lb][−10 lb pill]
//
// The banner is INTENTIONALLY non-blinking — only the rest-over phase
// strip blinks. That's a hard rule from the design pass: two competing
// orange-warn elements (banner border + blinking strip) must read at
// different visual weights so they don't visually conflict.

import SwiftUI

struct DropSetBannerV2: View {

    // MARK: Inputs

    let fromLb: Int
    let toLb:   Int
    let stepLb: Int

    /// Reserved for future use. Currently always rendered solid (no blink)
    /// per the design rule above. Plumbed so the call site can pass it
    /// without us silently dropping it on the floor.
    let blinkOn: Bool

    // MARK: Body

    var body: some View {
        HStack(spacing: 12) {
            // DROP-SET label
            Text("DROP-SET")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.warn)

            Spacer(minLength: 8)

            // 120 lb → 110 lb [−10 lb pill]
            HStack(spacing: 0) {
                Text("\(fromLb)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                Text(" lb ")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)
                Text("\u{2192}")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)
                    .padding(.horizontal, 6)
                Text("\(toLb)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                Text(" lb")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)

                // −STEP lb pill
                Text("\u{2212}\(stepLb) lb")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.warn)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(VoltraColor.warn.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(VoltraColor.warn.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VoltraColor.warn.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.warn.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
#Preview("Drop-set banner — 120→110") {
    VStack {
        DropSetBannerV2(fromLb: 120, toLb: 110, stepLb: 10, blinkOn: false)
            .padding()
        Spacer()
    }
    .background(VoltraColor.bg)
}
#endif
