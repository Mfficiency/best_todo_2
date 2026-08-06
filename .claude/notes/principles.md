# Engineering principles — the "good bones" of BestToDo

> Why the app is built the way it is, distilled so decisions can be made from
> logic instead of memory. The hard per-feature invariants are `SPEC.md` §13 —
> read those before touching code; this file is the level above them.

## The three fundamentals (README, unchanged since day one)

1. **Less than 1 second cold startup.**
2. **It must not be possible to do the same thing in fewer clicks/steps.**
3. **Open source.**

Everything below is a consequence of taking these three seriously.

## Derived architecture rules

### 1. No backend, no accounts, no database
All state is plain JSON files in the app documents directory. This is a
*decision with a written trigger for reversal*, not an accident — see
`docs/architecture/storage-decision.md` (revisit at ~5k items / ~2 MB, a
measured startup regression, or real sync). Until a trigger fires, do not add
SQLite/Hive/Isar "because it's proper".

### 2. The startup path is a budget, not a suggestion
`main()` → first frame is measured on every launch (`StartupTimeService`,
charted in-app). Every feature must add **zero** work before the first frame:
load lazily, defer with post-frame callbacks or flag-file-guarded one-shots,
fire-and-forget diagnostics (`unawaited`). The task list itself loads *after*
the first frame. When a feature needs startup work, the burden of proof is on
the feature. (The black-screen bug of 0.1.85 came from awaiting diagnostics in
`main()` — that's why they're fire-and-forget now.)

### 3. Fewest interactions wins arguments
Swipe-with-countdown auto-commit, add-row at the top of every tab, inline
editing, one-tap tools. If a design review stalls, count the taps.

### 4. Trust nothing you didn't read back
"We called schedule()" ≠ "the OS kept it". The alarm pipeline reads back
pending notifications, arms an independent watchdog, and logs every attempt.
Background Android *will* silently fail (manifest receivers, plugin
registration in fresh isolates, OEM power savers, Doze) — each bit this app
separately; see `alarm-work-spec.md`. The response is never just "fix the
bug": build the verification and logging into the pipeline.

### 5. Logs are features
Every debugging pain became a permanent in-app observability tool: App Logs,
alarm_log.txt + alarm doctor, SMS report log, startup times, sync history,
usage-data export, the in-app CI Test Results page. When something is hard to
debug on a device, ship the log viewer.

### 6. Durability by construction
- Atomic writes everywhere it matters: `SafeFile` tmp → rotate `.bak` → rename;
  per-path write chains against races.
- Corruption recovery: unparseable files are quarantined
  (`.corrupt-<timestamp>`), never overwritten; `.bak` used instead.
- Tolerant parsing: every `fromJson` defaults missing keys; unknown keys are
  ignored. Old exports must always import.
- One-shot migrations are guarded by flag files (`*_v1.txt`) so they run once
  per install and user deletions stick.
- Pre-update snapshot before the first write of a session, once per install.

### 7. Single source of truth in code, too
One rule, one place: `TestReport.newest` decides "latest run" everywhere;
`ItemViews` is the one query layer over the one task list; `TaskWidgetService`
builds the widget payload for both foreground and background;
`diceRingPayload` feeds both ring paths; `tool/render_test_report_summary.dart`
renders CI's summary from the same JSON the app parses. When two places can
disagree, refactor until they can't.

### 8. Deterministic, collision-free identity
Uuid-v4 for entities, uniqueness re-enforced on every load/import. Alarm
notification ids are pure functions of the uid (`base = (hash & 0x1FFFFFF)*8`
plus fixed offsets), so every isolate can find an alarm's notifications without
shared state.

### 9. Compatibility is part of the data model
JSON keys equal field names; new fields are optional-with-default; removed
behavior keeps serializing (`snoozeMaxCount`); schema upgrades happen inside
the parse (`schemaVersion`, `dueDate` ⇄ `startAt`/`endAt` mirror) so downgrades
and old imports keep working. Android notification channels are immutable —
changes need a new channel id (`_v2`).

### 10. Iterate in public, in small versions
87+ released versions in ~14 months. Ship rough, refine over consecutive patch
versions, keep the changelog honest (including the mistakes — read the 0.1.36
entry). Every feature batch bumps the version and gets a changelog entry.

### 11. Tests are siloed, and core is sacred
`test/core/` must always pass and runs for every change; feature silos run when
their area is touched; CI runs everything. A build is gated on a smoke test
(`tool/build.sh`). Test results are themselves a feature (packaged into every
build, red dot in the app when CI is red).

### 12. Documentation is part of done
`SPEC.md` Part I must stay rebuild-grade — a feature that isn't in the spec
isn't finished. Deep debugging sessions get a note in `.claude/notes/` (what
was asked, found, changed, and WHY) so nobody re-derives them.

## Meta-lessons (paid for in real bugs)

- **Asymmetry is the best diagnostic.** "Send test now works but the scheduled
  send doesn't" located the missing manifest receiver. Build test buttons that
  bypass the scheduled path on purpose.
- **Plugins lie by omission.** `periodic(exact: true)` silently maps to inexact
  `setRepeating`; the alarm plugin ships an empty manifest. When background
  behavior matters, read the plugin's Java/Kotlin source, not its README.
- **OEMs are part of the platform.** Samsung "Sleeping apps" et al. silently
  drop alarms; the app requests battery-optimization exemption and ships
  per-OEM hints in the alarm doctor.
- **Quirks documented beat quirks "fixed".** The Kotlin folder/package
  mismatch, the committed debug keystore, the stats heatmap's historical
  mislabel — all intentional or accepted, all documented (SPEC §13). Blind
  cleanups have broken builds before.
- **Release ≠ debug.** R8 full mode stripped Gson generics and broke *every*
  alarm schedule in release builds only (0.1.85–87). Keep
  `android/app/proguard-rules.pro`; test-drive release APKs on hardware.
