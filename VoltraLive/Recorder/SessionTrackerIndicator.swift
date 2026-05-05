// SessionTrackerIndicator.swift
// b82 — Bottom-left active-session indicator.
//
// PLACEMENT: mounted once at the app root via
//   .overlay(alignment: .bottomLeading) { SessionTrackerIndicator() }
// with env-objects re-injected (see KI-13 / E5 in AGENTS.md).
//
// VISIBILITY: visible only when at least one VOLTRA is connected
// (i.e. a live session may be active). Hidden otherwise.
//
// GATE: FeatureFlags.sessionTrackerEnabled (defaults ON).
//       Set VOLTRASessionTrackerEnabled = false in UserDefaults to hide.
//
// TAP: opens SessionRecorderViewer sheet — the existing live-timeline
// and export surface. Does NOT duplicate the recorder system.
//
// VISUAL: Square-rounded ring (not a solid circle, unlike the recorder
// dot) so users can distinguish it from the bottom-trailing recorder dot.
// Color: VoltraColor.accent (teal/mint) when connected; hidden when not.
// Accessibility label: "Session Tracker".
//
// NOTE: does NOT duplicate the SessionRecorder dot (bottom-trailing).
// The recorder dot = event recording on/off toggle.
// This dot = live hardware session indicator / tracker entry point.

import SwiftUI

struct SessionTrackerIndicator: View {

    @EnvironmentObject private var ble: VoltraBLEManager
    @EnvironmentObject private var mdm: MultiDeviceManager
    @EnvironmentObject private var recorder: SessionRecorder

    @AppStorage(FeatureFlags.sessionTrackerUserDefaultsKey)
    private var sessionTrackerStoredEnabled: Bool = true

    @State private var showViewer = false

    var body: some View {
        Group {
            if isVisible {
                button
                    .padding(.leading, 10)
                    .padding(.bottom, 10)
                    .sheet(isPresented: $showViewer) {
                        SessionRecorderViewer()
                            .environmentObject(recorder)
                    }
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Visibility

    /// True when the flag is on and at least one VOLTRA is connected.
    private var isVisible: Bool {
        guard sessionTrackerStoredEnabled || FeatureFlags.sessionTrackerEnabled else {
            return false
        }
        return ble.connectionState.isConnected
            || mdm.left.connectionState.isConnected
            || mdm.right.connectionState.isConnected
    }

    // MARK: - Button

    private var button: some View {
        Button {
            showViewer = true
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(VoltraColor.accent, lineWidth: 2)
                .frame(width: 20, height: 20)
                .overlay(
                    // Tiny filled inner square — visually distinct from
                    // the recorder's solid circle.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(VoltraColor.accent.opacity(0.35))
                        .frame(width: 10, height: 10)
                )
        }
        .accessibilityLabel("Session Tracker")
        .accessibilityHint("Opens live session data and recorder timeline")
    }
}
