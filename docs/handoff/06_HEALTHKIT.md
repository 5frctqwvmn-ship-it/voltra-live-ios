# 06 — HealthKit

## Goals

- Stream heart rate **continuously** during a live session.
- Stream active energy burned (calories) **continuously** during a session.
- Surface a fresh-data indicator on the HR and kcal tiles.

## Current state (build 29, broken)

- File: `VoltraLive/Health/HealthKitStore.swift`.
- HR populates **once** at session start (snapshot read) and never updates.
- Active calories never appear at all.

The user explicitly flagged this in build 29:

> "Heart rate is updating. I think it just got a snapshot... should be
> pulling that information the entire time along with calories... There
> should be an indication... maybe it's blinking when it's actively
> receiving data."

## Build 30 fix plan

### Streaming reads

Use `HKAnchoredObjectQuery` for both quantity types:

- `HKQuantityType.quantityType(forIdentifier: .heartRate)`
- `HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)`

Pattern:

1. Request authorization for both types when the session starts (already
   wired for HR, confirm kcal is in the read set).
2. Create one anchored query per type with `updateHandler` set, so new
   samples deliver as they arrive.
3. Persist the anchor for the lifetime of the session (in-memory is fine —
   no need to durably persist between sessions).
4. On each update, push the latest sample to the live tile.
5. Stop the query on session end (don't leak across sessions).

Alternative if anchored queries don't fire while in foreground reliably:
combine `HKObserverQuery` (callback when data lands) + a short
`HKSampleQuery` (read the most recent sample). Anchored is preferred.

### Fresh-data indicator (`PulseDot`)

New SwiftUI view, used on HR and kcal tiles:

- Tracks a `lastUpdateAt: Date` per tile.
- If `now - lastUpdateAt < 3 s`, show a green dot with a pulsing animation
  (scale or opacity loop, ~1 Hz).
- Else, fade to a solid grey dot.

Implementation notes:

- Drive the staleness check off a `Timer.publish(every: 0.5, on: .main, in: .common)`
  scoped to the tile, not a global tick — keeps idle tiles cheap.
- Tile owners pass `lastUpdateAt` in via binding so the dot is decoupled
  from the data source.

## Authorization

Verify in `Info.plist` that both `NSHealthShareUsageDescription` and
`NSHealthUpdateUsageDescription` are populated with user-facing strings
(don't leak engineering jargon).

## Test plan

- Real device only — HealthKit doesn't deliver in simulator.
- Wear an Apple Watch or other HK-source for HR.
- Start a workout in another app or on the Watch to generate
  `activeEnergyBurned` samples.
- Verify both tiles update at least every few seconds.
- Verify the green pulse appears while data flows and goes grey within
  ~3 s of the source pausing.
