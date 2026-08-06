# BestToDo Tasks — Obsidian plugin

Tier 2 of the BestToDo ↔ Obsidian integration (see
`.claude/notes/obsidian-integration.md` in the repo root): a **strictly
read-only** view of the task list inside Obsidian. It renders the
`besttodo_tasks.json` file that the app's synced mode (SPEC §4.7) writes into
a user-chosen folder every time the app is backgrounded — it never writes
anything back.

## What it shows

- The six home buckets, exactly like the app's tabs: Today (overdue
  included), Tomorrow, Day After Tomorrow, Next Week, Next Month, Future.
- Per task: a (disabled) checkbox, title, `📅` due date (the 2300-01-01
  "parked" sentinel is never shown), `✅` completion date, `🔁` for recurring
  tasks, a label chip, and a generic `📁 project` chip when the task belongs
  to a project (the sync file carries tasks only, so project names are not
  available).
- Open tasks before done ones, ordered by the app's list ranking.
- An "as of …" line with the sync timestamp and app version — freshness
  depends on the phone having been backgrounded, so the user should see it.

The view re-reads the file on Obsidian's file-change event. The app writes
the file atomically (tmp + rename), so a read can never see a half-written
snapshot.

## Setup

1. In BestToDo: Settings → Sync & export → enable **Synced mode** and pick a
   folder that lives inside (or is synced into, e.g. via Syncthing/Dropbox)
   your Obsidian vault.
2. Install this plugin (copy `manifest.json`, `main.js` and `styles.css`
   into `<vault>/.obsidian/plugins/besttodo-tasks/` and enable it).
3. If the JSON file is not at the vault root, set its vault-relative path in
   the plugin settings.
4. Open the view via the ribbon icon or the "BestToDo Tasks: Open task view"
   command.

An unknown `sync_version` in the file is refused with a friendly message
instead of rendering garbage — update the plugin or the app when that
happens.

## Development

Not part of the Flutter build; this folder is its own npm package.

```bash
npm ci          # install dependencies
npm test        # jest tests for the parsing/bucketing contract
npm run build   # bundle src/ into main.js (esbuild)
npm run dev     # rebuild on change
```

`src/model.ts` is the data contract (envelope + task parsing, bucketing,
sorting) and must mirror the Dart side: `Task.fromJson`
(`lib/models/task.dart`), `ItemViews.inHomeBucket`
(`lib/services/item_views.dart`) and `sortTasks`
(`lib/utils/task_utils.dart`). The jest tests in `test/model.test.ts` mirror
`test/sync/sync_markdown_test.dart` so both sides of the contract are pinned.
