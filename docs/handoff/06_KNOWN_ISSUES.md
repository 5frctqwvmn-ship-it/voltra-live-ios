# 06_KNOWN_ISSUES

> Live list of bugs, edge cases, and quirks. Fixed items move to
> `docs/WORK_LOG.md` and are deleted from here. Unfixed items
> stay until shipped.

## Open

### KI-1 (b57) — 2× pulley snap on ±1 displayed

**Symptom.** Under 2× pulley, tapping the displayed ±1 lb
button on the WEIGHT card or any nested mod row may move the
displayed value by 2 lb instead of 1 lb.

**Why.** The displayed value is `device × 2`. Adjusting by 1
lb at the display layer would require a 0.5-lb step on the
device — but the device only accepts integer pounds. We snap
to the nearest device int, which means the user-visible result
moves by 2 lb (one device increment).

**Workaround.** None at the firmware level. Documented for the
user via release notes.

**Possible future fix.** Add a "fine adjust" mode that
round-robins the snap direction (alternates floor/ceil) so the
user can land on any displayed value over two taps. Not in
scope for b57.

### KI-2 (b57) — DROP idle auto-fire is currently a no-op

**Symptom.** The 2-second idle timer after DROP arming does
nothing observable beyond what arming already did
(manualDropSequence is set immediately on tap).

**Why intentional.** The hook is reserved for future
side-effects (haptic confirmation, BLE pre-write to warm the
device, telemetry). The user asked for the *affordance* of an
idle commit — not a behavior change today.

**When to revisit.** When we add per-set haptics or device
pre-warming.

## Recently fixed (move to WORK_LOG before deleting)

### KI-F1 (b57, fixed) — Rest timer first-engage miss

The very first rep of the very first set of a session would
sometimes not arm the rest-timer idle detector, leaving the
user without a timer when they tapped End Set. Fixed in
`SessionStore.swift` line ~132 by accepting `cs.peakLb > 10`
alongside `cs.reps > 0` as engagement evidence.

### KI-F2 (b57, fixed) — BLE write multiplied by pulleyMultiplier

`pushUpcomingStateToDevice` was multiplying the planned base /
ECC / CHAIN values by `pulleyMultiplier` before writing to
BLE. The device received doubled values under 2× pulley. Fixed
by removing the `* m` from baseLb / eccLb / chainsLb in the
push function. Display side still multiplies (correct).
