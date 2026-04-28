// WorkoutVoltraPickerSheet.swift
//
// Build 42 "Workout Voltra picker".
//
// When both Voltras are paired (MultiDeviceManager has left + right both
// connected) and the user starts a workout, this sheet appears BEFORE the
// session is created. The user picks one of:
//
//   \u2022 Left only      \u2014 telemetry from Left only; Right stays paired but idle.
//   \u2022 Right only     \u2014 telemetry from Right only; Left stays paired but idle.
//   \u2022 Independent    \u2014 both Voltras tracked side-by-side; reps/force not summed.
//   \u2022 Combined       \u2014 virtual-twin: weights split, telemetry summed.
//
// The selection lives on `MultiDeviceManager.workoutMode` and stays in
// effect until the user starts another workout (or relaunches the app).
//
// Why this exists: the user said "Having them dual mode by default is not by
// intent. I want to be able to pair them and then engage with them
// separately." So when both are paired, default routing is .singleLeft and
// the user opts in to dual modes per-workout.
//
// This sheet is NOT shown when only one Voltra is paired (b40 unified
// connect already handles that case naturally).
//
// Sacred files (VoltraProtocol, TelemetryExtractor, PacketParser,
// FrameAssembler) are NOT touched.

import SwiftUI

struct WorkoutVoltraPickerSheet: View {

    @EnvironmentObject var mdm: MultiDeviceManager
    @Environment(\.dismiss) private var dismiss

    /// Called once the user confirms a mode. The caller is expected to
    /// kick off `LoggingStore.startSession(...)` from inside this closure.
    var onConfirm: () -> Void

    @State private var selection: WorkoutMode = .singleLeft

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Both Voltras are paired. Pick how you want to use them for this workout.")
                        .font(.system(size: 14))
                        .foregroundColor(VoltraColor.textDim)
                        .padding(.bottom, 4)

                    ForEach(WorkoutMode.allCases, id: \.self) { mode in
                        modeRow(mode)
                    }
                }
                .padding(20)
            }

            Spacer(minLength: 0)

            footer
        }
        .background(VoltraColor.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            // Default to whatever the user picked last; falls back to
            // .singleLeft on first run (set on MDM init).
            selection = mdm.workoutMode
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Cancel")
                }
                .foregroundColor(VoltraColor.accent)
            }
            Spacer()
            Text("Workout Mode")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(VoltraColor.text)
            Spacer()
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }

    // MARK: - Rows

    private func modeRow(_ mode: WorkoutMode) -> some View {
        let isSelected = (mode == selection)
        return Button {
            selection = mode
        } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? VoltraColor.accent : VoltraColor.textDim)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    Text(mode.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(VoltraColor.textDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? VoltraColor.accent : VoltraColor.textFaint)
            }
            .padding(14)
            .background(isSelected ? VoltraColor.bgElev : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? VoltraColor.accent : VoltraColor.border,
                            lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            mdm.workoutMode = selection
            onConfirm()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Start Workout")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(VoltraColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(VoltraColor.border).frame(height: 1)
        }
    }
}

#Preview {
    WorkoutVoltraPickerSheet(onConfirm: {})
        .environmentObject(MultiDeviceManager())
}
