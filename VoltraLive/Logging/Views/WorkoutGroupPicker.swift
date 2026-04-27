// WorkoutGroupPicker.swift
// v0.4.8 (build 30) — workout-creation Group dropdown.
//
// Renders a Menu-style picker that lets the user tag a workout with a
// training-split label (Push / Pull / Legs / Upper / Lower / Full Body /
// Custom). Orthogonal to `DayType` — see `WorkoutGroup` doc comment in
// `LoggingModels.swift`.
//
// Used from `LoggingHomeView`: the user picks an optional Group BEFORE
// tapping a day-type tile, and the chosen value flows into
// `LoggingStore.startSession`. "Custom…" routes through a small text-entry
// sheet that the parent owns (so the parent can present the keyboard at
// the right time relative to its own custom-day flow).
//
// Build badge: this is a regular SwiftUI view used inline, not a sheet.
// The global `BuildBadgeOverlay` (bottom-trailing on every screen) covers
// the build-number requirement.

import SwiftUI

struct WorkoutGroupPicker: View {

    @Binding var group: WorkoutGroup?
    @Binding var customLabel: String

    /// Called when the user taps "Custom…" so the parent can present the
    /// custom-label sheet at the right moment (Menu auto-dismisses).
    var onRequestCustom: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(VoltraColor.textDim)
            Text("GROUP")
                .font(VoltraFont.label())
                .kerning(2)
                .foregroundColor(VoltraColor.textDim)
            Spacer()
            Menu {
                ForEach(WorkoutGroup.presets) { g in
                    Button {
                        group = g
                        customLabel = ""
                    } label: {
                        HStack {
                            Text(g.displayName)
                            if group == g { Image(systemName: "checkmark") }
                        }
                    }
                }
                Divider()
                Button {
                    // Sheet is owned by the parent so the keyboard timing is right.
                    onRequestCustom()
                } label: {
                    HStack {
                        Text("Custom\u{2026}")
                        if group == .custom { Image(systemName: "checkmark") }
                    }
                }
                if group != nil {
                    Divider()
                    Button(role: .destructive) {
                        group = nil
                        customLabel = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(group == nil ? VoltraColor.textDim : VoltraColor.text)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VoltraColor.textDim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(VoltraColor.bgElev)
                .overlay(
                    Capsule().stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 18)
    }

    /// Label shown in the collapsed picker. Mirrors `WorkoutSession.groupLabel`
    /// logic so the displayed value matches what would be persisted.
    private var currentLabel: String {
        guard let g = group else { return "None" }
        if g == .custom {
            let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Custom\u{2026}" : trimmed
        }
        return g.displayName
    }
}

// MARK: - Custom-label sheet

/// Small text-entry sheet for the "Custom\u{2026}" option. Presented by the
/// parent via `.sheet(isPresented:)`. Mirrors the existing custom-day sheet
/// pattern so the visual language stays consistent.
struct WorkoutGroupCustomSheet: View {

    @Binding var customLabel: String
    @Binding var group: WorkoutGroup?
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Name your group")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    TextField("e.g. Hinge, Power, Conditioning", text: $customLabel)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(VoltraColor.bgElev2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(VoltraColor.text)
                    Button {
                        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            // Empty input falls back to nil — same contract as
                            // `WorkoutSession` init's whitespace normalization.
                            group = nil
                            customLabel = ""
                        } else {
                            group = .custom
                            customLabel = trimmed
                        }
                        isPresented = false
                    } label: {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(VoltraColor.accent)
                            .foregroundColor(VoltraColor.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Custom Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .presentationDetents([.medium])
        .buildBadgeOverlay()
    }
}

#Preview {
    struct Wrapper: View {
        @State var group: WorkoutGroup? = nil
        @State var customLabel = ""
        @State var showingCustom = false
        var body: some View {
            VStack {
                WorkoutGroupPicker(
                    group: $group,
                    customLabel: $customLabel,
                    onRequestCustom: { showingCustom = true }
                )
            }
            .frame(maxHeight: .infinity)
            .background(VoltraColor.bg)
            .sheet(isPresented: $showingCustom) {
                WorkoutGroupCustomSheet(
                    customLabel: $customLabel,
                    group: $group,
                    isPresented: $showingCustom
                )
            }
        }
    }
    return Wrapper()
}
