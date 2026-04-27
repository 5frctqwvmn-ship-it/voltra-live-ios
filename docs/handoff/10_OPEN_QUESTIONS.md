# 10 — Open Questions

Things blocked on the user. Resolve before the dependent task can ship.

> When you answer one of these, **delete it from this file in the same
> commit** as the code change that uses the answer. Don't let stale
> questions accumulate.

## Build 30

### Old-store import

Status: **needs user answer before any importer code is written.**

Build 29 abandoned the old SwiftData store at the legacy URL. The user's
prior session logs are still on disk but not visible in the app. Do they
want them imported, or is the fresh start fine?

If yes: write a one-shot importer that opens the legacy store with a
separate `ModelContainer`, reads all sets, writes them into the v2 store,
then sets a "imported" flag so it doesn't run again.

## Build 31 (Superset)

(Defer until build 30 ships.) See `08_SUPERSET.md` "Open questions for
build 31" — copy them here when build 31 begins.

## Process

### "Should we auto-update CloudKit re-enablement?"

Not a user question — a self-imposed gate. Don't re-enable CloudKit until
the v2 store has been stable across at least 2 releases past build 29.
Track the count: `0 / 2` after build 30 ships, `1 / 2` after build 31, etc.

(Move this to a tracker once we have 2+ open process gates.)
