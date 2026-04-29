// ForceChartV2.swift
//
// b58 V4 §1 — Tonal-style force-curve rendering.
//
//   - Dual-band ECC / CON: each rep polyline is now also stroked as a
//     filled gradient under the curve. The eccentric segment fills DOWN
//     to BOTTOM with a stronger gradient (bottom-anchored, deeper alpha)
//     to visually emphasize lowering work; the concentric segment fills
//     as a thinner band. This matches Tonal's "rep map" where the down-
//     phase reads heavier than the up-phase.
//   - CHAIN mirrored gradient: when CHAIN is engaged the gradient flips
//     for the rep — heaviest reading at top of ROM (right-side of the
//     normalized x-axis) instead of bottom — to communicate that load
//     accumulates as the cable extends. Implemented by reversing the
//     gradient stops on the eccentric fill.
//   - ECC / CON inline labels: the most-recent rep gets two small kerned
//     captions ("ECC" / "CON") placed at the centroid of each phase
//     segment, in phase color at 70% opacity. Suppressed for older reps
//     so the chart doesn't turn into noise. Suppressed entirely if the
//     rep doesn't actually contain both phases.
//
// b57 V3 — UI Layout V3 force-curve rewrite (§1 + §1a) carried forward:
//
// THREE rendering modes (same as b56):
//
//   1. ACTIVE — `samples` non-empty, `resting == false`
//      Phase-segmented polylines. b57 §1a: instead of one 30s scrolling
//      polyline, the canvas now overlays ALL reps in the current set.
//      Each rep is sliced from the sample stream by phase-boundary
//      detection and re-mapped to the SAME 0..1 normalized x-axis so
//      they superimpose. The newest rep renders at full opacity in the
//      current phase color; older reps fade per
//        opacity = max(0.10, 1 / (1 + ln(repsAgo + 1)))
//      and are clipped at 8 visible reps. Pattern follows Tonal's
//      "set-history overlay" — fatigue shows up as shape decay across
//      reps. Falls back to a single polyline if the slicer can't find
//      rep boundaries (e.g. one continuous pull).
//
//   2. RESTING — `resting == true`
//      Empty chart. Only the dashed BOTTOM marker line + label. The
//      rep-history stack is implicitly cleared because `samples` will
//      be the post-finalize buffer (lastFinalizedSamples) and the next
//      set start clears it.
//
//   3. IDLE-NO-DATA — `resting == false` and `samples` empty
//      Sparse 5-sample ramp from x≈0 up to ~14% of the chart width,
//      anchored to BOTTOM, colored by `idlePhase`.
//
// b57 §1: Y-axis is now driven by `yAxisMaxLb` from the parent and a
// 1.5s ease replaces the b56 0.35s rescale. Parent computes
//   yMax = max(working, working+ECC, working+CHAIN) × 1.2  (floor 60)
// so eccentric or chain-add never clips. The longer ease prevents
// "breathing" between reps.
//
// IMPORTANT — sacred-files boundary: this view is read-only on the
// telemetry stream. It does NOT mutate samples, does NOT call into
// VoltraProtocol / TelemetryExtractor / PacketParser / FrameAssembler.
// It just renders whatever `samples` the caller hands it.

import SwiftUI
import Foundation

struct ForceChartV2: View {

    // MARK: Inputs

    /// Live force samples for the current set, or `lastFinalizedSamples`
    /// if no live set is in progress. May be empty.
    let samples: [ForceSample]

    /// Peak force seen in this set (used to scale the y-axis if it
    /// exceeds `yAxisMaxLb`).
    let peakLb: Double

    /// True when a rest window is engaged (post-finalize). When true, we
    /// render the empty-rest variant (BOTTOM marker only).
    let resting: Bool

    /// Phase to use for the synthetic idle up-tick when `samples` is empty
    /// and we're not resting. Typically `ble.telemetry.phase`.
    let idlePhase: VoltraPhase

    /// b57 §1: Y-axis ceiling in lb, supplied by the parent. Drives the
    /// active-mode polyline scaling AND the idle-ramp scaling so both
    /// modes share the same vertical reference. Parent computes this as
    /// `max(working, working+ECC, working+CHAIN) × 1.2` with a 60 lb
    /// floor for headroom on light loads.
    let yAxisMaxLb: Double

    /// b58 V4 §1: when true, the force curve renders the ECC fill band.
    /// Driven by the parent's `eccArmed` so the dual-band only appears
    /// when the user has actually engaged eccentric mode for the set.
    let eccBandActive: Bool

    /// b58 V4 §1: when true, the gradient under the curve is MIRRORED
    /// (heaviest at top of ROM / right side of the normalized x-axis).
    /// Driven by the parent's `chainArmed`.
    let chainMirrorActive: Bool

    init(
        samples: [ForceSample],
        peakLb: Double,
        resting: Bool,
        idlePhase: VoltraPhase,
        yAxisMaxLb: Double = 160,
        eccBandActive: Bool = false,
        chainMirrorActive: Bool = false
    ) {
        self.samples = samples
        self.peakLb = peakLb
        self.resting = resting
        self.idlePhase = idlePhase
        self.yAxisMaxLb = yAxisMaxLb
        self.eccBandActive = eccBandActive
        self.chainMirrorActive = chainMirrorActive
    }

    // MARK: Tunables

    /// Defensive floor for the y-axis denominator — ensures an unloaded
    /// preview / idle screen still draws within sensible bounds.
    private let minYDenom: Double = 60

    /// Inner padding inside the SVG-equivalent viewBox.
    private let pad: CGFloat = 8

    /// Fixed drawing height to match the preview (h = 175). Width is
    /// inherited from the parent via a GeometryReader.
    private let canvasHeight: CGFloat = 175

    /// Max number of overlaid reps. Past this they blend into noise.
    private let repOverlayCap: Int = 8

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = canvasHeight
            ZStack(alignment: .topLeading) {
                // b57 §1: smoother y-axis rescale (1.5s ease) so the
                // chart doesn't "breathe" between reps when ECC nudges
                // the ceiling up/down within a set.
                Color.clear
                    .animation(.easeInOut(duration: 1.5), value: yAxisMaxLb)
                // BOTTOM dashed marker (always present, all three modes)
                bottomMarker(width: w, height: h)

                if resting {
                    // mode 2: empty resting chart — nothing else to draw
                    EmptyView()
                } else if samples.isEmpty {
                    // mode 3: synthetic idle ramp (5 samples, leftmost ~14% of width)
                    idleRamp(width: w, height: h)
                } else {
                    // mode 1: rep-history overlay (b57 §1a)
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
        // 5 samples ascending from 0 to a phase-typical peak.
        let phasePeak: Double = {
            switch idlePhase {
            case .pull:   return 86
            case .return: return 120
            default:      return 60
            }
        }()

        let n = 5
        // b57 §1: scale the idle ramp against the SAME y-axis the active
        // mode uses (yAxisMaxLb), with the defensive floor.
        let denom = max(minYDenom, yAxisMaxLb)
        let pts: [CGPoint] = (0..<n).map { i in
            let force = (Double(i) / Double(n - 1)) * phasePeak
            // Sparse: i / 28 of (w - 2*pad) — anchors leftmost ~14% of chart
            let x = pad + CGFloat(i) / 28.0 * (w - 2 * pad)
            let y = h - pad - CGFloat(force / denom) * (h - 2 * pad - 8)
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

    // MARK: - Mode 1 — active rep-history overlay (b57 §1a)

    @ViewBuilder
    private func activeChart(samples: [ForceSample], width w: CGFloat, height h: CGFloat) -> some View {
        // Y-axis denominator: parent-supplied yAxisMaxLb is the primary
        // driver. We still floor at the defensive minimum and ceiling-
        // bump for transient spikes above the planned ceiling.
        let observed = max(peakLb, samples.map { $0.forceLb }.max() ?? 0)
        let denom = max(max(minYDenom, yAxisMaxLb), observed)

        // Slice samples into reps by phase boundaries. A "rep" is the
        // span between two consecutive starts of pull/return after an
        // idle gap. Newest rep is the last entry.
        let reps = sliceIntoReps(samples)

        if reps.isEmpty {
            // Fallback: single continuous polyline of the whole sample
            // buffer mapped to 0..1 across the canvas. Keeps the chart
            // alive when the slicer can't find rep boundaries (e.g. one
            // long isometric hold).
            singlePolyline(samples: samples, width: w, height: h, denom: denom)
        } else {
            // Render up to repOverlayCap reps, oldest first so newest
            // ends up on top in z-order.
            let visible = Array(reps.suffix(repOverlayCap))
            ForEach(Array(visible.enumerated()), id: \.offset) { idx, rep in
                let repsAgo = visible.count - 1 - idx
                let opacity = fadeOpacity(repsAgo: repsAgo)
                // b58 V4 §1: dual-band fill under the curve, drawn FIRST
                // (z-below the polyline). Only the most-recent rep gets
                // the full-strength fill — older reps fade just like the
                // polyline. ECC band is conditional on the parent flag
                // so the chart stays clean for working-only sets.
                if eccBandActive {
                    eccConFill(
                        rep: rep,
                        width: w,
                        height: h,
                        denom: denom,
                        opacity: opacity * 0.55,
                        chainMirror: chainMirrorActive
                    )
                }
                repPolyline(rep: rep, width: w, height: h, denom: denom, opacity: opacity)
                // b58 V4 §1: ECC / CON inline labels on the most recent
                // rep ONLY (repsAgo == 0). Drawn last so they sit on top
                // of every other layer.
                if repsAgo == 0 {
                    inlinePhaseLabels(
                        rep: rep, width: w, height: h, denom: denom
                    )
                }
            }

            // Tip dot — pinned to the most recent sample of the most
            // recent rep, in current phase color. Anchors the eye.
            if let last = visible.last,
               let tip  = last.last {
                let nx = normalizedX(rep: last, sample: tip)
                let x = pad + CGFloat(nx) * (w - 2 * pad)
                let y = h - pad - CGFloat(tip.forceLb / denom) * (h - 2 * pad - 8)
                Circle()
                    .fill(VoltraColor.phase(tip.phase))
                    .frame(width: 7, height: 7)
                    .position(x: x, y: y)
            }
        }
    }

    // MARK: - b58 V4 §1: Tonal-style dual-band ECC/CON fill

    /// Renders a filled gradient band under the rep polyline, segmented by
    /// phase. The eccentric segment fills DOWN to BOTTOM with a deeper
    /// gradient; the concentric segment fills as a thinner top-anchored
    /// band. When `chainMirror` is true the gradient stops are reversed
    /// so the visual weight reads heaviest at top-of-ROM (right side of
    /// the normalized x-axis) — communicates that chain load builds as
    /// the cable extends.
    @ViewBuilder
    private func eccConFill(
        rep: [ForceSample],
        width w: CGFloat,
        height h: CGFloat,
        denom: Double,
        opacity: Double,
        chainMirror: Bool
    ) -> some View {
        let pts: [(x: CGFloat, y: CGFloat, phase: VoltraPhase)] = rep.map { s in
            let nx = normalizedX(rep: rep, sample: s)
            let x = pad + CGFloat(nx) * (w - 2 * pad)
            let y = h - pad - CGFloat(s.forceLb / denom) * (h - 2 * pad - 8)
            return (x, y, s.phase)
        }
        let segments = phaseSegment(points: pts)
        let baselineY = h - pad

        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
            let isEcc = (seg.phase == .return)   // VoltraPhase.return = lowering / eccentric
            let isCon = (seg.phase == .pull)     // VoltraPhase.pull  = lifting / concentric
            // Skip idle segments — no fill for between-rep idle pauses.
            if isEcc || isCon {
                Path { p in
                    guard let first = seg.points.first,
                          let last  = seg.points.last else { return }
                    p.move(to: CGPoint(x: first.x, y: baselineY))
                    p.addLine(to: CGPoint(x: first.x, y: first.y))
                    for pt in seg.points.dropFirst() {
                        p.addLine(to: pt)
                    }
                    p.addLine(to: CGPoint(x: last.x, y: baselineY))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: gradientStops(
                            for: seg.phase,
                            opacity: opacity,
                            isEcc: isEcc,
                            isCon: isCon
                        ),
                        startPoint: chainMirror ? .topTrailing : .top,
                        endPoint:   chainMirror ? .bottomLeading : .bottom
                    )
                )
            }
        }
    }

    /// Build the per-phase gradient. ECC = stronger fill (top stop ≈ 0.55
    /// of opacity), CON = thinner fill (top stop ≈ 0.22 of opacity). Both
    /// fade to ~0.04 at baseline so the BOTTOM marker stays legible.
    private func gradientStops(
        for phase: VoltraPhase,
        opacity: Double,
        isEcc: Bool,
        isCon: Bool
    ) -> Gradient {
        let color = VoltraColor.phase(phase)
        let topAlpha:    Double = isEcc ? 0.55 : (isCon ? 0.22 : 0.10)
        let bottomAlpha: Double = 0.04
        return Gradient(stops: [
            .init(color: color.opacity(topAlpha    * opacity), location: 0.0),
            .init(color: color.opacity(bottomAlpha * opacity), location: 1.0)
        ])
    }

    /// b58 V4 §1: inline ECC / CON kerned captions placed at the centroid
    /// of each phase segment of the most-recent rep. Suppressed if the rep
    /// doesn't contain both phases (avoids a lonely "ECC" hovering over a
    /// pull-only rep).
    @ViewBuilder
    private func inlinePhaseLabels(
        rep: [ForceSample],
        width w: CGFloat,
        height h: CGFloat,
        denom: Double
    ) -> some View {
        let hasPull   = rep.contains { $0.phase == .pull }
        let hasReturn = rep.contains { $0.phase == .return }
        if hasPull && hasReturn {
            ZStack {
                if let pos = phaseCentroid(rep: rep, width: w, height: h, denom: denom, phase: .pull) {
                    Text("CON")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .kerning(1.6)
                        .foregroundColor(VoltraColor.phase(.pull).opacity(0.7))
                        .position(x: pos.x, y: max(12, pos.y - 12))
                }
                if let pos = phaseCentroid(rep: rep, width: w, height: h, denom: denom, phase: .return) {
                    Text("ECC")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .kerning(1.6)
                        .foregroundColor(VoltraColor.phase(.return).opacity(0.7))
                        .position(x: pos.x, y: max(12, pos.y - 12))
                }
            }
        }
    }

    /// Centroid (mean x, mean y) of all samples in a rep matching the
    /// supplied phase. nil when no matching samples exist.
    private func phaseCentroid(
        rep: [ForceSample],
        width w: CGFloat,
        height h: CGFloat,
        denom: Double,
        phase: VoltraPhase
    ) -> CGPoint? {
        let matching = rep.filter { $0.phase == phase }
        guard !matching.isEmpty else { return nil }
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for s in matching {
            let nx = normalizedX(rep: rep, sample: s)
            sx += pad + CGFloat(nx) * (w - 2 * pad)
            sy += h - pad - CGFloat(s.forceLb / denom) * (h - 2 * pad - 8)
        }
        let n = CGFloat(matching.count)
        return CGPoint(x: sx / n, y: sy / n)
    }

    /// b57 §1a: opacity = max(0.10, 1 / (1 + ln(repsAgo + 1))).
    /// repsAgo == 0 → 1.0 (newest, full opacity)
    /// repsAgo == 1 → 1 / (1 + ln(2)) ≈ 0.59
    /// repsAgo == 4 → 1 / (1 + ln(5)) ≈ 0.38
    /// repsAgo == 7 → 1 / (1 + ln(8)) ≈ 0.32
    /// Clamped at 0.10 so deepest history is still faintly visible.
    private func fadeOpacity(repsAgo: Int) -> Double {
        guard repsAgo > 0 else { return 1.0 }
        let raw = 1.0 / (1.0 + log(Double(repsAgo + 1)))
        return max(0.10, raw)
    }

    /// Sliced reps. Each entry is a `[ForceSample]` containing the samples
    /// for that rep, in chronological order. A new rep starts when the
    /// phase transitions from idle (or a long gap) into pull/return AND
    /// the prior rep saw at least one non-idle sample. Returns at most
    /// the most recent ~12 reps to bound work.
    private func sliceIntoReps(_ samples: [ForceSample]) -> [[ForceSample]] {
        guard !samples.isEmpty else { return [] }
        var out: [[ForceSample]] = []
        var cur: [ForceSample] = []
        var curHasWork: Bool = false   // true when current rep has seen pull/return
        var lastWasIdle: Bool = true

        for s in samples {
            let isIdle = (s.phase == .idle)
            let isWork = (s.phase == .pull || s.phase == .return)
            // Boundary: idle → working transition AND current rep already
            // has some work in it. Cut here.
            if lastWasIdle && isWork && curHasWork {
                out.append(cur)
                cur = []
                curHasWork = false
            }
            cur.append(s)
            if isWork { curHasWork = true }
            lastWasIdle = isIdle
        }
        if !cur.isEmpty { out.append(cur) }
        // Bound: only keep the last 12 (we'll show up to 8).
        if out.count > 12 { out = Array(out.suffix(12)) }
        return out
    }

    /// Map a sample within a rep to a normalized x ∈ [0, 1] over the rep's
    /// own duration. If the rep has only one sample, returns 0.
    private func normalizedX(rep: [ForceSample], sample: ForceSample) -> Double {
        guard let first = rep.first?.timestamp,
              let last  = rep.last?.timestamp,
              last > first else { return 0 }
        let span = last.timeIntervalSince(first)
        let dt   = sample.timestamp.timeIntervalSince(first)
        return max(0, min(1, dt / span))
    }

    /// Render one rep's polyline with phase-segmented coloring and the
    /// supplied opacity. Same phase-segmentation logic as the b56
    /// activeChart, but now over the rep's normalized 0..1 x-axis.
    @ViewBuilder
    private func repPolyline(rep: [ForceSample], width w: CGFloat, height h: CGFloat, denom: Double, opacity: Double) -> some View {
        let pts: [(x: CGFloat, y: CGFloat, phase: VoltraPhase)] = rep.map { s in
            let nx = normalizedX(rep: rep, sample: s)
            let x = pad + CGFloat(nx) * (w - 2 * pad)
            let y = h - pad - CGFloat(s.forceLb / denom) * (h - 2 * pad - 8)
            return (x, y, s.phase)
        }
        let segments = phaseSegment(points: pts)
        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
            Path { p in
                guard let first = seg.points.first else { return }
                p.move(to: first)
                for pt in seg.points.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(
                VoltraColor.phase(seg.phase).opacity(opacity),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Fallback when slicer returns nothing — render the whole sample
    /// buffer as a single 30s-window polyline (matches b56 behavior).
    @ViewBuilder
    private func singlePolyline(samples: [ForceSample], width w: CGFloat, height h: CGFloat, denom: Double) -> some View {
        let now = samples.last?.timestamp ?? Date()
        let windowStart = now.addingTimeInterval(-30)
        let recent = samples.filter { $0.timestamp >= windowStart }
        let pts: [(x: CGFloat, y: CGFloat, phase: VoltraPhase)] = recent.map { s in
            let dt = max(0, min(30, s.timestamp.timeIntervalSince(windowStart)))
            let nx = CGFloat(dt / 30)
            let x = pad + nx * (w - 2 * pad)
            let y = h - pad - CGFloat(s.forceLb / denom) * (h - 2 * pad - 8)
            return (x, y, s.phase)
        }
        let segments = phaseSegment(points: pts)
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

    /// Group consecutive same-phase points into runs. Each run includes
    /// the boundary point in BOTH segments so the line stays continuous
    /// (no visual gap between teal and orange runs).
    private func phaseSegment(points: [(x: CGFloat, y: CGFloat, phase: VoltraPhase)]) -> [(phase: VoltraPhase, points: [CGPoint])] {
        guard let first = points.first else { return [] }
        var out: [(VoltraPhase, [CGPoint])] = []
        var curPhase = first.phase
        var curPoints: [CGPoint] = [CGPoint(x: first.x, y: first.y)]
        for i in 1..<points.count {
            let p = points[i]
            if p.phase != curPhase {
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
