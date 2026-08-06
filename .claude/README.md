# .claude — the operational knowledge base for BestToDo

This folder is the layer between "the code" and "the person or AI working on the
code": how to rebuild the app from zero, how to test it, how the automation
works, how to set up an environment, and the engineering principles that made
every past decision. It is written so the project does **not** depend on any
particular AI session, tool, or person — the logic is on paper.

## The documentation system (single source of truth per fact)

Every fact lives in exactly one canonical place; everything else links to it.
When you change something, update its canonical doc — never fork a second copy.

| Document | Canonical for |
|---|---|
| `SPEC.md` (repo root) | **What the app is and does** — every feature, data format, platform mechanism, invariant (§13), and the development history with reasoning. Rebuild-grade; Part I must always describe the current app. |
| `CHANGELOG.md` | The authoritative per-version record (user-facing bullets). |
| `CLAUDE.md` (repo root) | The short operational quickstart: commands, conventions, workflow. First thing a session reads. |
| `test/README.md` | The test-suite map: what each silo covers, which suites to run for which change. |
| `.github/workflows/*.yml` + `tool/*` | The automation itself — the scripts are commented and are their own reference. |
| `docs/architecture/` | Architecture Decision Records (e.g. `storage-decision.md`: why JSON files, what would trigger SQLite). |
| `.claude/notes/` (this folder) | The operational deep dives listed below. |

## Notes in this folder

| File | Read it when |
|---|---|
| [`notes/rebuild-playbook.md`](notes/rebuild-playbook.md) | You need to rebuild the app from scratch, or want the dependency order in which the system fits together. Stage-by-stage plan with verification gates. |
| [`notes/principles.md`](notes/principles.md) | Before designing anything. The three fundamentals, the derived engineering rules, and the meta-lessons 87+ versions paid for. |
| [`notes/testing.md`](notes/testing.md) | Writing or debugging tests. Conventions, the fake-async I/O trap, un-settleable animations, the machine-report pipeline. |
| [`notes/automation.md`](notes/automation.md) | Touching CI, releases, or the tool scripts. All three workflows, the `ci-reports` branch, loop protections, the release flow. |
| [`notes/environment.md`](notes/environment.md) | Setting up a dev machine, a CI runner, or a fresh AI sandbox (Flutter install recipe, what's not available where). |
| [`notes/alarm-work-spec.md`](notes/alarm-work-spec.md) | Touching anything in the alarm/SMS/background pipeline. Session-by-session history of the reliability arc — the bugs, root causes, and why each mechanism exists. |

## How to rebuild the app from scratch

1. Set up an environment — `notes/environment.md`.
2. Read `SPEC.md` Part I top to bottom once; keep §13 (invariants) open.
3. Follow `notes/rebuild-playbook.md` stage by stage; each stage names the SPEC
   sections it implements and the test suite that proves it done.
4. Recreate the automation last — `notes/automation.md`.

## Maintenance rules

- **New feature** → update `SPEC.md` Part I (it must stay rebuild-grade),
  add tests to the matching silo (`test/README.md` if the map changes),
  bump version + `CHANGELOG.md` entry (`dart run tool/bump_version.dart`).
- **New test convention or gotcha** → `notes/testing.md` (and the short form in
  `CLAUDE.md` if every session needs it).
- **CI/workflow change** → `notes/automation.md`.
- **Architecture decision** → an ADR in `docs/architecture/`.
- **Hard-won debugging session** in a new area → a new note here, in the style
  of `alarm-work-spec.md`: what was asked, what was found, what changed and WHY.
