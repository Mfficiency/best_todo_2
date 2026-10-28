# Voice inbox — handover: what you need to do to make it work

> **Status 28 Oct 2026 — sorting runs without steps 2 and 4.** The routine was
> created but never fired (no vault repo attached, no vault Action step). The
> old "Sync Pocket…" routine (`trig_01ApvNY8ogVMRRL33TUi3J9L`) was therefore
> repurposed as **"BestToDo voice inbox — hourly sort from Pocket"**: it runs
> `MODE: sort` every hour, straight from Pocket, with the same `[Group:]`/
> `[Suggest:]` markers. See `.claude/notes/pocket-todoist-ingestion.md`
> ("Hourly sort from Pocket").
> - **Step 4 (vault Action):** not needed any more. **Don't add it** while
>   the hourly task runs, or every item arrives twice.
> - **Step 5:** don't disable the hourly task. It *is* the sorter now.
> - **Still open:** the "BestToDo voice inbox" routine is only used for the
>   app's write-page/research fires. Those still need its vault repo (step 2)
>   and the app settings (step 3).

Everything inside the app is built and on `dev` (0.2.123 – 0.2.125). What's
left is on your side: one Claude Routine, one step in the vault repo's GitHub
Action, and two app settings. This page is the checklist, in order. Plan about
30–45 minutes.

The prompt to paste and the GitHub Action step are **not** copied here. They
live in one place, [`docs/proposals/voice-inbox-routine.md`](proposals/voice-inbox-routine.md),
so they can't drift apart. For how it all works, see `SPEC.md` §4.2j; for the
design and the reasons behind it, [`docs/proposals/voice-inbox.md`](proposals/voice-inbox.md).

---

## How it fits together (one minute)

```
You talk to Pocket
   │
   ▼  vault repo's Pocket-sync Action (hourly, plain Python, no AI)
Transcript note committed to the vault
   │
   ▼  NEW step you add: only if a new transcript arrived → fire the routine
Claude Routine, "MODE: sort"
   │  splits + sorts + suggests, creates Todoist tasks with [Group:]/[Suggest:]… lines
   ▼
Todoist  ──(app's Todoist sync)──►  BestToDo ▸ Waiting for Approval (by category)
                                       │ you edit / swipe / approve
                                       ├─ Backlog approved ──► routine "MODE: write-page"
                                       │      └─ writes the Obsidian page, replies "[Done] <link>"
                                       └─ Research → Active ──► routine "MODE: research-questions"
                                              └─ "[Questions]" → you answer in the app →
                                                 "MODE: research-answers" → page + "[Done] <link>"
```

The routine **always answers through Todoist** (comments on the item's task,
plus an `[Obsidian: …]` line at the top of its description). The app reads
those replies when you open the Wishlist or Research page.

---

## Step 0 — Decide the open points (2 minutes)

These change the text you paste in step 2. Pick one for each and note it down:

| Question | Options | Default in the prompt |
|---|---|---|
| Where do research pages go? | one research folder, **or** under the item's project when it has one | one research folder |
| Language of item titles | as spoken, **or** always English | as spoken |
| Wishlist section names | keep Active / Next / Someday / Done, **or** go back to Next release / Soon / Backlog / Newly implemented | Active / Next / Someday / Done (already in the app; tell Claude if you want them changed back) |

---

## Step 1 — Collect the placeholder values (5 minutes)

The prompt contains placeholders in `<ANGLE_BRACKETS>`. Fill them in **only in
the routine**, never in this public repo. Find each one in your vault:

| Placeholder | What it is | Where to find it |
|---|---|---|
| `<VAULT_NAME>` | The vault's name as Obsidian shows it (bottom left of the Obsidian sidebar) | Obsidian app |
| `<POCKET_FOLDER>` | The folder the Pocket-sync Action writes recordings to | the vault repo's `.github/scripts/pocket_sync.py` (top of the file) |
| `<PROJECTS_FOLDER>` | The projects folder | vault |
| `<APPS_FOLDER>` | The folder with one page per app (BestToDo, …) inside the projects folder | vault |
| `<BACKLOG_FOLDER>` | The folder for small or inactive projects | vault |
| `<RESEARCH_FOLDER>` | Where research pages go (see step 0; create it if it doesn't exist) | vault |
| `<GROCERY_CATEGORIES>` | Your grocery category list, comma-separated | app ▸ Tools ▸ Groceries ▸ Edit categories (defaults: Fruit & vegetables, Bread & bakery, Dairy & eggs, Meat & fish, Pasta & rice, Canned & jars, Frozen, Snacks & sweets, Drinks, Household, Other) |

---

## Step 2 — Create the Claude Routine (10 minutes)

At **claude.ai/code → Routines → New routine**:

- [ ] **Name:** e.g. "BestToDo voice inbox".
- [ ] **Repository:** your **vault repo**, with **push** access (it commits Obsidian pages).
- [ ] **Connector:** **Todoist**. This is the only connector it needs.
- [ ] **Schedule:** **none.** It's only ever started by the vault Action and the app, so an hour with nothing new costs nothing.
- [ ] **Prompt:** paste the block under "## Prompt" in
      [`voice-inbox-routine.md`](proposals/voice-inbox-routine.md), then replace
      every `<PLACEHOLDER>` with your values from step 1, and apply your step 0
      choices (edit the research-folder and language lines if you changed them).
- [ ] **Model:** a cheaper model (Haiku) is fine for sorting. Research
      answers are better with a stronger one. One routine has one model, so
      pick Sonnet if research quality matters most to you.
- [ ] **Add an API trigger** and copy the **fire URL** and the **token**. You
      need them twice: in step 3 and in step 4.

---

## Step 3 — App settings (2 minutes)

On the phone, BestToDo **0.2.125 or newer** (About shows the version):

- [ ] **Settings ▸ Todoist sync:** on, with your token. This is the routine's
      way back to the app; without it nothing below works.
- [ ] **Settings ▸ Claude Routine ▸ Voice inbox routine fire URL / Voice inbox
      routine token:** paste them from step 2 and tap **Save**. (The two fields above
      them, "Routine fire URL/token", belong to "Send to Claude"; leave them
      as they are.)
- [ ] Optional: **Settings ▸ Mode & features**: Lemmon and Groceries are on by
      default; switch off what you don't use.

Once both are set, these appear in the app:
- an expanded wish gets **Create Obsidian page**;
- Active research items get **Start research with Claude**;
- the Research page gets a **Check Claude's replies** button.

---

## Step 4 — Vault repo: start the routine when recordings arrive (10 minutes)

In the **vault repo** on GitHub:

- [ ] **Settings ▸ Secrets and variables ▸ Actions ▸ New repository secret**,
      twice:
  - `VOICE_INBOX_FIRE_URL` = the fire URL from step 2
  - `VOICE_INBOX_TOKEN` = the token from step 2
- [ ] Edit the Pocket-sync workflow (`.github/workflows/pocket-sync.yml`):
  - give its **commit step** an `id` and an output that says it really
    committed (so an hour with nothing new doesn't re-send the last batch);
  - add the **"Fire the voice-inbox routine for new recordings"** step from
    [`voice-inbox-routine.md`](proposals/voice-inbox-routine.md) after it,
    with `if:` on that output;
  - replace `<POCKET_FOLDER>` in it.

  Sketch of the commit-step change:

  ```yaml
      - name: Commit and push
        id: commit
        run: |
          # ... existing lines ...
          if git diff --cached --quiet; then
            echo "No changes to commit."
            exit 0
          fi
          git commit -m "Sync Pocket - $(date -u '+%Y-%m-%d %H:%M:%SZ')"
          echo "done=true" >> "$GITHUB_OUTPUT"
          # ... existing pull --rebase + push ...

      - name: Fire the voice-inbox routine for new recordings
        if: steps.commit.outputs.done == 'true'
        # ... the step from voice-inbox-routine.md ...
  ```
- [ ] Run the workflow once by hand (**Actions ▸ Sync Pocket Conversations ▸
      Run workflow**) and check the new step's log: either "No new recordings"
      or a JSON reply with a `claude_code_session_id`.

---

## Step 5 — Retire the old routine (1 minute)

- [ ] At claude.ai/code → Routines, **disable** the old "Sync Pocket to
      Obsidian + Todoist Hourly" routine (it runs once a day and reads Pocket
      directly). If both run, every item arrives twice. Disable it rather than
      delete it until the new one has run well for a few days.

---

## Step 6 — Test it end to end (10 minutes)

Do these in order. Each one checks one piece.

1. **Sorting.** Record a short Pocket note that covers several groups, e.g.
   "Call the dentist tomorrow. Buy milk and pasta. For BestToDo: the widget
   should have a dark mode. Look into heat batteries. I had a pasta pesto for
   lunch." Wait for the next hourly sync (or run the Action by hand), then
   in the app pull Todoist (Settings ▸ Todoist sync ▸ Sync now, or reopen the
   app).
   - Waiting for Approval shows **Todo**, **Groceries**, **Backlog** and
     **Research** sections, with "→ Tomorrow"-style suggestions.
   - The pasta lunch is already in the **Food Diary**, maybe with a blue dot.
2. **Editing.** Tap an item, change its description, add a tag. Close and reopen
   the panel: the edit is still there.
3. **Approving.** Swipe the dentist item: the day buttons appear and Tomorrow is
   bold. Swipe the milk: **Add to list**, and it appears in **Tools ▸ Groceries**.
4. **Obsidian page.** Approve the dark-mode item (Backlog → Next). Within a few
   minutes the routine commits a section on your BestToDo project page. Open
   the **Wishlist**: the item has **Open in Obsidian**.
5. **Research round.** Approve "heat batteries" into **Active**. Open
   **Research**. It shows "Claude is preparing questions…"; after a few
   minutes tap **Check Claude's replies** → **Answer N questions** → answer,
   **Send answers**. Later the item gets **Open in Obsidian** with the full
   page.
6. **Hand-typed Todoist task.** Add a task in Todoist itself. It first shows
   under **Other**; after the next routine run it moves to its category.
   Swiping an Other item asks where it belongs, so you never have to wait.

---

## If something doesn't work

| What you see | Most likely cause | Fix |
|---|---|---|
| Nothing new in Waiting for Approval | Todoist sync off, or the routine didn't run | Settings ▸ Todoist sync ▸ Sync now; check the Action's log and the routine's session list |
| Everything lands under **Other** | The routine creates tasks without the marker lines, or puts them below other text | The prompt must put `[Group:]` etc. on the **first lines** of the description |
| A snackbar says "Claude routine error 401" | Wrong voice inbox token in the app | Re-copy it from the routine's API trigger, Save |
| "Couldn't reach the Claude routine" | No network, or wrong URL | Check the fire URL; the button comes back, so try again |
| No "Create Obsidian page" / "Start research" buttons | Voice inbox URL/token or Todoist sync not set | Step 3 |
| "Claude is writing the Obsidian page…" never ends | The routine didn't post `[Done] <link>` | Open the item's task in Todoist: is there a `[Done] obsidian://…` comment? If not, check the routine run's log |
| "Open in Obsidian" opens the wrong vault / nothing | `<VAULT_NAME>` in the prompt doesn't match the vault's real name | Fix it in the routine prompt |
| Every item arrives twice | The old once-a-day routine is still on | Step 5 |
| The Action fires every hour although nothing was recorded | The commit-step output from step 4 is missing | Add `id: commit` + `done=true` and the `if:` |

App logs: **menu ▸ App Logs**. Look for `VoiceInboxService` lines ("Fired write-page
for …", "Fire failed …") and the Todoist tab for sync errors.

---

## Where everything is (for a future Claude session)

| Thing | Where |
|---|---|
| As-built description | `SPEC.md` §4.2j |
| Design, decisions, open items | `docs/proposals/voice-inbox.md` |
| Routine prompt, Action step, setup | `docs/proposals/voice-inbox-routine.md` |
| Marker parsing, groups, states | `lib/utils/voice_inbox.dart` |
| Routine fires + reply parsing | `lib/services/voice_inbox_service.dart` |
| Marker pull, food-skips-approval | `lib/services/todoist_sync_service.dart` |
| Approval page (categories, swipes, drag, editor) | `lib/ui/waiting_approval_page.dart` |
| Research round UI / Q&A page | `lib/ui/research_page.dart`, `lib/ui/research_questions_page.dart` |
| Groceries | `lib/ui/groceries_page.dart`, `lib/services/grocery_category_service.dart` |
| Home Todo/MLR/Lemmon toggles | `lib/models/home_contexts.dart`, `ItemViews.isOnHomeScreen` |
| The old routine it replaces | `.claude/notes/pocket-todoist-ingestion.md` |
