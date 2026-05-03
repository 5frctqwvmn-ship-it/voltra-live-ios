# tasks/todo.md — active task plan

> Plan-first working file for the **current** task only.
> Required by `docs/handoff/AGENT_WORKFLOW.md` Task Management
> #1 / #3 / #5.
>
> **Lifecycle per task:**
>
> 1. Agent writes the plan here as a markdown checklist BEFORE
>    writing any code (Plan Node Default, AGENT_WORKFLOW.md §1).
> 2. Agent checks in with the user, gets plan approval (Task
>    Management #2 "Verify Plan").
> 3. Agent ticks items as it works (`- [x]`).
> 4. When the task is done, agent appends a `## Review` section
>    summarizing what shipped, what was deferred, and any
>    surprises (Task Management #5).
> 5. The next task **replaces** the active plan (move the old
>    plan + review into `docs/handoff/CONVERSATION_LOG.md` so
>    history isn't lost, then start fresh here).
>
> Empty `## Active task` block below means no task is in flight.

---

## Active task

KI-20 visual bridge fix — `fix: apply device-originated base weight in live capture`

## Plan

- [x] Read AGENTS.md + AGENT_WORKFLOW.md + handoff docs
- [x] Read DeviceState.swift, VoltraBLEManager.swift, LiveCaptureViewV2.swift
- [x] Add `@Published deviceOriginatedBaseWeightUpdate` to VoltraBLEManager
- [x] Set bridge in handleNotification for `.deviceUnsolicited` only
- [x] Replace old `focusedConfirmedBaseWeightValue` onChange with `focusedDeviceOriginatedBaseWeightUpdateValue` onChange
- [x] Add `.onAppear` reconciliation call inside existing onAppear
- [x] Add `ui.deviceBaseWeightApplied` recorder event in applyDeviceOriginatedBase
- [x] Update 03_CURRENT_FEATURE_SPEC.md, 04_ARCHITECTURE.md, 06_KNOWN_ISSUES.md, QA_LOG.md
- [x] Append WORK_LOG.md entry
- [x] Update tasks/lessons.md
- [x] Commit locally (no push, no TestFlight)

## Review

Committed locally as `fix: apply device-originated base weight in live capture`.
Files changed: `VoltraBLEManager.swift`, `LiveCaptureViewV2.swift`,
`docs/handoff/03_CURRENT_FEATURE_SPEC.md`, `docs/handoff/04_ARCHITECTURE.md`,
`docs/handoff/06_KNOWN_ISSUES.md`, `docs/handoff/QA_LOG.md`,
`docs/handoff/CONVERSATION_LOG.md`, `docs/WORK_LOG.md`,
`tasks/todo.md`, `tasks/lessons.md`.

KI-20 status: fix implemented + event-based patch applied — pending hardware retest.
Next: push, ship to TestFlight, run A1 test (20→15 lb), confirm tile updates.
