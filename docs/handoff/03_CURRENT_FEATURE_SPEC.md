# 03_CURRENT_FEATURE_SPEC

> **Scope.** This doc captures the V3 LiveCaptureView feature spec as
> it stands at the b57 ship. It is the authoritative description of
> what the screen *does* — not how it's wired internally (that's
> `04_ARCHITECTURE.md`) and not what's planned next (that's
> `03_ROADMAP.md` — note: the 03_ROADMAP file predates this spec doc;
> the two are intentionally separate).

## V3 Live Capture screen — top-to-bottom

### §1. Header strip

- **Leading:** ← End button.
- **Inline:** small "V3" build watermark.
- **Center:** exercise-name marquee. 5s pause → scroll left → 1s
  pause at end → reset → loop. If name fits, no scroll.
- **Trailing:** telemetry cluster `[● 118 bpm · 42 kcal]`. The
  leading dot is the BLE connection status (green = connected,
  amber = scanning/connecting, grey = idle, red = disconnected).
  Tapping the dot opens a popover with full BLE state text.
- **No top dial.** The V2 dial is removed entirely.

### §1a. Phase strip OR Rest Timer Bar

Same swap behavior as V2: phase strip while a set is active, rest
bar after End Set is tapped. Rest bar HSL sweeps green → amber →
red over the rest preset, blinks 1Hz once over preset.

### §2. WEIGHT card (the big number)

- Big number shows **effective** weight (device frame ×
  pulleyMultiplier).
- Tap the number to toggle hardware LOAD / UNLOAD.
- Pill in upper-right shows LOADED / UNLOADED.
- **Stepper grid:** −5 / −1 / +1 / +5 (lb). Same shape as all four
  nested mod rows.

### §3. Mod tile row + nested mod rows

Four tiles: ECC, CHAIN, INV CHAIN, DROP. Tapping any tile
arms/disarms the mod. Nested rows expand below the tile row, one
row per armed mod.

**Increment grid (all four):** `−5 / −1 / +1 / +5`. ECC range
5–400, CHAIN/INV CHAIN range 0–300.

**DROP tile (toggle, b57 V3 §2):**

- First tap: arm a 5-lb drop. Nested row + stepper appear.
- Second tap: disarm. The nested row collapses entirely.
- Drop step is clamped to multiples of 5 lb. The ±1 buttons in
  the DROP stepper render greyed (`dropMode: true`) and are
  no-ops at the handler level.
- After 2 seconds of idle (no taps), the planned drop is
  considered committed. Disarm still works.

**Mutual exclusion:** CHAIN and INV CHAIN cannot be armed at the
same time — arming one disarms the other.

### §4. Pulley + Added-plates bar (above the force chart)

Two compact dial controls, sitting directly above the force
chart (same width as the chart):

- **Pulley:** 1× / 2× toggle. Default **1×**. Multiplies the
  effective force the user feels relative to the device cable
  load. UI side multiplies *display*; BLE side does NOT multiply
  (the device sees the device-frame value).
- **Added plates:** integer 0…N, default **1 lb**, increments
  of 1 lb.

**Pulley math (CRITICAL — verified b57):**

- `LoggingStore.pendingPlannedWeightLb` = device frame.
- WEIGHT card big number, force chart Y axis, log storage all
  use `× pulleyMultiplier`.
- BLE write (`pushUpcomingStateToDevice`) does **not** multiply.
- Under 2× pulley, displayed ±1 lb may snap by 2 lb — this is
  documented in `06_KNOWN_ISSUES.md`.

### §5. Force chart (b57 V3 §1)

Dynamic Y-axis ceiling, 1.5s ease on changes, recomputed live
as weight / ECC / CHAIN / INV CHAIN deltas land:

```
total = max(
    working,
    working + ECC,
    working + CHAIN,
    working + ECC + CHAIN
)
yMax = max(60, total × 1.2)
```

20% headroom above the highest possible peak; 60-lb floor for
unloaded screens.

**Rep history overlay (b57 V3 §1a):**

- Up to 8 most-recent reps drawn behind the live curve.
- Logarithmic fade: `opacity = max(0.10, 1/(1+ln(repsAgo+1)))`.
- Reset on End Set or when rest expires.

### §6. Rest timer (b57 V3 §6)

First-engage miss is fixed (b57). Idle detector now accepts
`cs.peakLb > 10` alongside `cs.reps > 0` — the very first rep
of the session no longer slips through the arm-check.

### §7. V1 restore section

Bottom of scroll view: logged sets list + bottom-actions row
(End Set, etc.). Pulley + plates were lifted out of this
section in b57 (now lives above the chart per §4).

## What the screen does **not** have

- ❌ Top dial (removed in V3).
- ❌ Micro-drops (DROP must always be a multiple of 5 lb).
- ❌ Simultaneous CHAIN + INV CHAIN.
