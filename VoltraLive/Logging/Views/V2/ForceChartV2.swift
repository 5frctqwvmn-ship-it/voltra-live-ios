// ForceChartV2.swift
//
// b55 (v0.4.33): V2-only force chart. Three rendering modes:
//
//   1. ACTIVE — `samples` non-empty, `resting == false`
//      Phase-segmented polyline of the last 30s of force history.
//      Each consecutive run of same-phase samples is drawn as a single
//      polyline in that phase's color (PULL teal / RETURN orange /
//      TRANSITION blue / IDLE dim). A small filled circle marks the
//      most recent (rightmost) tip in the current phase color.
//
//   2. RESTING — `resting == true`
//      Empty chart. Only the dashed BOTTOM marker line + label.
//
//   3. IDLE-NO-DATA — `resting == false` and `samples` empty
//      Sparse 5-sample ramp from x≈0 up to ~14% of the chart width,
//      anchored to BOTTOM, colored by `idlePhase`. This matches the
//      reference screenshots where an idle Voltra still shows a tiny
//      "alive" up-tick on the chart so the user knows the line is
//      plumbed through. Mirrors the web preview's `buildForceHistory`
//      function which generates 5 samples ramping 0 → peak.
//
// All three modes draw the BOTTOM dashed reference line in danger color
// at 50% opacity. The chart canvas is a fixed 175pt tall (matches the
// web preview h=175) and stretches to fill the parent's width.
//
// IMPORTANT — sacred-files boundary: this view is read-only on the
// telemetry stream. It does NOT mutate samples, does NOT call into
// VoltraProtocol / TelemetryExtractor / PacketParser / FrameAssembler.
// It just renders whatever `samples` the caller hands it.

import SwiftUI

struct ForceChartV2: View {

    // MARK: Inputs

    /// Live force samples for the current set, or `lastFinalizedSamples`
    /// if no live set is in progress. May be empty.
    let samples: [ForceSample]

    /// Peak force seen in this set (used to scale the y-axis).
    let peakLb: Double

    /// True when a rest window is engaged (post-finalize). When true, we
    /// render the empty-rest variant (BOTTOM marker only).
    let resting: Bool

    /// Phase to use for the synthetic idle up-tick when `samples` is empty
    /// and we're not resting. Typically `ble.telemetry.phase`.
    let idlePhase: VoltraPhase

    // MARK: Tunables (mirror web preview)

    /// Hard floor for the y-axis denominator so an early-set rep with a
    /// small peak still draws within the chart instead of slamming into
    /// the top edge. Matches the preview's `maxF = 160`.
    private let maxFCeiling: Double = 160

    /// Inner padding inside the SVG-equivalent viewBox.
    private let pad: CGFloat = 8

    /// Fixed drawing height to match the preview (h = 175). Width is
    /// inherited from the parent via a GeometryReader.
    private let canvasHeight: CGFloat = 175

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = canvasHeight
            ZStack(alignment: .topLeading) {
                // BOTTOM dashed marker (always present, all three modes)
                bottomMarker(width: w, height: h)

                if resting {
                    // mode 2: empty resting chart — nothing else to draw
                    EmptyView()
                } else if samples.isEmpty {
                    // mode 3: synthetic idle ramp (5 samples, leftmost ~14% of width)
                    idleRamp(width: w, height: h)
                } else {
                    // mode 1: phase-segmented polyline of last 30s
                    activeChart(samples: samples, width: w, height: h)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .frame(height: canvasHeight)
    }

    // MARK: - Mode 2/3 helpers — BOTTOM marker

    @ViewBuilder
    private func bottomMarker(width w: CGFloat, height h: CGFloat) -> some View {
        let y = h - pad
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
            }
            .stroke(
                VoltraColor.danger.opacity(0.5),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            Text("BOTTOM")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(VoltraColor.danger.opacity(0.7))
                .offset(x: 6, y: y - 14)
        }
    }

    // MARK: - Mode 3 — synthetic idle ramp (5 samples, sparse)

    @ViewBuilder
    private func idleRamp(width w: CGFloat, height h: CGFloat) -> some View {
        // 5 samples ascending from 0 to a phase-typical peak. Mirrors the
        // web preview: PULL → ~86 lb peak, RETURN → ~120 lb, anything else
        // → small dim teal up-tick (~60 lb).
        let phasePeak: Double = {
            switch idlePhase {
            case .pull:   return 86
            case .return: return 120
            default:      return 60
            }
        }()

        let n = 5
        let pts: [CGPoint] = (0..<n).map { i in
            let force = (Double(i) / Double(n - 1)) * phasePeak
            // Sparse: i / 28 of (w - 2*pad) — anchors leftmost ~14% of chart
            let x = pad + CGFloat(i) / 28.0 * (w - 2 * pad)
            let y = h - pad - CGFloat(force / maxFCeiling) * (h - 2 * pad - 8)
            return CGPoint(x: x, y: y)
        }

        let color = VoltraColor.phase(idlePhase)

        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(
            color,
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        // Tip dot
        if let tip = pts.last {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .position(x: tip.x, y: tip.y)
        }
    }

    // MARK: - Mode 1 — active phase-segmented chart

    @ViewBuilder
    private func activeChart(samples: [ForceSample], width w: CGFloat, height h: CGFloat) -> some View {
        // Use the last 30 seconds of samples. Use peakLb (caller-supplied)
        // OR samples' max OR maxFCeiling — whichever is largest — to pick
        // the y-axis denominator so spikes fit.
        let now = samples.last?.timestamp ?? Date()
        let windowStart = now.addingTimeInterval(-30)
        let recent = samples.filter { $0.timestamp >= windowStart }
        let denom = max(maxFCeiling, max(peakLb, recent.map { $0.forceLb }.max() ?? 0))

        // Map each sample to (x, y, phase). x is normalized over the 30s
        // window so the chart always feels like it's scrolling left.
        let pts: [(x: CGFloat, y: CGFloat, phase: VoltraPhase)] = recent.map { s in
            let dt = max(0, min(30, s.timestamp.timeIntervalSince(windowStart)))
            let nx = CGFloat(dt / 30)
            let x = pad + nx * (w - 2 * pad)
            let y = h - pad - CGFloat(s.forceLb / denom) * (h - 2 * pad - 8)
            return (x, y, s.phase)
        }

        // Phase-segmented runs. Each transition starts a new segment but
        // includes the boundary point in BOTH segments so the line stays
        // continuous (no gap between teal and orange runs).
        let segments: [(phase: VoltraPhase, points: [CGPoint])] = {
            guard let first = pts.first else { return [] }
            var out: [(VoltraPhase, [CGPoint])] = []
            var curPhase = first.phase
            var curPoints: [CGPoint] = [CGPoint(x: first.x, y: first.y)]
            for i in 1..<pts.count {
                let p = pts[i]
                if p.phase != curPhase {
                    // close current segment with the boundary point
                    curPoints.append(CGPoint(x: p.x, y: p.y))
                    out.append((curPhase, curPoints))
                    curPhase = p.phase
                    curPoints = [CGPoint(x: p.x, y: p.y)]
                } else {
                    curPoints.append(CGPoint(x: p.x, y: p.y))
                }
            }
            out.append((curPhase, curPoints))
            return out
        }()

        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
            Path { p in
                guard let first = seg.points.first else { return }
                p.move(to: first)
                for pt in seg.points.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(
                VoltraColor.phase(seg.phase),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }

        if let tip = pts.last {
            Circle()
                .fill(VoltraColor.phase(tip.phase))
                .frame(width: 7, height: 7)
                .position(x: tip.x, y: tip.y)
        }
    }
}

#if DEBUG
#Preview("Force chart — idle PULL") {
    ForceChartV2(samples: [], peakLb: 0, resting: false, idlePhase: .pull)
        .frame(width: 361, height: 175)
        .background(VoltraColor.bgElev)
}

#Preview("Force chart — resting (empty)") {
    ForceChartV2(samples: [], peakLb: 0, resting: true, idlePhase: .idle)
        .frame(width: 361, height: 175)
        .background(VoltraColor.bgElev)
}
#endif
