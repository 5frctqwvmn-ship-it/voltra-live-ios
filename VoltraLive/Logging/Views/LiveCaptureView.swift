// LiveCaptureView.swift
// Active capture for one ExerciseInstance: streams telemetry from the BLE
// layer (already wired into SessionStore) and surfaces auto-detected sets
// for confirmation/logging.
//
// Layout:
//   - Top: exercise name + set # + live force/reps/phase tiles.
//   - Middle: list of sets logged so far in THIS instance.
//   - Bottom: "Pending set" sheet appears when SessionStore detects an idle
//     set boundary. User taps Log to confirm.
//   - Bottom toolbar: "Next exercise" / "End session".

import SwiftUI
import SwiftData

struct LiveCaptureView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore

    @State private var showingSetLog = false
    @State private var showingEndConfirm = false
    @State private var showingExportSheet = false
    @State private var lastEndedSession: WorkoutSession? = nil

    /// Persisted target rest in seconds. nil = off. Persists across launches.
    @AppStorage("voltra.restTargetSeconds") private var restTargetRaw: Int = 90
    /// We use 0 as the sentinel for "off" in @AppStorage since it can't store
    /// nil directly. Wrap that as Int? for the timer view.
    private var restTargetBinding: Binding<Int?> {
        Binding(
            get: { restTargetRaw <= 0 ? nil : restTargetRaw },
            set: { restTargetRaw = $0 ?? 0 }
        )
    }



    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    liveTiles

                    RestTimerView(
                        anchor: logging.restAnchor,
                        targetSeconds: restTargetBinding
                    )

                    setsList

                    bottomActions
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
        }
        .onChange(of: logging.pendingTelemetrySet?.endedAt) { _, _ in
            if logging.pendingTelemetrySet != nil { showingSetLog = true }
        }
        .sheet(isPresented: $showingSetLog) {
            SetLogView()
                .environmentObject(logging)
                .environmentObject(session)
        }
        .alert("End session?", isPresented: $showingEndConfirm) {
            Button("Keep going", role: .cancel) { }
            Button("End and export", role: .destructive) {
                if let ended = logging.endSession() {
                    lastEndedSession = ended
                    showingExportSheet = true
                }
            }
        } message: {
            Text("This will save all logged sets and stop recording.")
        }
        .sheet(isPresented: $showingExportSheet, onDismiss: {
            // Session is over — ask the home view to pop the whole nav stack
            // back to root so the user can pick a new day or exit. Without
            // this they're stranded on a stale capture screen.
            lastEndedSession = nil
            logging.sessionExitTick &+= 1
        }) {
            if let s = lastEndedSession {
                ExportSheet(session: s)
                    .environmentObject(logging)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        let exName = logging.activeInstance?.exercise?.name ?? "Exercise"
        let equipment = logging.activeInstance?.equipment ?? ""
        let dayLabel = logging.activeSession?.displayLabel ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(dayLabel.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundColor(VoltraColor.accent)
            Text(exName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(VoltraColor.text)
            HStack(spacing: 8) {
                if !equipment.isEmpty {
                    Text(equipment)
                        .font(.system(size: 13))
                        .foregroundColor(VoltraColor.textDim)
                    Text("·")
                        .foregroundColor(VoltraColor.textFaint)
                }
                Text("Set \(logging.setNumberForCurrentInstance) coming up")
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Live tiles row

    private var liveTiles: some View {
        let live = ble.telemetry
        return HStack(spacing: 10) {
            miniTile(label: "REPS", value: "\(live.repCount)", color: VoltraColor.text)
            miniTile(label: "FORCE",
                     value: String(format: "%.0f", live.forceLb),
                     unit: "lb",
                     color: VoltraColor.accent)
            miniTile(label: "PHASE",
                     value: phaseLabel(live.phase),
                     color: VoltraColor.phase(live.phase))
        }
    }

    private func phaseLabel(_ p: VoltraPhase) -> String {
        switch p {
        case .pull:       return "PULL"
        case .return:     return "RETURN"
        case .transition: return "TRANS"
        case .idle:       return "IDLE"
        }
    }

    private func miniTile(label: String, value: String, unit: String? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let u = unit {
                    Text(u)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sets list

    private var setsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LOGGED SETS")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.5)
                    .foregroundColor(VoltraColor.textDim)
                Spacer()
                if let inst = logging.activeInstance {
                    Text("\(inst.sets?.count ?? 0)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(VoltraColor.textDim)
                }
            }

            let sets = logging.activeInstance?.orderedSets ?? []
            if sets.isEmpty {
                emptyHint
            } else {
                ForEach(sets) { s in
                    setRow(s)
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.path")
                .font(.system(size: 24))
                .foregroundColor(VoltraColor.textFaint)
            Text("Start lifting — sets auto-detect after a 4s rest.")
                .font(.system(size: 13))
                .foregroundColor(VoltraColor.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(VoltraColor.bgElev2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func setRow(_ s: LoggedSet) -> some View {
        HStack(spacing: 12) {
            Text("\(s.orderIndex)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(formatLb(s.weightLb)) lb")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    if let e = s.eccentricLb, e > 0 {
                        Text("+\(formatLb(e)) ecc")
                            .font(.system(size: 12))
                            .foregroundColor(VoltraColor.returnPhase)
                    }
                    if let c = s.chainsLb, c > 0 {
                        Text("+\(formatLb(c)) chains")
                            .font(.system(size: 12))
                            .foregroundColor(VoltraColor.transition)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(s.reps) reps")
                        .font(.system(size: 12))
                        .foregroundColor(VoltraColor.textDim)
                    if !s.labelText.isEmpty {
                        Text(s.labelText)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VoltraColor.bgElev2)
                            .clipShape(Capsule())
                            .foregroundColor(VoltraColor.textDim)
                    }
                }
            }
            Spacer()
            Text(String(format: "%.0f lb pk", s.peakForceLb))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(12)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button {
                showingSetLog = true
            } label: {
                Label("Log set manually", systemImage: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(VoltraColor.bgElev)
                    .foregroundColor(VoltraColor.text)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(VoltraColor.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                NavigationLink {
                    if let dt = logging.activeSession?.dayType {
                        ExercisePickerView(dayType: dt)
                    }
                } label: {
                    Label("Next exercise", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VoltraColor.bgElev)
                        .foregroundColor(VoltraColor.text)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showingEndConfirm = true
                } label: {
                    Label("End session", systemImage: "stop.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VoltraColor.danger.opacity(0.15))
                        .foregroundColor(VoltraColor.danger)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(VoltraColor.danger.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func formatLb(_ d: Double) -> String {
        d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    /// (Legacy fallback) completedAt of the most recent SwiftData LoggedSet in
    /// the active instance. Kept around for diagnostic builds. The view now
    /// reads `logging.restAnchor` directly because that source-of-truth is a
    /// `@Published` and updates synchronously when the Vulture reports an idle
    /// boundary (telemetry-driven rest start).
    private var lastSetCompletedAt: Date? {
        logging.activeInstance?.orderedSets.last?.completedAt
    }
}

#Preview {
    NavigationStack {
        LiveCaptureView()
            .environmentObject(VoltraBLEManager())
            .environmentObject(SessionStore())
            .environmentObject(LoggingStore())
    }
}
