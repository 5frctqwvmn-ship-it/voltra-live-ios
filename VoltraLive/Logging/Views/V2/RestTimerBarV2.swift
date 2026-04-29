// RestTimerBarV2.swift
//
// b56 — V2 rest-timer bar that REPLACES the phase strip when the user
// finalizes a set and enters rest. Spec from the b56 design handoff:
//
//   - Trigger: 2-second idle on push or pull (handled upstream by
//     SessionStore.restElapsedSeconds; this view just renders).
//   - Visual: left-to-right progress sweep over the full rest duration
//     (e.g. 2:00 → traverse takes 2 minutes).
//   - Color: continuous HSL interpolation —
//        0%   green   hsl(140, 70%, 45%)
//       ~50% amber   hsl( 40, 90%, 50%)
//       ~85% red     hsl(  0, 80%, 50%)
//     Linear interpolation on hue/sat/lightness between those stops.
//   - Over-time: bar holds deep red, blinks; header flips to
//     REST · OVER and shows +MM:SS overtime counter.
//   - Exit: caller hides this view when the next pull starts (i.e. when
//     `restElapsedSeconds` returns to 0). Not this view's responsibility.
//
// This view does NOT mutate state. It reads two ints (elapsed, preset)
// and a blink tick, and renders. The 1Hz blink driver lives in the
// parent (LiveCaptureViewV2) so all blinks across the screen stay in
// phase.
//
// Replaces the b55 TopBannerV2 phase-strip render during rest. The
// active-phase strip (PULL teal / RETURN orange) is rendered by a
// sibling component (PhaseStripV2) when not resting.

import SwiftUI

struct RestTimerBarV2: View {

    /// Seconds elapsed since rest started. Comes from
    /// `SessionStore.restElapsedSeconds`.
    let restElapsedSec: Int

    /// Configured rest duration in seconds (default 120 = 2:00).
    let restPresetSec: Int

    /// 1Hz blink tick — toggles every 0.5s in the parent. Used only
    /// when over-preset to drive the warn blink.
    let blinkOn: Bool

    /// Bar height. Matches the phase-strip height it replaces (4pt).
    private let barHeight: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            headerRow
            progressBar
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(over ? "REST \u{00B7} OVER" : "REST")
                .font(.system(size: 9, weight: .bold))
                .kerning(1.6)
                .foregroundColor(over ? VoltraColor.danger : VoltraColor.textDim)
                .opacity(over && !blinkOn ? 0.4 : 1.0)
            Spacer()
            Text(timeLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(over ? VoltraColor.danger : VoltraColor.text)
                .opacity(over && !blinkOn ? 0.4 : 1.0)
            Text(over ? "" : "TAP TO START")
                .font(.system(size: 9, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textFaint)
        }
    }

    private var timeLabel: String {
        if over {
            let extra = restElapsedSec - restPresetSec
            return "+" + format(extra)
        }
        // Match the design-handoff's countdown: show TIME REMAINING, not elapsed.
        let remaining = max(0, restPresetSec - restElapsedSec)
        return format(remaining)
    }

    private func format(_ s: Int) -> String {
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    // MARK: - Bar

    private var progressBar: some View {
        GeometryReader { geo in
            let total = max(1, restPresetSec)
            let progress = min(1.0, Double(restElapsedSec) / Double(total))
            let fillW = geo.size.width * CGFloat(progress)
            ZStack(alignment: .leading) {
                // Track
                Capsule(style: .continuous)
                    .fill(VoltraColor.bgElev2)
                    .frame(height: barHeight)

                // Sweep — width = progress, color = HSL(progress)
                Capsule(style: .continuous)
                    .fill(sweepColor)
                    .frame(width: fillW, height: barHeight)
                    .opacity(over && !blinkOn ? 0.3 : 1.0)
                    .animation(.linear(duration: 0.25), value: fillW)
            }
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
    }

    // MARK: - Color interpolation

    /// 3-stop linear HSL interpolation: green → amber → red.
    /// Stops:
    ///   0.00  hsl(140, 70%, 45%)
    ///   0.50  hsl( 40, 90%, 50%)
    ///   0.85  hsl(  0, 80%, 50%)
    /// > 0.85: hold deep red.
    private var sweepColor: Color {
        let p = over
            ? 1.0
            : min(1.0, max(0.0, Double(restElapsedSec) / Double(max(1, restPresetSec))))

        // Stop A → B: blend from (h,s,l) at p0 to (h,s,l) at p1.
        struct Stop { let p: Double; let h: Double; let s: Double; let l: Double }
        let stops: [Stop] = [
            Stop(p: 0.00, h: 140, s: 0.70, l: 0.45),
            Stop(p: 0.50, h:  40, s: 0.90, l: 0.50),
            Stop(p: 0.85, h:   0, s: 0.80, l: 0.50)
        ]

        // Find segment.
        var a = stops[0]
        var b = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            if p >= stops[i].p && p <= stops[i + 1].p {
                a = stops[i]
                b = stops[i + 1]
                break
            }
        }
        if p >= stops.last!.p {
            return hslColor(h: stops.last!.h, s: stops.last!.s, l: stops.last!.l)
        }
        let span = max(0.0001, b.p - a.p)
        let t = (p - a.p) / span
        let h = a.h + (b.h - a.h) * t
        let s = a.s + (b.s - a.s) * t
        let l = a.l + (b.l - a.l) * t
        return hslColor(h: h, s: s, l: l)
    }

    /// Convert HSL → SwiftUI Color via standard formula.
    /// h in degrees [0,360), s,l in [0,1].
    private func hslColor(h: Double, s: Double, l: Double) -> Color {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60.0
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r1 = 0.0, g1 = 0.0, b1 = 0.0
        switch hp {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        case 5..<6: (r1, g1, b1) = (c, 0, x)
        default:    (r1, g1, b1) = (c, x, 0)
        }
        let m = l - c / 2
        return Color(red: r1 + m, green: g1 + m, blue: b1 + m)
    }

    private var over: Bool { restElapsedSec > restPresetSec }
}

#if DEBUG
#Preview("Rest 0:30 of 2:00 (green)") {
    RestTimerBarV2(restElapsedSec: 30, restPresetSec: 120, blinkOn: true)
        .padding()
        .background(VoltraColor.bg)
}

#Preview("Rest 1:00 of 2:00 (amber)") {
    RestTimerBarV2(restElapsedSec: 60, restPresetSec: 120, blinkOn: true)
        .padding()
        .background(VoltraColor.bg)
}

#Preview("Rest 1:50 of 2:00 (red)") {
    RestTimerBarV2(restElapsedSec: 110, restPresetSec: 120, blinkOn: true)
        .padding()
        .background(VoltraColor.bg)
}

#Preview("Rest +0:18 over (blinking)") {
    RestTimerBarV2(restElapsedSec: 138, restPresetSec: 120, blinkOn: false)
        .padding()
        .background(VoltraColor.bg)
}
#endif
