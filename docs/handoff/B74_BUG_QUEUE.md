# B74 Bug Queue — opened May 1 2026 (CDT)

> Post-b73 ship feedback batch. Cycle target: TBD on the next
> feature branch the GPT-5 implementation agent opens against
> `main`. Per `docs/handoff/11_AGENT_ROLES.md`, GPT-5 owns the
> implementation; Claude is release-only and ships once the user
> says "Ship PR #N as build X."
>
> Last shipped at the time this queue opened: v0.4.46 / build 73
> ("Grid scroll fix"), Delivery UUID
> `6b12a064-b20a-4152-82c5-d578edb0c9d9`, run
> [25201372318](https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/runs/25201372318).

## Status table

| ID     | Title                                                                 | Status              | Closing commit |
|--------|-----------------------------------------------------------------------|---------------------|----------------|
| B74-F1 | Auto-connect L/R buttons to Voltras by advertised name                | QUEUED FOR GPT-5    | —              |
| B74-F2 | Surface Merge AND Mirror as two distinct modes after both sides pair  | OPEN                | —              |
| B74-F3 | Merge button performs Mirror behavior (semantics need separation)     | OPEN                | —              |
| B74-F4 | LiveCaptureViewV2 weight label shows "…" when weight exceeds ~100 lb  | OPEN                | —              |
| B74-F5 | Merge-mode minus-weight only decrements one Voltra (left-favored)     | OPEN                | —              |
| B74-F6 | Twin-mode L/R isolate tap does not actually isolate; LOAD fires both  | OPEN                | —              |
| B74-F7 | Misc Merge UI polish (bucket for items found while fixing F3/F5)      | OPEN                | —              |

---

## B74-F1 — Auto-connect L/R buttons to Voltras by advertised name

**Status:** QUEUED FOR GPT-5.

**Reported:** May 1 2026 (post-b74 ship feedback).

**User spec (verbatim from prompt):**

> Auto-connect L/R buttons to Voltras by advertised name (match
> "left" / "right" substrings). No picker menu. Both L and R
> must work independently for single-device pairing.

**What this means.** The two side-of-body pairing buttons (L
and R) should each scan and auto-connect to the first
advertised Voltra whose name contains the case-insensitive
substring `left` (for L) or `right` (for R). No disambiguation
picker should appear. Either button must be usable on its own
for single-device pairing — pressing only L should pair the
left Voltra and leave R unpaired, and vice versa.

**Why F1 is QUEUED FOR GPT-5 ahead of the rest.** F1 is a
pre-requisite for reproducing F2/F3/F5/F6 reliably — those bugs
all depend on having both sides paired in a known L/R
orientation. Until F1 lands, twin-mode regressions are awkward
to reproduce.

---

## B74-F2 — Surface Merge AND Mirror as two distinct modes after both sides pair

**Status:** OPEN.

**User spec (verbatim):**

> After both sides pair, surface Merge AND Mirror as two distinct
> modes. Currently only Merge shows.

**What this means.** Once both L and R are paired, the
twin-mode UI should expose two selectable modes: Merge and
Mirror. Today only Merge appears. Mirror needs to be a
first-class peer mode in the UI affordance, not a sub-state of
Merge.

---

## B74-F3 — Merge button performs Mirror behavior (semantics need separation)

**Status:** OPEN.

**User spec (verbatim):**

> Merge button performs Mirror behavior. Merge/Mirror semantics
> need to be defined and separated.

**What this means.** The current "Merge" button is wired to
what is functionally Mirror behavior. The two modes need clear,
documented semantics and the wiring must match the labels. Spec
for Merge vs. Mirror is part of this bug — GPT-5 should propose
the semantic split (e.g. Merge = sum forces, Mirror = duplicate
plan to both sides) and confirm with the user before
implementing.

---

## B74-F4 — LiveCaptureViewV2 weight label shows "…" when weight exceeds ~100 lb

**Status:** OPEN.

**User spec (verbatim):**

> LiveCaptureViewV2 weight label shows "…" when weight exceeds
> ~100 lb, especially in twin mode where the layout shifts.
> Likely a fixed-width text field or clipping frame.

**What this means.** Three-digit weight values truncate to an
ellipsis in the V2 weight tile, especially under twin-mode
layout. Suspected cause is a fixed-width frame or a
non-scaling `.lineLimit(1)` text field in
`LiveCaptureViewV2`. Prior fix for the analogous V1 issue was
KI-F4 (b58, V4-D9): `.minimumScaleFactor(0.6)`,
`.lineLimit(1)`, trailing-edge linear-gradient mask, and
`Spacer(minLength: 4)` between the number and the steppers.
That pattern likely needs to be ported to V2.

**Verification rule reminder.** Per the new agent-roles
verification rule, this is a UI layout bug — the close-out PR
must include real SwiftUI screenshots showing the V2 weight
label rendering correctly at 100, 150, 200, and 300 lb in both
single-device and twin-mode layouts. Synthetic math validators
are not sufficient.

---

## B74-F5 — Merge-mode minus-weight only decrements one Voltra (left-favored)

**Status:** OPEN.

**User spec (verbatim):**

> In Merge mode, minus-weight decrements only one Voltra
> (left-favored). Output is neither mirror nor symmetric split.

**What this means.** Tapping the minus stepper in Merge mode
sends the decrement to the left Voltra only. The expected
behavior depends on the F2/F3 Merge-vs-Mirror semantic split —
if Merge = symmetric sum, the decrement should split across
both devices (or apply to whichever side currently holds the
load); if Merge = duplicate plan, both sides should decrement
in lock-step. Resolution is blocked on F3's semantic
definition.

---

## B74-F6 — Twin-mode L/R isolate tap does not actually isolate; LOAD fires both

**Status:** OPEN.

**User spec (verbatim):**

> In twin mode, tapping L or R in Live View to isolate does not
> actually isolate. LOAD still fires both Voltras.

**What this means.** Tapping the L or R unit pill in Live View
under twin mode should restrict subsequent LOAD/UNLOAD writes
to only the tapped side. Currently the isolate-tap is observed
in the UI (pill highlight) but `pushUpcomingStateToDevice` /
LOAD payload still goes to both devices. Suspected
location: the twin-mode write path in `VoltraWriter` does not
read the isolated-side state, or the isolated-side state is
stored on the wrong observable.

---

## B74-F7 — Misc Merge UI polish

**Status:** OPEN.

**What this means.** Catch-all bucket for paper cuts the
implementation agent finds while fixing F3 and F5 — label
copy, button placement, mode-switch animation, edge-case
empty states, etc. Items added here should each get a
sub-bullet (F7-a, F7-b, …) when discovered, with a one-line
description and a closing commit.

- (none yet — populate as discovered.)

---

## Held questions

None at queue-open time. The implementation agent should ask
clarifying questions (especially the Merge-vs-Mirror semantic
split for F3) before coding, per the standard handoff sequence
in `docs/handoff/11_AGENT_ROLES.md`.

## Cross-references

- `docs/handoff/11_AGENT_ROLES.md` — split-role process
  governing this cycle.
- `docs/handoff/06_KNOWN_ISSUES.md` — KI-F4 (b58, V4-D9) is the
  prior weight-label scaling fix relevant to F4.
- `docs/handoff/04_DECISIONS_AND_CONSTRAINTS.md` — V4-D9 records
  the V1 weight-card scaling pattern.
