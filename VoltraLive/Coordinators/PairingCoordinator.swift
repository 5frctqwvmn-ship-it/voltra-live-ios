// PairingCoordinator.swift
//
// b67 V4.3 (Bug 07) — single source-of-truth for the "pair a Voltra"
// gesture across the whole UI.
//
// What this replaces
// ──────────────────
//   • LoggingHomeView's local @State showingPairSheet + per-view
//     subscription to MultiDeviceManager.scanRequestedSubject
//   • DualConnectView (deleted) as the sheet body — UnifiedConnectSheet
//     is now canonical
//   • Per-screen "tap a greyed L/R pill" handlers wired ad-hoc on
//     LoggingHomeView, ExerciseDetailView, LiveCaptureViewV2 — they
//     all funnel through this coordinator's presentPair(slot:) closure
//     surfaced via VoltraUnitHeader.onPairRequest.
//
// Lifecycle
// ─────────
//   • Owned by VoltraLiveApp.swift as a @StateObject so its identity
//     and presentation state survive view re-renders.
//   • Injected as @EnvironmentObject into the SwiftUI hierarchy.
//   • One sheet binding, one entry-point method, one cleanup hook.
//
// Sacred-file policy: this file is NEW; nothing in the sacred set
// (VoltraProtocol / TelemetryExtractor / PacketParser / FrameAssembler /
// release.yml / build.yml) is modified.

import Combine
import SwiftUI

@MainActor
final class PairingCoordinator: ObservableObject {

    // MARK: Published state

    /// Drives a `.sheet(isPresented:)` modifier on the root container.
    /// Toggle via `presentPair(slot:)` (or directly from a Button).
    @Published var isPresenting: Bool = false

    /// Which slot the user wanted to fill when they triggered the pair
    /// gesture. UnifiedConnectSheet ignores this for the moment (it
    /// supports multi-select), but downstream telemetry / undo paths
    /// can read it to know "this Voltra was meant for L vs R".
    @Published var requestedSlot: DeviceSlot? = nil

    // MARK: Wiring

    private var subscription: AnyCancellable?

    init() {
        // Pre-existing fan-in: the old VoltraAssignmentPanel posted to
        // MultiDeviceManager.scanRequestedSubject when a greyed L/R pill
        // was tapped. VoltraUnitHeader's `onPairRequest` hook bypasses
        // this entirely, but legacy emitters (deep-links, hot reloads,
        // debug menu) still go through the subject — keep the bridge.
        subscription = MultiDeviceManager.scanRequestedSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.presentPair(slot: nil)
            }
    }

    // MARK: Public API

    /// Surface the canonical pair sheet. Safe to call from any view via
    /// `@EnvironmentObject var pairing: PairingCoordinator`.
    func presentPair(slot: DeviceSlot? = nil) {
        requestedSlot = slot
        isPresenting = true
    }

    /// Dismiss programmatically (UnifiedConnectSheet usually calls
    /// `dismiss()` on its own; this is for forced teardown e.g. on
    /// disconnect events).
    func dismiss() {
        isPresenting = false
        requestedSlot = nil
    }
}
