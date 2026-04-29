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
//   • Visibility: only when `mdm.supersetTag == true` AND both Voltras
//     are paired. (Single-Voltra users never see the banner.)
//   • Mount: top of LiveCaptureViewV2 scroll, between the assignment
//     panel and the live grid.
//
// Logic preserved verbatim from V1:
//   • Save the current pending weight to whichever side WAS active.
//   • Flip the active slot via `mdm.flipSupersetActiveSlot()` — writer
//     router immediately retargets.
//   • Restore the incoming side's stored weight via
//     `logging.pendingPlannedWeightLb` and
//     `logging.reanchorCascadeIfActive(toLb:)`.
//   • Device push is delegated to the host via the `onAfterSwap` callback
//     so the V3 host can call its own `pushUpcomingStateToDevice` (private
//     to that view).

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

    /// Optional callback so the host can push device state after the
    /// swap. V1 called its own private `pushUpcomingStateToDevice`; in V3
    /// the host owns the writer router and decides when to push.
    var onAfterSwap: (() -> Void)? = nil

    // Breathing ring animation phase. SwiftUI's autoreverse on a Bool
    // toggle is the simplest stable pulse pattern.
    @State private var breathing = false

    var body: some View {
        // Visibility gate: superset tag set AND both Voltras paired.
        // Same gate V1 used (it lived inside a wrapping `if`); we render
        // EmptyView() when it does not apply so callers can mount the
        // banner unconditionally and let it self-hide.
        if mdm.supersetTag && mdm.left.connectionState.isConnected
            && mdm.right.connectionState.isConnected {
            content
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        let active = mdm.supersetActiveSlot
        let inactive = active.other
        let activeLabel = (active == .left
                           ? mdm.supersetLeftExercise
                           : mdm.supersetRightExercise)
        let inactiveLabel = (inactive == .left
                             ? mdm.supersetLeftExercise
                             : mdm.supersetRightExercise)
        let inactiveWeight = (inactive == .left
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

    // MARK: - Swap (V1 verbatim, host-decoupled)

    private func swap() {
        let outgoing = mdm.supersetActiveSlot
        // 1. Save current pending weight to the OUTGOING side.
        let curWeight = logging.pendingPlannedWeightLb ?? 0
        switch outgoing {
        case .left:  mdm.supersetLeftWeightLb  = curWeight
        case .right: mdm.supersetRightWeightLb = curWeight
        }
        // 2. Flip active slot. WriterRouter retargets.
        mdm.flipSupersetActiveSlot()
        // 3. Restore the INCOMING side's stored weight.
        let incoming = mdm.supersetActiveSlot
        let restored = (incoming == .left
                        ? mdm.supersetLeftWeightLb
                        : mdm.supersetRightWeightLb)
        logging.pendingPlannedWeightLb = restored
        logging.reanchorCascadeIfActive(toLb: restored)
        // 4. Host-owned device push (V1 used a private helper here).
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
