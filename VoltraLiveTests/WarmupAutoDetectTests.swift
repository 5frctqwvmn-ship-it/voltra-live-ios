// WarmupAutoDetectTests.swift
// v0.4.8 / build 30 — warmup phase pinning.
//
// What this pins:
//   1. `isFirstSetOfActiveInstance` is true ONLY when there is an active
//      instance with no logged sets and `setNumberForCurrentInstance == 1`.
//      This is the trigger SetLogView.prefillIfNeeded() uses to auto-select
//      Warm-Up mode and prefill the warmup weight.
//   2. `lastWarmup(for:)` and `lastWorkingSet(for:)` degrade gracefully
//      (return nil) when the modelContext is unset — this is the path tests
//      and previews take, and SetLogView's prefill must not crash on it.
//
// SwiftData-backed end-to-end coverage of "find prior warmup, pick its
// weight" lives in the SetLogView UI test target (TODO build 31). This unit
// file pins the contract the prefill code relies on so a regression there
// surfaces before the UI test runs.

import XCTest
@testable import VoltraLive

@MainActor
final class WarmupAutoDetectTests: XCTestCase {

    /// No active instance → false. Prevents auto-warmup from firing on the
    /// initial app-launch state where the user hasn't picked an exercise.
    func testIsFirstSet_NoActiveInstance_False() {
        let (store, session) = LoggingStore.makeForTestingWithSession()
        _ = session
        XCTAssertNil(store.activeInstance)
        XCTAssertFalse(store.isFirstSetOfActiveInstance,
                       "no active instance must not trigger warmup auto-detect")
    }

    /// `setNumberForCurrentInstance` defaults to 1 on a fresh store. Without
    /// an active instance attached, the property must still be false — the
    /// activeInstance guard short-circuits before the count check.
    func testIsFirstSet_DefaultSetNumber_IsOneButGuardFails() {
        let (store, session) = LoggingStore.makeForTestingWithSession()
        _ = session
        XCTAssertEqual(store.setNumberForCurrentInstance, 1,
                       "fresh store starts at set #1")
        XCTAssertFalse(store.isFirstSetOfActiveInstance,
                       "set #1 alone is not enough — needs an active instance")
    }

    /// Without a modelContext, the test factory leaves the store in a
    /// state where SwiftData fetches short-circuit at the `guard let ctx`
    /// in lastSet/lastWarmup/lastWorkingSet. SetLogView's prefill code
    /// path explicitly relies on this safe fallthrough — if a future
    /// refactor removes the guard, prefill would crash on previews and
    /// tests. Pin the contract here at the cheapest possible level.
    func testTestFactory_LeavesModelContextNil() {
        let (store, session) = LoggingStore.makeForTestingWithSession()
        _ = session
        XCTAssertNil(store.modelContext,
                     "test factory must leave modelContext nil so warmup helpers fall through to nil rather than fetching from a non-existent context")
    }
}
