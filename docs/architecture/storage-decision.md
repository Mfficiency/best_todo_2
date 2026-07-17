# ADR: Item storage stays on JSON files (for now)

**Status:** accepted · 0.1.109 (migration step 7)
**Context:** end of the item-model migration (steps 1–6: event journal, history
seeding, structured labels, schedule interval + schemaVersion, item-linked
reminders, views-as-queries). The obvious next step from the
[future-proof model](item-model-future.html) would be moving the store to
SQLite. This record explains why that step is deliberately deferred, and what
would change the decision.

## Decision

Keep the item store on JSON files (`tasks.json` + append-only
`item_events.jsonl` + companions), behind the new `ItemRepository` facade
(`lib/services/item_repository.dart`). SQLite is not adopted at this time.

## Why: priority #1 is startup speed

The app's startup path (`main()` → first frame, measured by
`StartupTimeService` and watched on the Startup Times page) currently performs,
before the first frame: `Config.load` (one small JSON read), notification
init, alarm load (one small JSON read). The task list itself loads *after* the
first frame in `HomePage.initState`. Every migration step was designed to add
**zero** work to this path:

| Component | Startup cost |
|---|---|
| Item-event journal | none — write-chained after saves, read on demand |
| History seeding | none — one flag-file stat, 3 s after first frame, once ever |
| Label registry | none — background registration, no-op in steady state |
| Schedule interval | none — upgrade happens inside the existing parse |
| Reminder sync | none — in-memory check after saves |
| Views layer | none — pure functions |
| Repository facade | none — thin delegation |

Adopting SQLite would add plugin initialization and a database open (plus,
first launch after the update, a full data migration) **on or near the
critical path**, to solve problems this app does not yet have:

- **Data volume:** the store is a few hundred KB at the observed usage scale;
  full-file JSON reads at this size are well under a millisecond of parse
  time on target hardware, and the journal self-compacts (~1 MB cap).
- **Query complexity:** every view is a linear filter over an in-memory list
  (`ItemViews`); there is no query SQLite would accelerate at this scale.
- **Transactions:** the multi-file consistency gap is real but bounded — each
  file is written atomically (`flush: true`) and every derived store
  (journal, labels, stats) tolerates being behind by one save; the journal
  even reconstructs (`seeded`) history.
- **Platform reach:** the JSON+swallowed-errors pattern is what keeps web and
  widget tests working with no documents directory. A database adds a
  platform matrix to maintain.

## The seam

`ItemRepository` is the single interface the UI uses for the item store
(active list, deleted list, daily stats, per-item history). Backup/export
tooling intentionally keeps talking to `StorageService` — it deals in files
regardless of backend. A future SQLite (or synced) backend is implemented by
swapping the internals of this one class.

## Revisit when any of these become true

1. **Sync ships.** The journal is already an op log; a synced backend wants a
   database and per-field merge. This is the strongest trigger.
2. **Scale.** Item count regularly above ~5,000 or `tasks.json` above ~2 MB —
   full-file rewrites on every save stop being free.
3. **Measured regression.** The Startup Times page shows the task load
   contributing meaningfully to time-to-usable (it currently does not — it
   happens after first frame).
4. **Cross-entity invariants** stop being tolerable as eventual (e.g. hard
   foreign-key needs between reminders and items).

Until then: fewer moving parts, faster cold start, and the same repository
seam either way.
