import { ItemView, WorkspaceLeaf } from "obsidian";
import {
  SECTION_TITLES,
  SyncContractError,
  SyncFile,
  SyncTask,
  buildBuckets,
  formatDate,
  formatDateTime,
  isFutureSentinel,
} from "./model";
import type BestToDoPlugin from "./main";

export const VIEW_TYPE_BESTTODO = "besttodo-tasks";

/**
 * The read-only task view: the six home buckets, checkbox + title + due
 * date, label/project chips, open-first ordering, and an "as of …" line so
 * the user can see how fresh the data is (the file only updates when the
 * app is backgrounded). It never writes anything — checkboxes are disabled.
 */
export class BestToDoView extends ItemView {
  private plugin: BestToDoPlugin;

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
    const row = list.createEl("div", {
      cls: task.isDone ? "besttodo-task is-done" : "besttodo-task",
    });
    const checkbox = row.createEl("input", {
      cls: "besttodo-checkbox",
      type: "checkbox",
    });
    checkbox.checked = task.isDone;
    // Strictly a viewer (Tier 2): the checkbox is state, not a control.
    checkbox.disabled = true;

    const body = row.createEl("div", { cls: "besttodo-task-body" });
    body.createEl("span", { cls: "besttodo-title", text: task.title });

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

  async onClose(): Promise<void> {
    this.contentEl.empty();
  }
}
