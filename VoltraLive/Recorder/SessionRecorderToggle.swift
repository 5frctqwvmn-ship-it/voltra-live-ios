// SessionRecorderToggle.swift
// B74-F11 Session Recorder — root-overlay 24x24 dot.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Activation" + "Toggle".
//
// Mounted exactly once at the app root via
//   .overlay(alignment: .bottomTrailing) { SessionRecorderToggle() }
// in `VoltraLiveApp`. NEVER per-screen.
//
// Hidden until the user triple-taps the build-badge chip (which flips
// `UserDefaults["VOLTRARecorderUnlocked"] = true`). Once unlocked:
//   - Tap        → toggle recording.
//   - Long-press → present `SessionRecorderViewer` sheet.
//   - Recording  → red 1 Hz pulse via `TimelineView(.animation)`.
//   - Idle       → faint `VoltraColor.textFaint` dot.
//
// Sits with extra bottom padding so it does not collide with the
// existing build-badge chip in the same bottom-trailing safe area.

import SwiftUI

struct SessionRecorderToggle: View {

    @EnvironmentObject private var recorder: SessionRecorder

    /// Triple-tap on the build-badge chip flips this to true. Until then
    /// the dot is hidden so the recorder is invisible to users who
    /// haven't intentionally enabled the surface.
    @AppStorage("VOLTRARecorderUnlocked") private var unlocked: Bool = false

    @State private var showViewer: Bool = false

    var body: some View {
        Group {
            if unlocked {
                dot
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        recorder.toggle()
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        showViewer = true
                    }
                    .accessibilityLabel(
                        "Session recorder \(recorder.isRecording ? "on" : "off"). Double tap to toggle. Long press to view."
                    )
                    .accessibilityAddTraits(.isButton)
                    // Sit above the build-badge chip in the same
                    // bottom-trailing safe area. The chip itself uses
                    // .padding(.trailing, 8) + .padding(.bottom, 6) and
                    // is ~14pt tall; 36pt of bottom padding keeps the
                    // 24pt dot clear with breathing room.
                    .padding(.trailing, 10)
                    .padding(.bottom, 36)
                    .sheet(isPresented: $showViewer) {
                        SessionRecorderViewer()
                            .environmentObject(recorder)
                    }
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var dot: some View {
        if recorder.isRecording {
            // 1 Hz pulse: full sin wave per second; opacity oscillates
            // between 0.5 and 1.0 so the dot never blacks out.
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let s = sin(t * .pi * 2.0)            // 1 Hz
                let alpha = 0.5 + 0.5 * (s * 0.5 + 0.5)
                Circle()
                    .fill(Color.red)
                    .opacity(alpha)
            }
        } else {
            Circle()
                .fill(VoltraColor.textFaint)
        }
    }
}
