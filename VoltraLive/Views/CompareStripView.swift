// CompareStripView.swift
// Small bar showing this-set vs last-session same-index set comparison.
// 4 cells: last set reps, last set peak, session total reps, vs-last delta.

import SwiftUI

struct CompareStripView: View {
    @EnvironmentObject var session: SessionStore

    private var lastSet: CompletedSet? { session.lastCompletedSet }
    private var totalReps: Int { session.totalRepsThisSession }

    private var vsLastDelta: Int? {
        guard let prev = session.fetchLastPastSession() else { return nil }
        let prevTotal = prev.totalReps
        guard prevTotal > 0 else { return nil }
        return totalReps - prevTotal
    }

    var body: some View {
        HStack(spacing: 14) {
            compareCell(
                label: "LAST SET",
                value: lastSet.map { "\($0.reps)" } ?? "—"
            )
            compareCell(
                label: "PEAK",
                value: lastSet.map { String(format: "%.1f lb", $0.peakLb) } ?? "—"
            )
            compareCell(
                label: "SESSION",
                value: "\(totalReps)"
            )
            compareDeltaCell(delta: vsLastDelta)
        }
    }

    private func compareCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func compareDeltaCell(delta: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VS LAST")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
                .textCase(.uppercase)
                .lineLimit(1)

            Group {
                if let delta {
                    Text("\(delta >= 0 ? "+" : "")\(delta) reps")
                        .foregroundColor(delta > 0 ? VoltraColor.accent : delta < 0 ? VoltraColor.warn : VoltraColor.text)
                } else {
                    Text("—")
                        .foregroundColor(VoltraColor.text)
                }
            }
            .font(.system(size: 22, weight: .semibold, design: .monospaced))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    CompareStripView()
        .environmentObject(SessionStore())
        .padding()
        .background(VoltraColor.bg)
}
