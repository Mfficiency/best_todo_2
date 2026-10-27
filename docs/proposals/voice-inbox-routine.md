# Voice inbox — the routine's setup and prompt

The app side is built (0.2.123 sorting, 0.2.124 Obsidian pages + research
rounds; SPEC §4.2j). The other half is **one Claude Code Routine** that runs
outside this repo, in four modes. This file is everything to set it up.
Names in `<ANGLE_BRACKETS>` are placeholders for things in the owner's private
vault, deliberately not written into this public repo.

## How the pieces talk

| Who | Starts the routine with | Routine answers through |
|---|---|---|
| Vault's Pocket-sync Action (hourly, only when new recordings arrived) | `MODE: sort` + the new recording folders | Todoist tasks with marker lines |
| App: Backlog item approved / "Create Obsidian page" | `MODE: write-page` + the item as JSON | `[Done] <link>` comment (+ `[Obsidian: <link>]` first description line) |
| App: Research item moved to Active / "Start research with Claude" | `MODE: research-questions` + the item | `[Questions]` comment |
| App: "Send answers" (it also posts an `[Answers]` comment) | `MODE: research-answers` + the item with its Q&A | `[Done] <link>` comment (+ `[Obsidian:]` line) |

The app's JSON carries `todoistTaskId` (the Todoist task to comment on),
`title`, `description`, `note`, `labels`, `kind` (backlog/research), `state`
(Active/Next/Someday), `project`, `transcript`, `source` and, for answers, `qa`.
The app syncs the item to Todoist before every fire, so the task exists.

## Setup (once)

1. **Create the routine** at claude.ai/code → Routines:
   - source: the **vault repo**, with push access;
   - connector: **Todoist**;
   - an **API trigger** — copy its fire URL and token;
   - no schedule (it is only ever fired).
2. **In the app:** Settings → Claude Routine → *Voice inbox routine fire URL* /
   *token* (Todoist sync must be on — it's the way back).
3. **In the vault repo:** add the step below to the Pocket-sync workflow (after
   its commit step) and the secrets `VOICE_INBOX_FIRE_URL`,
   `VOICE_INBOX_TOKEN`. An hour with no new recording fires nothing, so it
   costs no tokens.
4. **Retire** the old once-a-day "Sync Pocket to Obsidian + Todoist" routine
   (`.claude/notes/pocket-todoist-ingestion.md`) so items aren't made twice.

```yaml
      - name: Fire the voice-inbox routine for new recordings
        if: always()
        env:
          FIRE_URL: ${{ secrets.VOICE_INBOX_FIRE_URL }}
          TOKEN: ${{ secrets.VOICE_INBOX_TOKEN }}
        run: |
          [ -n "$FIRE_URL" ] || exit 0
          # Transcript notes added by this run's commit (none → no fire).
          NEW=$(git diff --name-only --diff-filter=A HEAD~1 HEAD -- '<POCKET_FOLDER>' \
                | grep -- ' - t\.md$' || true)
          [ -n "$NEW" ] || { echo "No new recordings"; exit 0; }
          TEXT=$(printf 'MODE: sort\n%s\n' "$NEW")
          curl -sS -X POST "$FIRE_URL" \
            -H "Authorization: Bearer $TOKEN" \
            -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg t "$TEXT" '{text: $t}')"
```

(If the commit step exits early with "No changes to commit", `HEAD~1..HEAD` is
an older sync commit — guard it by only running this step when that step
committed, e.g. set an output there and use `if: steps.commit.outputs.done`.)

## Prompt

```
You are the BestToDo voice-inbox routine. The message starts with a line
"MODE: <mode>". Do only that mode. Vault paths: Pocket transcripts in
<POCKET_FOLDER>, projects in <PROJECTS_FOLDER> (apps: <APPS_FOLDER>/<App>.md,
bigger projects in their own folder, small or inactive ones in
<BACKLOG_FOLDER>), research pages in <RESEARCH_FOLDER>. Obsidian links look
like obsidian://open?vault=<VAULT_NAME>&file=<url-encoded vault path without .md>.

Never put marker lines anywhere but the TOP of a Todoist description — the
app ignores everything below its own "BestToDo sync" trailer.

=== MODE: sort ===
The rest of the message lists new transcript notes ("<title> - t.md"; next to
each is pocket-meta.md with the recording time). For each:
1. Read it (mixed languages). Split it into separate items — one action,
   idea, topic, grocery or meal each; skip chatter. Short titles (< 80 chars)
   in the language spoken.
2. Group each item: todo (personal task) | migros (Migros/MLR work) |
   lemmon (Lemmon work) | backlog (idea/feature/project for later; app
   features too) | research (something to dig into) | groceries (to buy) |
   food (something eaten) | other (unclear).
3. Suggest a destination:
   todo/migros/lemmon: today | tomorrow | dayafter | nextweek | nextmonth |
     future — from what was said, default today.
   backlog/research: active | next | someday.
   groceries: a category from <GROCERY_CATEGORIES> (else Other).
   food: "match" if it is a meal already in the Food Diary (reuse its usual
     wording), "verify" if it is a new combination.
   backlog: the matching project page's vault path.
4. Create one Todoist task per item in Inbox, labels ["Waiting_for_approval",
   "AI"] (food: ["AI"] only), food due datetime = the recording time. The
   description starts with:
     [Source: <recording title, 3-6 words>]
     [Group: <group>]
     [Suggest: <destination>]
     [Project: <vault path>]            (backlog only)
     [GroceryCategory: <category>]      (groceries only)
     [Transcript: <vault path of the transcript note>]
   then any extra detail as normal text.
5. Skip an item whose title (ignoring case) already exists among
   Waiting_for_approval tasks.
6. Also sort Todoist tasks labeled Waiting_for_approval with no "[Group:"
   line yet (typed by hand): add the marker lines at the top of their
   description, change nothing else.
Finish with: recordings read, items per group, anything skipped.

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
