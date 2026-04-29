# QA_LOG.md — post-build verification

> Append-only log of post-build QA checklists run with the user
> after every TestFlight ship. One section per build. Established
> in b58 (April 2026) at user request — see AGENTS.md
> "Post-build QA checklist".
>
> Format per build:
>
> ```
> ## bNN — vX.Y.Z-buildNN — YYYY-MM-DD
> ### Items shipped
> ### User responses
> ### Actions taken
> ```
>
> Confirmed regressions that aren't fixed in-session must also
> get a KI-N entry in `06_KNOWN_ISSUES.md`. Don't edit past
> entries — they're history.

---

## b58 — v0.4.36-build58 — 2026-04-29

### Items shipped (V4)

1. **Dropset state-machine port** — `tapDropTile` /
   `adjustDropStep` rewired to `LoggingStore` cascade
   (`startDropSet`, `bumpCascadeTier`, `cancelDropSet`); nested
   DROP row uses `dropChainPlannedLb` + `previewNextCascade`;
   `dropArmed` reads `logging.dropSetActive`.
2. **Tonal-style force curve** — `ForceChartV2` ECC/CON
   dual-band gradient under polyline, inline ECC/CON labels at
   phase centroid (current rep only), CHAIN mirrors gradient
   direction.
3. **Weight cell single-line fix** — `lineLimit(1)` +
   `minimumScaleFactor(0.6)` + fade mask + `layoutPriority(1)`,
   no more wrap-overlap with WEIGHT label.
4. **Dual-VOLTRA L/MERGE/R header** — `bothVoltrasConnected`
   swaps header to dualHeaderCluster, with sideDot per slot,
   MERGE button toggling `mdm.workoutMode`.
5. **Twin Mode fused pill + TWIN badge** — fused pill replaces
   L/R cluster in `.combined`; TWIN badge inline next to weight
   number.
6. **Independent focus binding** — `focusedSlot` `@State` drives
   `focusOverrideAssignment` passed to both `writerRouter.apply`
   call sites; weight/mod writes scope to the focused side only.
7. **Pulley grey-out in Twin Mode** — `PulleyAndPlatesBarV3`
   gets `@EnvironmentObject mdm`; pulley chip `.disabled` with
   `lock.fill` icon and 0.55 opacity in Twin (not hidden,
   per V4-D5).

### User responses (partial — wave 1 of 2 returned)

- **Item 1 — Dropsets:** Not working as intended. Specifics:
  - DROP timer is 4 s; user wants **2 s**.
  - Idle bar should morph into the **dropset progress bar** (showing
    the 2 s countdown) when DROP is armed and the lift goes idle, then
    morph again into the rest timer once cascade hits floor.
  - DROP **should not pre-lower the weight on tap** — it should arm
    only; weight reduction fires when the lift goes idle and the 2 s
    timer elapses.
  - Separate bug observed: weight was **dropping by 5 lb during reps**
    even when the user wasn't touching DROP. Root cause unknown.
- **Item 2 — Force curve:** Not "not working" — user delivered a full
  design spec (saved as `docs/handoff/design/force_curve.md`). b58
  ForceChartV2 only landed §3b dual-band fill + §3c inline labels +
  §3d corner-mirror gradient. Missing for b59+:
  - §3b 200 ms blended phase transition
  - §3c label fade timing (3 s OR rep 2, mid-set mode-change re-surface)
  - §3d vertical gradient *within* fill encoding ROM-position
  - §3e dotted 80%-of-peak line, per-rep peak dots + labels, target line
  - §3f rep stacking with logarithmic opacity decay (cap ~8)
  - §3g compact mode-aware legend top-left
  - §6 low-weight Y floor `max(peak × 1.2, 15 lb)`, mid-set mode-change
    rule (historical reps keep prior render).
- **Item 3 — Weight cell:** Working as intended. ✅
- **Item 4 — Dual-VOLTRA L/MERGE/R header:** Not working as intended.
  - User saw legacy V1 `ACTIVE • LEFT / NEXT • RIGHT` header instead
    of the b58 dualHeaderCluster.
  - Confirmed via IMG_2400 (LiveCapture, b58, both Voltras paired,
    legacy header showing) and IMG_2401 (home screen, `Left ● Right ●`
    pill, both connected).
  - **Root cause found:** `LiveCaptureContainer.shouldUseV2` (b53/b54)
    explicitly routes to V1 the moment both Voltras pair. b58 added
    the dual UI to V2 but never updated this gate. All b58 V2 dual-
    Voltra code was dead in this scenario.
- **Items 5–7 (Twin Mode pill / TWIN badge / focus binding / pulley
  grey-out):** Not asked. Wave 2 deferred until b59 lands and the
  user can actually reach V2 with two Voltras paired.

### Actions taken

- Saved user-supplied force-curve spec verbatim to
  `docs/handoff/design/force_curve.md` (will be the source of truth
  for the b59+ force-curve rebuild).
- **Hotfix shipped as b59 (v0.4.37-build59):** rewrote
  `LiveCaptureContainer.shouldUseV2` so two paired Voltras force V2
  regardless of `uiVersion`, while chain sessions still pin to V1
  and single-Voltra still respects user preference. See
  `WORK_LOG.md` b59 entry for the full diff and routing matrix.
- Filed follow-ups for b59+ to `06_KNOWN_ISSUES.md`:
  - **KI-7** Dropset timer is 4 s, user wants 2 s.
  - **KI-8** Idle bar should morph into dropset progress bar then
    rest timer (state machine missing).
  - **KI-9** DROP tap pre-lowers weight; should arm-only and fire
    on idle + 2 s timer.
  - **KI-10** Phantom -5 lb weight drop during reps with no user
    DROP input. Repro unknown.
  - **KI-11** Force-curve full spec (force_curve.md) missing §3b
    blend, §3c label timing, §3d ROM gradient, §3e 80% line + peak
    dots, §3f rep stacking, §3g legend, §6 low-weight floor +
    mid-set rule. Tracked as a single epic.
- Wave 2 of b58 QA (items 5–7) re-runs after the user installs b59
  and can reach V2 with two Voltras paired.

---

## b60-prep — feat/ui-v4-dropset-armonly — branch open 2026-04-29

> Branch not yet shipped. No version bump in this commit. The b60
> tag will be cut after user sign-off on the PR.

### Items implemented (V4 b58 → b60 follow-ups)

1. **KI-9 — DROP tap is arm-only.** `armDropSet` captures
   anchor + writer; cable holds working weight; cascade engages
   on first 2 s sub-floor lift-idle boundary via
   `noteTelemetryActivity`.
2. **KI-8 — Unified progress bar.** `phaseOrRestBar` morphs
   across rest > dropset > phase. New `dropProgressBar`
   labels: `DROP · ARM` / `· IN` / `· NEXT` / `· BOTTOM`.
3. **KI-7 — Cascade interval = 2 s.** Already shipped in b45;
   doc was stale. Verified at LoggingStore.swift:113 and
   documented in `entities/dropset_state_machine.md`.
4. **KI-10 (likely fix) — Phantom −5 lb mid-rep drop.** The
   arm-only refactor blocks the most plausible cause path.
   Re-test on hardware after b60 ships before closing.

### Items NOT shipped this branch

- **KI-11 — Force curve full spec.** Deferred per the user's
  "keep features separate bills" rule. Tracked as a single
  epic; next branch.

### Hardware QA checklist (run after b60 TestFlight install)

- [ ] Tap DROP mid-rep, keep lifting → tile shows armed; weight
      unchanged; bar shows `DROP · ARM`.
- [ ] Tap DROP, finish rep, rack the cable → bar morphs to
      `DROP · IN` with 2 → 1 → 0 countdown. At 0, weight drops
      by tier 1 (5 lb).
- [ ] In active cascade, tap DROP → tier rolls 1→2→3→1; bar
      countdown resets.
- [ ] Active cascade reaches 5 lb floor → bar shows
      `DROP · BOTTOM`; no further drops; rest engages after 10 s
      no-rep watchdog.
- [ ] Tap DROP twice quickly before lift goes idle → arm
      clears; weight unchanged; cooldown prevents re-arm.
- [ ] Long-press DROP while armed → arm clears with haptic.
- [ ] Long-press DROP while active → cascade cancels; cable
      returns to anchor weight.
- [ ] Adjust weight (`±` stepper) while armed → next cascade
      drop steps off the new working weight, not the value
      captured at tap.
- [ ] Run a normal exercise (DO NOT engage DROP) → no phantom
      −5 lb drops between reps. If repro, this re-opens
      KI-10.

### User responses

(to be filled in post-ship)

### Actions taken

(to be filled in post-ship)
