// ForceChartView.swift
// Swift Charts line chart with phase-colored segments.
// v0.4.5: chart now spans the entire set (no 30s rolling window) so the user
// can review the full waveform after finishing. The X domain is anchored to
// the first/last sample timestamps. 5 horizontal grid lines with lb labels.
// Phase colors: pull=#00d4aa, return=#ffb84d, transition=#6c8de0, idle=#4a5f5b

import SwiftUI
import Charts

// Each plotted point carries its phase for coloring
struct ChartPoint: Identifiable {
    let id: Int           // absolute sample index — unique per session
    let timestamp: Date
    let forceLb: Double
    let phase: VoltraPhase
    let segmentIndex: Int // groups contiguous same-phase runs
}

struct ForceChartView: View {
    let samples: [ForceSample]
    let peakLb: Double

    /// v0.4.4: When provided, the Y-axis ceiling is anchored to the planned
    /// total weight (Voltra base + eccentric + added plates) plus 15% headroom.
    /// This keeps the waveform from looking tiny when the user lifts a small
    /// weight — e.g. 5 lb base + 5 ecc no longer scales against a 40 lb floor.
    /// If the user's actual peak exceeds the planned ceiling, the chart still
    /// expands to fit. Pass nil from contexts that don't know the planned
    /// weight (e.g. DashboardView) to preserve the prior 40 lb floor behavior.
    var plannedCeilingLb: Double? = nil

    /// v0.4.6: Pulley mode. When the cable runs through a pulley, the user
    /// feels 2× the cable force, but the device still reports the cable
    /// force. Multiply incoming sample forces by this to display EFFECTIVE
    /// load. Default 1.0 = no transform.
    var forceMultiplier: Double = 1.0

    private var now: Date { Date() }

    /// v0.4.5: All samples are visible — no 30s cutoff. The chart auto-spans
    /// the entire set so the user can review the full rep pattern.
    private var visibleSamples: [ForceSample] {
        samples
    }

    private var maxForce: Double {
        let maxVisible = smoothedSamples.map(\.forceLb).max() ?? 0
        if let planned = plannedCeilingLb, planned > 0 {
            // Planned-weight + 15% headroom OR observed peak + 15% headroom,
            // whichever is greater — so a strong overshoot doesn't clip the
            // waveform. Floor at 12 lb so an empty chart still has a sane
            // axis (smaller floor than the dashboard since planned-anchored
            // mode is used inside a session with light loads).
            return max(12, planned * 1.15, maxVisible * 1.15)
        }
        // Legacy behavior for callers that don't pass a planned ceiling.
        return max(40, maxVisible) * 1.1
    }

    /// v0.4.6: 3-sample moving average smoothing applied to the visible
    /// samples and their force values are pre-multiplied by `forceMultiplier`
    /// so the chart shows EFFECTIVE load (matters for pulley mode). Phase +
    /// timestamp are passed through unchanged.
    private var smoothedSamples: [ForceSample] {
        let m = forceMultiplier
        let raw = visibleSamples
        guard !raw.isEmpty else { return [] }
        if raw.count == 1 {
            let s = raw[0]
            return [ForceSample(timestamp: s.timestamp, forceLb: s.forceLb * m, phase: s.phase)]
        }
        var out: [ForceSample] = []
        out.reserveCapacity(raw.count)
        for i in 0..<raw.count {
            let lo = max(0, i - 1)
            let hi = min(raw.count - 1, i + 1)
            var sum = 0.0
            var n = 0
            for j in lo...hi { sum += raw[j].forceLb; n += 1 }
            let avg = n > 0 ? sum / Double(n) : raw[i].forceLb
            out.append(ForceSample(
                timestamp: raw[i].timestamp,
                forceLb: avg * m,
                phase: raw[i].phase
            ))
        }
        return out
    }

    // Build chart points with segment grouping for phase-colored segments
    private var chartPoints: [ChartPoint] {
        let src = smoothedSamples
        guard !src.isEmpty else { return [] }
        var points = [ChartPoint]()
        var segIdx = 0
        var lastPhase: VoltraPhase? = nil
        for (i, s) in src.enumerated() {
            if let lp = lastPhase, lp != s.phase { segIdx += 1 }
            points.append(ChartPoint(
                id: i,
                timestamp: s.timestamp,
                forceLb: s.forceLb,
                phase: s.phase,
                segmentIndex: segIdx
            ))
            lastPhase = s.phase
        }
        return points
    }

    // Grid line values (5 lines: 0%, 25%, 50%, 75%, 100% of maxForce)
    private var gridValues: [Double] {
        (0...4).map { Double($0) * maxForce / 4.0 }
    }

    // Group chart points by segment index
    private func segmentGroups() -> [(segIdx: Int, phase: VoltraPhase, pts: [ChartPoint])] {
        var result = [(Int, VoltraPhase, [ChartPoint])]()
        var currentPts = [ChartPoint]()
        var currentIdx = -1
        var currentPhase: VoltraPhase = .idle
        for pt in chartPoints {
            if pt.segmentIndex != currentIdx {
                if !currentPts.isEmpty {
                    result.append((currentIdx, currentPhase, currentPts))
                }
                currentPts = []
                currentIdx = pt.segmentIndex
                currentPhase = pt.phase
            }
            currentPts.append(pt)
        }
        if !currentPts.isEmpty { result.append((currentIdx, currentPhase, currentPts)) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chart header
            HStack(alignment: .firstTextBaseline) {
                Text("FORCE")
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                    .textCase(.uppercase)

                Spacer()

                // Legend
                HStack(spacing: 14) {
                    legendDot(color: VoltraColor.pull, label: "Pull")
                    legendDot(color: VoltraColor.returnPhase, label: "Return")
                    if peakLb > 0 {
                        Text("peak \(String(format: "%.1f", peakLb * forceMultiplier)) lb")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(VoltraColor.accent)
                    }
                }
                .font(.system(size: 12))
            }
            .padding(.bottom, 8)

            if smoothedSamples.isEmpty {
                // Empty state
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VoltraColor.bg)
                    Text("waiting for first rep…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                }
            } else {
                // v0.4.5: X domain spans the actual sample range (full set),
                // not a fixed 30s rolling window.
                let firstTS = smoothedSamples.first?.timestamp ?? now
                let lastTS = smoothedSamples.last?.timestamp ?? now
                let windowStart = firstTS
                // Guard against degenerate single-point ranges (Swift Charts
                // crashes if domain is empty). Also pad a small trailing
                // gutter so the most-recent sample isn't flush to the edge.
                let span = max(lastTS.timeIntervalSince(firstTS), 1.0)
                let windowEnd = firstTS.addingTimeInterval(span + span * 0.04)

                Chart {
                    // Horizontal grid lines
                    ForEach(gridValues, id: \.self) { val in
                        RuleMark(y: .value("Force", val))
                            .foregroundStyle(VoltraColor.border)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }

                    // Phase-colored line segments
                    // Each segment group is rendered as its own LineMark series
                    ForEach(segmentGroups(), id: \.segIdx) { seg in
                        ForEach(seg.pts) { pt in
                            LineMark(
                                x: .value("Time", pt.timestamp),
                                y: .value("Force (lb)", pt.forceLb),
                                series: .value("Segment", seg.segIdx)
                            )
                            .foregroundStyle(VoltraColor.phase(seg.phase))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .chartYScale(domain: 0...maxForce)
                .chartXScale(domain: windowStart...windowEnd)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: gridValues) { value in
                        AxisGridLine()
                            .foregroundStyle(VoltraColor.border)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v)) lb")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(VoltraColor.textFaint)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartBackground { _ in
                    VoltraColor.bg
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 12, trailing: 18))
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(VoltraColor.textDim)
        }
    }
}

#Preview {
    let now = Date()
    let samples = (0..<100).map { i -> ForceSample in
        let t = now.addingTimeInterval(Double(i) * 0.3 - 30)
        let phase: VoltraPhase = i < 30 ? .pull : (i < 60 ? .return : .idle)
        let f: Double = phase == .pull ? 80 + Double(i % 20) : (phase == .return ? 40 + Double(i % 10) : 2)
        return ForceSample(timestamp: t, forceLb: f, phase: phase)
    }
    return ForceChartView(samples: samples, peakLb: 98.3)
        .frame(height: 260)
        .padding()
        .background(VoltraColor.bg)
}
