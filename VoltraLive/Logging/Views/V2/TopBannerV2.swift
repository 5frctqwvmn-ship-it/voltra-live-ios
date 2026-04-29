// TopBannerV2.swift
//
// b55: Phase strip + optional rest row, used by LiveCaptureViewV2.
//
// Visual rules (matched to design-handoff/screenshots/A1-states.png and
// A1-drop2.png — the user signed off on a web preview render of these
// before this implementation, see voltra-v2-preview/index.html):
//
//   - Phase strip is ALWAYS visible.
//     PULL idle:          full-width teal glowing line, label "PULL" teal
//     RETURN idle:        full-width orange glowing line, label "RETURN" orange
//     IDLE/rest under:    dim half-fill teal segment, label "IDLE" faint
//     IDLE/rest OVER:     full-width WARN orange line + WARN label "IDLE",
//                         the parent rest row also blinks at 1Hz
//   - When rest is engaged, a SECOND row appears beneath the phase strip
//     separated by a 1px hairline divider:
//       Under preset:  green "REST" left  ·  green "01:23 SET 1 · TAP TO START" right
//       Over preset:   orange "REST · OVER" left + "+00:18 …" right, both blink
//
// This view is dumb: it takes resolved state and renders. Animation/timing
// live in the parent.

import SwiftUI

struct TopBannerV2: View {

    // Live BLE phase (only consulted when not over-rest).
    let phase: VoltraPhase

    // Rest state.
    let isResting: Bool
    let restElapsed: Int
    let restPreset: Int
    let over: Bool

    // 1Hz blink driver from the parent.
    let blinkOn: Bool

    // For the "SET 1 · TAP TO START" meta on the rest row.
    let setNumber: Int

    /// Tap anywhere on the strip while over-rest to start the next set.
    /// Optional — caller may leave a no-op until SessionStore wires it.
    let onTapToStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            phaseStripRow
            if isResting {
                Rectangle()
                    .fill(VoltraColor.border)
                    .frame(height: 1)
                    .padding(.top, 6)
                restRow
                    .padding(.top, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if over { onTapToStart() }
        }
    }

    // MARK: - Phase strip (top half)

    private var phaseStripRow: some View {
        VStack(spacing: 6) {
            stripLine
            HStack {
                Text(stripLabelText)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundColor(stripLabelColor)
                    .opacity(stripLabelOpacity)
                Spacer()
                Text("SET \(setNumber)")
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
            }
        }
    }

    @ViewBuilder
    private var stripLine: some View {
        // The track is a fixed 4px box. The line inside fills based on state.
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // No background — match the reference (no track box visible)
                RoundedRectangle(cornerRadius: 2)
                    .fill(stripFillColor)
                    .frame(width: w * stripFillFraction, height: 4)
                    .shadow(color: stripGlowColor, radius: 5)
            }
            .frame(width: w, alignment: .leading)
        }
        .frame(height: 4)
    }

    /// Computed visual state of the phase strip.
    private var stripFillColor: Color {
        if over { return VoltraColor.warn }
        if !isResting {
            switch phase {
            case .pull:       return VoltraColor.pull
            case .return:     return VoltraColor.returnPhase
            case .transition: return VoltraColor.transition
            case .idle:       return VoltraColor.pull.opacity(0.5)
            }
        }
        return VoltraColor.pull.opacity(0.5)
    }

    private var stripFillFraction: CGFloat {
        if over { return 1.0 }
        if !isResting {
            // Active idle/lifting → the phase strip is "full" by design (it's
            // a state indicator, not a progress bar). Phase changes recolor
            // the full line.
            return 1.0
        }
        // Under-preset rest → half-fill dim teal IDLE strip, matches reference
        return 0.5
    }

    private var stripGlowColor: Color {
        if over { return VoltraColor.warn.opacity(0.65) }
        if !isResting {
            switch phase {
            case .pull:       return VoltraColor.pull.opacity(0.65)
            case .return:     return VoltraColor.returnPhase.opacity(0.65)
            case .transition: return VoltraColor.transition.opacity(0.65)
            case .idle:       return .clear
            }
        }
        return .clear
    }

    private var stripLabelText: String {
        if isResting { return "IDLE" }
        switch phase {
        case .pull:       return "PULL"
        case .return:     return "RETURN"
        case .transition: return "TRANS"
        case .idle:       return "IDLE"
        }
    }

    private var stripLabelColor: Color {
        if over { return VoltraColor.warn }
        if isResting { return VoltraColor.textFaint }
        switch phase {
        case .pull:       return VoltraColor.pull
        case .return:     return VoltraColor.returnPhase
        case .transition: return VoltraColor.transition
        case .idle:       return VoltraColor.textFaint
        }
    }

    private var stripLabelOpacity: Double {
        if !over && isResting { return 0.55 }
        return 1.0
    }

    // MARK: - Rest row (bottom half, when isResting)

    private var restRow: some View {
        HStack {
            Text(over ? "REST \u{00B7} OVER" : "REST")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundColor(over ? VoltraColor.warn : VoltraColor.accent)
                .opacity(over ? blinkOpacity : 1.0)

            Spacer()

            HStack(spacing: 6) {
                Text(timerText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(over ? VoltraColor.warn : VoltraColor.accent)
                    .opacity(over ? blinkOpacity : 1.0)
                Text("SET \(setNumber) \u{00B7} TAP TO START")
                    .font(.system(size: 9.5, weight: .medium))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textFaint)
            }
        }
    }

    private var timerText: String {
        let remaining = restPreset - restElapsed
        if remaining >= 0 {
            return formatMMSS(remaining)
        } else {
            return "+" + formatMMSS(-remaining)
        }
    }

    private var blinkOpacity: Double { blinkOn ? 1.0 : 0.45 }

    private func formatMMSS(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}
