// TileView.swift
// Reusable big-number tile: label, large value, optional unit.
// Designed for 8-foot readability on a rack-mounted iPad.

import SwiftUI

struct TileView: View {
    let label: String
    let value: String
    var unit: String? = nil
    var sub: String? = nil
    var valueColor: Color = VoltraColor.text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .kerning(2.0)
                .foregroundColor(VoltraColor.textDim)
                .textCase(.uppercase)

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: dynamicSize, weight: .bold, design: .monospaced))
                    .foregroundColor(valueColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                if let unit {
                    Text(unit)
                        .font(.system(size: dynamicSize * 0.36, weight: .medium, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                        .padding(.leading, 6)
                        .lineLimit(1)
                }
            }

            if let sub {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textDim)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Scale value font size with horizontal size class (iPad gets larger numbers)
    @ScaledMetric(relativeTo: .largeTitle) private var dynamicSize: CGFloat = 72
}

#Preview {
    HStack {
        TileView(label: "REPS", value: "12", valueColor: VoltraColor.text)
        TileView(label: "FORCE", value: "127.4", unit: "lb", valueColor: VoltraColor.accent)
    }
    .frame(height: 170)
    .padding()
    .background(VoltraColor.bg)
}
