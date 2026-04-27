// ProgressChartView.swift
// v0.4.0 — per-exercise progress chart shown on ExerciseDetailView, above the
// mode controls.
//
// Spec (synthesized from progress-chart-research.md):
//   - Type:           line chart with gradient area fill
//   - X axis:         calendar-time (true elapsed time between sessions)
//   - Y axis:         weight, auto-scaled with ~12% top padding
//   - Default metric: top-set weight per session
//   - Toggles:        Top Weight | Est. 1RM | Volume | Reps
//   - Time range:     1M | 3M | 1Y | All — default 3M
//   - Interaction:    chartXSelection drag scrubber + floating callout tooltip
//                     showing date / weight / reps / mode
//   - PR markers:     gold filled point (1.6× normal) on any session that set
//                     an all-time top-weight PR within the visible series
//   - Trend chip:     "+12 lb in 30 days" green up / orange-red down,
//                     suppressed if <3 sessions in range
//   - Empty state:    ghosted hypothetical line + "Your first session will
//                     appear here" overlay
//   - Visual:         dark-mode native, accent line, accent gradient fill,
//                     gold PR dots, subtle bgElev2 chart background
//
// We deliberately read directly from `LoggingStore.previousSetSeries` plus a
// `samplePoints()` fallback so this view shows something compelling even
// before the user has any real history. The fallback is opt-in via the
// `useSampleData` parameter — wired to true when the per-exercise series is
// empty so first-time users see the shape, not a dead screen.

import SwiftUI
import Charts

// MARK: - Public API

/// One data point on the chart. Built from a session's top set OR fabricated
/// in `samplePoints()` for the empty-state preview.
struct ProgressPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let topWeightLb: Double
    let topReps: Int
    let totalSets: Int
    let volumeLb: Double
    let estimated1RM: Double
    let modeLabel: String
    let isPR: Bool

    static func == (lhs: ProgressPoint, rhs: ProgressPoint) -> Bool { lhs.id == rhs.id }
}

enum ProgressMetric: String, CaseIterable, Identifiable {
    case topWeight  = "Top Weight"
    case oneRm      = "Est. 1RM"
    case volume     = "Volume"
    case reps       = "Reps"

    var id: String { rawValue }

    func value(for p: ProgressPoint) -> Double {
        switch self {
        case .topWeight: return p.topWeightLb
        case .oneRm:     return p.estimated1RM
        case .volume:    return p.volumeLb
        case .reps:      return Double(p.topReps)
        }
    }

    var unit: String {
        switch self {
        case .topWeight, .oneRm: return "lb"
        case .volume:            return "lb·reps"
        case .reps:              return "reps"
        }
    }
}

enum ProgressRange: String, CaseIterable, Identifiable {
    case oneMonth   = "1M"
    case threeMonth = "3M"
    case oneYear    = "1Y"
    case all        = "All"

    var id: String { rawValue }

    /// Days back from `Date()`. nil = all.
    var days: Int? {
        switch self {
        case .oneMonth:   return 30
        case .threeMonth: return 90
        case .oneYear:    return 365
        case .all:        return nil
        }
    }
}

// MARK: - View

struct ProgressChartView: View {
    /// Real per-session top-set series. Pass empty → sample preview shows.
    let series: [ProgressPoint]

    @State private var metric: ProgressMetric = .topWeight
    @State private var range: ProgressRange = .threeMonth
    @State private var selectedDate: Date? = nil

    /// v0.4.4: Sample data ONLY shows when there's truly no logged history at
    /// all — a brand-new exercise the user has never touched. Real exercises
    /// with history (even if all of it falls outside the default range) show
    /// real data with the range auto-promoted instead of leaking sample points.
    private var isSample: Bool { series.isEmpty }
    private var effectiveSeries: [ProgressPoint] {
        isSample ? Self.samplePoints() : series
    }

    /// v0.4.4: When real history exists but the currently-selected range
    /// happens to be empty (e.g. last logged set is 7 months old, default 3M),
    /// auto-promote to the smallest range that contains data. The user can
    /// still tap any range chip to override.
    private var effectiveRange: ProgressRange {
        if isSample { return range }
        let sortedReal = series.sorted { $0.date < $1.date }
        guard !sortedReal.isEmpty else { return range }
        // v0.4.6: Require ≥3 points in the candidate window before stopping
        // — a single dot (or two) renders as an empty-looking chart, so we'd
        // rather widen to a range that has enough history to draw a real
        // trendline. The user can still tap any range chip to override.
        let minPoints = 3
        let order: [ProgressRange] = [range, .oneMonth, .threeMonth, .oneYear, .all]
        for candidate in order {
            guard let days = candidate.days else { return .all }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let count = sortedReal.reduce(0) { $1.date >= cutoff ? $0 + 1 : $0 }
            if count >= minPoints {
                return candidate
            }
        }
        return .all
    }

    private var visiblePoints: [ProgressPoint] {
        let sorted = effectiveSeries.sorted { $0.date < $1.date }
        guard let days = effectiveRange.days else { return sorted }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sorted.filter { $0.date >= cutoff }
    }

    private var selectedPoint: ProgressPoint? {
        guard let d = selectedDate else { return nil }
        return visiblePoints.min(by: {
            abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chart
            metricToggles
            rangeToggles
            if isSample { sampleBadge }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Header (title + trend chip)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PROGRESS")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
                Text(metric.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VoltraColor.text)
            }
            Spacer()
            trendChip
        }
    }

    private var trendChip: some View {
        // v0.4.4: Don't render a trend on synthetic sample data — it's
        // misleading on a brand-new exercise.
        let pts = visiblePoints
        guard !isSample,
              pts.count >= 3,
              let first = pts.first,
              let last = pts.last
        else {
            return AnyView(EmptyView())
        }
        let first30 = Calendar.current.date(byAdding: .day, value: -30, to: last.date) ?? first.date
        let baseline = pts.last(where: { $0.date <= first30 }) ?? first
        let delta = metric.value(for: last) - metric.value(for: baseline)
        let absStr = formatNum(abs(delta))
        let up = delta >= 0
        let color = up ? VoltraColor.accent : VoltraColor.warn
        let arrow = up ? "arrow.up.right" : "arrow.down.right"
        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: arrow).font(.system(size: 10, weight: .bold))
                Text("\(up ? "+" : "−")\(absStr) \(metric.unit) · 30d")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
        )
    }

    // MARK: Chart

    private var chart: some View {
        let pts = visiblePoints
        return Chart {
            // Gradient area fill below the line — gives the chart visual weight
            // even with sparse data.
            ForEach(pts) { p in
                AreaMark(
                    x: .value("Date", p.date),
                    y: .value(metric.rawValue, metric.value(for: p))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [VoltraColor.accent.opacity(0.35), VoltraColor.accent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
            ForEach(pts) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value(metric.rawValue, metric.value(for: p))
                )
                .foregroundStyle(VoltraColor.accent)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(pts) { p in
                PointMark(
                    x: .value("Date", p.date),
                    y: .value(metric.rawValue, metric.value(for: p))
                )
                .foregroundStyle(p.isPR ? Color(hex: "#FFD166") : VoltraColor.accent)
                .symbolSize(p.isPR ? 90 : 36)
            }
            // Scrub crosshair
            if let sel = selectedPoint {
                RuleMark(x: .value("Selected", sel.date))
                    .foregroundStyle(VoltraColor.textDim.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Selected", sel.date),
                    y: .value(metric.rawValue, metric.value(for: sel))
                )
                .foregroundStyle(.white)
                .symbolSize(60)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(VoltraColor.border)
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(VoltraColor.textFaint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(VoltraColor.border.opacity(0.5))
                AxisValueLabel(horizontalSpacing: 6)
                    .font(.system(size: 10))
                    .foregroundStyle(VoltraColor.textFaint)
            }
        }
        .chartXSelection(value: $selectedDate)
        // Reserve room on the leading edge so 3-digit Y-axis labels (e.g. "300")
        // never clip on narrower iPhones. Trailing/top padding keeps the
        // plot from kissing the rounded card border.
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
        }
        .padding(.leading, 8)
        .frame(height: 180)
        .background(VoltraColor.bgElev2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topLeading) {
            if let sel = selectedPoint {
                tooltip(for: sel)
                    .padding(8)
            } else if pts.isEmpty {
                emptyOverlay.padding(12)
            }
        }
    }

    private func tooltip(for p: ProgressPoint) -> some View {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return VStack(alignment: .leading, spacing: 2) {
            Text(df.string(from: p.date))
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .foregroundColor(VoltraColor.textDim)
            HStack(spacing: 6) {
                Text("\(formatNum(metric.value(for: p))) \(metric.unit)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
                if p.isPR {
                    Text("PR")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#FFD166"))
                        .foregroundColor(VoltraColor.bg)
                        .clipShape(Capsule())
                }
            }
            Text("\(p.totalSets) × \(p.topReps) reps · \(p.modeLabel)")
                .font(.system(size: 10))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(8)
        .background(VoltraColor.bg.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No history yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            Text("Your first set will plot here.")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textDim)
        }
    }

    // MARK: Toggles

    private var metricToggles: some View {
        HStack(spacing: 6) {
            ForEach(ProgressMetric.allCases) { m in
                Button { metric = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(metric == m ? VoltraColor.accent : VoltraColor.bgElev2)
                        .foregroundColor(metric == m ? VoltraColor.bg : VoltraColor.text)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(metric == m ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rangeToggles: some View {
        // v0.4.4: Highlight the *effective* range so the user can see at a
        // glance which range is actually showing data when auto-promotion
        // kicks in (e.g. they tap 3M but their only history is 7 mo. old
        // — the chart silently shows 1Y / All instead).
        let active = effectiveRange
        return HStack(spacing: 6) {
            ForEach(ProgressRange.allCases) { r in
                Button { range = r; selectedDate = nil } label: {
                    Text(r.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(active == r ? VoltraColor.bgElev2 : Color.clear)
                        .foregroundColor(active == r ? VoltraColor.text : VoltraColor.textDim)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(active == r ? VoltraColor.border : Color.clear, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sampleBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
            Text("SAMPLE DATA — log a set to see your real progress")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
        }
        .foregroundColor(VoltraColor.textFaint)
    }

    // MARK: Helpers

    private func formatNum(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%.1f", d)
    }
}

// MARK: - Sample data

extension ProgressChartView {
    /// Hand-crafted 12-week progression curve for the empty-state preview.
    /// Mostly upward with occasional dips and one PR a few weeks back, so the
    /// user sees the shape of a meaningful chart and the gold PR marker.
    static func samplePoints() -> [ProgressPoint] {
        let cal = Calendar.current
        let now = Date()
        // (daysAgo, weight, reps, sets, isPR)
        let raw: [(Int, Double, Int, Int, Bool)] = [
            (84, 135, 8, 3, false),
            (77, 140, 8, 3, false),
            (70, 145, 7, 3, false),
            (63, 145, 8, 3, false),
            (56, 150, 6, 4, false),
            (49, 150, 7, 4, false),
            (42, 155, 6, 4, true),   // PR
            (35, 150, 8, 4, false),
            (28, 155, 8, 4, false),
            (21, 160, 6, 4, true),   // PR
            (14, 160, 7, 4, false),
            (7,  165, 6, 4, true),   // PR (most recent)
        ]
        return raw.map { (days, w, reps, sets, pr) in
            let d = cal.date(byAdding: .day, value: -days, to: now) ?? now
            let oneRm: Double = {
                if reps <= 6 { return w / (1.0278 - 0.0278 * Double(reps)) }   // Brzycki
                return w * (1.0 + Double(reps) / 30.0)                          // Epley
            }()
            return ProgressPoint(
                date: d,
                topWeightLb: w,
                topReps: reps,
                totalSets: sets,
                volumeLb: w * Double(reps) * Double(sets),
                estimated1RM: oneRm,
                modeLabel: "Weight",
                isPR: pr
            )
        }
    }

    /// Build real points from a LoggingStore series (one per session).
    /// Each session contributes its top-weight set as the point.
    static func points(fromSeries series: [LoggedSet]) -> [ProgressPoint] {
        // Group by session.startedAt (one point per workout day).
        let bySession = Dictionary(grouping: series) { (s: LoggedSet) -> Date in
            s.instance?.session?.startedAt ?? s.completedAt
        }
        // Track all-time top weight to flag PRs in chronological order.
        let ordered = bySession.keys.sorted()
        var allTimeTop: Double = 0
        var out: [ProgressPoint] = []
        for date in ordered {
            let sets = bySession[date] ?? []
            guard let top = sets.max(by: { $0.weightLb < $1.weightLb }) else { continue }
            let isPR = top.weightLb > allTimeTop
            if isPR { allTimeTop = top.weightLb }
            let volume = sets.reduce(0.0) { $0 + $1.weightLb * Double($1.reps) }
            let reps = top.reps
            let oneRm: Double = {
                guard reps > 0 else { return top.weightLb }
                if reps <= 6 { return top.weightLb / (1.0278 - 0.0278 * Double(reps)) }
                return top.weightLb * (1.0 + Double(reps) / 30.0)
            }()
            out.append(ProgressPoint(
                date: date,
                topWeightLb: top.weightLb,
                topReps: reps,
                totalSets: sets.count,
                volumeLb: volume,
                estimated1RM: oneRm,
                modeLabel: top.mode.label,
                isPR: isPR
            ))
        }
        return out
    }
}

// Note: Color(hex:) is already declared in VoltraTheme.swift at module scope—
// we use that one for the gold PR dot here.

#Preview("With sample data") {
    ProgressChartView(series: [])
        .padding()
        .background(VoltraColor.bg)
}

#Preview("With real data") {
    ProgressChartView(series: ProgressChartView.samplePoints())
        .padding()
        .background(VoltraColor.bg)
}
