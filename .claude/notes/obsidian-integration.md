# Obsidian integration — roadmap for Tiers 2 and 3

Status of the three-tier plan for reaching the task list from Obsidian on a
computer. Tier 1 shipped in **0.1.135**; this note is the design record for the
two unbuilt tiers so a future session can implement either without re-deriving
the analysis.

| Tier | What | Status |
|---|---|---|
| 1 | Markdown checklist written by synced mode (`besttodo_tasks.md`) | **Shipped 0.1.135** — `lib/services/sync_markdown.dart`, SPEC §4.7 |
| 2 | Read-only Obsidian plugin rendering the synced JSON | Not started |
| 3 | Two-way: edits made in Obsidian flow back to the phone | Not started |

**The transport is settled and shared by all tiers:** the app's synced mode
(SPEC §4.7) atomically writes `besttodo_tasks.json` + `besttodo_tasks.md` into
a user-chosen folder every time the app is backgrounded. The user routes that
folder into an Obsidian vault (folder inside the vault synced by
Syncthing/Dropbox/Drive, or Obsidian mobile's own vault on the phone). No tier
adds networking to the app.

## Tier 2 — read-only Obsidian plugin

**Goal:** a proper task view inside Obsidian (tabs, labels, projects) instead
of the flat Tier 1 checklist. Strictly a *viewer*: it never writes.

**Shape:** a standard Obsidian community plugin — TypeScript + esbuild,
`manifest.json` + `main.js`. Keep it in a new top-level `obsidian-plugin/`
folder (own `package.json`, own CI job; it is not part of the Flutter build)
or a separate repo if the marketplace release process makes that easier.

**What it does:**

1. Setting: vault-relative path to `besttodo_tasks.json` (default: vault root).
2. Read the file via the vault adapter API; re-read on Obsidian's file-change
   event (the atomic tmp+rename write on the app side guarantees the file is
   never half-written, so a plain read-on-change is safe).
3. Render a custom `ItemView` (right sidebar or tab): the six home buckets,
   checkbox + title + due date, label/project chips, open-first ordering.

**Data contract (the part that must not drift):**

- Envelope: `{sync_version: 1, synced_at, app_version, task_count, tasks[]}`.
  Refuse (with a friendly notice) on an unknown `sync_version`.
- Tasks are `Task.toJson()` — schema v2 (see `lib/models/task.dart`): `uid`,
  `title`, `isDone`, `startAt`/`endAt` (plus legacy `dueDate` mirror),
  `completedAt`, `deletedAt`, `label`, `projectId`, `listRanking`,
  `hasExplicitTime`, recurrence fields. Parse tolerantly — missing keys get
  defaults, exactly like `Task.fromJson`.
- Bucketing must mirror `ItemViews.inHomeBucket` exactly: date-only diff from
  today; `<= 0` Today (overdue included), `1` Tomorrow, `2` Day After, `3–29`
  Next Week, `>= 30` Next Month, no date or the sentinel date **2300-01-01** →
  Future. Exclude `deletedAt != null`. Sort open before done, then by
  `listRanking` (nulls last) — `sortTasks` in `lib/utils/task_utils.dart`.
- Show `synced_at` ("as of …") in the view: freshness depends on the phone
  having been backgrounded, and the user should see that.

**Testing:** the bucketing/parsing logic goes in a pure module with jest tests
mirroring `test/sync/sync_markdown_test.dart`'s cases, so both sides of the
contract are pinned by tests.

**Effort:** a weekend-sized project. No Dart code is reusable, and none is
needed — the JSON contract is the whole interface.

## Tier 3 — two-way sync (Obsidian edits flow back)

**Goal:** checking off / adding / rescheduling a task in Obsidian shows up on
the phone. This is a real feature with real conflict cases — do not start it
as a side quest.

**Core design decision (made): a change journal, not file editing.** The
Obsidian side must never write into `besttodo_tasks.json`/`.md` — the app
overwrites both on every sync, so direct edits are guaranteed to be clobbered.
Instead the plugin (Tier 2 grown up, or a Tier 1-level markdown-diff watcher)
appends operations to a separate file the app never overwrites:

```
besttodo_changes.json
{ "journal_version": 1,
  "device": "<obsidian-device-id>",
  "ops": [ { "op": "complete" | "reopen" | "edit" | "create" | "delete",
             "uid": "...",            // omitted for create
             "at": "<ISO timestamp>",
             "fields": { ... } } ] }
```

**App side (the bulk of the work):**

1. On lifecycle **resume** (mirror of the quit-sync trigger in
   `SyncService.onLifecycleChanged`), read `besttodo_changes.json` from the
   sync folder, apply ops by `uid`, then delete/truncate the journal and
   immediately re-run a sync so both sides converge. Same fail-soft rules as
   sync: every failure is a red history entry, never an exception; overlap
   guard; nothing at startup.
2. Conflict rule: **last-writer-wins per field group** using the timestamps
   already on `Task` (`completedAt`, `movedAt`, `rescheduledAt`, `deletedAt`).
   An op older than the task's own newer change loses, silently. Deletions are
   tombstones (`deletedAt`), which the model already has — never hard-delete
   from an op.
3. `uid` is the anchor of the whole design; it is already stable (uuid v4,
   survives every save). Creates from Obsidian bring their own uid.
4. The app already has `ItemEventJournal` (`lib/services/item_event_journal.dart`)
   for recording item events — evaluate reusing its event vocabulary for the
   op format instead of inventing a second one.
5. Bump the sync envelope's `sync_version` if the contract changes; keep the
   journal's own `journal_version` independent.

**Failure modes to design for (test list, roughly):** journal present but
malformed (skip + red entry, do not delete it); op for an unknown uid (ignore);
op replayed twice (idempotent — applying `complete` to a done task is a no-op);
both sides edited the same task while offline (LWW per timestamps); journal
written while the app is mid-sync (overlap guard, picked up on next resume).

**Obsidian plugin side:** the Tier 2 view becomes interactive — checkbox click
appends a `complete` op and optimistically updates the view; a small "pending
changes" badge until the next refreshed JSON confirms the round trip.

**Prerequisite order:** Tier 2 first. It pins the read contract with tests and
provides the UI surface; Tier 3 is then journal-writing on the plugin side +
the resume-import path on the app side. Do not attempt markdown-checkbox
diffing as the write channel — it cannot represent creates/edits/reschedules
and breaks on every title change.

**Effort:** the app-side import path with its conflict/test matrix is the big
piece — comparable to the original synced-mode feature (0.1.131), not to
Tier 1.
