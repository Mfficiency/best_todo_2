# Pocket → Todoist ingestion routine — the thing that fills the approval queue

> **Replaced on 28 Oct 2026 — see "Hourly sort from Pocket" at the end.** The
> trigger `trig_01ApvNY8ogVMRRL33TUi3J9L` described below now runs the voice
> inbox's *sort* (categories + `[Group:]`/`[Suggest:]` markers) hourly, still
> straight from Pocket and with the same state task. Its old prompt is kept
> verbatim at the end of this note.

Every task in Tools ▸ **Waiting for Approval** (SPEC §4.2e) that wasn't typed by
hand into Todoist comes from one external, out-of-repo automation: a **Claude
Routine** (a Claude Code Remote scheduled trigger, *not* code in this repo,
*not* run by BestToDo itself) that reads the maintainer's Pocket voice-memo
conversations, extracts action items, and creates them in Todoist tagged
`Waiting_for_approval`. This note is its as-built record — what it does, how
it was found to interact with this app, and what changed and why — kept here
per `.claude/README.md`'s rule ("hard-won debugging session in a new area →
a new note").

The routine lives entirely outside this repo (it runs in its own Claude
session against the Pocket and Todoist MCP connectors) — this note documents
it and tracks the conventions it and BestToDo have to agree on, but editing
the actual schedule/prompt happens wherever that Routine is configured, not
by editing a file here.

## What it does

Trigger: **"Sync Pocket to Obsidian + Todoist Hourly"**, `claude-haiku-4-5`,
cron `27 18 * * *` (once daily, ~18:27 UTC — despite the name; see Issues
below). Each run:

0. Loads durable state from a dedicated Todoist task ("Pocket Sync State",
   fixed id) — a JSON blob in that task's *description* holding
   `processed_ids` (conversation ids already handled) and
   `last_sync_timestamp`. Todoist itself is the only persistence available to
   a stateless scheduled run, so this task doubles as a tiny key-value store.
1. Fetches only Pocket conversations created after `last_sync_timestamp`
   (bounded to the last 5-10), skipping anything already in `processed_ids`.
2. Extracts action items from each transcript (pattern list: "add to list",
   "buy", "research", "remember to", ...), normalizes them (strip filler
   words, lowercase for comparison, trim), and infers content tags
   (`bike-gear`, `todo-app`, `finance`, ...).
3. Deduplicates against existing `Waiting_for_approval`-tagged Todoist tasks
   by exact normalized text (deliberately scoped to the approval queue only
   — an item that already got approved and renamed shouldn't suppress a
   genuinely new one that happens to read the same).
4. Filters out vague (<8 chars) or overlong (>200 chars) items.
5. Creates a Todoist task per surviving item: tags `AI` + `Waiting_for_approval`
   + inferred content tags, due today, project Inbox.
6. Marks every examined conversation processed (whether or not it produced a
   task) and writes the updated `processed_ids`/`last_sync_timestamp` back to
   the state task's description.

Full current prompt text is on the trigger itself
(`trig_01ApvNY8ogVMRRL33TUi3J9L`) — not duplicated here since a copy would
drift; this note only documents behavior and the conventions BestToDo relies
on.

## How BestToDo reads what it creates

Nothing in this routine talks to BestToDo directly — it only ever touches
Todoist and Pocket. Everything downstream is the ordinary Todoist sync path:
a task appears in the queue exactly like any other Todoist-originated pull
(SPEC §4.2e — `TodoistSyncService._taskFromRemote`, gated by
`waitingApprovalToken`), and the app has no way to tell this routine's tasks
apart from ones a human typed directly into Todoist except by the `AI` tag it
adds (a plain, non-reserved label — no BestToDo behavior keys off it today).

## Issues found reviewing the prompt against 0.2.17's approval-queue work

Reviewed while adding expand-on-tap details, group-by-conversation and
multi-select to the Waiting for Approval page (0.2.17) — that work needed to
know what data actually reaches the app from this routine.

1. **No conversation identity reached Todoist at all (fixed, 0.2.18).** The
   durable-state task tracks `processed_ids`, but those ids never appear on
   the *created* tasks themselves — every item landed in Todoist's Inbox with
   no trace of which conversation produced it. `Task.pendingSourceTitle` (the
   field the new grouping/expand feature reads) had nothing to key off, so
   every item this routine creates would show "Unspecified" and pile into one
   undifferentiated group forever.

   Fixed on both sides: the routine now prefixes each created task's
   description with `[Source: <a short label for the conversation>]`, and
   `TodoistSyncService._taskFromRemote` recognizes that marker on pull (see
   SPEC's Waiting for Approval section, "`Task.pendingSourceTitle`..." —
   strips it from the visible description, sets `pendingSourceTitle`). No
   per-conversation Todoist project needed — the marker approach was chosen
   over routing each conversation into its own Todoist project specifically
   to avoid littering the project list with one-off entries.

2. **The documented user-facing approval step for "wish" tagging doesn't do
   what it says (flagged, not an app change).** The routine's own
   "APPROVAL WORKFLOW FOR USER" section told the user they "can add `btd` +
   `wish` tags if relevant during approval" to route an approved item into
   the wishlist. That's not how the app works: `Task.isWish` is a structural
   flag, and per `label_utils.dart`'s `wishToken` doc, a `Wish`-spelled label
   is deliberately inert (reserved for chip styling only, not a behavior
   trigger) — nothing about typing "wish" as a Todoist label sets it. The
   *actual* way to land a Todoist-created task in BestToDo's wishlist is to
   move it to the dedicated **Wishlist** Todoist project (auto-recognized on
   pull, same mechanism `Task.pendingSourceTitle` reads from), or toggle it
   on inside the app after approving. The routine's user-facing instructions
   were corrected to say that instead of promising a tag that's a no-op.

3. **Trigger name says "Hourly", cron says once a day** (`27 18 * * *`).
   Left alone — not something to silently "fix" without knowing whether the
   maintainer meant daily and the name is just stale, or meant hourly and the
   schedule regressed. Worth the maintainer's own look.

## The `[Source: ...]` convention, if this routine (or another one) is extended

- Format: the **very first line** of the Todoist task's `description` field,
  exactly `[Source: <title>]` (case-insensitive, one line, title is anything
  up to the closing `]`). Anything after it is the task's real description
  text and is preserved as-is.
- Keep the title short — it's a group header in the Waiting for Approval
  page (`<title> (<count>)`), not prose. A Pocket conversation's own title if
  it has a real one; otherwise a short 3-6 word phrase summarizing it is
  fine — the routine composes this, there is no requirement it match
  anything stored in Pocket verbatim.
- It's parsed only on first pull (`_taskFromRemote`) — editing an
  already-approved task's description later has no effect on its (already
  local-only) `pendingSourceTitle`.
- Never required: a task with no marker and no non-Inbox project just groups
  under "Unspecified" — existing behavior, unaffected.

## Hourly sort from Pocket (28 Oct 2026) — what actually runs now

**What went wrong.** The voice-inbox design (`docs/VOICE_INBOX_HANDOVER.md`) has
the *vault* repo's Pocket-sync GitHub Action fire the "BestToDo voice inbox"
routine (`trig_01CgX28iTSkpJTsPUYNLkzbh`, no schedule) with `MODE: sort` after
each new transcript.
- **Setup stopped halfway:** the old routine was disabled (handover step 5) at
  06:34 UTC on 28 Oct, but the vault Action step (step 4) was never added, and
  the routine had no vault repo attached (step 2).
- **Result:** the new routine never fired, and that morning's recordings never
  reached Todoist.

**The fix.**
- **What changed:** the old trigger `trig_01ApvNY8ogVMRRL33TUi3J9L` kept its
  Pocket + Todoist connectors (connectors can't be attached to a trigger from a
  session on this account; only the routines UI can). It was renamed "BestToDo
  voice inbox — hourly sort from Pocket", its prompt replaced by a
  Pocket-reading version of `MODE: sort`, and it was re-enabled on an hourly
  cron.
- **What it does each run:**
  - same state task `6hM6jF45GHVfpfVp` (`processed_ids`, `last_sync_timestamp`);
  - looks back 3 h for late transcripts;
  - splits recordings into English-titled items with the marker lines (§4.2j);
  - food gets only `AI` and a due time;
  - also sorts hand-typed pending tasks.
- **What it leaves out:** no `[Project:]`/`[Transcript:]` lines, since it has no
  vault access. Write-page mode finds the project itself.
- **What still uses the original routine:** the voice-inbox routine stays as is
  for the app's `write-page`/`research-*` fires.
- **Leftover:** the vault Action step is no longer needed for sorting. Don't
  add it unless this hourly task is switched off, or every item arrives twice.

### The old routine's prompt (verbatim, before 28 Oct 2026)

```
Extract action items from Pocket conversations and upload to Todoist (APPROVAL WORKFLOW with DURABLE SYNC TRACKING).

WORKFLOW: All extracted tasks go to "Waiting_for_approval" queue. Only process NEW conversations since last sync.

STEP 0: LOAD DURABLE STATE FROM TODOIST TASK
- Fetch Todoist task ID: 6hM6jF45GHVfpfVp (Pocket Sync State)
- Parse JSON from task description to extract:
  * processed_ids: array of conversation IDs already processed
  * last_sync_timestamp: ISO 8601 timestamp
- If task is not found or parse fails, start with empty processed_ids array
- Use last_sync_timestamp (or 1 hour ago if missing) as the time window cutoff

STEP 1: DETERMINE TIME WINDOW
- Extract last_sync_timestamp from Todoist task description
- Calculate time window: from last_sync_timestamp to now
- Only fetch conversations created AFTER last_sync_timestamp

STEP 2: FETCH ONLY NEW POCKET CONVERSATIONS
- Use search_pocket_conversations in recency mode with recordingDateAfter = last_sync_timestamp
- Limit to last 5-10 conversations
- This ensures only truly NEW conversations are processed
- Filter out any conversation IDs already in processed_ids list (safety check)

STEP 3: EXTRACT ACTION ITEMS WITH NORMALIZATION
For each NEW conversation only:
- Extract action items/todos from transcript
- Look for patterns: "add to list", "put on list", "make", "fix", "buy", "research", "call", "remember to", "look into", "investigate", etc.
- NORMALIZE each item:
  * Remove filler words (um, uh, so, like, etc.)
  * Convert to lowercase for comparison
  * Trim whitespace
  * Remove redundant qualifiers
  * Example: "maybe try to research X" → "research X"
- Infer tags: bike-gear, running-fitness, todo-app, research-notes, finance, to-buy, immediate, home, dev, admin, obsidian, mlr
- IMPORTANT: Check EVERY item for Migros/MLR references. If an item relates to Migros or MLR (any context, any mention), ALWAYS include the "mlr" tag
- Note the conversation's own title if Pocket provides one; if not, compose a short (3-6 word) phrase summarizing what the conversation was about. You will need this per-conversation label in STEP 6 — compute it once per conversation and reuse it for every item extracted from that same conversation.

STEP 4: DEDUPLICATE WITHIN APPROVAL QUEUE ONLY
For EACH extracted action item:
- Search Todoist for tasks with "Waiting_for_approval" tag using exact normalized text 
- If exact match found with approval tag → SKIP (don't create duplicate in queue)
- If no match → PROCEED to create

STEP 5: SMART FILTERING
Before creating task, apply filters:
- Filter out vague items: "do something", "think about it", "maybe later" → SKIP
- Filter out items < 8 characters (too vague)
- Filter out items > 200 characters (too long/complex)

STEP 6: CREATE TASKS IN TODOIST WITH APPROVAL TAG
For all items that pass filters:
- Create task with content = the normalized action item text
- Set the task's description field to exactly one line: "[Source: <conversation label>]" using the per-conversation label you computed in STEP 3 (its own title, or your short composed phrase). This MUST be the first line, in that exact bracket format, with nothing else added after it — BestToDo's app parses this marker to show "which conversation created this pending item" and to group the approval queue by conversation. Do not omit it and do not add any other text to the description.
- Add tags: "AI" + "Waiting_for_approval" + inferred content tags (bike-gear, todo-app, mlr, etc.) — ALWAYS include "mlr" tag if item relates to Migros or MLR
- Set due date: today
- Project: Inbox

STEP 7: MARK CONVERSATIONS AS PROCESSED
(add every processed conversation id to processed_ids, whether or not it produced tasks)

STEP 8: UPDATE DURABLE STATE IN TODOIST TASK
- Rewrite task 6hM6jF45GHVfpfVp's description JSON with processed_ids (old + new) and last_sync_timestamp = now; nothing else.
```
(STEP 7/8 and the trailing "approval workflow"/report sections are abridged; the
behaviour they describe is in "What it does" above.)
