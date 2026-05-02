# Context Ledger

Append-only rolling context summaries for Voltra Brain / Claude
sessions. Prevents large one-time transcript backfills. Every 10
turns, or sooner if context health is degrading / dangerous, append a
summary here.

Authoritative sources remain:

- `AGENTS.md`
- `docs/handoff/00_START_HERE.md`
- `docs/handoff/SESSION_RECORDER_SPEC.md`
- `docs/handoff/CONVERSATION_LOG.md`
- `docs/WORK_LOG.md`

## Entry format

```
## YYYY-MM-DD HH:MM UTC — entry N — <one-line headline>

- **Branch / head:** <branch> @ <short SHA>
- **Active goal:** <one line>
- **Decisions since last summary:**
  - <decision>
- **Files changed or planned:**
  - <path> (status)
- **Commands run / awaiting approval:**
  - <command or pending approval>
- **Blockers / risks:**
  - <blocker>
- **Next exact action:**
  - <step>
- **Context health:** good | degrading | dangerously low
```

## Ledger entries

(empty — first entry will be appended at the next 10-turn checkpoint
or context-health trigger)
