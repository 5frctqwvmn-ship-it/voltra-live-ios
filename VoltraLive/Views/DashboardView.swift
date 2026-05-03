// DashboardView.swift
// Main workout dashboard: 4 tiles (REPS, PHASE, FORCE, REST) in adaptive grid,
// ForceChartView, CompareStripView.
// iPad landscape is primary use case — huge numbers readable from 8 feet.

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore

    @Environment(\.horizontalSizeClass) var hSizeClass
    @Environment(\.verticalSizeClass) var vSizeClass

    @State private var showHistory = false

    // iPad landscape: 4-wide grid; iPhone or portrait: 2-wide
    private var gridColumns: [GridItem] {
        let isLarge = hSizeClass == .regular
        let count = isLarge ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    private var live: LiveTelemetry { ble.telemetry }

    // Current-set samples for chart. v0.4.5: falls back to the last
    // finalized set so the trace persists through rest instead of blanking
    // when the idle-grace finalize fires.
    private var chartSamples: [ForceSample] {
        session.currentSet?.samples ?? session.lastFinalizedSamples
    }
    private var chartPeak: Double {
        session.currentSet?.peakLb ?? session.lastFinalizedPeakLb
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Top bar
            topBar

            // MARK: Dashboard body
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 4 metric tiles
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        // REPS
                        TileView(
                            label: "REPS",
                            value: "\(live.repCount)",
                            valueColor: VoltraColor.text
                        )
                        .frame(minHeight: tileMinHeight)

                        // PHASE
                        PhaseTileView(phase: live.phase)
                            .frame(minHeight: tileMinHeight)

                        // FORCE
                        TileView(
                            label: "FORCE",
                            value: String(format: "%.1f", live.forceLb),
                            unit: "lb",
                            sub: live.peakForceLb.map { String(format: "peak %.1f lb", $0) },
                            valueColor: VoltraColor.accent
                        )
                        .frame(minHeight: tileMinHeight)

                        // REST
                        restTile
                            .frame(minHeight: tileMinHeight)
                    }

                    // Force chart
                    ForceChartView(samples: chartSamples, peakLb: chartPeak)
                        .frame(minHeight: chartMinHeight)

                    // Compare strip
                    CompareStripView()
                        .frame(height: 72)
                }
                .padding(14)
                // b74 V4-D24: attach content-space debug grid layer (scrolls with content).
                .debugGridContentLayer()
            }
        }
        .background(VoltraColor.bg)
        .sheet(isPresented: $showHistory) {
            HistoryDrawerView(isPresented: $showHistory)
        }
        // b66 V4.2: page-name badge.
        .pageBadge("DashboardView")
        // B74-F11: recorder screen tag.
        .recorderScreen("DashboardView")
        }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            // Brand
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(VoltraColor.accent)
                    .font(.system(size: 18, weight: .bold))
                Text("VOLTRA")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VoltraColor.text)
                Text("Live")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(VoltraColor.textDim)
            }

            Spacer()

            // Status + battery + history
            HStack(spacing: 12) {
                if let pct = ble.batteryPercent {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(pct))
                            .foregroundColor(pct < 20 ? VoltraColor.warn : VoltraColor.textDim)
                        Text("\(pct)%")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(VoltraColor.textDim)
                    }
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(VoltraColor.accent)
                        .frame(width: 10, height: 10)
                        .shadow(color: VoltraColor.accent, radius: 4)
                    Text(ble.deviceName ?? "VOLTRA")
                        .font(.system(size: 13))
                        .foregroundColor(VoltraColor.textDim)
                }

                // History / settings button
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 18))
                        .foregroundColor(VoltraColor.text)
                        .frame(width: 36, height: 36)
                        .background(VoltraColor.bgElev)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Disconnect
                Button {
                    ble.disconnect()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15))
                        .foregroundColor(VoltraColor.textDim)
                        .frame(width: 36, height: 36)
                        .background(VoltraColor.bgElev)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VoltraColor.border)
                .frame(height: 1)
        }
    }

    private var restTile: some View {
        Button {
            session.tapRestTile()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.restActive ? "REST" : "REST")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(2.0)
                    .foregroundColor(session.restActive ? VoltraColor.warn : VoltraColor.textDim)
                    .textCase(.uppercase)

                Spacer()

                Text(session.restActive ? session.restFormatted : "0:00")
                    .font(.system(size: dynamicTileSize, weight: .bold, design: .monospaced))
                    .foregroundColor(session.restActive ? VoltraColor.warn : VoltraColor.text)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                Text(session.restActive ? "auto" : "tap to reset")
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textDim)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(session.restActive ? VoltraColor.warn : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Adaptive sizing

    private var tileMinHeight: CGFloat {
        hSizeClass == .regular ? 170 : 110
    }

    private var chartMinHeight: CGFloat {
        hSizeClass == .regular ? 220 : 180
    }

    @ScaledMetric(relativeTo: .largeTitle) private var dynamicTileSize: CGFloat = 72

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 75...: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 10..<25: return "battery.25"
        default:     return "battery.0"
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
}
