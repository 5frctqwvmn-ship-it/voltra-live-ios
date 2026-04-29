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

### User responses

_(pending — checklist sent in this turn)_

### Actions taken

_(pending user response)_
