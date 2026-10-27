# Voice inbox — the sorting routine's prompt

The app side of the voice inbox shipped in 0.2.123 (SPEC §4.2j). The other half
is a **Claude Code Routine** that runs outside this repo. This file is the
prompt to paste into it, plus the setup it needs. Names in `<ANGLE_BRACKETS>`
are placeholders for things that live in the owner's private vault and are
deliberately not written into this public repo.

## Setup (once)

1. **Create the routine** (claude.ai/code → Routines) with:
   - the **vault repo** as a source, with push access;
   - the **Todoist** connector;
   - an **API trigger** (so it can be fired) — note its fire URL and token.
   - No schedule of its own: the vault's hourly Pocket-sync Action fires it
     (step 2), so an hour with nothing new costs no tokens.
2. **Vault repo:** after the Pocket-sync Action commits new recordings, call
   the routine's fire URL with the list of new recording folders as the
   message (`curl -X POST <FIRE_URL> -H "Authorization: Bearer <TOKEN>" -d …`).
   Store the URL and token as repo secrets. Optionally also fire it when the
   Todoist API reports tasks waiting for approval without a `[Group:]` line.
3. **Retire** the old once-a-day "Sync Pocket to Obsidian + Todoist" routine
   (`.claude/notes/pocket-todoist-ingestion.md`) so items aren't created twice.

## Prompt

```
You sort voice notes for the BestToDo app.

INPUT: the message lists new Pocket recording folders in the vault repo
(<POCKET_FOLDER>/<date>/<title>/). Each has "<title> - t.md" (the transcript,
mixed languages) and "pocket-meta.md" (pocket_id, pocket_title, recorded time).
If the message lists none, also look in Todoist for tasks labeled
Waiting_for_approval whose description has no "[Group:" line and sort those
(add the marker lines at the TOP of their description; change nothing else).

FOR EACH RECORDING:
1. Read the transcript. Split it into separate items: one action, idea, topic,
   grocery or meal each. Skip chatter. Keep each title short (under 80 chars),
   in the language that was spoken.
2. Give every item exactly one group:
   todo      – a personal task
   migros    – a task for the Migros/MLR work context
   lemmon    – a task for the Lemmon work context
   backlog   – an idea / feature / project for later (new app features too)
   research  – something to dig into
   groceries – something to buy
   food      – something eaten (a meal or snack)
   other     – unclear
3. Suggest a destination:
   todo/migros/lemmon: today | tomorrow | dayafter | nextweek | nextmonth | future
     (use what was said: "tomorrow", "next week", ...; default today)
   backlog/research:   active | next | someday
   groceries: also give a category from this list: <GROCERY_CATEGORIES>
     (the app's Groceries ▸ Edit categories list; else Other)
   food: compare with the existing Food Diary entries you know of; if it is
     the same meal, use that meal's usual wording and write [Suggest: match];
     if it's a new combination write [Suggest: verify].
   backlog: find the matching project page in <PROJECTS_FOLDER> (apps under
     <APPS_FOLDER>/<App>.md, bigger projects in their own folder, small or
     inactive ones in <BACKLOG_FOLDER>) and give its vault path.
4. Create one Todoist task per item, content = the title, labels =
   ["Waiting_for_approval", "AI"] (food items: ["AI"] only), project Inbox.
   The description STARTS with these lines, one per line, then any extra
   detail as normal text:
     [Source: <short recording title, 3-6 words>]
     [Group: <group>]
     [Suggest: <destination>]
     [Project: <vault path>]            (backlog only)
     [GroceryCategory: <category>]      (groceries only)
     [Transcript: <vault path of the transcript note>]
   For food, set the Todoist due datetime to the recording time.
5. Don't create an item twice: skip one whose title already exists, same
   wording ignoring case, among Waiting_for_approval tasks.

Never write marker lines anywhere but the top of a description — the app
ignores everything below its own "BestToDo sync" trailer.

FINISH with a 3-line summary: recordings read, items per group, anything
skipped.
```

## Later phases (not built yet)

- **Obsidian page after approval** — the app will fire a second prompt with the
  approved backlog item; it writes the page (vault frontmatter, `Status` =
  Doing/Soon/Someday from the state) and puts `[Obsidian: obsidian://open?vault=
  <VAULT_NAME>&file=<path>]` as the **first line** of the task's description.
- **Research "Active"** — the two-run Q&A described in `voice-inbox.md` §8.
