// RestTimerView.swift
// Rest-between-sets tracker.
//
// User scope (v0.3.3, verbatim): "The app should also track my rest between
// sets and track that also give me an option to set a rest duration and
// there should be an indicator when I'm approaching the time."
//
// Behavior:
//   - Counts UP from when the most recent set was logged (`anchor`).
//   - User can tap target chip to cycle through preset durations (45s, 60s,
//     75s, 90s, 120s, 180s, off) — last choice persists per app launch.
//   - Color states:
//       grey   — < target − 10s
//       amber  — within 10s of target ("approaching")
//       green  — at or past target ("ready")
//   - Subtle pulsing ring during the approaching window.
//   - Haptics: light tap when entering the approaching window, success
//     thunk when the target is reached. Both fire ONCE per rest window.
//   - When `anchor` is nil (no sets yet) the chip shows "—:—" placeholder.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RestTimerView: View {
    /// The completion timestamp of the most recent logged set in the active
    /// exercise instance. nil means "no sets yet — show placeholder".
    let anchor: Date?

    /// Target rest in seconds. nil disables the indicator entirely.
    @Binding var targetSeconds: Int?

    /// Tick to redraw once a second.
    @State private var now: Date = Date()
    /// Has the "approaching" haptic already fired for the current rest?
    @State private var firedApproachingHaptic = false
    /// Has the "ready" haptic already fired for the current rest?
    @State private var firedReadyHaptic = false
    /// Last anchor we saw — used to reset the haptic latches when a new set
    /// is logged.
    @State private var lastSeenAnchor: Date? = nil

    /// Cycle order for the target chip. nil = off.
    private static let targetCycle: [Int?] = [60, 75, 90, 120, 180, nil, 45]

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            elapsedTile
            Spacer(minLength: 4)
            targetChip
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(timer) { t in
            now = t
            updateHaptics()
        }
        .onChange(of: anchor) { _, newAnchor in
            // New set logged → reset haptics for the new rest window.
            if newAnchor != lastSeenAnchor {
                lastSeenAnchor = newAnchor
                firedApproachingHaptic = false
                firedReadyHaptic = false
            }
        }
        .onAppear { lastSeenAnchor = anchor }
    }

    // MARK: - Subviews

    private var elapsedTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("REST")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundColor(VoltraColor.textDim)
            HStack(spacing: 8) {
                Text(elapsedString)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(elapsedColor)
                    .contentTransition(.numericText())
                if state == .approaching {
                    Circle()
                        .fill(VoltraColor.warn)
                        .frame(width: 8, height: 8)
                        .opacity(pulseOpacity)
                }
                if state == .ready {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(VoltraColor.accent)
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
    }

    /// Tap to cycle preset target durations (or disable).
    private var targetChip: some View {
        Button {
            cycleTarget()
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                Text(targetLabel)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(VoltraColor.textDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(VoltraColor.bgElev2)
            .overlay(
                Capsule().stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rest target")
        .accessibilityValue(targetLabel)
        .accessibilityHint("Tap to change target rest duration")
    }

    // MARK: - State / formatting

    private enum RestState {
        case idle        // no anchor or target
        case resting     // counting up, well below target
        case approaching // within the last 10s of the target
        case ready       // at or past target
    }

    private var elapsed: TimeInterval {
        guard let a = anchor else { return 0 }
        return max(0, now.timeIntervalSince(a))
    }

    private var state: RestState {
        guard anchor != nil else { return .idle }
        guard let t = targetSeconds, t > 0 else { return .resting }
        let e = elapsed
        if e >= Double(t) { return .ready }
        if e >= Double(t - 10) { return .approaching }
        return .resting
    }

    private var elapsedString: String {
        guard anchor != nil else { return "--:--" }
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var elapsedColor: Color {
        switch state {
        case .idle:        return VoltraColor.textFaint
        case .resting:     return VoltraColor.text
        case .approaching: return VoltraColor.warn
        case .ready:       return VoltraColor.accent
        }
    }

    private var borderColor: Color {
        switch state {
        case .approaching: return VoltraColor.warn.opacity(0.55)
        case .ready:       return VoltraColor.accent.opacity(0.55)
        default:           return VoltraColor.border
        }
    }

    /// Pulsing opacity used for the approaching dot — derived from the
    /// current second so it doesn't need its own animation timeline.
    private var pulseOpacity: Double {
        let seconds = now.timeIntervalSince1970
        // half-second pulse: 0.4 ↔ 1.0
        let phase = (sin(seconds * .pi) + 1) / 2 // 0..1
        return 0.4 + 0.6 * phase
    }

    private var targetLabel: String {
        guard let t = targetSeconds else { return "Target: off" }
        if t < 60 { return "Target \(t)s" }
        let m = t / 60
        let s = t % 60
        return s == 0 ? "Target \(m)m" : "Target \(m)m\(s)s"
    }

    private func cycleTarget() {
        let order = Self.targetCycle
        let idx = order.firstIndex(where: { $0 == targetSeconds }) ?? -1
        let next = order[(idx + 1) % order.count]
        targetSeconds = next
    }

    // MARK: - Haptics

    private func updateHaptics() {
        guard anchor != nil, let t = targetSeconds, t > 0 else { return }
        let e = elapsed

        if !firedApproachingHaptic, e >= Double(t - 10), e < Double(t) {
            firedApproachingHaptic = true
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        if !firedReadyHaptic, e >= Double(t) {
            firedReadyHaptic = true
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
    }
}

#Preview {
    @Previewable @State var target: Int? = 90
    return VStack(spacing: 16) {
        RestTimerView(anchor: nil, targetSeconds: $target)
        RestTimerView(anchor: Date().addingTimeInterval(-30),
                      targetSeconds: $target)
        RestTimerView(anchor: Date().addingTimeInterval(-83),
                      targetSeconds: $target)
        RestTimerView(anchor: Date().addingTimeInterval(-120),
                      targetSeconds: $target)
    }
    .padding()
    .background(VoltraColor.bg)
    .preferredColorScheme(.dark)
}
