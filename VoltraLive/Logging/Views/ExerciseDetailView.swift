// ExerciseDetailView.swift
// The control screen shown after picking an exercise: top-level mode
// (Weight/Band/Damper), modifier toggles (eccentric/chains/inverse — only in
// weight, with chains↔inverse mutex), per-mode parameter steppers, target reps,
// a live "Voltra: ..." confirm strip, and a "Start set" CTA that opens
// LiveCaptureView.
//
// Ported 1:1 from the web prototype's renderDetail() in app.js. Every state
// change pipes through `VoltraWriter.apply(_:)`, which debounces and only
// sends the diff to the device.
//
// Why this is a new file (not edits to ExerciseStartView): the prototype
// detail screen and the smart-start screen are different shapes and different
// flows. Keeping ExerciseStartView intact avoids breaking the smart-start
// behavior anyone has tested in v0.2.x while we ship the new flow.
//
// Hardware note: we use `VoltraWriter` rather than calling
// `bleManager.writeControlFrame` directly so the user can hold +/- on a stepper
// without flooding the BLE characteristic. Writes coalesce within ~80 ms.

import SwiftUI

// MARK: - Top-level mode picker shape

private struct ModeOption: Identifiable {
    let id: VoltraMode
    let label: String
}

private let DETAIL_MODES: [ModeOption] = [
    .init(id: .weight, label: "Weight"),
    .init(id: .band,   label: "Band"),
    .init(id: .damper, label: "Damper"),
]

struct ExerciseDetailView: View {
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var ble: VoltraBLEManager

    /// Captured per-view so the writer's debounce/diff state is scoped to one
    /// detail-screen visit. On dismiss it deinits along with the view.
    @StateObject private var writerHolder: WriterHolder

    // Mode + modifier state — drives both the device and the UI
    @State private var mode: VoltraMode = .weight
    @State private var eccentric: Bool = false
    @State private var chains: Bool = false
    @State private var inverse: Bool = false

    // Weights for each mode (independent so switching modes preserves prior
    // values, matching the prototype's per-exercise state.weights)
    @State private var baseLb: Int = 100
    @State private var eccLb: Int = 0
    @State private var chainsLb: Int = 0
    @State private var bandMaxForceLb: Int = 60
    @State private var damperLevel: Int = 4
    @State private var targetReps: Int = 9

    @State private var navigateToCapture = false
    @State private var didInitialize = false

    init() {
        // Build the writer eagerly so the first apply() has a live target.
        // We can't reference @EnvironmentObject in init, so the writer's BLE
        // reference is wired in .onAppear via WriterHolder.attach.
        _writerHolder = StateObject(wrappedValue: WriterHolder())
    }

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    historyStrip
                    progressChart
                    modeSection
                    modifiersAndSteppers
                    targetSection
                    voltraConfirmStrip
                    startButton
                    Spacer(minLength: 24)
                }
                .padding(20)
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToCapture) {
            LiveCaptureView()
        }
        .onAppear {
            writerHolder.attach(ble: ble)
            if !didInitialize {
                seedFromHistory()
                didInitialize = true
            }
            pushToVoltra()
        }
        .onDisappear {
            // Don't reset device state on disappear — the user is going into
            // LiveCaptureView with the same loaded weight.
        }
    }

    // MARK: - Sections

    private var navTitle: String {
        logging.activeInstance?.exercise?.name ?? "Exercise"
    }

    // v0.4.0 — Per-exercise progress chart, sample-fallback when empty so a
    // first-time user still sees the shape. Sits between the history strip
    // and the mode picker per research recommendation.
    private var progressChart: some View {
        let history: [LoggedSet]
        if let ex = logging.activeInstance?.exercise {
            history = logging.historicalSets(for: ex)
        } else {
            history = []
        }
        let realPoints = ProgressChartView.points(fromSeries: history)
        return ProgressChartView(series: realPoints)
    }

    private var historyStrip: some View {
        let last = previousSeries.first
        return HStack(spacing: 0) {
            cell(label: "LAST SESSION", value: lastSessionSummary)
            Divider().frame(width: 1, height: 36).background(VoltraColor.border)
            cell(label: "SET \(currentSetIndex + 1)", value: lastMatchingSetSummary(last))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func cell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.2)
                .foregroundColor(VoltraColor.textFaint)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODE")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            HStack(spacing: 8) {
                ForEach(DETAIL_MODES) { option in
                    Button {
                        selectMode(option.id)
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(mode == option.id ? VoltraColor.accent : VoltraColor.bgElev2)
                            .foregroundColor(mode == option.id ? VoltraColor.bg : VoltraColor.text)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(mode == option.id ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var modifiersAndSteppers: some View {
        switch mode {
        case .weight: weightPanel
        case .band:   bandPanel
        case .damper: damperPanel
        }
    }

    private var weightPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MODIFIERS")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .foregroundColor(VoltraColor.textDim)
                    Spacer()
                    Text("stack eccentric with chains or inverse")
                        .font(.system(size: 10))
                        .foregroundColor(VoltraColor.textFaint)
                }
                HStack(spacing: 8) {
                    modToggle(label: "Eccentric", on: eccentric) {
                        eccentric.toggle()
                        if !eccentric { eccLb = 0 }
                        pushToVoltra()
                    }
                    modToggle(label: "Chains", on: chains) {
                        chains.toggle()
                        if chains {
                            inverse = false
                        } else if !inverse {
                            chainsLb = 0
                        }
                        pushToVoltra()
                    }
                    modToggle(label: "Inverse", on: inverse) {
                        inverse.toggle()
                        if inverse {
                            chains = false
                        } else if !chains {
                            chainsLb = 0
                        }
                        pushToVoltra()
                    }
                }
            }

            stepper(label: "Base weight", unit: "lb", value: baseLb, min: 5, max: 200, deltas: [-5, -1, 1, 5]) { newValue in
                baseLb = newValue
                pushToVoltra()
            }

            if eccentric {
                stepper(label: "Eccentric", unit: "lb", value: eccLb, min: 0, max: 200, deltas: [-5, -1, 1, 5], prefix: "+") { newValue in
                    eccLb = newValue
                    pushToVoltra()
                }
            }

            if chains || inverse {
                stepper(label: inverse ? "Inverse chains" : "Chains", unit: "lb", value: chainsLb, min: 0, max: 200, deltas: [-5, -1, 1, 5], prefix: "+") { newValue in
                    chainsLb = newValue
                    pushToVoltra()
                }
            }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var bandPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepper(label: "Max force", unit: "lb", value: bandMaxForceLb, min: 15, max: 200, deltas: [-5, -1, 1, 5]) { newValue in
                bandMaxForceLb = newValue
                pushToVoltra()
            }
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var damperPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAMPER LEVEL")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(VoltraColor.textDim)
            // 9 buttons in a row — they fit comfortably on iPhone widths
            HStack(spacing: 6) {
                ForEach(1...9, id: \.self) { n in
                    Button {
                        damperLevel = n
                        pushToVoltra()
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(damperLevel == n ? VoltraColor.accent : VoltraColor.bgElev2)
                            .foregroundColor(damperLevel == n ? VoltraColor.bg : VoltraColor.text)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(damperLevel == n ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("1 = light cable feel · 9 = heavy resistance")
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepper(label: "Target reps", unit: "reps", value: targetReps, min: 1, max: 30, deltas: [-5, -1, 1, 5]) { newValue in
                targetReps = newValue
                // Target reps does NOT call pushToVoltra — it's UI-only
            }
            Text(targetHint)
                .font(.system(size: 11))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(14)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var voltraConfirmStrip: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VoltraColor.accent)
                .frame(width: 8, height: 8)
            Text("Voltra:")
                .font(.system(size: 12))
                .foregroundColor(VoltraColor.textDim)
            Text(loadedSummary)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(VoltraColor.bgElev2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VoltraColor.accentDim, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var startButton: some View {
        Button {
            // v0.4.0 — plumb the FULL upcoming-set context into LoggingStore so
            // when telemetry detects the set boundary, autoLogTelemetrySet()
            // can build a complete LoggedSet without any user prompt.
            switch mode {
            case .weight:
                logging.pendingPlannedWeightLb = Double(baseLb)
                logging.upcomingMode = eccentric ? .eccentric : .working
                logging.upcomingEccLb = eccentric ? Double(eccLb) : 0
            case .band:
                logging.pendingPlannedWeightLb = Double(bandMaxForceLb)
                logging.upcomingMode = .band
                logging.upcomingEccLb = 0
            case .damper:
                logging.pendingPlannedWeightLb = nil
                logging.upcomingMode = .standard
                logging.upcomingEccLb = 0
            }
            logging.upcomingTargetReps = targetReps
            // Chains/inverse from this screen carry into the upcoming set as
            // an added-load entry (chains type, with sign captured by
            // inverseChains via the modifier toggles in LiveCapture).
            if (chains || inverse) && chainsLb > 0 {
                logging.upcomingAddedLoadLb = Double(chainsLb)
                logging.upcomingAddedLoadType = inverse ? "inverse_chains" : "chains"
            }
            navigateToCapture = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Start set \(currentSetIndex + 1)")
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VoltraColor.accent)
            .foregroundColor(VoltraColor.bg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Reusable controls

    private func modToggle(label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(on ? VoltraColor.bg : VoltraColor.text)
                Text(on ? "On" : "Off")
                    .font(.system(size: 10))
                    .foregroundColor(on ? VoltraColor.bg.opacity(0.7) : VoltraColor.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(on ? VoltraColor.accent : VoltraColor.bgElev2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(on ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func stepper(
        label: String,
        unit: String,
        value: Int,
        min: Int,
        max: Int,
        deltas: [Int],
        prefix: String = "",
        onChange: @escaping (Int) -> Void
    ) -> some View {
        let negs = deltas.filter { $0 < 0 }
        let pos  = deltas.filter { $0 > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .kerning(1.0)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(VoltraColor.textFaint)
            }
            HStack(spacing: 6) {
                ForEach(negs, id: \.self) { d in
                    stepBtn(delta: d) {
                        let next = Swift.max(min, Swift.min(max, value + d))
                        if next != value { onChange(next) }
                    }
                }
                Text("\(prefix)\(value)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(VoltraColor.text)
                    .frame(maxWidth: .infinity)
                ForEach(pos, id: \.self) { d in
                    stepBtn(delta: d) {
                        let next = Swift.max(min, Swift.min(max, value + d))
                        if next != value { onChange(next) }
                    }
                }
            }
        }
    }

    private func stepBtn(delta: Int, action: @escaping () -> Void) -> some View {
        let big = abs(delta) >= 5
        let sign = delta > 0 ? "+" : "−"
        return Button(action: action) {
            Text("\(sign)\(abs(delta))")
                .font(.system(size: big ? 14 : 13, weight: .bold, design: .monospaced))
                .frame(width: big ? 50 : 42, height: 40)
                .background(VoltraColor.bgElev2)
                .foregroundColor(VoltraColor.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behavior

    private var currentSetIndex: Int {
        // 0-based for prototype-style messaging; logging.setNumberForCurrentInstance is 1-based
        Swift.max(0, logging.setNumberForCurrentInstance - 1)
    }

    private var previousSeries: [LoggedSet] {
        guard let ex = logging.activeInstance?.exercise else { return [] }
        return logging.previousSetSeries(for: ex)
    }

    private var lastSessionSummary: String {
        guard let last = previousSeries.first else { return "—" }
        let dateStr: String
        if let started = last.instance?.session?.startedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            dateStr = f.localizedString(for: started, relativeTo: Date())
        } else {
            dateStr = ""
        }
        return "\(formatLb(last.weightLb)) lb × \(last.reps) \(dateStr)"
    }

    private func lastMatchingSetSummary(_ last: LoggedSet?) -> String {
        // Show the matching-slot set from last session
        let series = previousSeries
        let target = currentSetIndex
        if let s = series.first(where: { $0.orderIndex - 1 == target }) {
            return "\(formatLb(s.weightLb)) lb · \(s.reps) reps"
        }
        if let last = last {
            return "Last: \(formatLb(last.weightLb)) × \(last.reps)"
        }
        return "First time"
    }

    private var targetHint: String {
        let series = previousSeries
        let idx = currentSetIndex
        if let s = series.first(where: { $0.orderIndex - 1 == idx }) {
            return "Last time, set \(idx + 1): \(s.reps) reps"
        }
        if !series.isEmpty {
            return "No set \(idx + 1) last time — free entry"
        }
        return "First time — set your own target"
    }

    private var loadedSummary: String {
        switch mode {
        case .weight:
            var s = "\(baseLb) lb"
            if eccentric, eccLb > 0 { s += " + \(eccLb) ecc" }
            if chains, chainsLb > 0 { s += " + \(chainsLb) chain" }
            if inverse, chainsLb > 0 { s += " + \(chainsLb) inv-chain" }
            return s
        case .band:
            return "\(bandMaxForceLb) lb max · Resistance Band"
        case .damper:
            return "Level \(damperLevel) · Damper"
        }
    }

    private func selectMode(_ newMode: VoltraMode) {
        guard mode != newMode else { return }
        mode = newMode
        // Switching modes clears modifiers (matches prototype)
        eccentric = false
        chains = false
        inverse = false
        pushToVoltra()
    }

    /// Seed initial values from the last set on this exercise.
    private func seedFromHistory() {
        guard let last = previousSeries.first else { return }
        baseLb = Int(last.weightLb.rounded())
        if let ecc = last.eccentricLb, ecc > 0 {
            eccentric = true
            eccLb = Int(ecc.rounded())
        }
        if let c = last.chainsLb, c > 0 {
            chainsLb = Int(c.rounded())
            if last.inverseChains {
                inverse = true
            } else {
                chains = true
            }
        }
        if let band = last.bandMaxForceLb, band > 0 {
            bandMaxForceLb = Int(band.rounded())
        }
        if let damper = last.damperLevel, damper > 0 {
            damperLevel = damper
        }
        if last.reps > 0 { targetReps = last.reps }
    }

    private func pushToVoltra() {
        let state = VoltraDeviceState(
            mode: mode,
            modifiers: VoltraModifiers(eccentric: eccentric, chains: chains, inverse: inverse),
            weights: VoltraWeights(
                baseLb: baseLb,
                eccentricLb: eccLb,
                chainsLb: chainsLb,
                bandMaxForceLb: bandMaxForceLb,
                damperLevel: damperLevel
            )
        )
        writerHolder.writer?.apply(state)
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }
}

// MARK: - Writer holder

/// Why this exists: SwiftUI views can't construct a writer with closures
/// capturing @EnvironmentObject in init (env is not available there). We hold
/// the writer on a tiny ObservableObject and attach the BLE manager in
/// onAppear.
@MainActor
private final class WriterHolder: ObservableObject {
    var writer: VoltraWriter?

    func attach(ble: VoltraBLEManager) {
        guard writer == nil else { return }
        writer = VoltraWriter(
            writeFrame: { [weak ble] frame in ble?.writeControlFrame(frame) },
            log:        { [weak ble] msg   in ble?.addLog(msg) }
        )
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView()
            .environmentObject(LoggingStore())
            .environmentObject(SessionStore())
            .environmentObject(VoltraBLEManager())
    }
}
