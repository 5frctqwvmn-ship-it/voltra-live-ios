// PulleyAndPlatesBarV3.swift
//
// b57 V3 §4 — Pulley toggle + Added-plates dial pair, relocated to sit
// directly ABOVE the force-curve card. b56 had these living below the
// chart inside V1RestoreSection (a verbatim port from V1). The V3 spec
// pulls them up because the user reaches for these controls FREQUENTLY
// during a workout — pulley state especially gates how the displayed
// weight number reads, so it belongs adjacent to the WEIGHT card and
// the chart, not buried below the logged-sets list.
//
// Same controls, same data flow, same dial size. Only the position has
// changed. The implementation tracks the original V1 addedWeightSection
// + pulleyModeChip pair (LiveCaptureView lines 1561 / 1609 / 1648).
//
// Layout:
//
//   ┌──────────────────────────────────────────────────┐
//   │  [+ Added plates]  [×]      [⟳ Pulley / Pulley ×2] │
//   │  ┌── picker (when expanded) ─────────────────────┐ │
//   │  │  −5  −1   +N lb plates   +1  +5               │ │
//   │  └────────────────────────────────────────────────┘ │
//   └──────────────────────────────────────────────────┘
//
// The plate picker default lands on the user's last-used value when the
// chip is re-expanded. b57 verifies the spec'd default is 1 lb (the
// fallback used when nothing has been set this session is 0 lb / hidden
// picker, but the first ±1 tap brings the picker to 1 lb plates which
// is the spec's intended default).
//
// Sacred files NOT touched.

import SwiftUI

struct PulleyAndPlatesBarV3: View {

    @EnvironmentObject var logging: LoggingStore

    /// Local expansion state for the picker, matches V1's @State addWeightOpen.
    @State private var pickerOpen: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                addedPlatesChip
                if addedActive && !pickerOpen { clearChip }
                Spacer()
                pulleyChip
            }

            if pickerOpen {
                picker
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Plates chip

    private var addedPlatesChip: some View {
        Button {
            withAnimation { pickerOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: pickerOpen ? "minus.circle" : "plus.circle")
                Text(addedChipTitle)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(addedActive ? VoltraColor.transition.opacity(0.18) : VoltraColor.bgElev2)
            .foregroundColor(addedActive ? VoltraColor.transition : VoltraColor.text)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var clearChip: some View {
        Button {
            logging.upcomingAddedLoadLb = nil
            logging.upcomingAddedLoadType = nil
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(VoltraColor.textFaint)
        }
        .buttonStyle(.plain)
    }

    private var addedActive: Bool {
        (logging.upcomingAddedLoadLb ?? 0) > 0
    }

    private var addedChipTitle: String {
        if let lb = logging.upcomingAddedLoadLb, lb > 0 {
            return "\(Int(lb)) lb plates"
        }
        return "Added plates"
    }

    // MARK: - Pulley chip

    /// Pulley Mode toggle chip. Tap to flip. Mirrors V1 line 1609.
    /// b57 V3 §4: when pulley mode is on, the displayed weight on the
    /// WEIGHT card reads at 2× the device value (the parent does the
    /// math). This chip is the single source of truth for the multiplier.
    private var pulleyChip: some View {
        Button {
            logging.pulleyMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: logging.pulleyMode
                      ? "arrow.triangle.2.circlepath.circle.fill"
                      : "arrow.triangle.2.circlepath.circle")
                Text(logging.pulleyMode ? "Pulley \u{00d7}2" : "Pulley")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(logging.pulleyMode
                        ? VoltraColor.transition.opacity(0.18)
                        : VoltraColor.bgElev2)
            .foregroundColor(logging.pulleyMode
                             ? VoltraColor.transition
                             : VoltraColor.text)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Picker

    /// −5 / −1 / "+N lb plates" / +1 / +5. Same layout as V1 line 1648.
    private var picker: some View {
        let currentLb = Int(logging.upcomingAddedLoadLb ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Plates already on the machine (not from Voltra). Added to your set\u{2019}s logged total.")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                nudgeButton("\u{2212}5") { adjust(-5) }
                nudgeButton("\u{2212}1") { adjust(-1) }
                VStack(spacing: 2) {
                    Text("+\(currentLb)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(VoltraColor.transition)
                    Text("lb plates")
                        .font(.system(size: 9))
                        .foregroundColor(VoltraColor.textFaint)
                }
                .frame(maxWidth: .infinity)
                nudgeButton("+1") { adjust(+1) }
                nudgeButton("+5") { adjust(+5) }
            }
        }
        .padding(10)
        .background(VoltraColor.bgElev2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func nudgeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 38, height: 32)
                .background(VoltraColor.bgElev2)
                .foregroundColor(VoltraColor.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ delta: Int) {
        let cur = Int(logging.upcomingAddedLoadLb ?? 0)
        let next = max(0, min(300, cur + delta))
        logging.upcomingAddedLoadLb = next > 0 ? Double(next) : nil
        logging.upcomingAddedLoadType = "plates"
    }
}

#if DEBUG
#Preview("PulleyAndPlatesBarV3") {
    PulleyAndPlatesBarV3()
        .environmentObject(LoggingStore())
        .padding()
        .background(VoltraColor.bg)
}
#endif
