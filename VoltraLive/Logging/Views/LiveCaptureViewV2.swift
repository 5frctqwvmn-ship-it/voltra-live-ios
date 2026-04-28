// LiveCaptureViewV2.swift
//
// b53: V2 preview of the live-capture screen. Single-Voltra only, no
// chain UI, no SWAP, no drop-set cascade controls. The container view
// (LiveCaptureContainer) routes to V2 only when:
//   - the user opted into V2 via the first-launch picker, AND
//   - exactly one Voltra is paired, AND
//   - the superset chain has fewer than 2 entries.
// In any other shape (dual paired, chain >= 2) V1 is used so we keep
// the working production behavior for the long-tail flows.
//
// Design intent: this is the "lifting view I would build today if I
// did not have to keep V1's chain/cascade hooks alive". It uses the
// design-system tokens from VoltraTheme (VoltraColor / VoltraFont)
// and the same ForceChartView component the dashboard renders, so
// the visual language is consistent end to end.
//
// Layout (top -> bottom inside a scroll view):
//   1. Header card  - exercise name + day strip + SET N counter
//   2. 2x2 tile grid - REPS / PEAK / HR / REST
//   3. Force chart   - 30s rolling waveform of the in-flight set
//   4. Plan card     - planned weight + a single "LOG SET" CTA
//
// Anything more complex (drop-set chains, dual writers, swap, undo
// toast, expanded set rows) is intentionally absent. If the user
// needs those, they should toggle back to V1 from Settings (a TODO
// for b54). V2's job is to demonstrate the cleaner direction without
// breaking the working screen.

import SwiftUI

struct LiveCaptureViewV2: View {

    // MARK: Environment

    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var health: HealthKitStore
    @EnvironmentObject var mdm: MultiDeviceManager

    @Environment(\.dismiss) private var dismiss

    // MARK: Local state

    @State private var showingEndConfirm = false
    @State private var showingExportSheet = false
    @State private var lastEndedSession: WorkoutSession? = nil

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    tileGrid
                    forceChart
                    planCard
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingEndConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(VoltraColor.textDim)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("V2")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.bg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VoltraColor.accent)
                    .clipShape(Capsule())
            }
        }
        .confirmationDialog(
            "What do you want to do?",
            isPresented: $showingEndConfirm,
            titleVisibility: .visible
        ) {
            Button("Just go back (keep session running)") {
                dismiss()
            }
            Button("End and export", role: .destructive) {
                if let active = logging.activeSession {
                    active.supersetTag = mdm.supersetTag
                }
                if let ended = logging.endSession() {
                    lastEndedSession = ended
                    showingExportSheet = true
                }
            }
            Button("Keep going (stay here)", role: .cancel) { }
        } message: {
            Text("End and export saves and stops recording. Just go back lets you peek at the home screen \u{2014} your session keeps running in the background.")
        }
        .sheet(isPresented: $showingExportSheet, onDismiss: {
            lastEndedSession = nil
            logging.sessionExitTick &+= 1
        }) {
            if let s = lastEndedSession {
                ExportSheet(session: s)
                    .environmentObject(logging)
            }
        }
        .onAppear {
            // V2 does not own a WriterRouter \u2014 single Voltra means we
            // write straight through the BLE manager for any nudges. We
            // still kick off HealthKit so the HR tile is live.
            health.start()
        }
    }

    // MARK: - Sections

    /// b53: Header card. V2 does not render the superset kicker because
    /// V2 is gated to single-Voltra sessions. We show exercise name +
    /// day strip + SET N of M counter, all inside an elevated card.
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIVE")
                .font(VoltraFont.label())
                .kerning(1.6)
                .foregroundColor(VoltraColor.accent)

            Text(exerciseName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(VoltraColor.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let day = logging.activeSession?.dayTypeRaw, !day.isEmpty {
                    pill(day.uppercased(), color: VoltraColor.accent)
                }
                pill("SET \(setNumber)", color: VoltraColor.textDim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// b53: 2x2 telemetry tile grid. V2 deliberately keeps this to four
    /// values (REPS / PEAK / HR / REST) \u2014 the design system caps
    /// primary tiles at 4, and anything beyond that competes with the
    /// big number on each tile from 8 ft of viewing distance.
    private var tileGrid: some View {
        let live = ble.telemetry
        let reps = session.currentSet?.reps ?? 0
        let peak = session.currentSet?.peakLb ?? live.forceLb
        let hr = health.currentHR
        let rest = Int(session.restElapsedSeconds.rounded())

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile(label: "REPS", value: "\(reps)", unit: nil, color: VoltraColor.text)
                tile(
                    label: "PEAK",
                    value: peak > 0 ? String(format: "%.0f", peak) : "\u{2014}",
                    unit: peak > 0 ? "lb" : nil,
                    color: phaseColor(live.phase)
                )
            }
            HStack(spacing: 12) {
                tile(
                    label: "HR",
                    value: hr.map(String.init) ?? "\u{2014}",
                    unit: hr != nil ? "bpm" : nil,
                    color: VoltraColor.warn
                )
                tile(
                    label: "REST",
                    value: formatRest(rest),
                    unit: nil,
                    color: VoltraColor.transition
                )
            }
        }
    }

    /// b53: Same ForceChartView as the dashboard \u2014 keeps the live
    /// waveform identical across the two screens. Empty state: we just
    /// show the chart frame with the rest message.
    private var forceChart: some View {
        let samples = session.currentSet?.samples ?? session.lastFinalizedSamples
        let peak = session.currentSet?.peakLb ?? session.lastFinalizedPeakLb
        return VStack(alignment: .leading, spacing: 8) {
            Text("FORCE")
                .font(VoltraFont.label())
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            ForceChartView(samples: samples, peakLb: peak)
                .frame(height: 160)
                .padding(12)
                .background(VoltraColor.bgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    /// b53: Plan card with the planned weight + LOG SET CTA. V2 keeps
    /// this compact: no nudge chips, no add-plates flow, no drop-set
    /// chain. If the user needs those, they should switch to V1.
    private var planCard: some View {
        let planned = logging.pendingPlannedWeightLb ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PLAN")
                    .font(VoltraFont.label())
                    .kerning(1.4)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text(planned > 0 ? "\(Int(planned)) lb" : "\u{2014}")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
            }

            Button {
                logSetTapped()
            } label: {
                HStack {
                    Spacer()
                    Text("LOG SET")
                        .font(.system(size: 14, weight: .bold))
                        .kerning(1.2)
                        .foregroundColor(VoltraColor.bg)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(canLogSet ? VoltraColor.accent : VoltraColor.accent.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canLogSet)
        }
        .padding(16)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Components

    private func tile(label: String, value: String, unit: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(VoltraFont.tileLabel())
                .kerning(1.2)
                .foregroundColor(VoltraColor.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(VoltraFont.bigNumber(size: 44))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let u = unit {
                    Text(u)
                        .font(VoltraFont.unit())
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .kerning(1.2)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule().stroke(color.opacity(0.5), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private var exerciseName: String {
        logging.activeInstance?.exercise?.name ?? "\u{2014}"
    }

    private var setNumber: Int {
        logging.setNumberForCurrentInstance
    }

    private var canLogSet: Bool {
        // Mirror V1: a set is loggable once we have at least 1 rep in
        // the in-flight set OR a finalized telemetry packet pending.
        if let cs = session.currentSet, cs.reps > 0 { return true }
        if logging.pendingTelemetrySet != nil { return true }
        return false
    }

    private func phaseColor(_ phase: VoltraPhase) -> Color {
        switch phase {
        case .pull:        return VoltraColor.pull
        case .return:      return VoltraColor.returnPhase
        case .transition:  return VoltraColor.transition
        case .idle:        return VoltraColor.idle
        }
    }

    private func formatRest(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func logSetTapped() {
        // b53 V2: direct commit using whatever telemetry has accrued.
        // We mirror SetLogView.commit() with sensible defaults: weight
        // = pending plan, ecc/chains = nil, reps/peak from telemetry.
        // Anything more nuanced (custom labels, notes, mode) belongs in
        // V1's SetLogView \u2014 V2's CTA is a one-tap log.
        let pending: CompletedSet? = logging.pendingTelemetrySet ?? session.currentSet.map { cs in
            CompletedSet(
                reps: cs.reps,
                peakLb: cs.peakLb,
                startedAt: cs.startedAt,
                endedAt: cs.endedAt ?? Date()
            )
        }
        let weight = logging.pendingPlannedWeightLb ?? 0
        logging.logSet(
            weightLb: weight,
            eccentricLb: nil,
            reps: pending?.reps ?? 0,
            chainsLb: nil,
            peakForceLb: pending?.peakLb ?? 0,
            startedAt: pending?.startedAt,
            endedAt: pending?.endedAt,
            mode: .working,
            labelText: "",
            notes: nil,
            autofilledFromTelemetry: pending != nil
        )
    }
}
