// NestedModRowV2.swift
//
// b56 — single nested mod-state row used inside the WEIGHT card. One
// row per engaged mod, in this fixed order:
//
//   ECC        156    (+30% on lower)
//   CHAIN      120 → 150  (+30 lb at top)
//   INV CHAIN  150 → 120  (-30 lb thru ROM)
//   DROP       120 → 110  (-10 lb next)
//
// Per the b56 spec: only render rows for mods that are engaged or armed.
// Inactive mods are HIDDEN, not greyed-out. The parent decides
// visibility — this view always renders when instantiated.
//
// Layout: leading kerned uppercase label + trailing right-aligned
// value-and-subline. The value styling matches the WEIGHT card numeric
// style at smaller scale so the four rows read as variants of the same
// weight, not as separate cards.

import SwiftUI

struct NestedModRowV2: View {

    /// Uppercase label shown leading, e.g. "ECC", "CHAIN", "INV CHAIN", "DROP".
    let label: String

    /// Headline value text shown trailing in mono. Examples:
    ///   ECC:       "156"
    ///   CHAIN:     "120 → 150"
    ///   INV CHAIN: "150 → 120"
    ///   DROP:      "120 → 110"
    let valueText: String

    /// Small dim subline next to the value. Examples:
    ///   ECC:       "+30% on lower"
    ///   CHAIN:     "+30 lb at top"
    ///   INV CHAIN: "-30 lb thru ROM"
    ///   DROP:      "-10 lb next"
    let subline: String

    /// Whether this row is the DROP row, which gets the warn-orange tint
    /// (matches the design-handoff's pre-fire DROP styling). All other
    /// rows render with the neutral text color.
    let isDrop: Bool

    init(label: String, valueText: String, subline: String, isDrop: Bool = false) {
        self.label = label
        self.valueText = valueText
        self.subline = subline
        self.isDrop = isDrop
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            Spacer()
            Text(valueText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(isDrop ? VoltraColor.warn : VoltraColor.text)
            Text(subline)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Convenience builders for each mod type

extension NestedModRowV2 {
    /// ECC nested row. Shows working-weight + ecc as a single number
    /// (e.g. "156" for 120 base + 30% ecc) plus the percentage subline.
    /// b56: ECC range supports up to 400 lb working — see ModStepperRowV2.
    static func ecc(workingLb: Int, eccLb: Int) -> NestedModRowV2 {
        let total = workingLb + eccLb
        let pct: Int = workingLb > 0
            ? Int((Double(eccLb) / Double(workingLb) * 100).rounded())
            : 0
        return NestedModRowV2(
            label: "ECC",
            valueText: "\(total)",
            subline: "+\(pct)% on lower"
        )
    }

    /// CHAIN nested row. Working weight at start of ROM, working+chains
    /// at top (e.g. "120 → 150" with "+30 lb at top").
    static func chain(workingLb: Int, chainsLb: Int) -> NestedModRowV2 {
        return NestedModRowV2(
            label: "CHAIN",
            valueText: "\(workingLb) \u{2192} \(workingLb + chainsLb)",
            subline: "+\(chainsLb) lb at top"
        )
    }

    /// INV CHAIN nested row. Working+inverse at start of ROM, working at
    /// top (e.g. "150 → 120" with "-30 lb thru ROM").
    static func invChain(workingLb: Int, inverseLb: Int) -> NestedModRowV2 {
        return NestedModRowV2(
            label: "INV CHAIN",
            valueText: "\(workingLb + inverseLb) \u{2192} \(workingLb)",
            subline: "-\(inverseLb) lb thru ROM"
        )
    }

    /// DROP nested row. Current working weight → next dropped weight,
    /// armed but not yet fired (e.g. "120 → 110" with "-10 lb next").
    /// Tinted warn-orange.
    static func drop(currentLb: Int, nextLb: Int) -> NestedModRowV2 {
        let stepLb = currentLb - nextLb
        return NestedModRowV2(
            label: "DROP",
            valueText: "\(currentLb) \u{2192} \(nextLb)",
            subline: "-\(stepLb) lb next",
            isDrop: true
        )
    }
}

#if DEBUG
#Preview("All four nested rows") {
    VStack(spacing: 6) {
        NestedModRowV2.ecc(workingLb: 120, eccLb: 36)
        NestedModRowV2.chain(workingLb: 120, chainsLb: 30)
        NestedModRowV2.invChain(workingLb: 120, inverseLb: 30)
        NestedModRowV2.drop(currentLb: 120, nextLb: 110)
    }
    .padding()
    .background(VoltraColor.bg)
}
#endif
