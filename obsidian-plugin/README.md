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

## Install — step by step

This plugin is not in Obsidian's community plugin store, so it is installed by
hand: you put three files into a folder inside your vault and switch it on.
That is all an Obsidian plugin ever is. No prior experience needed — follow
the steps in order.

You need: the **Obsidian** app with a vault you already use, and **BestToDo**
on your phone.

### Step 1 — get the three plugin files

You need `manifest.json`, `main.js` and `styles.css`. `main.js` is the built
bundle; it is not stored in this repository, so pick one of the two ways to
get it.

**Option A — download the ready-made build (no tools needed).**

1. Sign in to GitHub (downloading build files requires an account — a free one
   is fine).
2. Open <https://github.com/Mfficiency/best_todo_2/actions/workflows/obsidian_plugin.yml>.
3. Click the topmost run with a green check mark.
4. Scroll to **Artifacts** at the bottom and download
   **besttodo-tasks-plugin**.
5. Unzip it. Inside are exactly the three files you need.

**Option B — build it yourself.**

Install [Node.js](https://nodejs.org) (version 20 or newer, the "LTS"
download), then in a terminal, inside this `obsidian-plugin/` folder:

```bash
npm ci        # download the build tools (once)
npm run build # creates main.js next to manifest.json
```

`manifest.json` and `styles.css` are already in the folder, so after this you
have all three.

### Step 2 — copy them into your vault

Your vault is just a normal folder on disk. In Obsidian: **Settings → About →
Advanced → Override config folder** shows the config folder name (`.obsidian`
unless you changed it), and the vault switcher (the vault icon at the bottom
left → *Manage vaults*) shows the vault's path on disk.

Inside the vault, create this folder structure and copy the three files in:

```
<your vault>/.obsidian/plugins/besttodo-tasks/
    manifest.json
    main.js
    styles.css
```

The folder name `besttodo-tasks` must match exactly — it is the plugin `id`
from `manifest.json`.

Folders starting with a dot are hidden by default:

- **Windows** — in File Explorer: *View → Show → Hidden items*.
- **macOS** — in Finder press `Cmd` + `Shift` + `.` to toggle hidden files.
- **Linux** — in most file managers `Ctrl` + `H`.

### Step 3 — turn the plugin on in Obsidian

1. Obsidian → **Settings** (gear, bottom left) → **Community plugins**.
2. If it says restricted mode is on, click **Turn on community plugins**.
   (That warning is about third-party code in general; this plugin only reads
   one file in your vault and never writes anything.)
3. Next to **Installed plugins**, click the **reload** (circular arrow) icon so
   Obsidian notices the new folder.
4. **BestToDo Tasks** now appears in the list — flip its toggle on.

If it does not appear, the folder is in the wrong place or one of the three
files is missing — recheck the path in step 2.

### Step 4 — make the app write its task file into the vault

In BestToDo on your phone: **Settings → Sync & export → Synced mode**, enable
it, and pick a folder that ends up inside your vault — either a folder in the
vault itself (if the vault is on the phone), or one that is mirrored into the
vault by whatever you already use to sync files (Syncthing, Dropbox, Obsidian
Sync, …).

The app writes `besttodo_tasks.json` there **every time the app goes to the
background**, so open BestToDo once and switch away from it to produce the
first file.

### Step 5 — open the view

Click the ✓ **Open BestToDo tasks** icon in Obsidian's left ribbon, or press
`Ctrl`/`Cmd` + `P` and run **BestToDo Tasks: Open task view**. Your tasks
appear in the right sidebar and refresh by themselves whenever a new file
arrives.

If the file is not at the vault root, tell the plugin where it is:
**Settings → Community plugins → BestToDo Tasks** (gear icon) → **Sync file
path**, e.g. `Sync/besttodo_tasks.json`. The path is relative to the vault
root, with `/` as the separator.

### On phone or tablet

The plugin works in Obsidian mobile too. Copy the same three files into
`<vault>/.obsidian/plugins/besttodo-tasks/` on the device (any file manager
will do) and follow steps 3–5 the same way.

### Updating later

Replace `main.js` (and `manifest.json`/`styles.css` if they changed) with the
newer copies, then restart Obsidian — or toggle the plugin off and on under
Community plugins.

## If something looks wrong

| What you see | What it means |
| --- | --- |
| Plugin missing from the list | Wrong folder, wrong folder name, or `main.js` missing — see step 2. |
| *"…was not found in this vault"* | The app has not written the file into the vault yet (background the app once), or the **Sync file path** setting does not match its actual location. |
| A message about an unknown `sync_version` | The app and the plugin are from different eras. Update whichever is older — the plugin refuses to render a file it does not understand rather than showing you wrong tasks. |
| Tasks look stale | Check the *"as of …"* line at the top: it is the moment the app last wrote the file. Open and background BestToDo to refresh it. |
| Checkboxes do nothing | Intentional — this view is strictly read-only. Tick tasks off in the app. |

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
