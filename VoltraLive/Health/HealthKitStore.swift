// HealthKitStore.swift
// v0.4.6 — Lightweight HealthKit reader (iPhone-only v1).
//
// Goal: while the user is wearing an Apple Watch and has an active workout
// running in the default Apple Workout app, the iPhone polls HealthKit's
// shared store for the most recent heart-rate samples and active-energy-burned
// samples and exposes them as live @Published values for the LIVE tile grid.
// No HKWorkoutSession on watchOS yet (that's v0.4.7+).
//
// This is intentionally minimal:
//   - HKAnchoredObjectQuery with continuous updates for `.heartRate` and
//     `.activeEnergyBurned`.
//   - `currentHR` reflects the most recent BPM sample we've seen.
//   - `sessionKcal` accumulates active-energy-burned since `start()` was called.
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

    /// Begin polling. Idempotent — safe to call on every session start.
    func start() {
        #if canImport(HealthKit)
        guard isAvailable else { return }
        sessionStartDate = Date()
        sessionKcal = 0

        // Lazy auth: if we haven't asked yet, do it now.
        if !hasRequestedAuthorization {
            requestAuthorization { [weak self] _ in
                Task { @MainActor in
                    self?.hasRequestedAuthorization = true
                    self?.startQueries()
                }
            }
        } else {
            startQueries()
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

    private func handleHRSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        guard let qs = samples as? [HKQuantitySample], !qs.isEmpty else { return }
        // Most recent sample wins.
        let unit = HKUnit.count().unitDivided(by: .minute())
        let latest = qs.max(by: { $0.endDate < $1.endDate })
        guard let s = latest else { return }
        let bpm = Int(s.quantity.doubleValue(for: unit).rounded())
        Task { @MainActor in
            self.currentHR = bpm
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

    private func handleKcalSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        guard let qs = samples as? [HKQuantitySample], !qs.isEmpty else { return }
        let unit = HKUnit.kilocalorie()
        let delta = qs.reduce(0.0) { acc, s in acc + s.quantity.doubleValue(for: unit) }
        Task { @MainActor in
            self.sessionKcal += delta
            if let a = newAnchor { self.kcalAnchor = a }
        }
    }
    #endif
}
