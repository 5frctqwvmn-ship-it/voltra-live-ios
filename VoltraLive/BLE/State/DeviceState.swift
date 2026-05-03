// DeviceState.swift
// Telemetry v2 — authoritative device state.
//
// Source of truth = the device. The app's most recent UI value is just
// a request; what the device echoes back via decoded confirmations is
// what we believe. This struct holds those confirmed values and the
// reducer applies decoded events to produce a new state.
//
// Slice (b79) only models `baseWeight`. Eccentric, chains, inverse-
// chains, mode, damper, and band-max-force are intentionally absent —
// when those decode patterns land, add fields here in the same shape.
//
// The reducer is pure (no I/O) so it's trivial to test. Side-effects
// (recorder emit, UI updates) happen in the caller after applying.

import Foundation

/// One confirmed value for a single field, with provenance and timing.
/// `lb` is in pounds (matches `VoltraControlFrames` units). `source`
/// distinguishes app-issued vs. machine-side change. `at` is the wall
/// clock when we observed the confirmation.
struct ConfirmedValue<T: Equatable & Codable & Sendable>: Equatable, Codable, Sendable {
    let value: T
    let source: DeviceStateChangeSource
    let at: Date
}

/// Authoritative device-side state, as far as the app currently knows.
/// All fields optional — until the device has confirmed a value, we
/// don't pretend to know it.
struct DeviceState: Equatable, Codable, Sendable {
    var baseWeightLb: ConfirmedValue<Int>? = nil

    static let empty = DeviceState()
}

/// Result of applying one event to a `DeviceState`. `change` describes
/// what (if anything) actually moved, so the caller can decide whether
/// to emit a `device.state.change` recorder event.
struct DeviceStateReduction: Equatable {
    let newState: DeviceState
    let change: DeviceStateChange?
}

/// Description of a single field transition. The `from`/`to` encoding
/// is the canonical pound value on both sides; `nil` on `from` means
/// "we hadn't seen this field before".
struct DeviceStateChange: Equatable {
    let field: DeviceStateField
    let from: Int?
    let to: Int
    let source: DeviceStateChangeSource
    let rawHex: String
}

enum DeviceStateReducer {

    /// Pure reducer: apply one decoded event and return the new state
    /// plus whatever change was recorded. Idempotent — emitting the
    /// same value twice produces no change on the second call.
    static func apply(_ event: VoltraDecodedEvent, to state: DeviceState) -> DeviceStateReduction {
        switch event {
        case .candidate:
            return DeviceStateReduction(newState: state, change: nil)

        case let .stateConfirmation(field, lb, source, rawHex):
            switch field {
            case .baseWeight:
                let priorLb = state.baseWeightLb?.value
                if priorLb == lb {
                    // Noop confirmation — keep the existing
                    // ConfirmedValue (don't churn `at`/`source`).
                    return DeviceStateReduction(newState: state, change: nil)
                }
                var next = state
                next.baseWeightLb = ConfirmedValue(
                    value: lb, source: source, at: Date()
                )
                let change = DeviceStateChange(
                    field: .baseWeight,
                    from: priorLb,
                    to: lb,
                    source: source,
                    rawHex: rawHex
                )
                return DeviceStateReduction(newState: next, change: change)
            }
        }
    }
}
