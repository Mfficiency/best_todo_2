# Voice inbox — speak it, Claude sorts it, you approve it

**Status: proposal, not built.** Agreed with the owner on 2026-10-27 from a
whiteboard sketch plus two rounds of Q&A. Nothing here exists in the app yet;
when a phase ships, its as-built description moves into `SPEC.md` Part I (which
only describes the current app) and this file keeps the design record.
"Open" items at the end still need an answer before their phase is built.

Builds on what already exists — read these first:
SPEC §4.2e (Waiting for Approval, quick tags, `[Source: …]` marker,
`pendingSourceTitle`), §4.8 (Todoist sync), §10.6 (Wishlist and its release
groups), §10.6a (Food Diary), §10.6c (Worklist), the Research tool (§4.2e,
"Research tool"), `.claude/notes/pocket-todoist-ingestion.md` (the routine
this replaces/extends) and `.claude/notes/obsidian-integration.md`.

## 1. The flow

```
Pocket recording ──► transcript ──► Claude Routine (cloud) ──► Todoist tasks ──► app pull
                                         │                                    │
                                         └──► transcript note in Obsidian     ▼
                                                                Waiting for Approval
                                                                (grouped by category)
                                                                   │ approve │ deny
                                                                   ▼         ▼
                                                          destination   Deleted bin
```

1. **Source: a Pocket recording.** One recording can be long and mention many
   unrelated things; Claude splits it into separate items.
2. **Claude runs in the cloud**, as the existing Pocket ingestion Routine does
   today (a Claude Code Routine with the Pocket + Todoist connectors). It does
   not run inside the app and the app holds no Anthropic key.
3. **Transport back to the phone is Todoist**, exactly as today: the routine
   creates Todoist tasks, the app's Todoist pull turns them into tasks gated by
   `Waiting_for_approval`. Category and suggested destination travel as extra
   description marker lines (§4).
4. **Tasks typed straight into Todoist also get sorted.** The routine also
   classifies new Todoist Inbox tasks that carry no group marker yet (it adds
   the markers to their description). One the app pulled before the routine
   got to it lands in **Other** (§3).
5. **The full transcript is kept in Obsidian** (§6), and every item made from it
   names it as its source (`[Source: …]`, already shown as "From:" and used as
   the approval group header today).

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

Migros (= the existing MLR / Worklist tag) and Lemmon are **work contexts**.

### State words for Backlog and Research

- **Active** — what I'm working on now / look at when I have time. For
  Research it also starts a Claude research session (§7).
- **Next** — not urgent or relevant now, but will be soon.
- **Someday** — a good idea, not for the near future; the bottom of the pile.
  (Renamed from "archive" on the board — it is *not* the app's Archived Items.)

Items in both tools are **grouped by state** (Active, Next, Someday sections).
Research items keep their due date field but it is no longer shown or used for
grouping.

## 3. Waiting for Approval changes

The existing page stays the entry point; it changes in these ways:

- **Grouped by category**, in the table's order, instead of by conversation.
  The conversation ("From: …") stays visible on each row's details panel (and
  could be a second grouping level later).
- **Claude's suggested destination is pre-selected.** "Call the dentist
  tomorrow" arrives as Todo → Tomorrow; a research topic as Research → Next.
  The row shows it as a small chip (e.g. "→ Tomorrow"), and the swipe's
  countdown default is that suggestion instead of Today.
- **Swipe stays the same gesture, the options depend on the group:**
  - Todo / Migros / Lemmon: today's options unchanged — approve side = the day
    buckets, deny side = Deny + Fri/Sat/Sun/Mon.
  - Backlog / Research: approve side = Active / Next / Someday.
  - Groceries: approve side = "Add to list".
  - Other: swiping opens a **group picker**; picking one moves the item into
    that group, still waiting for approval.
  - Deny side everywhere: Deny → the real Deleted bin after the undo window
    (today's behavior, recoverable from Deleted Items until it ages out).
- **Long press + drag moves an item to another group** (fixes a wrong
  category). The item keeps its text; the destination resets to that group's
  default. *Conflict:* long press starts multi-select today — see Open #5.
- Approving into Backlog/Research flips `isWish`/`isResearch` (as the quick-tag
  buttons do today) and sets the state; into Groceries sets the grocery flag
  (§8); into Migros/Lemmon adds the `mlr`/`lemmon` label.

## 4. Routine ↔ app contract (description markers)

Extends the existing `[Source: <title>]` convention (first description line,
case-insensitive, stripped on pull, parsed only on first pull). New lines,
each optional, directly after it:

```
[Source: Tuesday walk – bike & groceries]
[Group: todo|migros|lemmon|backlog|research|groceries|food|other]
[Suggest: today|tomorrow|dayafter|nextweek|nextmonth|future|active|next|someday]
[Project: <Obsidian project path>]        (backlog only, Claude's best match)
[GroceryCategory: <category>]              (groceries only)
[Transcript: <obsidian link>]
```

- No `[Group:]` (a hand-typed Todoist task the routine hasn't classified yet,
  or an old routine) → **Other**.
- A `[Suggest:]` that doesn't belong to the group is ignored (group default).
- Stored locally on the task (like `pendingSourceTitle`: local-only, never
  pushed back, no effect on sync fingerprints).
- **Food diary items skip the gate**: the app turns a `[Group: food]` task into
  a Food Diary entry directly (no `Waiting_for_approval`), timed at the
  recording's time, then closes/deletes it on the Todoist side so it is pulled
  only once (Food Diary entries are otherwise never synced — SPEC §10.6a).

## 5. Home: Todo / MLR / Lemmon toggles

- **Default unchanged:** the home list shows regular items; `mlr` items stay
  Worklist-only (the current standing rule's behavior); Lemmon items default to
  hidden too (Open #1).
- In the drawer, the **Home** entry folds out three toggle icons — **Todo**,
  **MLR**, **Lemmon** — each switching that group on/off in the home tabs and
  the schedule view, alone or in any combination ("Todo" = every item with
  neither the `mlr` nor the `lemmon` label). Shown items carry their label chip.
- Each context also keeps its **own list showing only that label**: Tools ▸
  Worklist (MLR, exists) and Tools ▸ **Lemmon** (new, another
  `HomePage(tagFilter: 'lemmon')` instance like Worklist).
- Structurally this stays inside `ItemViews.isVisibleInMainViews` /
  `isOnHomeScreen` (one gate for tabs and schedule view, as the 0.2.46 fix
  requires); the toggles become a parameter of that gate, not a second filter.
  The CLAUDE.md MLR standing rule gets reworded to "hidden from home by
  default, shown only when the MLR toggle is on".

## 6. Obsidian

- The vault is a **git repo**, so the cloud routine clones it, writes, commits
  and pushes (the app's synced-folder file is not needed for this).
- **Transcripts:** one note per Pocket recording (folder: Open #6), holding the
  full transcript and a list of the items made from it with their group.
- **Backlog pages, written only after approval.** Layout: `Projects/` has a
  subfolder per bigger project; smaller or inactive ones go into
  `Projects/Backlog/`. Generally one page per project with a section per item;
  a big topic can get its own sub-project page. New app features go under their
  app's project. Claude matches against the existing folders/pages; no match →
  a new page in `Projects/Backlog/`.
- The phone keeps the list (Wishlist); each backlog item gets a link to its
  Obsidian page/section, where drawings and longer text go.
- **How approval reaches the routine:** approving into Backlog (and swiping
  Research to Active, §7) fires a Claude Routine via the existing
  `ClaudeRoutineService` ("Send to Claude") with the item; that run writes the
  page and returns the link through Todoist (an `[Obsidian: …]` marker on the
  item), so the app shows it as a tappable link. A watcher run every hour or so
  catches anything a fire missed (offline, failure).

## 7. Research "Active"

- Swiping a research item to **Active** starts a Claude research session right
  away (same `ClaudeRoutineService` fire; the hourly watcher is the fallback).
- The session reads the item, **asks the owner questions, which appear in the
  BestToDo app**; the answers go back to the session. Then it writes a full
  research page into the vault (`Research/` or under its project — Open #6).
- The finished page **lives in Obsidian**; the research item in the app gets a
  link to it.
- Q&A transport: Open #7.

## 8. Groceries (new tool, Tools ▸ Groceries)

- A **checklist, auto-grouped by category**: fresh fruit & vegetables, canned,
  pasta & rice, dairy, … (Claude sets the category on items it creates).
- **No dates.**
- At the top: **Check all** and **Reset list** (unchecks everything).
- It's a reusable list: checked items stay until reset; adding something
  already on the list unchecks the existing item instead of making a duplicate.
- Model: a flag on the one task list (like `isEatingHabit`/`isResearch`) plus a
  category field, gated out of every main view in `isVisibleInMainViews`.

## 9. Food diary from voice

- Goes straight into the Food Diary, no approval (§4).
- Claude **matches against existing entries** (same meal/ingredient
  combination → same title and tags). When it can't, it creates a new
  combination and the entry gets a **small blue dot** meaning "please verify";
  editing or confirming the entry clears the dot.

## 10. Phases (suggested build order)

1. App: group/suggest markers, grouped approval page, per-group swipe options,
   Other picker, food diary direct import with blue dot. Routine: emit markers,
   classify untagged Todoist tasks, write transcripts to the vault.
2. Backlog/Research states (Active/Next/Someday sections, hidden research due
   date) and the Home Todo/MLR/Lemmon toggles + Tools ▸ Lemmon.
3. Groceries tool.
4. Obsidian backlog pages + links (approve → routine fire → link back).
5. Research Active sessions with in-app Q&A.

## 11. Open items

1. **Toggle defaults:** Todo on, MLR off, Lemmon off? Remembered across
   restarts (assumed yes)? Do they also apply to the home-screen widget and the
   Obsidian sync file, or only the in-app home list (assumed in-app only)?
2. **Drawer gesture:** tapping Home goes home today. Fold the toggles out with
   a small arrow on the Home row (tap the name = go home), or does tapping
   Home itself fold them out?
3. **Wishlist sections:** the Wishlist already has Newly implemented / Next
   release / Soon / Backlog. Proposed: Active = Next release, Next = Soon,
   Someday = Backlog, keep Newly implemented as is — or replace the four with
   Active / Next / Someday?
4. **Grocery categories:** fixed list or editable in Settings? How does an item
   typed in by hand get its category (pick it, or keyword guess like
   auto-tagging)?
5. **Long press in approval** starts multi-select today. Make long press =
   drag to another group and move multi-select to a toolbar button (or a
   long press on the leading icon)?
6. **Vault paths & name:** folders for transcripts and research pages, the
   vault's name (for `obsidian://open?vault=…` links), and the vault repo's
   location so the routine can be given access.
7. **Research Q&A transport:** research items are kept out of Todoist sync
   today. Proposed: sync only Active research items, with the questions and
   answers as Todoist comments, shown in the app on the item — or another
   channel?
8. **Routine schedule:** the current Pocket routine runs once a day despite
   its "Hourly" name. Should the new one run hourly?
