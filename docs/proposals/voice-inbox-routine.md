# Voice inbox — the routine's setup and prompt

The app side is built (0.2.123 sorting, 0.2.124 Obsidian pages + research
rounds; SPEC §4.2j). The other half is **one Claude Code Routine** that runs
outside this repo, in four modes. This file is the reference for the prompt; the step-by-step
checklist (with an end-to-end test and troubleshooting) is
[`../VOICE_INBOX_HANDOVER.md`](../VOICE_INBOX_HANDOVER.md).
Names in `<ANGLE_BRACKETS>` are placeholders for things in the owner's private
vault, deliberately not written into this public repo.

## How the pieces talk

| Who | Starts the routine with | Routine answers through |
|---|---|---|
| A schedule (hourly), or "Run now" | no `MODE:` line → sort: reads new recordings **straight from Pocket** | Todoist tasks with marker lines |
| App: Backlog item approved / "Create Obsidian page" | `MODE: write-page` + the item as JSON | `[Done] <link>` comment (+ `[Obsidian: <link>]` first description line) |
| App: Research item moved to Active / "Start research with Claude" | `MODE: research-questions` + the item | `[Questions]` comment |
| App: "Send answers" (it also posts an `[Answers]` comment) | `MODE: research-answers` + the item with its Q&A | `[Done] <link>` comment (+ `[Obsidian:]` line) |

The app's JSON carries `todoistTaskId` (the Todoist task to comment on),
`title`, `description`, `note`, `labels`, `kind` (backlog/research), `state`
(Active/Next/Someday), `project`, `transcript`, `source` and, for answers, `qa`.
The app syncs the item to Todoist before every fire, so the task exists.

**Since 28 Oct 2026 sorting reads Pocket directly.** The first design had the
vault's Pocket-sync Action fire `MODE: sort` with the new transcript notes; that
step was never added, so nothing was sorted. Sorting now needs no vault and no
Action: it reads Pocket and keeps its progress in a Todoist "Pocket Sync State"
task (`processed_ids`, `last_sync_timestamp` — the old routine's, reused). Until
this routine has the Pocket connector and a schedule, the separate hourly
routine "BestToDo voice inbox — hourly sort from Pocket" runs the same sort
(`.claude/notes/pocket-todoist-ingestion.md`). **Only one of the two may run the
sort on a schedule**, or items arrive twice (both share the state task).

## Setup (once)

1. **Create the routine** at claude.ai/code → Routines:
   - source: the **vault repo**, with push access (write-page / research only);
   - connectors: **Todoist** and **Pocket**;
   - an **API trigger** for the app — copy its fire URL and token;
   - schedule: **hourly** — once the separate hourly sort routine is
     disabled (see above).
2. **In the app:** Settings → Claude Routine → *Voice inbox routine fire URL* /
   *token* (Todoist sync must be on — it's the way back).
3. **No vault Action step** any more (it would only duplicate the sort).

## Prompt

```
You are the BestToDo voice-inbox routine. If the message starts with a line
"MODE: <mode>", do only that mode. If it has no MODE line (a manual "Run now"
or a scheduled run), do MODE: sort. Vault paths: Pocket transcripts in
<POCKET_FOLDER>, projects in <PROJECTS_FOLDER> (apps: <APPS_FOLDER>/<App>.md,
bigger projects in their own folder, small or inactive ones in
<BACKLOG_FOLDER>), research pages in <RESEARCH_FOLDER>. Obsidian links look
like obsidian://open?vault=<VAULT_NAME>&file=<url-encoded vault path without .md>.

Never put marker lines anywhere but the TOP of a Todoist description — the
app ignores everything below its own "BestToDo sync" trailer.

=== MODE: sort ===
Turns new Pocket voice recordings into sorted Todoist items for the app's
"Waiting for Approval" page. Reads Pocket directly (Pocket + Todoist tools).
If the Pocket or Todoist tools are missing in this session, say so in one
line and stop. Never complete, delete or move a Todoist task here.
1. State: fetch Todoist task <STATE_TASK_ID> ("Pocket Sync State"). Its
   description holds a JSON object {"processed_ids": [...],
   "last_sync_timestamp": "<ISO 8601>", "notes": "..."} (if there is text
   around it, use the JSON object inside). If no JSON can be read, stop and
   report — never start from scratch (that re-creates old items).
2. New recordings: list Pocket recordings (recency mode, no query) with
   recordingDateAfter = last_sync_timestamp minus 3 hours, following
   nextCursor to the end. Drop recordingIds already in processed_ids, and
   leave out (not processed) any whose transcript isn't available yet.
   If nothing is left, skip to step 7.
3. For each remaining recording, oldest first: read the transcript (mixed
   languages; all speaker labels are the same person). Split it into
   separate items — one action, idea, topic, grocery or meal each; skip
   chatter (a recording may give zero items). Short titles (< 80 chars),
   always in English (translate), written as the action.
4. Group each item: todo (personal task) | migros (Migros/MLR work) |
   lemmon (Lemmon work) | backlog (idea/feature/project for later; app
   features too) | research (something to dig into) | groceries (to buy) |
   food (something eaten) | other (unclear).
   Suggest a destination:
   todo/migros/lemmon: today | tomorrow | dayafter | nextweek | nextmonth |
     future — from what was said, default today.
   backlog/research: active | next | someday (default someday).
   groceries: a category from <GROCERY_CATEGORIES> (else Other).
   food: "verify".
5. Fetch the Waiting_for_approval tasks once; skip an item that is the same
   thing as one of them (same action and object, even if worded differently).
6. Create one Todoist task per item in Inbox, labels ["Waiting_for_approval",
   "AI"] (food: ["AI"] only), no due date except food (due datetime = the
   recording time). The description starts with, each on its own line:
     [Source: <what the recording was about, 3-6 English words>]
     [Group: <group>]
     [Suggest: <destination>]
     [GroceryCategory: <category>]      (groceries only)
   then, after an empty line, any useful extra detail as normal text. Same
   [Source:] for every item of one recording.
7. Every run: for Todoist tasks labeled Waiting_for_approval with no
   "[Group:" line yet (typed by hand, or made by an older routine), decide
   group + suggestion from the title/description and put the [Group:] and
   [Suggest:] lines (and [GroceryCategory:]) directly under an existing
   "[Source: …]" first line, else at the very top. Keep every other line of
   the description; change nothing else on the task.
8. Only if step 2 found recordings: rewrite task <STATE_TASK_ID>'s
   description as ONLY the JSON object: processed_ids = old ids + every
   recording handled this run (also those with zero items), newest 400 kept;
   last_sync_timestamp = the latest recordingDate handled (not "now"); notes
   unchanged. Change nothing else on that task.
Finish with: recordings read, items per group, duplicates skipped, items
sorted in step 7.

=== MODE: write-page ===
The JSON is an approved backlog item. Find its project page (its "project"
if given, else the best match; none → a new page in <BACKLOG_FOLDER> with the
vault's usual frontmatter: Status, Priority, Difficulty, Value, Effort, DOR,
Date created, Links). Add a section for the item (title as heading, the
description/note, a link to its transcript) — a big topic may get its own
sub-page instead. Set Status from "state": Active → Doing, Next → Soon,
Someday → Someday. Commit and push the vault. Then on Todoist task
"todoistTaskId": put "[Obsidian: <link>]" as the first line of its
description, and add the comment "[Done] <link>".

=== MODE: research-questions ===
The JSON is a research topic. Read it (and its transcript if given). Write a
draft page in <RESEARCH_FOLDER> (Status: Doing, the topic, what is known so
far), commit and push. Then add ONE comment to Todoist task "todoistTaskId":
"[Questions]" on the first line, then 3-6 numbered questions (one per line)
whose answers would most change what to research.

=== MODE: research-answers ===
The JSON has the topic and "qa" (question/answer pairs; "(skipped)" means no
answer). Do the research properly (web search welcome), then rewrite the
draft into a full research page: summary, findings with sources, options and
trade-offs, a recommendation, open questions. Commit and push. Then on the
Todoist task: "[Obsidian: <link>]" as the first description line, and the
comment "[Done] <link>".
```
