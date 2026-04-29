# 04_DECISIONS_AND_CONSTRAINTS

> Append-only record of design decisions and constraints. New
> entries go at the bottom. Each decision lists the build it
> landed in, the question it answers, the chosen path, and the
> rejected alternatives.

## D1 (b57) — DROP off-state collapses tile entirely

**Q.** When the user taps an armed DROP tile to disarm, do we
keep the nested row visible (with state cleared) or collapse
the row entirely?

**Decision.** Collapse the nested row entirely. The DROP tile
goes back to its un-armed visual state. `manualDropSequence` is
set to `nil`.

**Why.** Symmetry with ECC/CHAIN/INV CHAIN: when those mods are
disarmed, their nested rows disappear. DROP should match.

**Rejected.**
- Keep nested row with greyed values — felt inconsistent and
  led to confusion in V2 user testing.

## D2 (b57) — Logarithmic fade for rep history overlay

**Q.** What fade curve for the historical reps drawn behind the
live force curve?

**Decision.** Logarithmic. `opacity = max(0.10, 1/(1+ln(repsAgo+1)))`,
hard cap at 8 visible reps.

**Why.** Most recent rep stays bold (opacity ~1.0); the next 2-3
reps remain clearly visible (~0.6, 0.5, 0.4); older reps fade
softly without disappearing. Linear fade made rep 2 already
feel washed out; exponential made rep 8 invisible.

**Rejected.**
- Linear `1.0 - repsAgo/8`.
- Exponential `0.5^repsAgo`.

## D3 (b57) — Pulley doubling logic ported from git history

**Q.** Source for the pulley-multiplier doubling logic.

**Decision.** Ported from commits `8a980d6` and `ec71bcc` (b51-era).

**Why.** That logic was correct for the displayed-vs-device
distinction. b56 introduced a regression (multiplied on BLE
write side). b57 restores the b51 split.

**Constraint.** `pendingPlannedWeightLb` is device frame.
Display = device × multiplier. BLE write = device (no
multiplication). See `03_CURRENT_FEATURE_SPEC.md` §4 and
`06_KNOWN_ISSUES.md` for the 2× snap edge case.

## D4 (b57) — Status reveal on tap, not hover/long-press

**Q.** How does the user surface full BLE state from the small
header status dot?

**Decision.** Tap the dot opens a SwiftUI `.popover` with the
full state string ("Connected to VOLTRA-A1B2", "Scanning…",
etc.).

**Why.** iOS has no hover; long-press conflicts with VoiceOver
and feels hidden. Tap-to-popover is discoverable.

**Rejected.**
- Always-on text label (eats horizontal space, defeats the
  point of the V3 cleanup).
- Long-press.

## C1 (carryover, b50+) — Sacred files DO NOT MODIFY

`VoltraProtocol.swift`, `TelemetryExtractor.swift`,
`PacketParser.swift`, `FrameAssembler.swift`. Any change here
requires firmware-side coordination.

## C2 (carryover) — User has no Mac

All signing is browser-only / CI. We do not run xcodebuild,
xcrun, altool, or fastlane on the user's machine.

## C3 (carryover) — 5-gate ship verification

Every TestFlight ship must verify all five:

1. Release workflow returns success.
2. Run log is pulled to `/tmp/release_log_<build>.txt`.
3. altool step duration ≥ 20s.
4. "UPLOAD COMPLETED SUCCESSFULLY" marker appears in the log.
5. Zero ERROR lines in the log.

CI green alone is not enough.

## C4 (carryover) — Append-only WORK_LOG

`docs/WORK_LOG.md` is append-only. Never edit prior entries.
New build entry goes at the bottom.

## C5 (carryover) — `keep features separate bills`

The user pays per build. Keep features small and shippable so
they can correlate cost to feature; never bundle unrelated work
into one build unless the user requests it.
