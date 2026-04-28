# VOLTRA Live — Design System

This folder is a **specification of how VOLTRA Live looks, sounds, and behaves** — pulled out of the SwiftUI source so designers, copywriters, and future agents can reason about the app without opening Xcode.

It is descriptive, not prescriptive: every token in `colors_and_type.css` is reverse-mapped from `VoltraLive/Views/VoltraTheme.swift` and the actual view code. If something here disagrees with the SwiftUI source, the SwiftUI source wins — open a PR to update this doc in the same commit.

> **Do not** import `colors_and_type.css` into the iOS app. SwiftUI consumes the Swift theme file directly. The CSS exists so the design-system preview pages and any future web/marketing surface have a single source of truth that matches the app pixel-for-pixel.

## Files

| File | What it is |
|---|---|
| `colors_and_type.css` | All color, type, spacing, radius, and effect tokens. Mirror of `VoltraTheme.swift`. |
| `preview/index.html` | Browseable design-system gallery (open in browser). |
| `preview/*.html` | Individual cards: palette, type ramp, components, screens, iconography. |
| `ui-kit.html` | Single-page UI kit — every component variant rendered against the dark canvas. |
| `SKILL.md` | How agents should use this design system when designing new features. |

---

## CONTENT FUNDAMENTALS

VOLTRA Live is a **single-purpose live readout** for a cable strength machine. The screen is mounted on a rack and the user is mid-set, lifting heavy. Every word and number on screen has to work at three constraints:

1. **8 ft viewing distance.** Numbers must be legible across a garage gym.
2. **Sweat-and-grip interaction.** Buttons must work with one finger, no precision, no scrolling mid-set.
3. **Zero-attention reading.** Glance for ≤ 1 second between reps, get the answer, look away.

### Voice

- **Operator, not coach.** The app reports state; it does not motivate. No emoji, no exclamation marks, no "Great job!" copy. The user is the coach.
- **Verbs are imperative when needed, descriptive otherwise.** *"Pair your VOLTRA"* not *"Let's get you connected!"*. *"Set complete"* not *"Nice set!"*.
- **Numbers do the talking.** A tile that shows `12 REPS` doesn't need a sentence above it explaining what reps are.
- **Errors are factual.** *"Bluetooth Off"* + *"Turn on Bluetooth in Settings to scan for VOLTRA"* — no apology, no anthropomorphism.

### Naming the things on screen

| Concept | Always called | Never called |
|---|---|---|
| The hardware | **VOLTRA** (caps) or **VOLTRA cable** | "the device", "the machine", "BP" |
| One pull-and-return | **rep** | "repetition", "lift" |
| Group of reps | **set** | "round" |
| Up phase (concentric) | **PULL** | "lift", "up", "concentric" |
| Down phase (eccentric) | **RETURN** | "release", "down", "eccentric" |
| Pause between reps | **TRANSITION** | "rest" — `REST` is reserved for *between sets* |
| Pause between sets | **REST** | "break", "recovery" |
| One workout session | **session** | "workout" (avoid; ambiguous w/ exercise) |

### Units

- **Force** is shown in **lb** (always). The protocol gives tenths-of-pounds; we display whole pounds in the live readout, one decimal in history.
- **Resistance / target weight** in **lb**, integer.
- **Heart rate** in **bpm**, integer, sourced from HealthKit, always with a green pulse dot when fresh (≤ 5 s) and a grey dot when stale.
- **Active calories** in **kcal**, integer, same fresh/stale rule.
- **Time** uses **MM:SS** for rest (never `0:42`, always `00:42`), and shorthand (`12 min`, `1 h 04 m`) for session totals.
- **Eccentric multiplier** is shown as **%**, integer (`100%` baseline, `120%` heavier on the way down).

### Numerals

All live numbers are **monospaced + tabular**. The digit `1` and the digit `8` must take the same column width, or the readout shimmers as the count climbs. Ports of this UI to web must use `font-variant-numeric: tabular-nums` and a mono family.

### Information density rule

A live screen has **at most 4 primary tiles** (REPS · PHASE · FORCE · REST) plus one optional secondary strip (HR · KCAL paired tile, or compare-strip). If a feature needs a 5th tile, something else is removed first. Never crowd.

---

## VISUAL FOUNDATIONS

### The aesthetic in one sentence

**A black instrument panel with a single teal phosphor color and big mono numerals.** Think: trading terminal, lab oscilloscope, spec-sheet PDF — not consumer fitness app.

### Why dark-only

The app is rack-mounted in garages and basements. Light mode would blow out a phone's auto-brightness in a dim room, and white tiles look medical. Dark canvas + one bright accent reads as instrumentation, which is what this is.

### Surface system (3 elevations)

```
─── --vl-bg          #0a0e0c   page / canvas — almost-black with a green hint
─── --vl-bg-elev     #11181a   tiles, sheets, primary surfaces
─── --vl-bg-elev-2   #1a2426   nested elements (chips inside tiles, hover)
─── --vl-border      #1f2c2e   1px hairlines around every elevated surface
```

Surfaces are flat. **No gradients on canvas. No drop-shadows on tiles.** A 1px hairline is the only edge treatment. Sheets get one card-shadow on the way in; tiles do not.

### Color principles

- **One accent color**, `--vl-accent` `#00d4aa`. It marks: PULL phase, primary CTAs, active connection state, the icon. Nothing else gets to be teal.
- **Phase colors are semantic, not decorative.** `--vl-pull` (teal), `--vl-return` (orange), `--vl-transition` (blue), `--vl-idle` (dim). These appear on the force chart, the phase tile, and nowhere else. Don't reach for them as accents.
- **Warning ≠ danger.** `--vl-warn` (orange) is for stale-but-recoverable state (Bluetooth off, no telemetry for 2 s). `--vl-danger` (red) is reserved for the **BOTTOM** marker on the force chart and hard errors. Mixing them is a spec violation.
- **Translucent washes.** Phase tiles get a 12% wash of their phase color as background — `--vl-pull-wash`, `--vl-return-wash`, `--vl-transition-wash`. This is the only place we use color-tinted backgrounds.

### Type system

| Use | Stack | Size | Weight | Notes |
|---|---|---|---|---|
| Big tile readout (REPS, FORCE) | mono | 72 / 44 iPhone | 700 | tabular-nums, line-height 0.95 |
| Phase value (PULL / RETURN) | UI | 52 | 700 | same color as phase |
| Tile label (REPS, FORCE, REST) | UI | 11 | 700 | UPPERCASE, +2.0px tracking |
| Wordmark "VOLTRA Live" | UI | 28 | 700 | Connect screen only |
| Body / instructions | UI | 15 | 400 | dim text |
| Row text (history list) | UI | 14 | 500 | primary text |
| Meta (RSSI, dBm, time-ago) | UI | 13 | 400 | dim text |

The full ramp lives in `colors_and_type.css` as CSS custom properties. **All numbers are mono.** All labels are uppercase + letter-spaced. All body copy is sentence case — not title case.

### Spacing & radius

- **Tile radius `18px`.** This is the project signature. Buttons are smaller (`12px`), compact cells smaller still (`10px`), pills are full-round.
- **Tile interior padding `18px 20px`.** Looks generous because numbers inside are large.
- **Live grid gap `12px`.** Tighter than typical card grids — adjacent tiles read as one instrument cluster.
- **Tap target floor `44px`** (HIG). Primary CTA `50px`. Tile tap area `56px` so a sweaty thumb hits it.

### Effects

- **No blur. No glow.** A phosphor look is tempting on dark UI; resist. The app is read in bright sun on a phone, and glow turns numbers into smudges.
- **One motion primitive: phase pulse.** The PHASE tile's wash brightens 12% → 20% on phase change, eases back over 240 ms. Nothing else moves.
- **Pulse dot** on HR/KCAL tile blinks at 1 Hz when data is < 5 s old, holds steady grey when stale. Mirror with `<span class="vl-pulse-dot">` in the preview.

---

## ICONOGRAPHY

The app uses **two glyph sources**:

1. **The wordmark / app icon** — three nested teal triangles on `--vl-bg`. Render the mark, not "BP" or "VL" text. Source: `VoltraLive/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Mirrored in `assets/app-icon-1024.png`.
2. **Apple SF Symbols** — system icons only, used sparingly. The codebase uses these specific symbols:

| Symbol | Where | Meaning |
|---|---|---|
| `bolt.fill` / `bolt` | Connect button, status dot | The cable / power |
| `antenna.radiowaves.left.and.right` | RSSI, BLE scanning | Wireless signal |
| `heart.fill` | HR tile | Heart rate (HealthKit) |
| `flame.fill` | KCAL tile | Active calories (HealthKit) |
| `arrow.clockwise` | Re-scan, retry | Refresh / retry |
| `gear` | Settings sheet trigger | App settings |
| `chevron.up` / `chevron.down` | History drawer | Expand / collapse |
| `xmark` | Sheet dismiss | Close |
| `clock.fill` | Rest timer tile (decorative) | Rest |

**Icons never carry semantic load alone.** Every icon has a label next to it (the heart icon is paired with "HR" and a number). This is an instrument, not a Material design.

When in doubt: skip the icon. A label and a number is almost always clearer than a label, an icon, and a number.

---

## How to use this design system

If you are an agent designing a new screen for VOLTRA Live:

1. Read `SKILL.md` first.
2. Open `preview/index.html` and skim every card so you know what already exists.
3. Reach for an existing component (TileView, CompareStrip, ConnectCard) before inventing one.
4. If you must invent: match the surface elevation, hairline border, 18px radius, mono numerals, and the tap-target floor. New components belong in this design system, not as one-offs in a screen.
5. Update this README and `colors_and_type.css` in the same commit as the SwiftUI change. The repo is the source of truth — do not let docs drift.
