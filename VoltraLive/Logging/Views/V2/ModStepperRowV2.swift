// ModStepperRowV2.swift
//
// b56 — Per-engaged-mod inline stepper row used inside the WEIGHT card,
// directly below the matching NestedModRowV2. One row per engaged
// mod. Layout per spec:
//
//   ECC                  −10  −5  +5  +10
//   CHAIN                −10  −5  +5  +10
//   INV CHAIN            −10  −5  +5  +10
//   DROP                 −10  −5  +5  +10
//
// Each tap calls back with the signed delta. The parent owns the
// underlying value (LoggingStore.upcomingEccLb / Chains / Inverse, or
// the manualDropSequence next-step) and clamps to its own bounds. ECC
// gets a special clamp helper here because its working range is
// 5–400 lb per the b56 spec — see `clampedECC`.
//
// All stepper buttons share the same compact 38×30 footprint as the
// WEIGHT card's main stepper pair, so the rows visually nest under it.
//
// Sacred files NOT touched. This view writes nothing to BLE — it just
// publishes deltas via closures. The parent triggers
// pushUpcomingStateToDevice() after applying the delta.

import SwiftUI

struct ModStepperRowV2: View {

    /// Uppercase label shown leading. Same kerned-9pt style as
    /// NestedModRowV2 so the two read as a pair.
    let label: String

    /// Current value in lb (already clamped by the parent). Display only.
    let valueLb: Int

    /// Suffix shown after the number, e.g. "lb". Defaults to "lb".
    let unit: String

    /// Tint applied to the value text. Default is the neutral text color.
    /// DROP variant uses warn-orange to match its NestedModRowV2.
    let valueTint: Color

    /// Called with a signed delta when a button is tapped. Parent applies
    /// any clamping (e.g. ECC 5–400, others 0–N).
    let onDelta: (Int) -> Void

    init(
        label: String,
        valueLb: Int,
        unit: String = "lb",
        valueTint: Color = VoltraColor.text,
        onDelta: @escaping (Int) -> Void
    ) {
        self.label = label
        self.valueLb = valueLb
        self.unit = unit
        self.valueTint = valueTint
        self.onDelta = onDelta
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
                .frame(width: 76, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(valueLb)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(valueTint)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)
            }

            Spacer()

            stepperBtn("\u{2212}10") { onDelta(-10) }
            stepperBtn("\u{2212}5")  { onDelta(-5) }
            stepperBtn("+5")          { onDelta(+5) }
            stepperBtn("+10")         { onDelta(+10) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepperBtn(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .frame(minWidth: 32, minHeight: 28)
        }
        .buttonStyle(.plain)
        .background(VoltraColor.bgElev2)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Clamp helpers

extension ModStepperRowV2 {
    /// b56: ECC working range is 5–400 lb. Use this in the parent before
    /// assigning `logging.upcomingEccLb` from a delta.
    static func clampedECC(current: Int, delta: Int) -> Int {
        return max(5, min(400, current + delta))
    }

    /// b56: CHAIN / INV CHAIN range is 0–300 lb. Same clamp the V1
    /// adjustEcc helper uses, applied to the per-mod weights.
    static func clampedChain(current: Int, delta: Int) -> Int {
        return max(0, min(300, current + delta))
    }

    /// b56: DROP next-step range. We clamp at 5 lb (device floor) on the
    /// low end and the current head weight on the high end. The parent
    /// supplies `headLb` so the user can't step the next-drop ABOVE the
    /// current weight (which would be a drop UP — meaningless).
    static func clampedDropNext(current: Int, delta: Int, headLb: Int) -> Int {
        return max(5, min(headLb, current + delta))
    }
}

#if DEBUG
#Preview("Mod stepper rows") {
    VStack(spacing: 4) {
        ModStepperRowV2(label: "ECC",       valueLb: 36) { _ in }
        ModStepperRowV2(label: "CHAIN",     valueLb: 30) { _ in }
        ModStepperRowV2(label: "INV CHAIN", valueLb: 30) { _ in }
        ModStepperRowV2(label: "DROP",      valueLb: 110, valueTint: VoltraColor.warn) { _ in }
    }
    .padding()
    .background(VoltraColor.bg)
}
#endif
