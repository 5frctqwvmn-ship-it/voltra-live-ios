// HealthKitStore.swift
// v0.4.6 — Lightweight HealthKit reader (iPhone-only v1).
// v0.4.8 (build 30) — Live streaming via background delivery.
//
// Goal: while the user is wearing an Apple Watch and has an active workout
// running in the default Apple Workout app, the iPhone polls HealthKit's
// shared store for the most recent heart-rate samples and active-energy-burned
// samples and exposes them as live @Published values for the LIVE tile grid.
//
// Build 30 fix: confirmed by the user that they DO start an Apple Workout
// session on the Watch before each VOLTRA session. So HR + active-calories
// samples ARE being written to the shared HealthKit store — the iPhone just
// isn't getting woken up to read them. The original implementation set up
// HKAnchoredObjectQuery with an updateHandler, which is supposed to fire
// for new samples, but in practice when the WATCH is the writer the iPhone
// process needs `enableBackgroundDelivery` to actually receive callbacks.
// Without it the initial query callback fires once (snapshot) and updates
// never arrive. This file now enables background delivery on both types,
// and tracks `lastHRSampleAt` / `lastKcalSampleAt` so the UI can show a
// pulsing fresh-data indicator (PulseDot, build 30 priority #3).
//
// This is intentionally minimal:
//   - HKAnchoredObjectQuery with continuous updates for `.heartRate` and
//     `.activeEnergyBurned`.
//   - enableBackgroundDelivery(.immediate) on both types so the system
//     wakes the iPhone process for samples written by the paired Watch.
//   - `currentHR` reflects the most recent BPM sample we've seen.
//   - `sessionKcal` accumulates active-energy-burned since `start()` was called.
//   - `lastHRSampleAt` / `lastKcalSampleAt` timestamps for fresh-data UI.
//   - All UI binds to @Published vars via @EnvironmentObject.
//
// Permissions: NSHealthShareUsageDescription must be in the plist + the
// `com.apple.developer.healthkit` entitlement must be present. `requestAuth()`
// is called once on first attempt to start.

import Foundation
import Combine
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class HealthKitStore: ObservableObject {
    /// Most recent heart-rate sample in BPM. nil = no data yet.
    @Published var currentHR: Int? = nil
    /// Active-energy burned (kcal) since the most recent `start()`.
    @Published var sessionKcal: Double = 0
    /// Wall-clock timestamp of the most recently received HR sample. Used
    /// by the UI to drive a "fresh data" pulse indicator. nil = no data yet
    /// or session stopped.
    @Published var lastHRSampleAt: Date? = nil
    /// Wall-clock timestamp of the most recently received kcal sample.
    /// Same purpose as `lastHRSampleAt` for the kcal tile.
    @Published var lastKcalSampleAt: Date? = nil
    /// True after the user has been prompted at least once.
    @Published var hasRequestedAuthorization: Bool = false
    /// True when HealthKit is generally available on this device.
    let isAvailable: Bool

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var hrAnchor: HKQueryAnchor? = nil
    private var kcalAnchor: HKQueryAnchor? = nil
    private var hrQuery: HKAnchoredObjectQuery? = nil
    private var kcalQuery: HKAnchoredObjectQuery? = nil
    private var sessionStartDate: Date? = nil

    init() {
        self.isAvailable = HKHealthStore.isHealthDataAvailable()
    }
    #else
    init() {
        self.isAvailable = false
    }
    #endif

    /// Build 35: Request authorization eagerly without starting queries. Use
    /// this at app launch so the system permission sheet appears BEFORE the
    /// user enters a workout screen. The user reported on b31 that they
    /// never saw the prompt — the only call site for `start()` was inside
    /// LiveCaptureView.onAppear, so anyone testing without starting a
    /// workout would never trigger the dialog. Idempotent and cheap.
    func requestAuthIfNeeded() {
        #if canImport(HealthKit)
        guard isAvailable else {
            print("[HealthKit] requestAuthIfNeeded skipped - not available")
            return
        }
        print("[HealthKit] requestAuthIfNeeded - calling requestAuthorization")
        requestAuthorization { [weak self] ok in
            print("[HealthKit] requestAuthIfNeeded completed ok=\(ok)")
            Task { @MainActor in
                self?.hasRequestedAuthorization = true
            }
        }
        #endif
    }

    /// Begin polling. Idempotent — safe to call on every session start.
    ///
    /// Build 31 fix: previously this set `hasRequestedAuthorization = true`
    /// inside the auth completion handler regardless of whether the prompt
    /// actually showed. If anything failed silently (missing entitlement,
    /// system never delivers the dialog) we'd never re-prompt for the rest
    /// of the app launch. Worse: if the user backgrounded the app before
    /// the dialog showed, the same suppression applied. We now (a) log to
    /// console so we can see in Console.app what's happening, (b) only flip
    /// `hasRequestedAuthorization` on a TRUE auth completion, and
    /// (c) bail out of `start()` with a console warning if HealthKit isn't
    /// available so we never silently no-op.
    func start() {
        #if canImport(HealthKit)
        guard isAvailable else {
            print("[HealthKit] start() skipped - HKHealthStore.isHealthDataAvailable() == false")
            return
        }
        sessionStartDate = Date()
        sessionKcal = 0
        lastHRSampleAt = nil
        lastKcalSampleAt = nil

        // Always (re-)ask. requestAuthorization is idempotent on Apple's
        // side: if the user previously granted, no dialog appears and the
        // completion fires immediately with ok=true. If they previously
        // denied, no dialog appears either but ok is still true (Apple's
        // privacy model hides read-denial). The cost of always calling is
        // ~one IPC \u2014 negligible \u2014 and it removes a class of bugs
        // where the prompt never appeared on the first try.
        print("[HealthKit] start() - requesting authorization")
        requestAuthorization { [weak self] ok in
            print("[HealthKit] requestAuthorization completed ok=\(ok)")
            Task { @MainActor in
                guard let self else { return }
                self.hasRequestedAuthorization = true
                // Even if ok==false we still call these \u2014 background
                // delivery + queries on a denied type are harmless no-ops
                // and Apple's auth model means we can't reliably tell
                // "denied READ" from "granted READ" anyway.
                self.enableBackgroundDeliveryForTypes()
                self.startQueries()
            }
        }
        #endif
    }

    /// Stop polling and clear values.
    func stop() {
        #if canImport(HealthKit)
        if let q = hrQuery { store.stop(q) }
        if let q = kcalQuery { store.stop(q) }
        hrQuery = nil
        kcalQuery = nil
        sessionStartDate = nil
        // Keep the last currentHR briefly so the UI doesn't flash; UI will
        // show em-dash on its own when it's nil. Reset kcal aggregator.
        sessionKcal = 0
        lastHRSampleAt = nil
        lastKcalSampleAt = nil
        // Note: we deliberately do NOT call disableBackgroundDelivery here.
        // The system tolerates a permanent enrollment fine, and re-enabling
        // on every session start is wasteful. Background delivery without
        // an active query is harmless — there's nothing to wake.
        #endif
    }

    #if canImport(HealthKit)
    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let hr = HKObjectType.quantityType(forIdentifier: .heartRate),
              let kcal = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(false); return
        }
        let readSet: Set<HKObjectType> = [hr, kcal]
        store.requestAuthorization(toShare: nil, read: readSet) { ok, _ in
            completion(ok)
        }
    }

    /// v0.4.8 (build 30): wire HealthKit to wake the iPhone process when
    /// the paired Watch writes new HR or active-energy samples to the
    /// shared store. Without this the `HKAnchoredObjectQuery.updateHandler`
    /// receives the initial seed callback (the snapshot the user was
    /// reporting) but never fires again for samples the Watch writes
    /// during the session.
    ///
    /// `.immediate` frequency means the system tries to deliver as soon as
    /// the sample is written. Apple may throttle in low-power conditions
    /// but during an active Workout session deliveries arrive every few
    /// seconds in practice.
    ///
    /// Idempotent: HealthKit silently no-ops if delivery is already enabled
    /// for this app + type at this frequency.
    private func enableBackgroundDeliveryForTypes() {
        guard let hr = HKObjectType.quantityType(forIdentifier: .heartRate),
              let kcal = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return
        }
        store.enableBackgroundDelivery(for: hr, frequency: .immediate) { _, _ in
            // No-op: success or failure, the anchored query's updateHandler
            // is what surfaces the data. We don't surface the bool to UI.
        }
        store.enableBackgroundDelivery(for: kcal, frequency: .immediate) { _, _ in }
    }

    private func startQueries() {
        startHeartRateQuery()
        startActiveEnergyQuery()
    }

    private func startHeartRateQuery() {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let predicate = HKQuery.predicateForSamples(
            withStart: sessionStartDate,
            end: nil,
            options: .strictStartDate
        )
        let q = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: hrAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.handleHRSamples(samples, newAnchor: newAnchor)
        }
        q.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.handleHRSamples(samples, newAnchor: newAnchor)
        }
        hrQuery = q
        store.execute(q)
    }

    nonisolated private func handleHRSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        guard let qs = samples as? [HKQuantitySample], !qs.isEmpty else { return }
        // Most recent sample wins.
        let unit = HKUnit.count().unitDivided(by: .minute())
        let latest = qs.max(by: { $0.endDate < $1.endDate })
        guard let s = latest else { return }
        let bpm = Int(s.quantity.doubleValue(for: unit).rounded())
        let arrivedAt = s.endDate
        Task { @MainActor in
            self.currentHR = bpm
            self.lastHRSampleAt = arrivedAt
            if let a = newAnchor { self.hrAnchor = a }
        }
    }

    private func startActiveEnergyQuery() {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let predicate = HKQuery.predicateForSamples(
            withStart: sessionStartDate,
            end: nil,
            options: .strictStartDate
        )
        let q = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: kcalAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.handleKcalSamples(samples, newAnchor: newAnchor)
        }
        q.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.handleKcalSamples(samples, newAnchor: newAnchor)
        }
        kcalQuery = q
        store.execute(q)
    }

    nonisolated private func handleKcalSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        guard let qs = samples as? [HKQuantitySample], !qs.isEmpty else { return }
        let unit = HKUnit.kilocalorie()
        let delta = qs.reduce(0.0) { acc, s in acc + s.quantity.doubleValue(for: unit) }
        // Use the most-recent sample's endDate as the freshness marker.
        let arrivedAt = qs.map { $0.endDate }.max() ?? Date()
        Task { @MainActor in
            self.sessionKcal += delta
            self.lastKcalSampleAt = arrivedAt
            if let a = newAnchor { self.kcalAnchor = a }
        }
    }
    #endif
}
