// DropSetConfigureSheet.swift
//
// b55 (v0.4.33): V2-only configure sheet. Opens when the user taps the
// DROP mod tile in LiveCaptureViewV2. Lets them define a manual drop
// sequence by entering:
//
//   FROM   — starting weight (defaults to current pendingPlannedWeight)
//   TO     — final weight in the sequence
//   STEP   — pounds dropped between consecutive stops
//
// On confirm we generate the `[Int]` step list (FROM, FROM-STEP, ..., TO,
// inclusive) and hand it back via `onConfirm`. The caller is responsible
// for stuffing the list onto `LoggingStore.manualDropSequence` and
// pushing the head weight to the device.
//
// We deliberately validate STEP > 0 and TO < FROM so the resulting list
// is at least 2 entries (otherwise there's no "drop" to perform).
//
// Visual styling matches V2's dark theme so the sheet doesn't clash with
// the LiveCapture view it's rising from.

import SwiftUI

struct DropSetConfigureSheet: View {

    // MARK: Inputs

    /// Initial value for FROM. Typically the current planned weight.
    let startingLb: Int

    /// Called when the user confirms a valid sequence. The argument is
    /// the resolved step list, e.g. [120, 110, 100, 90].
    let onConfirm: ([Int]) -> Void

    /// Called when the user cancels (also called when the sheet is
    /// dismissed via swipe).
    let onCancel:  () -> Void

    @EnvironmentObject var logging: LoggingStore
    @Environment(\.dismiss) private var dismiss

    // MARK: State

    @State private var fromLb: Int = 0
    @State private var toLb:   Int = 0
    @State private var stepLb: Int = 10

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()

                VStack(spacing: 18) {
                    headerBlurb
                    fromCard
                    toCard
                    stepCard
                    previewCard
                    Spacer(minLength: 0)
                    confirmButton
                }
                .padding(16)
            }
            .navigationTitle("Drop-set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .onAppear {
            fromLb = max(0, startingLb)
            // Sensible default TO: 60% of FROM rounded to step.
            let defaultTo = max(stepLb, Int((Double(startingLb) * 0.6 / Double(stepLb)).rounded()) * stepLb)
            toLb = min(defaultTo, max(0, fromLb - stepLb))
        }
    }

    // MARK: - Sub-views

    private var headerBlurb: some View {
        Text("Tap-set a manual drop sequence. We'll push each step to the Voltra as you finalize a set.")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(VoltraColor.textDim)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fromCard: some View {
        configCard(
            label: "FROM",
            valueLb: $fromLb,
            range: 5...500,
            stepIncrement: 5,
            tint: VoltraColor.accent
        )
    }

    private var toCard: some View {
        configCard(
            label: "TO",
            valueLb: $toLb,
            range: 5...max(5, fromLb - stepLb),
            stepIncrement: 5,
            tint: VoltraColor.warn
        )
    }

    private var stepCard: some View {
        configCard(
            label: "STEP",
            valueLb: $stepLb,
            range: 5...max(5, fromLb - 5),
            stepIncrement: 5,
            tint: VoltraColor.textDim
        )
    }

    private func configCard(
        label: String,
        valueLb: Binding<Int>,
        range: ClosedRange<Int>,
        stepIncrement: Int,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundColor(tint)
                .frame(width: 56, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(valueLb.wrappedValue)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(VoltraColor.text)
                Text("lb")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)
            }
            Spacer()
            HStack(spacing: 6) {
                stepperBtn("\u{2212}\(stepIncrement)") {
                    let next = max(range.lowerBound, valueLb.wrappedValue - stepIncrement)
                    valueLb.wrappedValue = next
                }
                stepperBtn("+\(stepIncrement)") {
                    let next = min(range.upperBound, valueLb.wrappedValue + stepIncrement)
                    valueLb.wrappedValue = next
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func stepperBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(VoltraColor.text)
                .frame(minWidth: 44, minHeight: 32)
        }
        .buttonStyle(.plain)
        .background(VoltraColor.bgElev2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Live preview of the resolved step list. Updates as FROM/TO/STEP change.
    private var previewCard: some View {
        let steps = resolvedSteps()
        return VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW")
                .font(.system(size: 9, weight: .bold))
                .kerning(1.6)
                .foregroundColor(VoltraColor.textDim)

            if steps.count >= 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, lb in
                            HStack(spacing: 4) {
                                if idx > 0 {
                                    Text("\u{2192}")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(VoltraColor.textDim)
                                }
                                Text("\(lb)")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(idx == 0 ? VoltraColor.accent : VoltraColor.text)
                            }
                        }
                    }
                }
            } else {
                Text("Pick FROM > TO with a positive STEP to build a sequence.")
                    .font(.system(size: 11))
                    .foregroundColor(VoltraColor.textFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var confirmButton: some View {
        let steps = resolvedSteps()
        let isValid = steps.count >= 2
        return Button {
            guard isValid else { return }
            onConfirm(steps)
            dismiss()
        } label: {
            Text("Arm drop-set")
                .font(.system(size: 14, weight: .bold))
                .kerning(0.6)
                .foregroundColor(isValid ? VoltraColor.bg : VoltraColor.textFaint)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(isValid ? VoltraColor.accent : VoltraColor.bgElev2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isValid ? VoltraColor.accent : VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
    }

    // MARK: - Step list resolution

    /// Build the descending step list inclusive of TO.
    /// e.g. FROM=120 TO=90 STEP=10 → [120, 110, 100, 90]
    /// If the math doesn't land exactly on TO, the final entry is clamped
    /// to TO so the user always ends on the weight they asked for.
    private func resolvedSteps() -> [Int] {
        guard stepLb > 0, fromLb > toLb else { return [] }
        var out: [Int] = []
        var cur = fromLb
        while cur > toLb {
            out.append(cur)
            cur -= stepLb
        }
        out.append(toLb)
        return out
    }
}

#if DEBUG
#Preview("Drop-set configure") {
    DropSetConfigureSheet(
        startingLb: 120,
        onConfirm: { _ in },
        onCancel:  { }
    )
    .environmentObject(LoggingStore())
}
#endif
