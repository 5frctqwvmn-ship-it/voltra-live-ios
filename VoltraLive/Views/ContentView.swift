// ContentView.swift
// Root view.
//
// b67 V4.3 (Bug 01) — cold-launch routing flip.
//
//   OLD (b40–b66): ConnectView was the cold-launch landing surface;
//   you only saw LoggingHomeView once a Voltra was paired or Demo
//   was active. That meant a returning user with no Voltra in range
//   (battery, BT off, left at the gym) was forced through a pair
//   wall before they could see their workout history or even pick a
//   day.
//
//   NEW: LoggingHomeView is the unconditional cold-launch screen.
//   Voltra pairing is a foreground gesture surfaced via the
//   PairingCoordinator (greyed L/R pill tap in VoltraUnitHeader →
//   UnifiedConnectSheet). ConnectView is reserved for the legacy
//   onboarding deeplink only and is no longer wired here.

import SwiftUI

struct ContentView: View {
    /// b70 / V4-D17: root-scope observers for the demo \u2192 live handoff.
    /// Mirrors the V2 LiveCaptureViewV2 hook from V4-D16 (b68) but at root
    /// scope, so the handoff fires regardless of which screen is foreground
    /// when the device pairs (including DebugView, ExerciseDetailView,
    /// ExportSheet, etc.).
    @EnvironmentObject private var demo: DemoController
    @EnvironmentObject private var ble: VoltraBLEManager
    @EnvironmentObject private var mdm: MultiDeviceManager

    var body: some View {
        ZStack {
            VoltraColor.bg.ignoresSafeArea()
            LoggingHomeView()
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        }
        .preferredColorScheme(.dark)
        .tint(VoltraColor.accent)
        .buildBadgeOverlay()
        // b66 V4.2: page-name badge — INTENTIONALLY OMITTED on this
        // root container. ContentView wraps LoggingHomeView (which owns
        // the NavigationStack) and every view pushed onto that stack,
        // so a `.pageBadge(...)` mounted here propagates via SwiftUI's
        // `.overlay(alignment: .bottomLeading)` and stacks with every
        // child screen's own badge at the same anchor (visible as
        // garbled "CoggingMomeView" / "CourCoptureCostainer" double-
        // render in IMG_2438/2442/2444/2445/2446/2447). Sheet-presented
        // surfaces (e.g. DebugView) get a fresh overlay context and were
        // not affected. Containers must not own a `.pageBadge`; only
        // leaf, user-visible screens do.
        // See `docs/handoff/03_CURRENT_FEATURE_SPEC.md` §9 and
        // `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` V4-D19.
        // b70 / V4-D17: real-device handoff. Exit prePair demo as soon as
        // any of the three connection sources transitions to connected.
        // postPair demo is intentionally untouched \u2014 that's a user-explicit
        // demo that should outlive a connection blip (V4-D16 contract).
        .onChange(of: ble.connectionState) { _, _ in
            handoffIfNeeded()
        }
        .onChange(of: mdm.left.connectionState) { _, _ in
            handoffIfNeeded()
        }
        .onChange(of: mdm.right.connectionState) { _, _ in
            handoffIfNeeded()
        }
    }

    /// If the active demo session was started as `.prePair` and any device
    /// is now connected, exit demo so live telemetry takes over.
    private func handoffIfNeeded() {
        guard demo.isActive, demo.entrySource == .prePair else { return }
        let anyDeviceConnected =
            ble.connectionState.isConnected
            || mdm.left.connectionState.isConnected
            || mdm.right.connectionState.isConnected
        if anyDeviceConnected {
            _ = demo.exit()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
        .environmentObject(LoggingStore())
        .environmentObject(DemoController())
        .environmentObject(MultiDeviceManager())
        .environmentObject(PairingCoordinator())
        .environmentObject(HealthKitStore())
}
