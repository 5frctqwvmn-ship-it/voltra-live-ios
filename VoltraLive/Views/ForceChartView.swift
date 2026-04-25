// ForceChartView.swift
// Swift Charts line chart with phase-colored segments, last 30s rolling window.
// 5 horizontal grid lines with lb labels.
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

    private var now: Date { Date() }

    private var visibleSamples: [ForceSample] {
        let cutoff = now.addingTimeInterval(-30)
        return samples.filter { $0.timestamp >= cutoff }
    }

    private var maxForce: Double {
        let maxVisible = visibleSamples.map(\.forceLb).max() ?? 0
        return max(40, maxVisible) * 1.1
    }

    // Build chart points with segment grouping for phase-colored segments
    private var chartPoints: [ChartPoint] {
        guard !visibleSamples.isEmpty else { return [] }
        var points = [ChartPoint]()
        var segIdx = 0
        var lastPhase: VoltraPhase? = nil
        for (i, s) in visibleSamples.enumerated() {
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
                Text("FORCE — 30s")
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
                        Text("peak \(String(format: "%.1f", peakLb)) lb")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(VoltraColor.accent)
                    }
                }
                .font(.system(size: 12))
            }
            .padding(.bottom, 8)

            if visibleSamples.isEmpty {
                // Empty state
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VoltraColor.bg)
                    Text("waiting for first rep…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                }
            } else {
                let windowStart = now.addingTimeInterval(-30)

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
                .chartXScale(domain: windowStart...now)
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
