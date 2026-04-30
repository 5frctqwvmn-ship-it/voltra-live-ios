// b66 V4.2: Superset switcher banner.
//
// User ask (verbatim): "This is the old V1 live view UI. This needs to
// live on the new UI." (Re: the V1 ACTIVE/NEXT swap banner — commit
// e22aaa6, b47, function `supersetBanner` on `LiveCaptureView`.)
//
// Spec (locked via MC this session):
//   • Layout: V1 verbatim — NOW · L · ExerciseA   [⇄ SWAP]   NEXT · R · ExerciseB · ##lb
//   • Delta vs. V1: a breathing mint ring (1.4 s autoreverse, 2.5 pt) wraps
//     the ACTIVE side so on the new live screen the user can see at a
//     glance which Voltra they are currently lifting. V1 lived inside the
//     V1 live view and there was no ambiguity; on V3 the panel header has
//     a separate active dot, so the breathing ring on the banner is the
//     deltaring that ties the two together.
//   • b71 (V4-D21 part 2): visibility gate widened from
//     "supersetTag AND bothPaired" to
//     "(supersetTag AND bothPaired) OR hasActiveSupersetChain". The
//     b71 routing flip (Step 3) sends single-Voltra chain users through
//     V2; they need the banner so they can see / SWAP between chained
//     exercises. V1's `LiveCaptureView.swift:120` gates exactly on
//     `mdm.hasActiveSupersetChain`, so the new gate is V1-equivalent.
//   • Mount: top of LiveCaptureViewV2 scroll, between the assignment
//     panel and the live grid.
//
// b71 (V4-D21 part 2) chain-aware swap behavior:
//
// Pre-b71 the banner's `swap()` did the minimal V1 weight-mirror:
//   1. Save current pending weight to the OUTGOING side mirror.
//   2. Flip the active slot via `mdm.flipSupersetActiveSlot()`.
//   3. Restore the INCOMING side's stored weight via the per-side mirror.
//   4. Host-owned device push (via `onAfterSwap`).
//
// V1's `LiveCaptureView.swapSupersetSide()` (line 908) does FIVE things
// the b66 banner skipped, all of which matter for chain users:
//
//   1. `session.forceFinalizeCurrentSet()` if a set is in flight — telemetry-
//      detected sets must commit under the OUTGOING exercise's instance
//      BEFORE the slot flips, otherwise the set is attributed to the wrong
//      exercise.
//   2. `mdm.unload(target: outgoing)` so the outgoing Voltra's cable goes
//      slack while the user walks to the other side. b53 explicitly
//      removed the SYMMETRIC auto-LOAD on the incoming side (dangerous —
//      the cable would tension up while the user was still mid-walk),
//      but the outgoing UNLOAD is still mandatory.
//   3. `logging.switchActiveInstanceByExerciseName(incoming.exerciseName)`
//      so future telemetry sets log under the right exercise.
//   4. Prefer `mdm.activeSupersetEntry?.plannedWeightLb` over the
//      per-side mirror when restoring the incoming weight, so each
//      chained exercise remembers its own starting weight.
//   5. Re-anchor the cascade + push device state — already done by
//      `onAfterSwap` (host's `pushUpcomingStateToDevice`), with the
//      `reanchorCascadeIfActive` call done here.
//
// b71 V4-D21 ports all five into `swap()`. The banner now requires
// `SessionStore` as an `@EnvironmentObject` so it can call
// `forceFinalizeCurrentSet()` directly. Hosts that previously omitted
// the env (none in production) would need to inject one, but the only
// callsite (`LiveCaptureViewV2`) already has session as an env object.
//
// SWAP safety (preserved from b53):
//   • NO auto-LOAD on the INCOMING side. The user manually taps LOAD
//     when they're ready. This is non-negotiable per the b53 ADR — the
//     user reported the b48-era auto-LOAD as dangerous.
//   • The outgoing UNLOAD IS sent so the cable goes slack.

import SwiftUI

// b66 hotfix: explicit `@MainActor` so the body's reads of `mdm.supersetTag`
// (and other main-actor-isolated MDM state) are safe under Xcode 26 / Swift 6
// strict concurrency. SwiftUI's implicit body isolation is sufficient on
// most call paths, but the static helpers in this file (and the swap()
// method that touches multiple main-actor stores) need belt-and-suspenders.
@MainActor
struct SupersetSwitcherBanner: View {
    @ObservedObject var mdm: MultiDeviceManager
    @ObservedObject var logging: LoggingStore
    /// b71 (V4-D21 part 2): SessionStore needed for the V1-verbatim swap
    /// flow's set-finalize step. Optional so the banner can still
    /// instantiate from non-live contexts (previews, etc.); when nil the
    /// finalize step is skipped and the swap behaves like the b66
    /// weight-mirror-only path.
    var session: SessionStore? = nil

    /// Optional callback so the host can push device state after the
    /// swap. V1 called its own private `pushUpcomingStateToDevice`; in V3
    /// the host owns the writer router and decides when to push.
    var onAfterSwap: (() -> Void)? = nil

    // Breathing ring animation phase. SwiftUI's autoreverse on a Bool
    // toggle is the simplest stable pulse pattern.
    @State private var breathing = false

    var body: some View {
        // b71 (V4-D21 part 2): visibility gate is now V1-equivalent.
        // Pre-b71: "supersetTag AND bothPaired" — hid the banner from
        // single-Voltra chain users entirely. Post-b71: ALSO show when
        // `mdm.hasActiveSupersetChain` regardless of pair state, since
        // V1 LiveCaptureView.swift:120 gates exactly on that. The Step
        // 3 routing flip sends chain users to V2 unconditionally, so
        // the banner must render for them too.
        let bothPaired = mdm.left.connectionState.isConnected
            && mdm.right.connectionState.isConnected
        if (mdm.supersetTag && bothPaired) || mdm.hasActiveSupersetChain {
            content
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        let active = mdm.supersetActiveSlot
        let inactive = active.other
        // b71 (V4-D21 part 2): prefer chain-entry exerciseName +
        // plannedWeightLb when the chain has ≥ 2 entries, mirroring V1
        // LiveCaptureView.swift:805-814. Falls back to the per-side
        // label cache + per-side weight mirror when no chain is
        // populated (legacy two-exercise / single-Voltra-paired flow).
        let activeChain = mdm.activeSupersetEntry
        let nextChain   = mdm.nextSupersetEntry
        let activeLabel = activeChain?.exerciseName
            ?? (active == .left
                ? mdm.supersetLeftExercise
                : mdm.supersetRightExercise)
        let inactiveLabel = nextChain?.exerciseName
            ?? (inactive == .left
                ? mdm.supersetLeftExercise
                : mdm.supersetRightExercise)
        let inactiveWeight = nextChain?.plannedWeightLb
            ?? (inactive == .left
                ? mdm.supersetLeftWeightLb
                : mdm.supersetRightWeightLb)
        let activeName = activeLabel.isEmpty
            ? "Exercise \(active == .left ? "A" : "B")"
            : activeLabel
        let inactiveName = inactiveLabel.isEmpty
            ? "Exercise \(inactive == .left ? "A" : "B")"
            : inactiveLabel

        HStack(spacing: 10) {
            // ACTIVE side — wrapped in breathing-ring delta.
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW \u{2022} \(active.label.uppercased())")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.accent)
                Text(activeName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VoltraColor.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                // b66 delta: breathing mint ring on active side.
                RoundedRectangle(cornerRadius: 6)
                    .stroke(VoltraColor.accent.opacity(breathing ? 0.85 : 0.25),
                            lineWidth: 2.5)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: breathing
                    )
            )

            Spacer(minLength: 6)

            // SWAP button — V1 verbatim.
            Button {
                swap()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("SWAP")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.0)
                }
                .foregroundColor(VoltraColor.accent)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(VoltraColor.accent.opacity(0.18))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap superset side")

            Spacer(minLength: 6)

            // NEXT side preview — V1 verbatim, no ring.
            VStack(alignment: .trailing, spacing: 2) {
                Text("NEXT \u{2022} \(inactive.label.uppercased())")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.textDim)
                HStack(spacing: 6) {
                    Text(inactiveName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(VoltraColor.textDim)
                        .lineLimit(1)
                    Text("\(formatLbCompact(inactiveWeight)) lb")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VoltraColor.accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { breathing = true }
    }

    // MARK: - Swap (b71 V4-D21 part 2 — V1 verbatim chain-aware flow)

    /// Full chain-aware swap. Mirrors V1
    /// `LiveCaptureView.swapSupersetSide()` (line 908) verbatim except
    /// for the auto-LOAD on the incoming side (b53 removed it; we keep
    /// it removed). The five steps are commented inline.
    private func swap() {
        let outgoing = mdm.supersetActiveSlot

        // 1. Auto-end any in-flight set on the outgoing side. The set
        //    will be auto-logged via SessionStore's normal finalize
        //    path once it lands in completedSets, attributed to the
        //    OUTGOING exercise's activeInstance (which is still set
        //    at this point because step 3 below hasn't fired yet).
        if let s = session, s.currentSet != nil {
            s.forceFinalizeCurrentSet()
        }

        // 2. Save current pending weight to the OUTGOING side mirror
        //    so a subsequent swap restores it. Stays in sync with
        //    mdm.supersetLeft/RightWeightLb regardless of chain mode.
        let curWeight = logging.pendingPlannedWeightLb ?? 0
        switch outgoing {
        case .left:  mdm.supersetLeftWeightLb  = curWeight
        case .right: mdm.supersetRightWeightLb = curWeight
        }

        // 3. UNLOAD the outgoing Voltra so its cable goes slack while
        //    the user walks to the other side. SWAP safety (b53):
        //    no auto-LOAD on the incoming side — the user must tap
        //    LOAD when they're ready. mdm.unload's target arg is
        //    optional; we pass `outgoing` explicitly.
        mdm.unload(target: outgoing)

        // 4. Flip the active slot (or advance the chain index if
        //    a chain is populated). WriterRouter + telemetry routing
        //    both follow supersetActiveSlot, so this single line
        //    atomically moves the in-app side.
        mdm.flipSupersetActiveSlot()

        // 5. Switch the active instance so future auto-logged sets
        //    are attributed to the INCOMING exercise. No-op when no
        //    chain entry exists (single-exercise mode — SWAP is
        //    still useful as an L↔R toggle there).
        if let incomingEntry = mdm.activeSupersetEntry {
            _ = logging.switchActiveInstanceByExerciseName(incomingEntry.exerciseName)
        }

        // 6. Restore the incoming side's stored weight. Prefer the
        //    chain entry's plannedWeightLb when available so each
        //    exercise remembers its own starting weight; fall back
        //    to the per-side mirror otherwise.
        let incoming = mdm.supersetActiveSlot
        let mirrored = (incoming == .left
                        ? mdm.supersetLeftWeightLb
                        : mdm.supersetRightWeightLb)
        let restored: Double = mdm.activeSupersetEntry?.plannedWeightLb ?? mirrored
        logging.pendingPlannedWeightLb = restored
        logging.reanchorCascadeIfActive(toLb: restored)

        // 7. Host-owned device push (V1 used its private
        //    pushUpcomingStateToDevice). NOT auto-LOAD; just retarget
        //    the writer with the restored weight.
        onAfterSwap?()
    }

    // MARK: - Helpers

    /// Compact lb formatter — V1 had this private to `LiveCaptureView`.
    /// Inlined here so the banner is self-contained.
    private func formatLbCompact(_ lb: Double) -> String {
        if lb >= 100 {
            return String(format: "%.0f", lb)
        } else if lb >= 10 {
            // 1 decimal if not whole, else integer.
            return lb.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", lb)
                : String(format: "%.1f", lb)
        } else {
            return String(format: "%.1f", lb)
        }
    }
}
