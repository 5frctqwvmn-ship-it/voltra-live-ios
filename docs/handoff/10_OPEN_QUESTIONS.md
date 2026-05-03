# 10 — Open Questions

Things blocked on the user. Resolve before the dependent task can ship.

> When you answer one of these, **delete it from this file in the same
> commit** as the code change that uses the answer. Don't let stale
> questions accumulate.

## V2 promotion

### Should SWAP's no-auto-LOAD change get an in-app hint?

Status: **needs user answer (UX decision).**

b53 changed SWAP behavior — it no longer pushes the stored weight
back to the newly-active Voltra. Users who learned the b49 SWAP will
find the bar quiet on their first b53 swap. Options:

a. Add a one-time toast/banner the first time SWAP is tapped on b53+.
b. Add a permanent caption under the SWAP button.
c. Document only (release notes / TestFlight description).
d. No change — the empty bar IS the hint.

## Old-store import (carried from b30)

Status: **needs user answer before any importer code is written.**

Build 29 abandoned the old SwiftData store at the legacy URL. The user's
prior session logs are still on disk but not visible in the app. Do they
want them imported, or is the fresh start fine?

If yes: write a one-shot importer that opens the legacy store with a
separate `ModelContainer`, reads all sets, writes them into the v2 store,
then sets a "imported" flag so it doesn't run again.

## Recently closed

### Per-instance Voltra routing (b53)

Resolved in b53. Routing source of truth moved from
`mdm.hasAnySupersetChainEntry(for:)` predicate to
`ExerciseInstance.assignedVoltra` field stamped at exercise-add time.
3-way L/R/Both picker replaces binary L/R. SWAP unloads both sides
without auto-LOAD. See `08_SUPERSET.md`.

### Should V2 become the default? (b71)

Resolved in b71 (V4-D21 part 3 / Step 3). After V4-D21 part 1
(below-chart parity) and part 2 (chain UI port) closed every
behavior gap, `LiveCaptureContainer.shouldUseV2` collapsed to
`return uiVersion != "v1"`. V2 is now the canonical live capture
view for every session shape; `@AppStorage("liveCaptureUIVersion")`
is an emergency rollback kill switch only. The first-launch picker
remains for compatibility but both choices route to V2 unless the
user explicitly picks V1. See ADR **V4-D21 part 3** in
`04_DECISIONS_AND_CONSTRAINTS.md` and the routing section in
`08_SUPERSET.md`.

### V2 spec match (b54)

Resolved in b54. V2 was rebuilt as a 1:1 port of
`design-system/ui-kit.html` (design-studio branch HEAD `74d0d3b9`),
replacing the b53 generic version that was built from a prose summary
without opening the spec. New rule in `00_START_HERE.md`: external
specs must be opened verbatim before any code is written, with file
path + commit hash cited in WORK_LOG.

### HealthKit first-launch prompt (b47/b48 deferred, b49 closed)

Resolved in b49. Provisioning profile granted all three HealthKit
entitlement keys but the app-side entitlements only declared
`.healthkit`. iOS 17+ silently rejected auth on fresh installs. Fixed
app-side by declaring all three keys; CI verify hardened to assert
them with exact-key match. See `06_HEALTHKIT.md` for the full writeup.

## Telemetry v2 / Authoritative Device State (post-b78)

These 8 questions block the Telemetry Collector v2 + Authoritative
Device State cycle. Answers must come from a BLE characteristic audit
plus controlled hardware experiments before the decoder can promote
any hypothesis to a constant. See `03_CURRENT_FEATURE_SPEC.md`
("Telemetry v2") and `06_KNOWN_ISSUES.md` (KI-23, KI-24, KI-26).

### OQ-T0 — Base-weight confirmation byte layout — RESOLVED 2026-05-03

Status: **resolved.** The hypothesis that the `86 3e XX` pattern in
the notify stream is a base-weight confirmation is now pinned by
byte-vector parity with the writer side: `setBaseWeightPayload(N)`
produces `01 00 86 3E <lo> <hi>` (uint16-LE pounds) and the device
echo-confirms the same layout. The May-2026 hardware observations
(`86 3e 5f / 86 3e 14 / 86 3e 0f`) decode to 95 / 20 / 15 lb under
this rule. Implemented in `VoltraDecodeTable.baseWeight`; see
`05_BLE_AND_PROTOCOL.md` “Base-weight confirmation byte layout”.

### OQ-T1 — Meaning of `0x03` byte in `553404ac` status frames

Status: **needs hardware experiment + spec confirmation.**

Observed once during a 1000-event live session: a `553404ac` status
frame transitioned `0x02 → 0x03` around what appeared to be a load
cutout. Hypothesis: `0x03` = "load dropped / cutout". This is a single
observation; do not treat as canonical until reproduced under
controlled load-drop conditions and cross-checked against any vendor
docs the user can surface. Tracked as KI-23.

### OQ-T2 — Byte positions for ecc, conc, chains in stream frames

Status: **non-hardware resolution path identified (2026-05-03)** —
still needs implementation, but inference may not be required.

The existing pipeline emits ecc / conc / chains values that drift
build-to-build, suggesting the byte offsets we read from are not
stable or not the true source. **Update from BLE audit
(2026-05-03):** the Android reference implementation
([`VoltraOfficialReadOnlyBootstrap.kt`](../../docs/handoff/artifacts/ble_characteristic_audit_2026-05-03.md)
bootstrap packet 10) requests these values authoritatively via
`CMD_PARAM_READ` for `PARAM_BP_CHAINS_WEIGHT`,
`PARAM_BP_ECCENTRIC_WEIGHT`, and `PARAM_FITNESS_INVERSE_CHAIN` on
the C3 transport characteristic. iOS currently does **not** issue
this read (iOS has 9 bootstrap writes; Android has 10). The v2
collector should issue this read either at bootstrap (additively
appending a 10th packet, **not** modifying the sacred constant) or
lazily on connect, and use the parameter response as source of
truth for ecc / conc / chains. Stream-frame byte-position pinning
becomes a fallback / cross-check rather than the primary mechanism.
Tracked as KI-21.

### OQ-T3 — Meaning of `2b000100` vs `2b010100` in `553a0470` frames

Status: **hypothesis only.**

Working guess: this is a phase / tension flag (e.g.
ecc-active vs con-active, or load-engaged vs load-released). Need
paired observation: log frame bytes against simultaneous user-visible
phase to confirm. Until confirmed, decoder must flag this as
hypothesis and round-trip the raw bytes. Tracked as KI-24.

### OQ-T4 — Is there a dedicated notify/indicate status characteristic we are not subscribed to?

Status: **partially resolved (2026-05-03 paper audit)** — still
open on the substantive question pending an on-device scan.

**What is now known.** Cross-referencing this repo's
`VoltraProtocol.swift` against two independent public reference
implementations by the same reverse-engineering author — the
Android controller (`Beyond-Power-Voltra-Android`,
`core/protocol/.../VoltraUuidRegistry.kt`) and the Home Assistant
integration (`Beyond-Power-HomeAssistant`,
`custom_components/voltra/const.py`) — all three clients enumerate
the **same 4 characteristic UUIDs** on the VOLTRA service
(`e4dada34-…c7e4`) and subscribe to **the same 3 of the 4**
(C1 cmdChar, C2 notifyChar, C3 transport). The fourth (C4
`justWrite`) is `WRITE_NO_RESPONSE` only in all three sources and
is not a notify/indicate target. **No reference implementation
documents any unsubscribed notify or indicate channel on the VOLTRA
service.** Full table and per-row sources in
`docs/handoff/artifacts/ble_characteristic_audit_2026-05-03.md`.
Audit results section is appended to
`docs/handoff/05_BLE_AND_PROTOCOL.md`.

**What remains open.** The paper audit cannot rule out:
  - additional services advertised by the VOLTRA peripheral beyond
    `e4dada34-…c7e4` (DIS `0x180A`, Battery `0x180F`, vendor
    diagnostic) — all three reference clients filter discovery to
    the VOLTRA service only and would not have noticed.
  - additional characteristics on the VOLTRA service beyond the 4
    documented UUIDs — iOS uses
    `discoverCharacteristics([4-UUID list], for: service)`
    (`VoltraBLEManager.swift` line 424) so a 5th characteristic, if
    it exists, is invisible to the iOS app and to its logs.
  - the actual `CBCharacteristicProperties` bitmask iOS sees on a
    paired VOLTRA — not yet logged.

**Recommended close.** An on-device nRF Connect / LightBlue scan
exported to `docs/handoff/artifacts/ble_scan_<date>.{json,txt}`
would close the substantive question. A non-sacred debug log of
`char.uuid` + `char.properties.rawValue` in `VoltraBLEManager.swift`
(post-discovery callback) would close the properties-bitmask
uncertainty without a scanner. Neither was done in this docs-only
commit per release-only mode. Tracked as KI-26.

### OQ-T5 — Is force / tension decodable from current frames?

Status: **partial — needs systematic mapping.**

Some force-shaped values appear in stream frames but their unit,
scale, and zero-point are not pinned. Need to perform a known-load
experiment: hold N pounds of static load, capture frames, fit
decoder. If the field is not present at any current offset, that
becomes a hard "requires hardware spec" gate.

### OQ-T6 — Compression strategy that preserves rep / force debug data

Status: **design open.**

The 5000-event ring buffer (per spec) will overflow on long sessions.
We need a compression / aggregation strategy that drops bulk
telemetry without losing per-rep force debug data (rep markers,
peak force, ecc/con phase boundaries). Options to evaluate:
per-rep summarization with raw-frame retention only on anomaly,
delta-encoded stream frames, or tiered ring buffer (raw last N reps
+ summarized older reps). Decide before implementation step 6.

### OQ-T7 — Should `load.state.change` be its own event or a field of `device.state.change`?

Status: **schema decision — needs user / spec call.**

Two viable shapes:
  a. Two event types: `device.state.change` (connected/paired/etc.)
     and `load.state.change` (loaded/unloaded/fault). Subscribers
     filter by type.
  b. One `device.state.change` event with a `load` sub-field. Fewer
     event types; consumers must read nested fields.
Leaning (a) for clarity and so the recorder can index by event type,
but not committed. Affects schemaVersion 2 export shape; pick before
implementation step 4.

### OQ-T8 — Exact UI copy for unloaded / fault / unknown device states

Status: **needs user / brand-voice call.**

Telemetry v2 surfaces three new states the UI doesn't currently word
for:
  - **unloaded** (cable not engaged or load released mid-set)
  - **fault** (device reports an error condition)
  - **unknown** (state cannot be determined — e.g. stale notify, BLE
    drop, or bytes outside known hypothesis range)
Need exact short strings (≤ 24 chars) for each, plus tone
(neutral / warning / error). Affects `VoltraUnitHeader` + any
live-capture status surface. Pick before implementation step 9.

## Process

### "Should we auto-update CloudKit re-enablement?"

Not a user question — a self-imposed gate. Don't re-enable CloudKit until
the v2 store has been stable across at least 2 releases past build 29.
Track the count: **post-b54 → 25 / 2 (well past gate, can re-enable
when desired).**

### Karpathy-method ship discipline (added post-b54)

Not a user question — a process gate. After b53 shipped wrong because
handoff docs were 25+ builds stale, every ship now updates `02`,
`03`, `00`, the relevant topic doc, and `WORK_LOG.md` in the same
commit as the version bump. See `00_START_HERE.md` "Mandatory ship
discipline" section. If a ship lands without doc updates, the next
session should treat that as a bug and back-fill before any new work.
