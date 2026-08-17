# BestToDo Tasks — Obsidian plugin

Tiers 2 and 3 of the BestToDo ↔ Obsidian integration (see
`.claude/notes/obsidian-integration.md` in the repo root). It renders the
`besttodo_tasks.json` file that the app's synced mode (SPEC §4.7) writes into
a user-chosen folder every time the app is backgrounded, and lets a checkbox
tap flow back to the phone.

## What it shows

- The six home buckets, exactly like the app's tabs: Today (overdue
  included), Tomorrow, Day After Tomorrow, Next Week, Next Month, Future.
- Per task: a checkbox, title, `📅` due date (the 2300-01-01 "parked"
  sentinel is never shown), `✅` completion date, `🔁` for recurring tasks, a
  label chip, and a generic `📁 project` chip when the task belongs to a
  project (the sync file carries tasks only, so project names are not
  available).
- Open tasks before done ones, ordered by the app's list ranking.
- An "as of …" line with the sync timestamp and app version — freshness
  depends on the phone having been backgrounded, so the user should see it.

The view re-reads the file on Obsidian's file-change event. The app writes
the file atomically (tmp + rename), so a read can never see a half-written
snapshot.

## Checking a task off (Tier 3)

Tapping the checkbox does **not** edit `besttodo_tasks.json` — the app
overwrites it on every sync, so a direct edit would just be clobbered.
Instead the tap appends a `complete`/`reopen` operation to
`besttodo_changes.json`, written next to the sync file. The view updates
immediately (optimistic) and shows a "syncing…" chip on that task until the
phone app has actually picked the change up — which only happens the next
time it's **resumed** (opened or brought to the foreground), the same way
the phone → Obsidian direction only happens when the app is backgrounded.
The app then applies the op, truncates the journal, and re-syncs, which
clears the chip on the next file-change refresh.

Conflicts (the same task changed on both sides while offline) resolve
last-writer-wins per field, using timestamps already on the task — see
`.claude/notes/obsidian-integration.md` and
`lib/services/sync_import_service.dart` for the exact rules.

## Setup

1. In BestToDo: Settings → Sync & export → enable **Synced mode** and pick a
   folder that lives inside (or is synced into, e.g. via Syncthing/Dropbox)
   your Obsidian vault.
2. Install this plugin (copy `manifest.json`, `main.js` and `styles.css`
   into `<vault>/.obsidian/plugins/besttodo-tasks/` and enable it).
3. If the JSON file is not at the vault root, set its vault-relative path in
   the plugin settings — the change journal is written next to it, so this
   one setting covers both tiers.
4. Open the view via the ribbon icon or the "BestToDo Tasks: Open task view"
   command.

An unknown `sync_version` in the file is refused with a friendly message
instead of rendering garbage — update the plugin or the app when that
happens.

## Development

Not part of the Flutter build; this folder is its own npm package.

```bash
npm ci          # install dependencies
npm test        # jest tests for the parsing/bucketing/journal contract
npm run build   # bundle src/ into main.js (esbuild)
npm run dev     # rebuild on change
```

`src/model.ts` is the data contract and must mirror the Dart side:
- envelope + task parsing, bucketing, sorting → `Task.fromJson`
  (`lib/models/task.dart`), `ItemViews.inHomeBucket`
  (`lib/services/item_views.dart`), `sortTasks` (`lib/utils/task_utils.dart`).
- the change journal (`ChangeOp`/`ChangeJournal`, `parseJournal`,
  `makeToggleOp`) → the op vocabulary and conflict rules in
  `lib/services/sync_import_service.dart`. This side only ever *writes*
  `complete`/`reopen`; `edit`/`create`/`delete` are parsed-through for a
  future richer write surface.

The jest tests in `test/model.test.ts` mirror `test/sync/sync_markdown_test
.dart` and `test/sync/sync_import_service_test.dart` so both sides of the
contract are pinned.
