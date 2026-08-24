// Pins the plugin's side of the sync-file contract, mirroring the Dart cases
// in test/sync/sync_markdown_test.dart so both readers of the format are
// tested against the same expectations.
import {
  SECTION_TITLES,
  SUPPORTED_SYNC_VERSION,
  SyncContractError,
  SyncTask,
  appendOp,
  bucketIndex,
  buildBuckets,
  dateDiffInDays,
  emptyJournal,
  formatDate,
  formatDateTime,
  generateDeviceId,
  isFutureSentinel,
  makeToggleOp,
  parseJournal,
  parseSyncFile,
  parseTask,
  serializeJournal,
} from "../src/model";

const now = new Date(2026, 7, 6, 14, 30); // 2026-08-06 14:30 local

const addDays = (base: Date, days: number): Date =>
  new Date(
    base.getFullYear(),
    base.getMonth(),
    base.getDate() + days,
    base.getHours(),
    base.getMinutes()
  );

const sentinel = new Date(2300, 0, 1);

let uidCounter = 0;
const task = (overrides: Partial<SyncTask>): SyncTask => ({
  uid: `uid-${uidCounter++}`,
  title: "Task",
  isDone: false,
  dueDate: null,
  completedAt: null,
  deletedAt: null,
  label: "",
  projectId: null,
  listRanking: null,
  hasExplicitTime: false,
  isRecurring: false,
  ...overrides,
});

describe("bucketing", () => {
  test("tasks land in the same buckets as the home tabs", () => {
    const buckets = buildBuckets(
      [
        task({ title: "Overdue", dueDate: addDays(now, -3) }),
        task({ title: "Due today", dueDate: now }),
        task({ title: "Due tomorrow", dueDate: addDays(now, 1) }),
        task({ title: "Day after", dueDate: addDays(now, 2) }),
        task({ title: "This week", dueDate: addDays(now, 10) }),
        task({ title: "Next month", dueDate: addDays(now, 45) }),
        task({ title: "Someday" }),
        task({ title: "Parked", dueDate: sentinel }),
      ],
      now
    );

    const titles = buckets.map((b) => b.map((t) => t.title));
    expect(titles).toEqual([
      ["Overdue", "Due today"],
      ["Due tomorrow"],
      ["Day after"],
      ["This week"],
      ["Next month"],
      ["Someday", "Parked"],
    ]);
  });

  test("bucket boundaries: 3 and 29 days are Next Week, 30 is Next Month", () => {
    expect(bucketIndex(task({ dueDate: addDays(now, 3) }), now)).toBe(3);
    expect(bucketIndex(task({ dueDate: addDays(now, 29) }), now)).toBe(3);
    expect(bucketIndex(task({ dueDate: addDays(now, 30) }), now)).toBe(4);
  });

  test("the 2300-01-01 sentinel and missing dates both mean Future", () => {
    expect(isFutureSentinel(sentinel)).toBe(true);
    expect(bucketIndex(task({ dueDate: sentinel }), now)).toBe(5);
    expect(bucketIndex(task({}), now)).toBe(5);
  });

  test("deleted tasks are excluded from every bucket", () => {
    const buckets = buildBuckets(
      [
        task({ title: "Kept", dueDate: now }),
        task({ title: "Trashed", dueDate: now, deletedAt: now }),
      ],
      now
    );
    expect(buckets[0].map((t) => t.title)).toEqual(["Kept"]);
    expect(buckets.flat()).toHaveLength(1);
  });

  test("each bucket sorts open tasks before done ones, by ranking", () => {
    const buckets = buildBuckets(
      [
        task({ title: "Done early", dueDate: now, isDone: true, listRanking: 0 }),
        task({ title: "Second", dueDate: now, listRanking: 2 }),
        task({ title: "First", dueDate: now, listRanking: 1 }),
        task({ title: "Unranked", dueDate: now }),
      ],
      now
    );
    expect(buckets[0].map((t) => t.title)).toEqual([
      "First",
      "Second",
      "Unranked",
      "Done early",
    ]);
  });

  test("date-only distance ignores the time of day", () => {
    // 23:59 today to 00:00 tomorrow is one day, not zero.
    const lateTonight = new Date(2026, 7, 6, 23, 59);
    const earlyTomorrow = new Date(2026, 7, 7, 0, 0);
    expect(dateDiffInDays(earlyTomorrow, lateTonight)).toBe(1);
    expect(bucketIndex(task({ dueDate: earlyTomorrow }), lateTonight)).toBe(1);
  });

  test("there are exactly the six home sections, in tab order", () => {
    expect(SECTION_TITLES).toEqual([
      "Today",
      "Tomorrow",
      "Day After Tomorrow",
      "Next Week",
      "Next Month",
      "Future",
    ]);
  });
});

describe("task parsing (Task.fromJson tolerance)", () => {
  test("a full schema-v2 record round-trips the fields the view renders", () => {
    const parsed = parseTask({
      schemaVersion: 2,
      uid: "abc-123",
      title: "Buy milk",
      label: "errand",
      startAt: "2026-08-06T18:00:00.000",
      endAt: "2026-08-06T18:00:00.000",
      dueDate: "2026-08-06T18:00:00.000",
      completedAt: "2026-08-05T09:00:00.000",
      isDone: true,
      hasExplicitTime: true,
      listRanking: 3,
      isRecurring: true,
      projectId: "proj-1",
      kanbanStatus: "todo",
    });
    expect(parsed.uid).toBe("abc-123");
    expect(parsed.title).toBe("Buy milk");
    expect(parsed.label).toBe("errand");
    expect(parsed.isDone).toBe(true);
    expect(parsed.hasExplicitTime).toBe(true);
    expect(parsed.listRanking).toBe(3);
    expect(parsed.isRecurring).toBe(true);
    expect(parsed.projectId).toBe("proj-1");
    expect(formatDate(parsed.dueDate!)).toBe("2026-08-06");
    expect(formatDate(parsed.completedAt!)).toBe("2026-08-05");
  });

  test("missing keys get defaults, exactly like Task.fromJson", () => {
    const parsed = parseTask({});
    expect(parsed.title).toBe("");
    expect(parsed.isDone).toBe(false);
    expect(parsed.dueDate).toBeNull();
    expect(parsed.completedAt).toBeNull();
    expect(parsed.deletedAt).toBeNull();
    expect(parsed.label).toBe("");
    expect(parsed.projectId).toBeNull();
    expect(parsed.listRanking).toBeNull();
  });

  test("a record missing endAt falls back to the legacy dueDate mirror", () => {
    const parsed = parseTask({
      title: "Legacy",
      dueDate: "2026-08-07T18:00:00.000",
    });
    expect(formatDate(parsed.dueDate!)).toBe("2026-08-07");
  });

  test("a date-only string is read as a local date, not UTC", () => {
    const parsed = parseTask({ title: "Hand edited", endAt: "2026-08-06" });
    expect(formatDate(parsed.dueDate!)).toBe("2026-08-06");
  });
});

describe("envelope parsing", () => {
  const envelope = (overrides: Record<string, unknown>): string =>
    JSON.stringify({
      sync_version: SUPPORTED_SYNC_VERSION,
      synced_at: "2026-08-06T14:30:00.000",
      app_version: "0.1.140+112",
      task_count: 0,
      tasks: [],
      ...overrides,
    });

  test("a valid envelope parses with header fields intact", () => {
    const file = parseSyncFile(
      envelope({ tasks: [{ title: "Only", isDone: false }], task_count: 1 })
    );
    expect(file.syncVersion).toBe(1);
    expect(file.appVersion).toBe("0.1.140+112");
    expect(file.taskCount).toBe(1);
    expect(file.tasks).toHaveLength(1);
    expect(formatDateTime(file.syncedAt!)).toBe("2026-08-06 14:30");
  });

  test("an unknown sync_version is refused with a friendly message", () => {
    expect(() => parseSyncFile(envelope({ sync_version: 2 }))).toThrow(
      SyncContractError
    );
    expect(() => parseSyncFile(envelope({ sync_version: 2 }))).toThrow(
      /Unsupported sync_version 2/
    );
  });

  test("a missing sync_version is refused too", () => {
    const raw = JSON.parse(envelope({}));
    delete raw.sync_version;
    expect(() => parseSyncFile(JSON.stringify(raw))).toThrow(SyncContractError);
  });

  test("non-JSON and non-envelope contents are refused, never thrown raw", () => {
    expect(() => parseSyncFile("not json at all")).toThrow(SyncContractError);
    expect(() => parseSyncFile('"just a string"')).toThrow(SyncContractError);
    expect(() => parseSyncFile("[1, 2, 3]")).toThrow(SyncContractError);
  });

  test("malformed task entries are skipped, valid ones kept", () => {
    const file = parseSyncFile(
      envelope({ tasks: [{ title: "Good" }, "bogus", 42, null] })
    );
    expect(file.tasks.map((t) => t.title)).toEqual(["Good"]);
  });
});

describe("the change journal (Tier 3)", () => {
  test("makeToggleOp completes an open task and reopens a done one", () => {
    const at = new Date(2026, 7, 6, 9, 0);
    const open = task({ isDone: false });
    expect(makeToggleOp(open, at)).toEqual({
      op: "complete",
      uid: open.uid,
      at: at.toISOString(),
    });

    const done = task({ isDone: true });
    expect(makeToggleOp(done, at)).toEqual({
      op: "reopen",
      uid: done.uid,
      at: at.toISOString(),
    });
  });

  test("appendOp is pure: it returns a new journal and leaves the old one alone", () => {
    const original = emptyJournal("obsidian-1");
    const op = makeToggleOp(task({}), new Date());
    const updated = appendOp(original, op);

    expect(original.ops).toHaveLength(0);
    expect(updated.ops).toEqual([op]);
    expect(updated).not.toBe(original);
  });

  test("serializeJournal round-trips through parseJournal", () => {
    const op = makeToggleOp(task({}), new Date());
    const journal = appendOp(emptyJournal("obsidian-1"), op);

    const parsed = parseJournal(serializeJournal(journal), "obsidian-1");

    expect(parsed).toEqual(journal);
  });

  test("a missing or malformed journal parses as empty, never throws", () => {
    expect(parseJournal("", "obsidian-1")).toEqual(emptyJournal("obsidian-1"));
    expect(parseJournal("not json", "obsidian-1")).toEqual(
      emptyJournal("obsidian-1")
    );
    expect(parseJournal("[1,2,3]", "obsidian-1")).toEqual(
      emptyJournal("obsidian-1")
    );
  });

  test("an unsupported journal_version parses as empty rather than clobbering it", () => {
    const raw = JSON.stringify({
      journal_version: 99,
      device: "obsidian-1",
      ops: [{ op: "complete", uid: "x", at: "2026-08-06T09:00:00.000Z" }],
    });
    expect(parseJournal(raw, "obsidian-1")).toEqual(emptyJournal("obsidian-1"));
  });

  test("parseJournal keeps ops already in the file when appending is not involved", () => {
    const existingOp = {
      op: "complete" as const,
      uid: "existing",
      at: "2026-08-06T09:00:00.000Z",
    };
    const raw = JSON.stringify({
      journal_version: 1,
      device: "obsidian-1",
      ops: [existingOp],
    });
    expect(parseJournal(raw, "obsidian-1").ops).toEqual([existingOp]);
  });

  test("generateDeviceId is stable in shape and varies per call", () => {
    let counter = 0;
    const fakeRandom = () => {
      counter += 1;
      return counter / 10;
    };
    const first = generateDeviceId(fakeRandom);
    const second = generateDeviceId(fakeRandom);
    expect(first).toMatch(/^obsidian-[a-z0-9]+-[a-z0-9]+$/);
    expect(first).not.toEqual(second);
  });
});
