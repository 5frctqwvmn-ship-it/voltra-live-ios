// VoltraUnitHeader.swift
//
// b67 V4.2 — single canonical unit-status header for VOLTRA Live.
//
// Replaces (deleted in same commit):
//   • VoltraAssignmentPanel.swift          — had the duplicate `VL1 ⌚ │ … │ SS` strip
//   • LiveStatusPill (legacy)              — top wordmark + LIVE pill chrome
//   • LeftRightStatusPill (legacy)         — `Left ● Right ●` summary pill
//   • DeviceStatusStrip / VoltraWordmark   — VOLTRA wordmark text label
//
// Bugs closed by this view:
//   • B67-03 — kills the 4-pill row + 3-state HR regression on home
//   • B67-06 — single source of truth for unit chrome across all screens
//   • B67-08 — collapse all duplicate unit-status surfaces into one component
//
// Mount points (exactly one per screen, per B67-08 invariant):
//   • LoggingHomeView                      → VoltraUnitHeader(mdm: …, hk: …)
//   • ExerciseDetailView                   → VoltraUnitHeader(mdm: …, hk: …, exerciseName: name)
//   • LiveCaptureViewV2 / LiveWorkoutScreen → VoltraUnitHeader(mdm: …, hk: …, exerciseName: name, isReadOnly: live)
//
// Spec (locked via B67_BUG_QUEUE.md, Bug 08 + cross-cutting flag #3):
//   • Single horizontal row: `L`  `R`  `⋏`  `●●`
//   • NO `SS` pill (superset lives in `SupersetSwitcherBanner` only).
//   • NO `VL1` device label, NO `⌚` watch glyph, NO `VOLTRA` wordmark,
//     NO separate header glyph row, NO `Left ● Right ●` summary pill.
//   • NO breathing ring on the active pill (B67-03 reverts the b66 V4.2 delta).
//   • Tap-to-pair on greyed L/R (fast warn-color pulse while pair-scan in flight).
//   • L/R always render. ⋏ (combined) only renders when BOTH paired.
//   • `●●` HR pill is 3-state per B67-03:
//       dark  — HK auth not yet requested
//       blink — HK authorized but no recent HR sample
//       solid — receiving live HR samples
//   • Mirror rule 1A: no exerciseName → writes mdm.workoutMode
//                     exerciseName     → writes mdm.exerciseAssignmentOverride[name]
//   • isReadOnly = true locks every pill (mid-set lock).

import SwiftUI
import Combine

// MARK: - Public model: assignment "mode" the header exposes
//
// Keeps the legacy `VoltraAssignment` enum intact for downstream callers
// (LoggingHomeView's pair-sheet plumbing reads it). SS is dropped from the
// user-facing pill set but kept in the enum for write-back compatibility
// (the SupersetSwitcherBanner is the only writer now).

enum VoltraAssignment: Equatable {
    case left          // singleLeft
    case right         // singleRight
    case combined      // ⋏ — both, summed
    case independent   // •• (legacy — NOT rendered as a pill in the new header)
    case superset      // SS (legacy — NOT rendered; lives in SupersetSwitcherBanner)
}

extension VoltraAssignment {
    @MainActor
    static func currentMode(exerciseName: String?, mdm: MultiDeviceManager) -> VoltraAssignment {
        if mdm.supersetTag {
            return .superset
        }
        if let name = exerciseName, !name.isEmpty,
           let override = mdm.exerciseAssignmentOverride[name] {
            return modeFor(override)
        }
        return modeFor(mdm.workoutMode)
    }

    private static func modeFor(_ wm: WorkoutMode) -> VoltraAssignment {
        switch wm {
        case .singleLeft:   return .left
        case .singleRight:  return .right
        case .combined:     return .combined
        case .independent:  return .independent
        case .superset:     return .superset
        }
    }

    var asWorkoutMode: WorkoutMode {
        switch self {
        case .left:        return .singleLeft
        case .right:       return .singleRight
        case .combined:    return .combined
        case .independent: return .independent
        case .superset:    return .superset
        }
    }
}

// MARK: - Header

@MainActor
struct VoltraUnitHeader: View {
    @ObservedObject var mdm: MultiDeviceManager
    @ObservedObject var hk: HealthKitStore

    /// If set, this header WRITES to the per-exercise override dict instead
    /// of `mdm.workoutMode`. Mirror rule 1A.
    var exerciseName: String? = nil

    /// If true, all pills are non-interactive (live-set lock — rule 2A).
    var isReadOnly: Bool = false

    /// Hook for Bug 04+05+07 — when the user taps a greyed L/R pill, route
    /// the pair request through the shared `PairingCoordinator` so all three
    /// mount points (home / detail / live) get the same modal pair flow.
    /// `nil` = fall back to `mdm.requestPairScan(for:)` (single-device).
    var onPairRequest: ((DeviceSlot) -> Void)? = nil

    @State private var searchingSlot: DeviceSlot? = nil

    var body: some View {
        HStack(spacing: 8) {
            pill(.left,     glyph: "L",  enabled: true)
            pill(.right,    glyph: "R",  enabled: true)
            if bothPaired {
                pill(.combined, glyph: "\u{22CF}", enabled: true)  // ⋏
            }
            Spacer(minLength: 4)
            heartRatePill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: mdm.left.connectionState) { _, new in
            if searchingSlot == .left && new.isConnected { searchingSlot = nil }
        }
        .onChange(of: mdm.right.connectionState) { _, new in
            if searchingSlot == .right && new.isConnected { searchingSlot = nil }
        }
    }

    // MARK: - L/R/⋏ Pills

    @ViewBuilder
    private func pill(_ assignment: VoltraAssignment, glyph: String, enabled: Bool) -> some View {
        let isActive = (current == assignment)
        let isGreyed = !enabled || !slotPaired(for: assignment)
        let isSearching = (searchingSlot != nil) && (
            (assignment == .left  && searchingSlot == .left) ||
            (assignment == .right && searchingSlot == .right)
        )

        Button {
            handleTap(assignment)
        } label: {
            Text(glyph)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .kerning(0.8)
                .foregroundColor(pillTextColor(active: isActive, greyed: isGreyed))
                .frame(minWidth: 28, minHeight: 28)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(pillBgColor(active: isActive, greyed: isGreyed))
                )
                .overlay(pillRing(active: isActive, searching: isSearching))
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly || (isGreyed && !canTapGreyed(assignment)))
        .accessibilityLabel(accessibilityLabel(assignment))
    }

    /// B67-03 spec: NO breathing ring on active pill (revert of V4.2 delta).
    /// Searching = fast warn-color pulse (0.4 s).
    /// Active    = static mint border.
    /// Otherwise = static border.
    @ViewBuilder
    private func pillRing(active: Bool, searching: Bool) -> some View {
        if searching {
            TimelineView(.animation(minimumInterval: 0.4)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (Int(t / 0.4) % 2 == 0) ? 0.85 : 0.25
                RoundedRectangle(cornerRadius: 8)
                    .stroke(VoltraColor.warn.opacity(phase), lineWidth: 2.5)
            }
        } else if active {
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.accent, lineWidth: 1.5)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.border, lineWidth: 1)
        }
    }

    // MARK: - HR pill (3-state per B67-03)

    private enum HRState { case dark, blinking, solid }

    private var hrState: HRState {
        // Dark: HK never authorized.
        guard hk.hasRequestedAuthorization else { return .dark }
        // Blinking: authorized but no current HR sample.
        if hk.currentHR == nil { return .blinking }
        // Solid: live HR streaming.
        return .solid
    }

    private var heartRatePill: some View {
        // Two stacked dots — the `●●` glyph that the design language uses.
        // Color and animation driven by hrState.
        Group {
            switch hrState {
            case .dark:
                hrDots(color: VoltraColor.textFaint, opacity: 0.45)
            case .blinking:
                TimelineView(.animation(minimumInterval: 0.5)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let on = Int(t / 0.5) % 2 == 0
                    hrDots(color: VoltraColor.accent, opacity: on ? 0.95 : 0.25)
                }
            case .solid:
                hrDots(color: VoltraColor.accent, opacity: 0.95)
            }
        }
        .frame(minWidth: 28, minHeight: 28)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(VoltraColor.bgElev2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .accessibilityLabel(hrAccessibilityLabel)
    }

    private func hrDots(color: Color, opacity: Double) -> some View {
        Text("\u{2022}\u{2022}")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .kerning(0.8)
            .foregroundColor(color.opacity(opacity))
    }

    private var hrAccessibilityLabel: String {
        switch hrState {
        case .dark:     return "Heart rate not authorized"
        case .blinking: return "Heart rate authorized, awaiting first sample"
        case .solid:    return "Heart rate \(hk.currentHR ?? 0) bpm"
        }
    }

    // MARK: - Tap dispatch

    private func handleTap(_ a: VoltraAssignment) {
        guard !isReadOnly else { return }

        // B67-04+05+07: greyed L or R = pair-scan request via shared coordinator.
        if (a == .left || a == .right), !slotPaired(for: a) {
            let slot: DeviceSlot = (a == .left) ? .left : .right
            searchingSlot = slot
            if let coordinator = onPairRequest {
                coordinator(slot)
            } else {
                mdm.requestPairScan(for: slot)
            }
            return
        }

        // B67-08: SS is no longer a pill on this header. Tap dispatch only
        // covers L / R / ⋏. Independent + Superset are not user-facing here.
        if let name = exerciseName, !name.isEmpty {
            var dict = mdm.exerciseAssignmentOverride
            dict[name] = a.asWorkoutMode
            mdm.exerciseAssignmentOverride = dict
        } else {
            mdm.workoutMode = a.asWorkoutMode
        }
    }

    // MARK: - Helpers

    private var current: VoltraAssignment {
        VoltraAssignment.currentMode(exerciseName: exerciseName, mdm: mdm)
    }

    private var bothPaired: Bool {
        mdm.left.connectionState.isConnected
            && mdm.right.connectionState.isConnected
    }

    private func slotPaired(for a: VoltraAssignment) -> Bool {
        switch a {
        case .left:        return mdm.left.connectionState.isConnected
        case .right:       return mdm.right.connectionState.isConnected
        case .combined,
             .independent,
             .superset:    return bothPaired
        }
    }

    private func canTapGreyed(_ a: VoltraAssignment) -> Bool {
        switch a {
        case .left, .right: return true
        default:            return false
        }
    }

    private func pillTextColor(active: Bool, greyed: Bool) -> Color {
        if active { return VoltraColor.bg }
        if greyed { return VoltraColor.textFaint }
        return VoltraColor.text
    }

    private func pillBgColor(active: Bool, greyed: Bool) -> Color {
        if active { return VoltraColor.accent }
        if greyed { return VoltraColor.bgElev2.opacity(0.4) }
        return VoltraColor.bgElev2
    }

    private func accessibilityLabel(_ a: VoltraAssignment) -> String {
        switch a {
        case .left:        return "Single left"
        case .right:       return "Single right"
        case .combined:    return "Combined — both Voltras summed"
        case .independent: return "Independent — both Voltras separate"
        case .superset:    return "Superset chain"
        }
    }
}
