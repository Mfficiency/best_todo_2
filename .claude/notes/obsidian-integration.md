# Obsidian integration — roadmap for Tiers 2 and 3

Status of the three-tier plan for reaching the task list from Obsidian on a
computer. All three tiers have shipped; this note is kept as the design
record for the conflict rules and failure modes so a future session touching
this area doesn't have to re-derive them from the code.

| Tier | What | Status |
|---|---|---|
| 1 | Markdown checklist written by synced mode (`besttodo_tasks.md`) | **Shipped 0.1.135** — `lib/services/sync_markdown.dart`, SPEC §4.7 |
| 2 | Read-only Obsidian plugin rendering the synced JSON | **Shipped 0.1.141** — `obsidian-plugin/`, SPEC §4.7 |
| 3 | Two-way: checking a task off in Obsidian flows back to the phone | **Shipped 0.1.235** — `lib/services/sync_import_service.dart`, `obsidian-plugin/`, SPEC §4.7 |

**The transport is settled and shared by all tiers:** the app's synced mode
(SPEC §4.7) atomically writes `besttodo_tasks.json` + `besttodo_tasks.md` into
a user-chosen folder every time the app is backgrounded. The user routes that
folder into an Obsidian vault (folder inside the vault synced by
Syncthing/Dropbox/Drive, or Obsidian mobile's own vault on the phone). No tier
adds networking to the app.

## Tier 2 — read-only Obsidian plugin (shipped 0.1.141)

Implemented as designed below, in the top-level `obsidian-plugin/` folder
(own npm package + `obsidian_plugin.yml` CI job; contract module
`src/model.ts`, jest tests in `test/model.test.ts`). The original design
record is kept for context.

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

**Shipped 0.1.235.** Checking a task off (or back on) in the Obsidian view
flows back to the phone on its next resume. The design below was implemented
essentially as planned; this section is now the as-built record.

**Core design decision: a change journal, not file editing.** The Obsidian
side never writes into `besttodo_tasks.json`/`.md` — the app overwrites both
on every sync, so direct edits are guaranteed to be clobbered. Instead the
plugin appends operations to a separate file the app never overwrites,
written next to the sync file (`syncFilePath`'s directory — one setting
covers both tiers):

```
besttodo_changes.json
{ "journal_version": 1,
  "device": "<obsidian-device-id>",
  "ops": [ { "op": "complete" | "reopen" | "edit" | "create" | "delete",
             "uid": "...",            // omitted for create; carried in fields.uid instead
             "at": "<ISO timestamp>",
             "fields": { ... } } ] }
```

The plugin's checkbox only ever emits `complete`/`reopen`
(`makeToggleOp` in `obsidian-plugin/src/model.ts`). `edit`/`create`/`delete`
are part of the shared vocabulary the app-side importer understands and are
covered by its tests, but nothing in this repo writes them yet — they're
where a richer write surface (rename, reschedule, delete from Obsidian) would
plug in without a format change.

**App side — `lib/services/sync_import_service.dart`:**

1. Runs on lifecycle **resume** (`SyncService.onLifecycleChanged`, mirroring
   the quit-time sync trigger): read `besttodo_changes.json` from the sync
   folder, apply ops by `uid`, truncate the journal to an empty envelope
   (never delete the file — that's the well-defined "nothing pending" state
   the plugin's read-modify-write expects), then re-run `SyncService.syncNow`
   so both sides converge. Same fail-soft contract as sync: every failure
   (folder gone, malformed journal, unknown `journal_version`) becomes a red
   entry in the same App Logs "Sync" history (`SyncService.recordEntry`),
   never an exception; overlap-guarded (`_importInFlight`); nothing runs at
   startup, only on an actual resume.
2. Conflict rule, **last-writer-wins per field group**, implemented as:
   - `complete`/`reopen`: idempotent and monotonic against `Task.completedAt`
     — completing an already-done task never regresses it; a `reopen` op
     older than the task's own `completedAt` is dropped silently (local
     completion wins).
   - `edit`'s date fields (`dueDate`/`hasExplicitTime`): LWW against
     `Task.rescheduledAt` (the timestamp the app itself sets on every
     reschedule). Text fields (`title`/`label`/`description`/`note`) have no
     per-field timestamp to arbitrate on, so they apply unconditionally —
     acceptable while the only real writer is the checkbox; would need a
     timestamp if free-text editing from Obsidian is ever added.
   - `delete`: tombstone via `Task.deletedAt`, never a hard delete; idempotent
     if replayed.
   - `create`: idempotent by `uid` — a uid already on the list is a no-op,
     not a duplicate. `fields.uid` is required; missing it skips the op.
3. `uid` is the anchor, as planned (stable uuid v4). `ItemEventJournal` was
   evaluated but not reused — its event vocabulary (diff-based, keyed off
   before/after snapshots) doesn't map cleanly onto discrete ops applied to a
   live list, and the op format here is simple enough not to need it.
4. `sync_version` (the export envelope) is unchanged; `journal_version` is
   the journal's own, independent number, currently `1`.

**Failure modes, as tested (`test/sync/sync_import_service_test.dart`):**
malformed JSON (red entry, journal left untouched); unknown `journal_version`
(same); an op for an unknown uid (ignored); a replayed `complete`/`create`
(idempotent no-op); a stale `reopen`/date-`edit` older than the task's own
timestamp (dropped, LWW); overlapping `importPending()` calls (second is a
no-op); offline mode (nothing runs); the `SyncService.onLifecycleChanged`
resume wiring end to end.

**Obsidian plugin side — `obsidian-plugin/src/view.ts` + `main.ts`:** the
checkbox is live. A tap appends a `complete`/`reopen` op
(`BestToDoPlugin.appendChangeOp`, read-modify-write on the journal so an
op still unconsumed by the app survives alongside the new one), marks the
task pending in `BestToDoView.pending` (`uid → expected isDone`), and
re-renders immediately from the last read file rather than waiting on a
fresh (still-stale) read. The task shows a "syncing…" chip and its checkbox
is disabled until a subsequent file-change event re-reads
`besttodo_tasks.json` and the app's `isDone` agrees with what was expected —
which only happens once the phone app has actually resumed and processed the
journal. A failed write (journal folder gone, vault write denied) reverts the
optimistic state and shows a `Notice`.

**Device id:** `generateDeviceId()` stamps a stable `obsidian-<random>-<ts>`
id into plugin settings on first load (persisted via `saveData`), written
into every journal's `device` field. Not used for anything beyond
identifying the writer in the file today.
