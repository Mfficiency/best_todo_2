# Voice inbox — speak it, Claude sorts it, you approve it

**Status: all five phases built on the app side (0.2.123 sorting, 0.2.124
Obsidian pages + research rounds)** — as-built in `SPEC.md` §4.2j. What's left
is outside this repo: the routine, the vault Action step and the app settings,
all in `voice-inbox-routine.md`. One change from §7/§8 below: the routine
answers through Todoist comments (`[Questions]`, `[Done] <link>`) as well as
the `[Obsidian:]` description line, and there is no separate hourly watcher —
the app checks for replies when the Wishlist/Research page opens. Agreed with the owner on
2026-10-27 from a whiteboard sketch plus several rounds of Q&A. Deviations
while building: grocery categories are edited from the Groceries page ("Edit
categories"), not Settings; the Approval page keeps "By conversation" as a
second grouping; food entries say `[Suggest: verify]` (or `new`) to get the
blue dot; markers must be at the top of a description (above the app's
metadata trailer).

Builds on what already exists — read these first:
SPEC §4.2e (Waiting for Approval, quick tags, `[Source: …]` marker,
`pendingSourceTitle`), §4.8 (Todoist sync), §10.6 (Wishlist and its release
groups), §10.6a (Food Diary), §10.6c (Worklist), the Research tool (§4.2e,
"Research tool"), `.claude/notes/pocket-todoist-ingestion.md` (the routine
this replaces) and `.claude/notes/obsidian-integration.md`.

## 1. The flow

```
Pocket ──(vault's own hourly GitHub Action, no AI)──► vault repo: one folder per recording
                                                         │ only when something new arrived
                                                         ▼
                                    Claude Routine (cloud): split + sort + suggest
                                                         │
                                                         ▼
                                    Todoist tasks (with markers) ──► app pull
                                                                       ▼
                                                     Waiting for Approval (grouped by category)
                                                         approve │          │ deny
                                                                 ▼          ▼
                                                           destination   Deleted bin
```

1. **Source: a Pocket recording.** One recording can be long and mention many
   unrelated things; Claude splits it into separate items.
2. **Transcripts already reach the vault without AI.** The owner's Obsidian
   vault is a private git repo with its own hourly GitHub Action that writes
   each Pocket recording into a per-date, per-recording folder (a transcript
   note plus a metadata note with the Pocket id, title and recording time).
   Exact paths live in the vault, not in this public repo. That *is* the
   "keep the transcript in Obsidian" requirement — the routine doesn't fetch
   from Pocket or write transcripts itself.
3. **Claude runs in the cloud** as a Claude Code Routine with the vault repo and
   the Todoist connector. It reads the new transcript folders, splits and sorts
   the items, and creates them in Todoist. It does not run inside the app and
   the app holds no Anthropic key.
4. **Transport back to the phone is Todoist**, exactly as today: the app's
   Todoist pull turns the tasks into items gated by `Waiting_for_approval`.
   Category and suggested destination travel as description marker lines (§4).
5. **Tasks typed straight into Todoist also get sorted** (§11). Until the
   routine has sorted one, it sits in **Other**.
6. Every item names its recording as its source (`[Source: …]`, already shown as
   "From:" today) and links to the transcript note (`[Transcript: …]`).

## 2. Categories (groups)

| Group | Needs approval | Destinations after approval | Where it lives |
|---|---|---|---|
| **Todo** | yes | Today, Tomorrow, Day after, Next week, Next month, Future | Home tabs (plain task) |
| **Migros** | yes | same day buckets | Home tabs with the `mlr` label + Tools ▸ Worklist |
| **Lemmon** | yes | same day buckets | Home tabs with a `lemmon` label + Tools ▸ Lemmon (new) |
| **Backlog** | yes | Active, Next, Someday | Wishlist (+ an Obsidian page per project) |
| **Research** | yes | Active, Next, Someday | Research tool (+ an Obsidian research page) |
| **Groceries** | yes | into the list (no date) | Tools ▸ Groceries (new) |
| **Food diary** | **no** | straight into the diary | Food Diary |
| **Other** | yes | pick the real group → back into approval under it | — |

Migros (= the existing MLR / Worklist tag) and Lemmon are **work contexts**
(each has its own area in the vault).

### State words for Backlog and Research

- **Active** — what I'm working on now / look at when I have time. For
  Research it also starts a Claude research session (§8).
- **Next** — not urgent or relevant now, but will be soon.
- **Someday** — a good idea, not for the near future; the bottom of the pile.
  (Renamed from "archive" on the board — it is *not* the app's Archived Items.)

These match the `Status` values the vault's project notes already use
(Doing / Soon / Someday / Done): Active = `Doing`,
Next = `Soon`, Someday = `Someday`, finished = `Done`. The routine writes the
same word into a page's `Status` frontmatter, so the vault's own Dataview
overviews keep working.

Items in both tools are **grouped by state**. Research items keep their due
date field but it is no longer shown or used for grouping.

## 3. Wishlist sections (proposal)

The Wishlist today has four release groups: Newly implemented, Next release,
Soon, Backlog. Proposal — keep the four groups and their mechanics (Send to
build, Propose for next, the 8 s sweep), just line them up with the new words
and the vault's statuses:

| New section title | Today's group | Vault `Status` | Meaning |
|---|---|---|---|
| **Active** | Next release | `Doing` | Being built now; Send to build lives here |
| **Next** | Soon | `Soon` | Comes after the current release |
| **Someday** | Backlog | `Someday` | Bottom of the pile |
| **Done** | Newly implemented | `Done` | Shipped, kept for reference |

Note the shift from the earlier quick answer ("Next = Next release"): "Next
release" is what's being built *now*, which is what Active means, so it maps to
Active and "Soon" becomes Next. Existing items keep their group (only the
titles change), so nothing moves. Research gets the same four sections, with
Done = research page finished.

## 4. Waiting for Approval changes

The existing page stays the entry point; it changes in these ways:

- **Grouped by category**, in the table's order, instead of by conversation.
  The conversation ("From: …") stays visible on each row's details panel.
- **Claude's suggested destination is pre-selected.** "Call the dentist
  tomorrow" arrives as Todo → Tomorrow; a research topic as Research → Next.
  The row shows it as a small chip (e.g. "→ Tomorrow"), and the swipe
  countdown's default is that suggestion instead of Today.
- **Swipe stays the same gesture, the options depend on the group:**
  - Todo / Migros / Lemmon: today's options unchanged — approve side = the day
    buckets, deny side = Deny + Fri/Sat/Sun/Mon.
  - Backlog / Research: approve side = Active / Next / Someday.
  - Groceries: approve side = "Add to list".
  - Other: swiping opens a **group picker**; picking one moves the item into
    that group, still waiting for approval.
  - Deny everywhere: Deny → the real Deleted bin after the undo window (today's
    behavior, recoverable from Deleted Items until it ages out).
- **Long press + drag moves an item to another group** (fixes a wrong
  category). The item keeps its text; the destination resets to that group's
  default. This replaces long-press-to-multi-select; **multi-select moves to a
  "Select" button in the app bar** (the selection mode itself is unchanged:
  Approve-selected / Deny-selected, tap a group header to select the group).
- Approving into Backlog/Research flips `isWish`/`isResearch` (as the quick-tag
  buttons do today) and sets the state; into Groceries sets the grocery flag
  (§9); into Migros/Lemmon adds the `mlr`/`lemmon` label.

## 5. Routine ↔ app contract (description markers)

Extends the existing `[Source: <title>]` convention (description lines,
case-insensitive, stripped from the visible description on pull). New lines,
each optional, directly after it:

```
[Source: Tuesday walk – bike & groceries]
[Group: todo|migros|lemmon|backlog|research|groceries|food|other]
[Suggest: today|tomorrow|dayafter|nextweek|nextmonth|future|active|next|someday]
[Project: <vault path of the matching project page>]   (backlog only, Claude's best match)
[GroceryCategory: <category>]                          (groceries only)
[Transcript: <vault path of the transcript note>]
```

- No `[Group:]` (a hand-typed Todoist task the routine hasn't sorted yet, or an
  old routine) → **Other**.
- A `[Suggest:]` that doesn't belong to the group is ignored (group default).
- **Re-read while waiting:** unlike `[Source:]` today (first pull only), the
  markers are re-read on every pull *while the item is still waiting for
  approval*, so a hand-typed task the routine sorts later moves out of Other by
  itself. After approval they're never read again.
- Stored locally on the task (like `pendingSourceTitle`: local-only, never
  pushed back, no effect on sync fingerprints).
- **Food diary items skip the gate**: the app turns a `[Group: food]` task into
  a Food Diary entry directly (no `Waiting_for_approval`), timed at the
  recording's time, then closes/deletes it on the Todoist side so it is pulled
  only once (Food Diary entries are otherwise never synced — SPEC §10.6a).

## 6. Home: Todo / MLR / Lemmon toggles

- **Defaults: Todo on, MLR off, Lemmon off** — so out of the box the home list
  looks exactly like today (`mlr` items Worklist-only, as the current standing
  rule says).
- In the drawer, the **Home** row gets a small **arrow** on its right. Tapping
  the row's name still goes home (`_goHome()`, unchanged); tapping the arrow
  folds out three toggle icons — **Todo**, **MLR**, **Lemmon** — each switching
  that group on/off, alone or in any combination ("Todo" = every item with
  neither the `mlr` nor the `lemmon` label). Shown items carry their label chip.
- The toggle state is **remembered** across app restarts.
- The toggles apply **only to the in-app home list** (tabs and schedule view) —
  not the home-screen widget, the Wear sync or the Obsidian sync file.
- Each context keeps its **own list showing only that label**: Tools ▸ Worklist
  (MLR, exists) and Tools ▸ **Lemmon** (new, another
  `HomePage(tagFilter: 'lemmon')` instance like Worklist).
- Structurally this stays inside `ItemViews.isVisibleInMainViews` /
  `isOnHomeScreen` (one gate for tabs and schedule view, as the 0.2.46 fix
  requires); the toggles become a parameter of that gate, not a second filter.
  The CLAUDE.md MLR standing rule gets reworded to "hidden from home by
  default, shown only when the MLR toggle is on".

## 7. Obsidian

The vault is a private git repo (name and paths are kept in the vault itself,
not in this public repo). The routine gets it as a source with push access, clones it, writes,
commits and pushes — the same `git pull --rebase` + push dance the Pocket sync
Action already does, so the two never clobber each other.

**Where things go** (the vault's existing layout; concrete paths are in a note
inside the vault):

| What | Where |
|---|---|
| Transcripts | the vault's Pocket folder — already written by its Pocket sync; the routine only reads them |
| App features | under that app's page in the apps area of the projects folder (a BestToDo tool's feature under that tool's page) |
| Bigger projects | their own folder in the projects folder |
| Smaller / not active | the backlog folder inside the projects folder (a subfolder when a topic grows) |
| Migros / Lemmon notes | their work-context areas (only if an item there needs a page) |
| Research pages | a research folder (Open #1) |

- **Backlog pages are written only after approval.** Generally one page per
  project with a section per item; a big topic can get its own sub-project
  page. Claude matches against the existing folders and pages; no match → a
  new page in the backlog folder using the frontmatter the vault's project
  pages already have (`Status`, `Priority`, `Effort`, …).
- The phone keeps the list (Wishlist); each backlog item gets a link to its
  page/section, where drawings and longer text go. Links are
  `obsidian://open?vault=<vault name>&file=<path>` (vault name: Open #2).
- **How approval reaches the routine:** approving into Backlog fires a Claude
  Routine via the existing `ClaudeRoutineService` ("Send to Claude") with the
  item; that run writes the page and returns the link through Todoist (an
  `[Obsidian: …]` marker on the item), which the app shows as a tappable link.
  The hourly check (§11) catches anything a fire missed (offline, failure).

## 8. Research "Active" (proposal)

A routine run can't sit and wait for you to answer, so the research is done in
**two runs**, with Todoist carrying the questions and answers:

1. **Swipe to Active** → the app fires the research routine right away (the
   hourly check is the fallback). **Run 1** reads the item (and its transcript),
   writes a draft research page (`Status: Doing`), and
   posts its questions (usually 3–6) as **comments on the item's Todoist task**.
2. **In the app**, the research item shows a "3 questions" badge. Tapping it
   opens a small Q&A page: each question with an answer field (with the mic
   button), "Skip" per question, and **Send answers**. Sending posts the answers
   as one Todoist comment and fires the routine again.
3. **Run 2** reads the answers, does the actual research, writes the full page
   into the vault, and puts the link on the item (`[Obsidian: …]`). The item
   shows "Research ready" with the link; it stays Active until you move it.

Why Todoist: the app already syncs with it both ways and the routine already
has it as a connector, so no new channel is needed. Change this requires:
research items are kept out of Todoist sync today — **only Active research
items** get synced (into a dedicated Todoist "Research" project, like the
Wishlist project); Next/Someday ones stay local, as now. The app needs to read
and post comments for those tasks (new in `TodoistSyncService`).

Rejected alternative: questions written into the vault page and read by the app
through the GitHub API — needs a token for a private repo, a second sync path
and markdown parsing in the app; more work for the same result.

## 9. Groceries (new tool, Tools ▸ Groceries)

- A **checklist, auto-grouped by category**: fresh fruit & vegetables, canned,
  pasta & rice, dairy, … Claude sets the category on items it creates.
- **Categories are editable** (Settings ▸ Groceries: add, rename, reorder,
  delete; a deleted category's items move to "Other"). Claude is told the
  current list, so it only uses categories that exist.
- An item typed in by hand gets a category picker, pre-set to the category that
  item had last time (so "milk" always lands in dairy after the first time).
- **No dates.**
- At the top: **Check all** and **Reset list** (unchecks everything).
- A reusable list: checked items stay until reset; adding something already on
  the list unchecks the existing item instead of making a duplicate.
- Model: a flag on the one task list (like `isEatingHabit`/`isResearch`) plus a
  category field, gated out of every main view in `isVisibleInMainViews`.

## 10. Food diary from voice

- Goes straight into the Food Diary, no approval (§5).
- Claude **matches against existing entries** (same meal/ingredient
  combination → same title and tags). When it can't, it creates a new
  combination and the entry gets a **small blue dot** meaning "please verify";
  editing or confirming the entry clears the dot.

## 11. Schedule and token cost

**Rule: an hour with nothing new costs no tokens.** The hourly checking is done
by the vault's GitHub Action (plain Python, no AI); Claude only runs when there
is something to sort.

- After the vault's Pocket sync Action commits new recordings, it calls the sorting
  routine's API trigger (`/fire`, the same mechanism `ClaudeRoutineService`
  uses) with the list of new folders. No new recording → no call → no tokens.
- The same Action also asks Todoist (one API call) whether there are tasks
  waiting for approval with no `[Group:]` marker, and fires the routine only if
  there are (hand-typed tasks get sorted within the hour).
- It also looks for approved backlog items without an `[Obsidian:]` link and
  Active research items whose run never happened — the "watcher" fallback of
  §7/§8 — again firing only when something's found.
- Needs two new secrets on the vault repo: the routine's fire URL + token, and
  a Todoist API token.

For comparison, a Claude run every hour that checks and exits would spend tens
of thousands of tokens per empty run just on its instructions and tool
definitions (×24 a day) — that's why the check lives in the Action.

The current out-of-repo Pocket→Todoist routine (once a day, reads Pocket
directly) is retired once this runs, so items aren't created twice.

## 12. Phases (suggested build order)

1. **Sorting:** routine prompt + vault Action trigger (§11); app: markers,
   approval page grouped by category, per-group swipe options, Other picker,
   long-press drag + Select button, food diary direct import with blue dot.
2. **States and contexts:** Active/Next/Someday/Done sections in Wishlist and
   Research, hidden research due date; Home Todo/MLR/Lemmon toggles + Tools ▸
   Lemmon.
3. **Groceries** tool with editable categories.
4. **Obsidian backlog pages** + links (approve → routine fire → link back).
5. **Research Active**: Todoist sync for Active research items, in-app Q&A,
   two-run research routine.

## 13. Open items

1. **Research folder:** one research folder, or under the item's project when
   it has one?
2. **Vault name:** the name Obsidian shows for the vault (needed for
   `obsidian://open?vault=…` links).
3. **Language:** transcripts mix several languages. Items in the
   language spoken, or always English?
4. **Wishlist sections (§3):** OK to map Active = Next release and Next = Soon?

### Answered

- Home toggles: Todo on / MLR off / Lemmon off, remembered, in-app home list
  only; folded out by an arrow on the Home row (§6).
- Wishlist sections: proposal in §3. Research Q&A: proposal in §8.
- Grocery categories: editable (§9).
- Long press in approval = drag to group; multi-select via a Select button (§4).
- Vault: its private repo, layout in the vault (§7). Schedule: hourly, at no token cost
  when nothing is new (§11).
