# ADR: Presentation filters as an explicit layer; countdown becomes an item-linked capability

**Status:** accepted · 0.2.5 (unified-item-model migration, step 9)
**Context:** the [current-state map](item-model-current.html) and the
[future-proof proposal](item-model-future.html) describe the migration this
app has been running incrementally since 0.1.106 (event journal, history
seeding, structured labels, schedule interval + schemaVersion, item-linked
reminders, views-as-queries, repository seam, upgrade safety — see
`storage-decision.md`, which also deferred the SQLite move). This record
covers the next step: making *presentation* — how a view displays and edits
the items its filter already selected — as explicit as *data filtering*
already is, and closing the biggest remaining "separate world" called out on
the current-state map: countdown timers.

## What was already true (verified against the code, not just the docs)

- **Data filters are already a real, explicit layer.** `ViewFilterRules`
  (`lib/models/view_filter_rules.dart`) is a first-class, user-configurable
  include/exclude-tag model keyed by view id (home, wishlist, approval,
  projects, foodDiary, alarms, countdown, archived, bin); `ItemViews`
  (`lib/services/item_views.dart`) is the shared, pure query layer every page
  reads through. This is the "data filters: which items belong in a view"
  half of the redesign, and it was already done.
- **Presentation was not.** Every view that renders a tile — Home
  (`TaskTile`), Wishlist, Alarms, Countdown, Food Diary, Waiting for
  Approval, Projects, Archived Items, Deleted bin — hand-rolls its own
  layout with zero shared config. `TaskTile` is reused only by Home; every
  other Task-shaped view (Wishlist, Food Diary, Waiting for Approval,
  Projects' "All Tasks" pane) is a separate, bespoke widget. There was no
  "presentation filter" concept anywhere to mirror `ViewFilterRules`.
- **`Alarm` and `CountdownTimerItem` are, correctly, separate models** — not
  `Task` with a flag. An alarm's fields (time-of-day, melody, snooze) and a
  countdown's (target, milestones) have no analog on a plain task, so forcing
  them onto a `Task`-shaped tile would be the wrong move, not a unification.
  What *should* be unified at the data level — and, for `Alarm`, already was
  — is the relationship: an alarm/countdown can be an independent thing, or
  it can be a capability *attached to* an item.
- **Reminders already prove the pattern.** `Alarm.itemUid` (0.1.110) plus
  `ReminderSyncService` make a reminder either standalone or item-linked,
  with the linked one following the item's schedule automatically. Countdown
  timers had no such link — every countdown on the current-state map is
  "standalone — no link to items at all."

## Decision

1. **`ViewPresentation`** (`lib/models/view_presentation.dart`) is the
   presentation counterpart to `ViewFilterRules`: a small, explicit,
   per-view config, looked up by the same view ids
   (`ViewPresentation.forView(viewId)`), defaulting to today's actual
   behavior so adopting it anywhere is additive. `TaskDetailPage` — the one
   page already shared across Projects, Archived Items and the Deleted bin —
   is its first real consumer: `viewId` controls whether the item-linked
   capability sections (reminder, countdown) render. Archived/deleted items
   hide both (their reminders are already gone via `ReminderSyncService`;
   offering to attach a *new* one to something over is never useful).
2. **`CountdownTimerItem.itemUid`** (mirroring `Alarm.itemUid` exactly) plus
   **`CountdownSyncService`** make a countdown timer attachable to an item.
   Unlike reminders, this is resolved *lazily* — on Countdown page load,
   not eagerly on every task save — because countdown milestones are a
   foreground-only feature (checked by `CountdownTimerPage`'s own ticker;
   there is no background delivery path to keep correct between app opens,
   unlike the alarm ladder). A timer whose item disappears is **unlinked**,
   not deleted — a countdown still means something once detached, unlike a
   reminder with nothing left to remind about. `TaskDetailPage` gained a
   `TaskCountdownSection` mirroring the existing `TaskReminderSection`
   one-tap "remind me" affordance.

## Why not go further this round

Forcing every bespoke tile (Wishlist, Alarms, Countdown, Food Diary, Waiting
for Approval, Projects, Archived, Bin) onto one shared, `ViewPresentation`-
driven widget was considered and rejected for this step: `TaskTile` alone is
1000+ lines with an extensive test suite, most of its few conditionals
(`showSwipeButton`, `swipeLeftDelete`) turned out to be platform/settings
concerns rather than per-view presentation, and each bespoke tile exists for
real per-view reasons already, not because the concept was missing. Adding
the model and proving it with one real, low-risk consumer — the same
incremental strategy every prior migration step in this file's history
used — was judged the higher-value, lower-risk move over a sweeping rewrite
of already-working, already-tested UI.

## Revisit when any of these become true

1. **A third `ViewPresentation` consumer is needed** for something beyond
   section visibility (e.g. field emphasis/ordering) — extend the model
   then, rather than speculatively adding fields no page reads yet.
2. **A tile is added or rewritten anyway** for unrelated reasons — that's
   the moment to have it read `ViewPresentation` from the start instead of
   hardcoding its layout, the same way new code should use `ItemViews`
   instead of hand-rolled `where()` chains.
3. **Countdown notifications go background** (a ladder like alarms') —
   `CountdownSyncService.resolveAgainstTasks` would need an eager
   sync-on-save hook like `ReminderSyncService`, not just a page-load
   resolve.

Until then: one small, real, tested model plus one real consumer, not a
parallel system nobody reads yet.
