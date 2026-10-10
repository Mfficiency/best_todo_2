// The BestToDo sync-file contract, mirrored in TypeScript.
//
// This module is pure (no Obsidian imports) so jest can pin it against the
// Dart side. Everything here must track its Flutter counterpart exactly:
//  * envelope + task parsing  → lib/services/sync_service.dart / lib/models/task.dart
//  * bucketing                → ItemViews.inHomeBucket (lib/services/item_views.dart)
//  * sorting                  → sortTasks (lib/utils/task_utils.dart)
// The app writes `besttodo_tasks.json` atomically (tmp + rename), so a plain
// read-on-change never sees a half-written file.

/** The one envelope version this viewer understands (SPEC §4.7). */
export const SUPPORTED_SYNC_VERSION = 1;

/** Sentinel due date meaning "parked in the Future tab". */
export const FUTURE_SENTINEL = { year: 2300, month: 1, day: 1 };

/** Section titles for the six home buckets, in tab order (SyncMarkdown.sectionTitles). */
export const SECTION_TITLES = [
  "Today",
  "Tomorrow",
  "Day After Tomorrow",
  "Next Week",
  "Next Month",
  "Future",
] as const;

export const FUTURE_TAB_INDEX = 5;

/** The subset of Task.toJson() (schema v2) this viewer renders. */
export interface SyncTask {
  uid: string;
  title: string;
  isDone: boolean;
  /** The deadline: endAt, falling back to the legacy dueDate mirror. */
  dueDate: Date | null;
  completedAt: Date | null;
  deletedAt: Date | null;
  label: string;
  projectId: string | null;
  listRanking: number | null;
  hasExplicitTime: boolean;
  isRecurring: boolean;
}

export interface SyncFile {
  syncVersion: number;
  syncedAt: Date | null;
  appVersion: string;
  taskCount: number;
  tasks: SyncTask[];
}

/** Thrown for envelopes this viewer must refuse (unknown version, not an envelope). */
export class SyncContractError extends Error {}

/**
 * Parses an ISO-8601 timestamp the way Dart's DateTime.tryParse + JS agree on
 * it. Dart writes full local date-times without an offset; a date-only string
 * (hand-edited files) must also mean local, but `new Date("yyyy-MM-dd")`
 * would read it as UTC — so date-only strings get their components pulled out
 * explicitly.
 */
export function parseDate(value: unknown): Date | null {
  if (typeof value !== "string" || value.length === 0) return null;
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (dateOnly) {
    return new Date(
      Number(dateOnly[1]),
      Number(dateOnly[2]) - 1,
      Number(dateOnly[3])
    );
  }
  const parsed = new Date(value);
  return isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * One task, parsed as tolerantly as Task.fromJson: every missing key gets a
 * default, and a v2 record missing endAt falls back to the legacy dueDate.
 */
export function parseTask(json: Record<string, unknown>): SyncTask {
  const legacyDue = parseDate(json["dueDate"]);
  let end = parseDate(json["endAt"]);
  end ??= legacyDue;
  return {
    uid: typeof json["uid"] === "string" ? json["uid"] : "",
    title: typeof json["title"] === "string" ? json["title"] : "",
    isDone: json["isDone"] === true,
    dueDate: end,
    completedAt: parseDate(json["completedAt"]),
    deletedAt: parseDate(json["deletedAt"]),
    label: typeof json["label"] === "string" ? json["label"] : "",
    projectId: typeof json["projectId"] === "string" ? json["projectId"] : null,
    listRanking:
      typeof json["listRanking"] === "number" ? json["listRanking"] : null,
    hasExplicitTime: json["hasExplicitTime"] === true,
    isRecurring: json["isRecurring"] === true,
  };
}

/**
 * Parses the whole sync file. Refuses (SyncContractError) anything that is
 * not a `{sync_version: 1, ...}` envelope so the view can show a friendly
 * notice instead of rendering garbage.
 */
export function parseSyncFile(contents: string): SyncFile {
  let data: unknown;
  try {
    data = JSON.parse(contents);
  } catch {
    throw new SyncContractError("The sync file is not valid JSON.");
  }
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new SyncContractError(
      "The sync file is not a BestToDo sync envelope."
    );
  }
  const envelope = data as Record<string, unknown>;
  const version = envelope["sync_version"];
  if (version !== SUPPORTED_SYNC_VERSION) {
    throw new SyncContractError(
      `Unsupported sync_version ${String(version)} — this plugin understands ` +
        `version ${SUPPORTED_SYNC_VERSION}. Update the plugin or the app.`
    );
  }
  const rawTasks = envelope["tasks"];
  const tasks: SyncTask[] = [];
  if (Array.isArray(rawTasks)) {
    for (const raw of rawTasks) {
      if (typeof raw === "object" && raw !== null && !Array.isArray(raw)) {
        tasks.push(parseTask(raw as Record<string, unknown>));
      }
    }
  }
  return {
    syncVersion: SUPPORTED_SYNC_VERSION,
    syncedAt: parseDate(envelope["synced_at"]),
    appVersion:
      typeof envelope["app_version"] === "string"
        ? envelope["app_version"]
        : "",
    taskCount:
      typeof envelope["task_count"] === "number"
        ? envelope["task_count"]
        : tasks.length,
    tasks,
  };
}

export function isFutureSentinel(date: Date): boolean {
  return (
    date.getFullYear() === FUTURE_SENTINEL.year &&
    date.getMonth() + 1 === FUTURE_SENTINEL.month &&
    date.getDate() === FUTURE_SENTINEL.day
  );
}

/**
 * Date-only distance in days, `dateDiffInDays` (lib/utils/date_utils.dart).
 * Computed over UTC-anchored calendar days so DST transitions cannot skew
 * the division.
 */
export function dateDiffInDays(from: Date, to: Date): number {
  const fromDay = Date.UTC(from.getFullYear(), from.getMonth(), from.getDate());
  const toDay = Date.UTC(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((fromDay - toDay) / 86_400_000);
}

/**
 * The home-tab index for a task, mirroring ItemViews.inHomeBucket: `<= 0`
 * Today (overdue included), 1 Tomorrow, 2 Day After, 3–29 Next Week, 30+
 * Next Month, and the sentinel or no date at all → Future.
 */
export function bucketIndex(task: SyncTask, today: Date): number {
  const due = task.dueDate;
  if (due === null) return FUTURE_TAB_INDEX;
  if (isFutureSentinel(due)) return FUTURE_TAB_INDEX;
  const diff = dateDiffInDays(due, today);
  if (diff <= 0) return 0;
  if (diff === 1) return 1;
  if (diff === 2) return 2;
  if (diff < 30) return 3;
  return 4;
}

/** Open tasks before done ones, then by listRanking with nulls last (sortTasks). */
export function compareTasks(a: SyncTask, b: SyncTask): number {
  const doneCompare = (a.isDone ? 1 : 0) - (b.isDone ? 1 : 0);
  if (doneCompare !== 0) return doneCompare;
  const rankA = a.listRanking ?? 2 ** 31;
  const rankB = b.listRanking ?? 2 ** 31;
  return rankA - rankB;
}

/**
 * The six home buckets in tab order: deleted tasks excluded, each bucket
 * sorted open-first then by ranking — exactly the sections of the Tier 1
 * markdown file and the home tabs.
 */
export function buildBuckets(tasks: SyncTask[], today: Date): SyncTask[][] {
  const buckets: SyncTask[][] = SECTION_TITLES.map(() => []);
  for (const task of tasks) {
    if (task.deletedAt !== null) continue;
    buckets[bucketIndex(task, today)].push(task);
  }
  for (const bucket of buckets) {
    bucket.sort(compareTasks);
  }
  return buckets;
}

const two = (n: number) => String(n).padStart(2, "0");

/** `yyyy-MM-dd`, the date format of the Tier 1 markdown lines. */
export function formatDate(d: Date): string {
  return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`;
}

/** `yyyy-MM-dd HH:mm`, the "Synced …" header format. */
export function formatDateTime(d: Date): string {
  return `${formatDate(d)} ${two(d.getHours())}:${two(d.getMinutes())}`;
}

// --- Tier 3: the change journal (`besttodo_changes.json`) -----------------
//
// Two-way sync (.claude/notes/obsidian-integration.md §Tier 3). The plugin
// never edits besttodo_tasks.json/.md directly — the app overwrites both on
// every sync, so a direct edit would just be clobbered. Instead it appends
// operations here; the app applies them on resume, truncates the file, and
// re-syncs. This module only ever *writes* "complete"/"reopen" (the
// checkbox), but parses the full op vocabulary the app-side importer
// understands (lib/services/sync_import_service.dart) so a future richer
// write surface has somewhere to grow into without a format change.

/** The one journal version this plugin writes. */
export const SUPPORTED_JOURNAL_VERSION = 1;

export interface ChangeOp {
  op: "complete" | "reopen" | "edit" | "create" | "delete";
  uid?: string;
  at: string;
  fields?: Record<string, unknown>;
}

export interface ChangeJournal {
  journal_version: number;
  device: string;
  ops: ChangeOp[];
}

/** The well-defined "nothing pending" state — what the app truncates the
 * journal to once it has applied every op in it. */
export function emptyJournal(device: string): ChangeJournal {
  return { journal_version: SUPPORTED_JOURNAL_VERSION, device, ops: [] };
}

/**
 * Parses the change journal tolerantly: a missing file, invalid JSON, or an
 * unrecognized journal_version all fall back to an empty journal rather than
 * throwing. Refusing on version mismatch is the app importer's job (it must
 * not silently drop another device's ops); this side only ever needs to keep
 * appending, so losing an unreadable journal to "start fresh" is the safer
 * failure than blocking every future checkbox tap on it.
 */
export function parseJournal(contents: string, device: string): ChangeJournal {
  try {
    const data: unknown = JSON.parse(contents);
    if (
      typeof data === "object" &&
      data !== null &&
      !Array.isArray(data) &&
      (data as Record<string, unknown>)["journal_version"] ===
        SUPPORTED_JOURNAL_VERSION &&
      Array.isArray((data as Record<string, unknown>)["ops"])
    ) {
      const envelope = data as Record<string, unknown>;
      return {
        journal_version: SUPPORTED_JOURNAL_VERSION,
        device:
          typeof envelope["device"] === "string"
            ? (envelope["device"] as string)
            : device,
        ops: envelope["ops"] as ChangeOp[],
      };
    }
  } catch {
    // fall through to an empty journal
  }
  return emptyJournal(device);
}

export function serializeJournal(journal: ChangeJournal): string {
  return JSON.stringify(journal);
}

/** Appends [op] to [journal], returning a new journal (pure — no mutation). */
export function appendOp(journal: ChangeJournal, op: ChangeOp): ChangeJournal {
  return { ...journal, ops: [...journal.ops, op] };
}

/** The op a checkbox toggle produces: the inverse of the task's current
 * (pre-toggle) done state. */
export function makeToggleOp(task: SyncTask, at: Date): ChangeOp {
  return {
    op: task.isDone ? "reopen" : "complete",
    uid: task.uid,
    at: at.toISOString(),
  };
}

/** A short id stamped on every op this install writes — not identity, just
 * enough to tell log entries apart if that's ever useful. Generated once
 * and persisted in plugin settings. */
export function generateDeviceId(random: () => number = Math.random): string {
  return `obsidian-${random().toString(36).slice(2, 10)}-${Date.now().toString(36)}`;
}
