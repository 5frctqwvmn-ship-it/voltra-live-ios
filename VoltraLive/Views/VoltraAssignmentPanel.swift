// b66 V4.2: ASSIGN TO VOLTRA panel.
//
// User asks (this session, in order):
//   1. "Move VOLTRA1 down, put the VL1, the L/R/⋏/••, SS, and the watch
//      all in the same plane, all the same line where the header is.
//      What does SS stand for?" → SS = SUPERSET.
//   2. MC-locked header layout: `VL1 ⌚ │ L R ⋏ •• │ SS`.
//   3. MC-locked single-Voltra UX: L+R always render; ⋏ (combined) and
//      •• (independent) are hidden until BOTH Voltras are paired.
//   4. MC-locked ACTIVE/NEXT vocabulary on the superset switcher (handled
//      in `SupersetSwitcherBanner.swift`, not here).
//   5. MC-locked mirror rule 1A: day screen sets the default
//      (`mdm.workoutMode`); exercise screen overrides per-exercise via
//      `mdm.exerciseAssignmentOverride[name]`. Live screen reads but does
//      not write (`isReadOnly` flag — pills lock during live set).
//   6. MC-locked breathing-ring spec: mint, 1.4 s autoreverse, 2.5 pt
//      stroke on the ACTIVE pill. Fast pulse (warn color, 0.4 s) on a
//      greyed pill that the user just tapped to request a pair scan.
//
// Mount points (all three):
//   • LoggingHomeView (day picker) — no exerciseName, default scope.
//   • ExerciseDetailView — exerciseName: <current exercise>, override scope.
//   • LiveCaptureViewV2 — exerciseName + isReadOnly while a set is live.

import SwiftUI
import Combine

// MARK: - Public model: assignment "mode" the panel exposes

/// User-facing pill states. Maps to `WorkoutMode` for write-back, but the
/// panel itself thinks in terms of these because the L/R/⋏/•• pills are
/// the user's mental model. SS lives in this enum too because the superset
/// pill toggles `mdm.supersetTag` (NOT `workoutMode = .superset` — those
/// are two different switches in the canonical engine).
enum VoltraAssignment: Equatable {
    case left          // singleLeft
    case right         // singleRight
    case combined      // ⋏ — both, summed
    case independent   // •• — both, separate
    case superset      // SS — superset chain (also flips mdm.supersetTag)
}

extension VoltraAssignment {
    /// Resolve the panel's current pill state from MDM, given an optional
    /// exercise name. If `exerciseName` is set and an override exists for
    /// that name, the override wins; otherwise we read `mdm.workoutMode`.
    /// SS is reported when the superset tag is set (regardless of mode).
    static func currentMode(exerciseName: String?, mdm: MultiDeviceManager) -> VoltraAssignment {
        // SS is a separate orthogonal switch — superset tag wins for
        // display because it is the most user-meaningful state.
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

    /// Map back to a `WorkoutMode` for write-back. SS is special — the
    /// host writes `mdm.supersetTag = true` AND leaves `workoutMode`
    /// alone (or sets it to .superset, depending on canonical wiring).
    /// Returning .independent here is the safe-default fall-through; the
    /// host's tap handler does the real SS dispatch.
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

// MARK: - Panel

struct VoltraAssignmentPanel: View {
    @ObservedObject var mdm: MultiDeviceManager

    /// If set, this panel WRITES to the per-exercise override dict instead
    /// of `mdm.workoutMode`. Mirror rule 1A.
    var exerciseName: String? = nil

    /// If true, all pills are non-interactive (live-set lock — rule 2A).
    var isReadOnly: Bool = false

    // Searching state for the greyed-pill pulse — when the user taps
    // L or R while that side is unpaired, we kick a pair-scan request
    // and show a fast pulse on that pill until the connection state
    // changes. Local UI state only.
    @State private var searchingSlot: DeviceSlot? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            pillRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // When connection state changes, clear the searching marker —
        // the pair sheet either succeeded (now connected) or the user
        // dismissed it (still disconnected; let them tap again).
        .onChange(of: mdm.left.connectionState) { _, new in
            if searchingSlot == .left && new.isConnected { searchingSlot = nil }
        }
        .onChange(of: mdm.right.connectionState) { _, new in
            if searchingSlot == .right && new.isConnected { searchingSlot = nil }
        }
    }

    // MARK: - Header  `VL1 ⌚ │ L R ⋏ •• │ SS`
    //
    // Single-line layout, locked via MC. The header itself is non-
    // interactive — it is the title strip for the panel below. The pills
    // are the row underneath. We render the same glyph set in both rows
    // so the user can see "VL1 has these options" and then tap them.

    private var header: some View {
        HStack(spacing: 8) {
            Text("VL1")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(VoltraColor.textDim)
                .kerning(1.0)
            // ⌚ — placeholder for future watch-pair slot. Faint mint so
            // the user sees the "next paired device" affordance is here
            // when watch-pair lands. NOT a tap target until then.
            Image(systemName: "applewatch")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(VoltraColor.textFaint)
            divider
            // Echo the pill glyph set in the header so the user can read
            // the row vocabulary at a glance.
            headerGlyph("L")
            headerGlyph("R")
            if bothPaired {
                headerGlyph("\u{22CF}")     // ⋏
                headerGlyph("\u{2022}\u{2022}")  // ••
            }
            divider
            headerGlyph("SS")
            Spacer(minLength: 0)
        }
    }

    private func headerGlyph(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(VoltraColor.textDim)
            .kerning(0.6)
    }

    private var divider: some View {
        Text("|")
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(VoltraColor.textFaint)
    }

    // MARK: - Pill row

    private var pillRow: some View {
        HStack(spacing: 8) {
            pill(.left,  glyph: "L",  enabled: true)
            pill(.right, glyph: "R",  enabled: true)
            if bothPaired {
                pill(.combined,    glyph: "\u{22CF}",     enabled: true)
                pill(.independent, glyph: "\u{2022}\u{2022}", enabled: true)
            }
            Spacer(minLength: 4)
            pill(.superset, glyph: "SS", enabled: bothPaired)
        }
    }

    // MARK: - Pill

    @ViewBuilder
    private func pill(_ assignment: VoltraAssignment, glyph: String, enabled: Bool) -> some View {
        let isActive = (current == assignment)
        let isGreyed = !enabled || !slotPaired(for: assignment)
        let isSearching = (searchingSlot != nil) && (assignment == .left
            ? searchingSlot == .left
            : assignment == .right ? searchingSlot == .right : false)

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
        .disabled(isReadOnly || isGreyed && !canTapGreyed(assignment))
        .accessibilityLabel(accessibilityLabel(assignment))
    }

    // Active = mint breathing ring (1.4 s autoreverse).
    // Searching = fast warn-color pulse (0.4 s).
    // Otherwise = static border.
    @ViewBuilder
    private func pillRing(active: Bool, searching: Bool) -> some View {
        if searching {
            // Fast pulse — implemented with TimelineView so it does not
            // need a @State toggle and cannot leak between pills.
            TimelineView(.animation(minimumInterval: 0.4)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (Int(t / 0.4) % 2 == 0) ? 0.85 : 0.25
                RoundedRectangle(cornerRadius: 8)
                    .stroke(VoltraColor.warn.opacity(phase), lineWidth: 2.5)
            }
        } else if active {
            BreathingRing()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoltraColor.border, lineWidth: 1)
        }
    }

    // MARK: - Tap dispatch

    private func handleTap(_ a: VoltraAssignment) {
        guard !isReadOnly else { return }

        // Greyed L or R = pair-scan request.
        if (a == .left || a == .right), !slotPaired(for: a) {
            let slot: DeviceSlot = (a == .left) ? .left : .right
            searchingSlot = slot
            mdm.requestPairScan(for: slot)
            return
        }

        // SS toggle — flips the supersetTag rather than writing
        // workoutMode. Two distinct switches in the canonical engine.
        if a == .superset {
            mdm.supersetTag.toggle()
            return
        }

        // Standard pill — write back to override scope (per-exercise) or
        // to the canonical workoutMode (day default).
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

    /// Is the slot this pill represents paired? L/R are direct; ⋏/••
    /// require both; SS requires both.
    private func slotPaired(for a: VoltraAssignment) -> Bool {
        switch a {
        case .left:        return mdm.left.connectionState.isConnected
        case .right:       return mdm.right.connectionState.isConnected
        case .combined,
             .independent,
             .superset:    return bothPaired
        }
    }

    /// Greyed pills are tappable ONLY when the tap is meaningful — i.e.
    /// L/R when unpaired (request pair scan). ⋏/•• and SS when not
    /// both-paired are dead-greyed.
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

// MARK: - BreathingRing

/// Mint, 1.4 s autoreverse, 2.5 pt stroke. Self-contained so it can be
/// reused on the superset switcher banner without coupling to the panel.
private struct BreathingRing: View {
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(VoltraColor.accent.opacity(on ? 0.85 : 0.25),
                    lineWidth: 2.5)
            .animation(
                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: on
            )
            .onAppear { on = true }
    }
}
