import { ItemView, Notice, WorkspaceLeaf } from "obsidian";
import {
  SECTION_TITLES,
  SyncContractError,
  SyncFile,
  SyncTask,
  buildBuckets,
  formatDate,
  formatDateTime,
  isFutureSentinel,
  makeToggleOp,
} from "./model";
import type BestToDoPlugin from "./main";

export const VIEW_TYPE_BESTTODO = "besttodo-tasks";

/**
 * The task view: the six home buckets, checkbox + title + due date,
 * label/project chips, open-first ordering, and an "as of …" line so the
 * user can see how fresh the data is (the file only updates when the app is
 * backgrounded). Tier 2 was strictly read-only; Tier 3 makes the checkbox
 * live — a tap appends a complete/reopen op to the change journal, updates
 * the view optimistically, and shows a "syncing…" chip until a refreshed
 * `besttodo_tasks.json` confirms the app picked it up (on its next resume).
 */
export class BestToDoView extends ItemView {
  private plugin: BestToDoPlugin;

  /** uid → the isDone value a checkbox tap is waiting to see confirmed by a
   * fresh read of the sync file. Cleared once the file agrees, so a pending
   * marker never outlives its own op. */
  private pending = new Map<string, boolean>();

  /** The last successfully parsed sync file, so a checkbox tap can
   * re-render optimistically without waiting on a fresh (and, right after
   * the tap, still stale) read of besttodo_tasks.json. */
  private lastFile: SyncFile | null = null;

  constructor(leaf: WorkspaceLeaf, plugin: BestToDoPlugin) {
    super(leaf);
    this.plugin = plugin;
  }

  getViewType(): string {
    return VIEW_TYPE_BESTTODO;
  }

  getDisplayText(): string {
    return "BestToDo tasks";
  }

  getIcon(): string {
    return "check-circle";
  }

  async onOpen(): Promise<void> {
    await this.refresh();
  }

  /** Re-reads the sync file and re-renders; called on open and file change. */
  async refresh(): Promise<void> {
    const container = this.contentEl;
    container.empty();
    container.addClass("besttodo-view");

    let file: SyncFile;
    try {
      file = await this.plugin.readSyncFile();
    } catch (error) {
      this.renderError(container, error);
      return;
    }
    this.lastFile = file;
    // A pending tap is confirmed once the freshly read file agrees with it;
    // an unconfirmed one (the app hasn't resumed yet) keeps its "syncing…"
    // marker across this refresh.
    for (const task of file.tasks) {
      if (this.pending.get(task.uid) === task.isDone) {
        this.pending.delete(task.uid);
      }
    }
    this.renderFile(container, file);
  }

  private renderError(container: HTMLElement, error: unknown): void {
    const message =
      error instanceof SyncContractError
        ? error.message
        : `Could not read "${this.plugin.settings.syncFilePath}". ` +
          "Check the file path in the BestToDo Tasks settings.";
    container.createEl("div", {
      cls: "besttodo-error",
      text: message,
    });
  }

  private renderFile(container: HTMLElement, file: SyncFile): void {
    const header = container.createEl("div", { cls: "besttodo-header" });
    const open = file.tasks.filter(
      (t) => t.deletedAt === null && !t.isDone
    ).length;
    const total = file.tasks.filter((t) => t.deletedAt === null).length;
    header.createEl("div", {
      cls: "besttodo-counts",
      text: `${open} open / ${total} total`,
    });
    if (file.syncedAt !== null) {
      header.createEl("div", {
        cls: "besttodo-synced-at",
        text:
          `as of ${formatDateTime(file.syncedAt)}` +
          (file.appVersion ? ` · BestToDo ${file.appVersion}` : ""),
      });
    }

    const buckets = buildBuckets(file.tasks, new Date());
    let any = false;
    for (let tab = 0; tab < SECTION_TITLES.length; tab++) {
      const bucket = buckets[tab];
      if (bucket.length === 0) continue;
      any = true;
      const section = container.createEl("div", { cls: "besttodo-section" });
      section.createEl("h4", {
        cls: "besttodo-section-title",
        text: SECTION_TITLES[tab],
      });
      const list = section.createEl("div", { cls: "besttodo-list" });
      for (const task of bucket) {
        this.renderTask(list, task);
      }
    }
    if (!any) {
      container.createEl("div", {
        cls: "besttodo-empty",
        text: "No tasks in the sync file.",
      });
    }
  }

  private renderTask(list: HTMLElement, task: SyncTask): void {
    const isPending = this.pending.has(task.uid);
    const effectiveDone = isPending ? this.pending.get(task.uid)! : task.isDone;
    const row = list.createEl("div", {
      cls: effectiveDone ? "besttodo-task is-done" : "besttodo-task",
    });
    const checkbox = row.createEl("input", {
      cls: "besttodo-checkbox",
      type: "checkbox",
    });
    checkbox.checked = effectiveDone;
    // A tap already in flight can't be retapped until it's confirmed —
    // avoids appending a second, redundant op for the same toggle.
    checkbox.disabled = isPending;
    checkbox.addEventListener("change", () => {
      void this.toggleTask(task);
    });

    const body = row.createEl("div", { cls: "besttodo-task-body" });
    body.createEl("span", { cls: "besttodo-title", text: task.title });
    if (isPending) {
      body.createEl("span", {
        cls: "besttodo-chip besttodo-pending",
        text: "syncing…",
      });
    }

    const due = task.dueDate;
    if (due !== null && !isFutureSentinel(due)) {
      body.createEl("span", {
        cls: "besttodo-date",
        text: `📅 ${formatDate(due)}`,
      });
    }
    if (task.isDone && task.completedAt !== null) {
      body.createEl("span", {
        cls: "besttodo-date",
        text: `✅ ${formatDate(task.completedAt)}`,
      });
    }
    if (task.isRecurring) {
      body.createEl("span", { cls: "besttodo-date", text: "🔁" });
    }
    if (task.label !== "") {
      body.createEl("span", { cls: "besttodo-chip", text: task.label });
    }
    if (task.projectId !== null) {
      // The sync file carries tasks only (no projects.json), so the project
      // name is not available — a generic chip marks project membership.
      const chip = body.createEl("span", {
        cls: "besttodo-chip besttodo-chip-project",
        text: "📁 project",
      });
      chip.setAttribute("title", task.projectId);
    }
  }

  /** Appends the checkbox's op to the change journal, marks the task
   * pending, and re-renders immediately from the last known file — the sync
   * file itself won't reflect the change until the app next resumes. Reverts
   * on failure (journal folder gone, vault write denied) with a Notice. */
  private async toggleTask(task: SyncTask): Promise<void> {
    this.pending.set(task.uid, !task.isDone);
    this.renderFromCache();
    try {
      await this.plugin.appendChangeOp(makeToggleOp(task, new Date()));
    } catch (error) {
      this.pending.delete(task.uid);
      this.renderFromCache();
      new Notice(
        `Could not record the change: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }
  }

  private renderFromCache(): void {
    if (this.lastFile === null) return;
    const container = this.contentEl;
    container.empty();
    container.addClass("besttodo-view");
    this.renderFile(container, this.lastFile);
  }

  async onClose(): Promise<void> {
    this.contentEl.empty();
  }
}
