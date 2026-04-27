# 08 — Superset Spec (deferred to build 31)

This is **deferred** until dual-Voltra ships and stabilizes in build 30.
Captured here so the spec doesn't get lost.

## What a superset is (in the user's words)

Two or more exercises performed back-to-back. Hit Start on the first one;
when it completes, the system **automatically logs it** and switches to
the next one. Can be 2, 3, 4, 5+ steps. Each step is bound to a specific
Voltra (Left or Right).

## Creation flow — "+" button

The user rejected a separate planner. Supersets are built **from the
existing workout screens** the user already configures sets on.

- A "+" button on the live workout screen labelled **"Add to superset"**.
- Tapping it appends the **workout-as-configured** to the in-progress
  superset:
  - exercise type
  - target weight
  - target reps
  - Voltra assignment (Left/Right) — comes from how the user is
    currently set up
- After tap, returns the user to the main workout picker so they can
  configure the next step.

## Persistent tray chip

While a superset is being assembled (or running), a chip is pinned at the
top or bottom of the screen:

```
Superset · N steps · [Start] [Clear]
```

- `N` is the current step count.
- `Start` begins execution from step 1.
- `Clear` discards the in-progress superset.

## Execution

1. Tap **Start** on the chip.
2. The superset's first step's Voltra (Left or Right) becomes the
   **active side**. Tiles, controls, and write surface flip to that side.
3. Auto-detection of set completion uses the existing 4 s / 10 s
   drop-cascade detector (same as today).
4. On set complete:
   - Auto-log the step (no user tap).
   - Auto-advance to the next step.
   - Active side flips to the next step's Voltra.
5. Repeat until the last step completes. Surface a success toast.

## Pre-loading

To minimize between-step idle time:

- At superset **Start**, pre-load **both** Voltras with their first
  upcoming step's weight (one for each side, even if step 1 only uses
  one side — step 2's weight goes on the other in the background).
- After each step completes, push the next planned weight for that
  side in the background, so by the time the user is at the next
  station the device is ready.

## Logging

A completed superset is logged in history as **one superset block**,
with the constituent step rows nested inside. History UI to be designed
when build 31 starts; for now persist enough metadata to reconstruct.

## Dependencies

- Dual-Voltra Independent mode must work (each step is bound to a side).
- `VoltraWriter` weight pre-load must be reliable enough that pre-loading
  the "wrong" side mid-set doesn't corrupt the active set.

## Open questions for build 31

Move to `10_OPEN_QUESTIONS.md` when build 31 starts:

- Should supersets allow the same Voltra on consecutive steps, or
  require alternating? (User said any number of steps; assume any
  combination is allowed.)
- What's the UI when the user wants to **edit** a superset mid-build
  (remove a step, reorder)? Tap on the chip → list view with delete
  and reorder is the obvious fallback.
- If a Voltra disconnects mid-superset, do we pause execution or skip
  to the next step on the still-connected side?
