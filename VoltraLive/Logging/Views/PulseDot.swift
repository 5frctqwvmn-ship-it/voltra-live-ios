// PulseDot.swift
// v0.4.8 (build 30) — Live data freshness indicator.
//
// A small circular dot that pulses green when fresh data is arriving and
// fades to a solid grey when the feed has gone stale. Intended for the
// HR and kcal tiles in LiveCaptureView so the user can tell at a glance
// whether HealthKit is actively delivering samples from the paired
// Apple Watch.
//
// Behavior:
//   - `lastSampleAt == nil`            → solid faint grey (no data yet).
//   - now − lastSampleAt ≤ freshWindow → pulsing green at ~1.4 Hz.
//   - now − lastSampleAt > freshWindow → solid grey (stale).
//
// `freshWindow` defaults to 8 seconds, which is a comfortable margin for
// HealthKit's typical delivery cadence (HR ≈ every 5s during a Watch
// workout). The pulse animation runs continuously while fresh; the host
// view doesn't have to drive a redraw — TimelineView ticks 4×/s.
//
// Pure SwiftUI, no environment dependencies. Drop in next to any value
// that has a "last seen at" timestamp.

import SwiftUI

struct PulseDot: View {
    /// Wall-clock timestamp of the most recent sample. nil = never.
    let lastSampleAt: Date?
    /// Color of the pulsing state (defaults to a vivid green).
    var freshColor: Color = Color(red: 0.20, green: 0.85, blue: 0.40)
    /// Color of the stale/never state (defaults to a faint grey).
    var staleColor: Color = Color(white: 0.35)
    /// Diameter in points.
    var size: CGFloat = 8
    /// How long after the last sample the dot is still considered fresh.
    /// b45: bumped 8 → 15 seconds. HealthKit delivery during a Watch
    /// workout is bursty: a heart-rate sample every 5 s typical but with
    /// gaps to 12+ s when the wrist motion sensor is quiet. The 8 s window
    /// kept flipping the dot to grey between samples even when streaming
    /// was healthy, so users assumed it was broken.
    var freshWindow: TimeInterval = 15.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let now = ctx.date
            let isFresh: Bool = {
                guard let last = lastSampleAt else { return false }
                return now.timeIntervalSince(last) <= freshWindow
            }()
            // Pulse opacity drives a sin-wave at ~1.4 Hz when fresh.
            let pulse: Double = {
                guard isFresh else { return 1.0 }
                let phase = now.timeIntervalSince1970 * 1.4 * 2 * .pi
                // Map sin (-1...1) → 0.45...1.0 so the dot never fully
                // disappears (eye-tracking would lose it).
                return 0.45 + 0.55 * (0.5 + 0.5 * sin(phase))
            }()
            Circle()
                .fill(isFresh ? freshColor : staleColor)
                .frame(width: size, height: size)
                .opacity(isFresh ? pulse : 0.55)
                .animation(.easeOut(duration: 0.2), value: isFresh)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("PulseDot states") {
    VStack(spacing: 24) {
        HStack(spacing: 12) {
            PulseDot(lastSampleAt: Date())
            Text("Fresh (just now)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
        }
        HStack(spacing: 12) {
            PulseDot(lastSampleAt: Date().addingTimeInterval(-30))
            Text("Stale (30s ago)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
        }
        HStack(spacing: 12) {
            PulseDot(lastSampleAt: nil)
            Text("Never")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
        }
    }
    .padding(40)
    .background(Color.black)
}
#endif
