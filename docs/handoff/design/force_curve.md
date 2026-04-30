# Force Curve — Design Spec & Research

**Doc location:** `docs/handoff/design/force_curve.md`
**Status:** Design reference. **⚠️ 2026-04-30 update (b71 / ADR V4-D20):** the b58/b67 `ForceChartV2` implementation that landed against this doc was reverted. V1's `ForceChartView` (raw-sample phase-colored polyline + Catmull-Rom smoothing) is now the canonical force-curve renderer for both V1 and V2. The Tonal-style dual-band fill / CHAIN gradient mirror / rep-history overlay / parametric sine lobes documented below are NOT currently mounted. They are preserved here as design references in case any of them are reintroduced — but per V4-D20 they must be added to V1's `ForceChartView` (so V1 and V2 stay in sync), not by re-mounting `ForceChartV2.swift` (which is retained on disk with a SUPERSEDED banner for rollback only).
**Primary inspirations:** Tonal (force/power overlays, dual-phase rendering, rep stacking)  and sport-science force-time conventions [tonal](https://tonal.com/blogs/all/eccentric-mode-improves-performance)

---

## 1. The Canonical Shape: Force-Time Curve

The fitness industry converges on a **force-time curve** (force on the Y-axis, time on the X-axis) for in-rep visualization. Each rep is rendered as a shape that rises into the concentric phase and falls (or rises again, if eccentric overload is active) during the eccentric phase. [elitefts](https://elitefts.com/blogs/motivation/understanding-the-force-time-curves-role-in-breaking-prs)

Four phases are recognized in sport science, which we can collapse to two for display: [elitefts](https://elitefts.com/blogs/motivation/understanding-the-force-time-curves-role-in-breaking-prs)
- **Concentric** (pushing/pulling — muscle shortening)
- **Eccentric** (lowering — muscle lengthening, naturally 20–50% stronger) [youtube](https://www.youtube.com/watch?v=F9qXAekG7vU)

Force is naturally **higher during eccentric** than concentric for the same movement. Our visualization must make this asymmetry visible — it's the whole point of eccentric overload and chain modes. [brookbushinstitute](https://brookbushinstitute.com/glossary/force-velocity-curve)

---

## 2. How Tonal Renders It (reference)

From Tonal's public material and user-captured screen footage:

- **Real-time line graph at the top of the workout screen**, force on Y, time on X, scrolling left-to-right. [tonal](https://tonal.com/blogs/all/more-real-time-data-in-workouts)
- **Dotted reference lines overlay the curve** — Tonal draws an 80%-of-peak-power dashed line so the athlete can see whether each rep is clearing the quality threshold. [youtube](https://www.youtube.com/watch?v=uuzgZc361co)
- **Per-rep tracking**: Tonal automatically counts reps and annotates each rep's peak force/power on the curve. [youtube](https://www.youtube.com/shorts/5YNP-cjHY5A)
- **Eccentric Mode** adds digital weight on the lowering phase (25% by default, research-backed at 20–50%) and removes it on the concentric — so the curve visibly has a **taller eccentric hump** than concentric. [tonal](https://tonal.com/blogs/all/eccentric-training-for-strength)
- **Chains mode** is the spatial inverse: lightest at the bottom of the ROM, heaviest at the top — the curve ramps up as you extend and falls as you return.
- Tonal uses **color coding to separate metrics** (force vs. power vs. weight) rather than color-coding phases — phases are implied by the curve's direction.

---

## 3. Recommended Visual Language for Voltra V4

### 3a. Base layer: force-time polyline

- X-axis: **time** (rolling 30-second window, matching current `FORCE · 30 S` label).
- Y-axis: **force / effective load (lb)**, auto-scaled per V3 spec (peak × 1.2, 20% headroom floor, 1–2 s eased rescale).
- Single smoothed polyline traces instantaneous force from the Voltra's sensor.

### 3b. Phase differentiation: dual-band fill under the polyline

Rather than two separate lines, fill the area under the polyline with **phase-colored bands**:

- **Concentric phase fill** — primary brand color (e.g., green/teal) at lower opacity (~35%).
- **Eccentric phase fill** — warmer accent color (amber → orange) at higher opacity (~55%), visually "weightier" because the load is actually higher.
- Transition between phases uses a **short gradient blend (~200 ms of X-axis width)** so the handoff feels continuous rather than a hard color break.

This matches sport-science convention: the **area under the curve is impulse**, so filling the area (not just coloring the line) conveys real training information, not just decoration. [whistleperformance](https://www.whistleperformance.ai/post/eccentric-and-concentric-impulse-key-metrics-in-sport-performance)

### 3c. Inline phase labels

- On the **first rep of each set**, draw small text labels `CON` and `ECC` above the respective bands.
- Labels fade out after **3 seconds or on rep 2, whichever comes first** — they're tutorial affordances, not permanent chrome.
- If a new mode activates mid-set (e.g., user toggles ECC on), re-surface the labels on the next rep.

### 3d. Chain mode rendering

Chains produce an **inverse gradient** vs. eccentric:
- Eccentric mode: highest force at the **bottom of the ROM** (lowering phase peaks).
- Chain mode: highest force at the **top of the ROM** (top of concentric peaks). [tonal](https://tonal.com/blogs/all/transform-your-strength-training-routine-with-dynamic-weight-modes)

Render chain mode by **mirroring the gradient direction** of the fill:
- ECC: eccentric band fades **darker as you descend** (bottom-heavy).
- Chain: concentric band fades **darker as you ascend** (top-heavy).
- Inverse chain: same as chain but mirrored — **darker as you descend** on concentric.

Use a subtle **vertical gradient within the fill** (not just a flat color) to encode this direction. The user should be able to glance at the rep shape and instantly read *where in the ROM the load was heaviest* without reading any label.

### 3e. Peak markers and reference lines

Borrow from Tonal: [youtube](https://www.youtube.com/watch?v=uuzgZc361co)
- **Dotted horizontal reference line at 80% of the set's peak force** — a quality threshold. Reps that don't clear it are visually obvious.
- **Small dot at each rep's peak**, labeled with the peak force value (e.g., `47 lb`).
- **Optional target line** if the user has a force/power target (for future Intensity metric overlay).

### 3f. Rep stacking (history overlay)

Per V3 spec and Tonal's per-rep tracking: [tonal](https://tonal.com/blogs/all/more-real-time-data-in-workouts)
- All reps of the **current set** stacked on the same canvas, aligned by rep-start time or normalized to equal width.
- Older reps fade with **logarithmic opacity decay** — newest rep at 100%, rep N−1 at ~70%, N−2 at ~50%, trailing off to a ~15% floor.
- Cap at ~8 visible overlays; beyond that, oldest drops off entirely.
- **Fatigue visualization:** because peak force typically drops across reps in a set, the stacked overlay naturally shows the **fatigue envelope** — each rep's peak is a little lower than the last, and the set's "decay shape" is readable at a glance. [instagram](https://www.instagram.com/p/DQSAPvJki5L/)
- Reset the stack when the set ends (rest timer expires or End Set pressed).

### 3g. Color legend (compact)

In the top-left of the force-curve panel, a small legend that only appears when a non-baseline mode is active:

```
■ CON   ■ ECC +25%   (or)   ■ CON   ■ CHAIN +30 at top
```

Colors match the fill. Legend is the only place where mode details live — the curve itself stays clean.

---

## 4. Layering Priorities (what draws on top of what)

From bottom to top:
1. Grid / axis (very faint)
2. 80%-peak dotted reference line
3. Historical rep fills (faded)
4. Current rep fill (dual-band with gradient)
5. Polyline (crisp stroke over the fill)
6. Peak dots + labels
7. Inline CON/ECC text labels (first rep only)

---

## 5. Metrics Worth Considering (research followups)

Beyond raw force, the industry tracks: [metric](https://www.metric.coach/articles/eccentric-power-a-new-metric)
- **Peak power** (force × velocity) — Tonal exposes this as a standalone mode with its own 80% dashed line. [youtube](https://www.youtube.com/watch?v=uuzgZc361co)
- **Eccentric impulse** (area under the eccentric portion of the curve) — correlates with concentric strength gains. [metric](https://www.metric.coach/articles/eccentric-power-a-new-metric)
- **Eccentric peak force** — distinct from concentric peak, worth surfacing in the end-of-set summary. [instagram](https://www.instagram.com/p/DQSAPvJki5L/)
- **Effort / Strength Score** — Tonal's effort-weighted score = load ÷ estimated 1RM. [tonal](https://tonal.com/blogs/all/level-up-with-tonals-enhanced-strength-score)

**Recommendation:** ship force-time only this pass (per V3 scope). In the intensity-metric research doc, evaluate:
1. Adding a secondary **power curve** as a translucent second line (Tonal parity). [youtube](https://www.youtube.com/watch?v=uuzgZc361co)
2. Displaying **eccentric impulse** as a post-set number.
3. Whether the primary in-rep visual should pivot to **power** (more actionable for athletes) rather than raw force. [youtube](https://www.youtube.com/watch?v=uuzgZc361co)

---

## 6. Edge Cases & Gotchas

- **Very low weights (5–10 lb):** even with 20% headroom, the curve can look flat. Apply a higher minimum Y-axis range (e.g., `max(peak × 1.2, 15 lb)`) so a bodyweight-assist set still renders with visible shape.
- **Very long sets (>8 reps):** rep stacking gets crowded. Consider **horizontal stacking** (mini rep-shapes laid out left-to-right like a sparkline) as a follow-up variant.
- **Partial reps / failed reps:** when force doesn't complete a full cycle, still render whatever phase did occur. Don't hide failed reps — the shape *is* the feedback.
- **Mid-set mode changes:** if the user activates ECC mid-set, prior reps keep their original (non-ECC) rendering; new reps render with the new band. Don't retroactively restyle.

---

## 7. References
- Tonal real-time in-workout data [tonal](https://tonal.com/blogs/all/more-real-time-data-in-workouts)
- Tonal Eccentric Mode (20–50% eccentric load) [tonal](https://tonal.com/blogs/all/eccentric-mode-improves-performance)
- Tonal power output visualization with 80% dashed reference line [youtube](https://www.youtube.com/watch?v=uuzgZc361co)
- Tonal rep tracking [youtube](https://www.youtube.com/shorts/5YNP-cjHY5A)
- Tonal Strength Score (effort-weighted) [tonal](https://tonal.com/blogs/all/level-up-with-tonals-enhanced-strength-score)
- Tonal dynamic weight modes overview [tonal](https://tonal.com/blogs/all/transform-your-strength-training-routine-with-dynamic-weight-modes)
- Force-time curve phase definitions (sport-science) [scienceforsport](https://www.scienceforsport.com/force-velocity-curve/)
- Force-velocity curve (concentric vs. eccentric force capacity) [brookbushinstitute](https://brookbushinstitute.com/glossary/force-velocity-curve)
- Eccentric impulse as performance metric [whistleperformance](https://www.whistleperformance.ai/post/eccentric-and-concentric-impulse-key-metrics-in-sport-performance)

---

## 8. b58 → b59 delta (what's missing as of v0.4.36-build58)

b58 ForceChartV2 landed only the 3b dual-band fill + 3c inline labels (current rep only) + 3d direction mirror via gradient corner-flip. **Still TODO for b59:**

- 3a: explicit per-V3-spec auto-scale (peak × 1.2, 20% floor, 1–2 s eased rescale) — verify it matches.
- 3b: 200 ms blended phase transition (current is hard-cut at phase boundary).
- 3c: label fade timing (3 s **or** rep-2-whichever-first, mid-set mode-change re-surface). b58 only suppresses for `repsAgo > 0`.
- 3d: vertical gradient *within* the fill encoding ROM-position (not just outer corner direction).
- 3e: **NOT IMPLEMENTED** — 80% dashed line, per-rep peak dots + labels, target line hook.
- 3f: **NOT IMPLEMENTED** — rep stacking with log opacity decay, cap ~8.
- 3g: **NOT IMPLEMENTED** — compact legend top-left.
- 4: layering verified — grid → 80% line (todo) → history (todo) → current fill → polyline → peak dots (todo) → labels.
- 6: low-weight Y floor (`max(peak × 1.2, 15 lb)`) — confirm V3 auto-scale already does this.
- 6: mid-set mode-change rule — historical reps keep prior rendering; new rule for `ForceChartV2` data model.

## 9. Handoff Checklist

In the same commit:
1. Save this doc to `docs/handoff/design/force_curve.md`. ✅ (b59-prep)
2. Append decision to `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md`:
   - Force curve uses dual-band fill under single polyline (not two lines).
   - Phase encoding via fill color + vertical gradient direction; chain is mirrored-gradient eccentric.
   - 80%-peak dotted reference line borrowed from Tonal's power visualization.
   - Rep stacking with logarithmic fade, cap ~8.
   - Power / eccentric impulse deferred to intensity-metric research doc.
3. Append `docs/WORK_LOG.md` entry (b59 when shipped).
4. Link this doc from `docs/handoff/03_CURRENT_FEATURE_SPEC.md` under the Force Curve P0 section.
5. Update `docs/handoff/09_NEXT_AGENT_PROMPT.md` to cite this design doc as the implementation source of truth for the force curve.

---

## 10. b67 implementation status (Apr 29 2026) — SUPERSEDED 2026-04-30

> **⚠️ This entire section is SUPERSEDED by ADR V4-D20 (b71,
> 2026-04-30).** The b67-10 parametric-sine implementation
> documented here landed in `ForceChartV2.swift` and was reverted
> in b71. V1's `ForceChartView` (raw-sample phase-colored polyline)
> is now the canonical force-curve renderer for both V1 and V2;
> `ForceChartV2.swift` is retained on disk for rollback only and
> is no longer mounted anywhere. Read this section as historical
> context for what was tried and intentionally walked back, not as
> current implementation. The ground truth is in
> `03_CURRENT_FEATURE_SPEC.md` §5 and ADR V4-D20 in
> `04_DECISIONS_AND_CONSTRAINTS.md`.

Bug 10 (B67_BUG_QUEUE.md) closed by commit `660853a` on
`feat/ui-v4-2-claude`. Implementation per ADR V4-D13 in
`04_DECISIONS_AND_CONSTRAINTS.md` (now superseded by V4-D20):

- §3a **Auto-scaled Y-axis** — preserved from b58 (parent-supplied
  `yAxisMaxLb`, 1.5 s ease).
- §3b **Dual-band fill** — preserved + rewired. `eccConFill` now
  follows the parametric sine path so stroke + fill cannot drift.
  CHAIN gradient mirror preserved.
- §3c **Inline CON/ECC labels** — preserved. Most-recent rep only.
- §3d **Chain mirrored gradient** — preserved (gradient stops
  reversed for ECC band when `chainMirrorActive`).
- §3e **80% reference line + peak dots + target line** — NOT
  implemented in b67. Geometry now exposes per-lobe peak via
  `RepSineGeometry.conPeak / .eccPeak`, so this is a small
  follow-up.
- §3f **Rep stacking with log opacity decay, cap 8** — preserved
  from b58. `fadeOpacity(repsAgo:)` formula =
  `max(0.10, 1 / (1 + ln(repsAgo + 1)))`.
- §3g **Compact legend top-left** — NOT implemented in b67.
- §6 **Mid-set mode change** — historical reps continue to use
  their original geometry (peakLb is computed per-rep from that
  rep's samples, so a mode flip mid-set doesn't restyle prior
  reps).

### What changed in b67 vs b58

`repPolyline` no longer traces raw sensor samples. It draws two
half-sine lobes computed from the rep's measured per-phase peak
force, with phase-boundary `splitT` derived from the first
`.return` sample's normalized timestamp. See ADR V4-D13 for
rationale and rejected alternatives (full-period sine,
`|sin(π · t)|`, sample-mean polyline).
