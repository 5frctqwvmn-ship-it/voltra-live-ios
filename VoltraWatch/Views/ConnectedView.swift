// ConnectedView.swift
// Watch dashboard: reps (huge mono), phase indicator, force, rest timer.
// Phase-tinted containerBackground animates between phases.

import SwiftUI

struct ConnectedView: View {
    @EnvironmentObject var store: WatchTelemetryStore
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {

                // ── REPS ──────────────────────────────────────────────────
                VStack(spacing: 0) {
                    Text("REPS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Text("\(store.reps)")
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.25), value: store.reps)
                        .redacted(reason: isDimmed ? .privacy : [])
                }
                .frame(maxWidth: .infinity)

                // ── PHASE ─────────────────────────────────────────────────
                PhaseIndicator(phase: store.phase)
                    .padding(.vertical, 2)

                // ── FORCE ─────────────────────────────────────────────────
                VStack(spacing: 0) {
                    Text("FORCE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", store.forceLb))
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.linear(duration: 0.1), value: store.forceLb)
                        Text("lb")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .redacted(reason: isDimmed ? .privacy : [])
                }
                .frame(maxWidth: .infinity)

                // ── REST TIMER (only when resting) ────────────────────────
                if store.restSeconds > 0 {
                    Divider().opacity(0.3)
                    VStack(spacing: 0) {
                        Text("REST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(2)
                        Text(restFormatted)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }

                // ── SET NUMBER (small, bottom) ────────────────────────────
                if store.setNumber > 0 {
                    Text("Set \(store.setNumber)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .containerBackground(phaseColor.opacity(0.25), for: .navigation)
        .animation(.easeInOut(duration: 0.4), value: store.phase)
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch store.phase {
        case "Pull":       return Color(red: 0.0,  green: 0.831, blue: 0.667) // #00D4AA teal
        case "Return":     return Color(red: 1.0,  green: 0.722, blue: 0.302) // #FFB84D amber
        case "Transition": return Color(red: 0.424, green: 0.553, blue: 0.878) // #6C8DE0 blue
        default:           return Color(red: 0.290, green: 0.373, blue: 0.357) // #4A5F5B dim
        }
    }

    private var restFormatted: String {
        let s = store.restSeconds
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
