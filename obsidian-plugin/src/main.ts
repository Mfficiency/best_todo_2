import {
  App,
  Notice,
  Plugin,
  PluginSettingTab,
  Setting,
  TAbstractFile,
  WorkspaceLeaf,
  normalizePath,
} from "obsidian";
import {
  ChangeOp,
  SyncContractError,
  SyncFile,
  appendOp,
  emptyJournal,
  generateDeviceId,
  parseJournal,
  parseSyncFile,
  serializeJournal,
} from "./model";
import { BestToDoView, VIEW_TYPE_BESTTODO } from "./view";

/** Fixed file name for the Tier 3 change journal, written next to the sync
 * JSON (same folder — `syncFilePath`'s directory). */
const CHANGE_JOURNAL_FILE_NAME = "besttodo_changes.json";

interface BestToDoSettings {
  /** Vault-relative path to the synced JSON file (default: vault root). */
  syncFilePath: string;
  /** Stable per-vault id stamped on every op this install writes into the
   * change journal. Generated once on first load, then persisted. */
  deviceId: string;
}

const DEFAULT_SETTINGS: BestToDoSettings = {
  syncFilePath: "besttodo_tasks.json",
  deviceId: "",
};

/**
 * BestToDo Tasks — Tiers 2 and 3 of the Obsidian integration
 * (.claude/notes/obsidian-integration.md). Renders the `besttodo_tasks.json`
 * file the app's synced mode writes into a folder routed into this vault
 * (Tier 2), and lets a checkbox tap flow back to the phone (Tier 3) by
 * appending an operation to `besttodo_changes.json` next to it — never by
 * editing the sync file itself, which the app overwrites on every sync.
 */
export default class BestToDoPlugin extends Plugin {
  settings: BestToDoSettings = { ...DEFAULT_SETTINGS };

  async onload(): Promise<void> {
    await this.loadSettings();

    this.registerView(
      VIEW_TYPE_BESTTODO,
      (leaf) => new BestToDoView(leaf, this)
    );

    this.addRibbonIcon("check-circle", "Open BestToDo tasks", () => {
      void this.activateView();
    });

    this.addCommand({
      id: "open-view",
      name: "Open task view",
      callback: () => void this.activateView(),
    });

    // The app's write is atomic (tmp + rename), so any modify event for the
    // sync file means a complete new snapshot is on disk.
    this.registerEvent(
      this.app.vault.on("modify", (file: TAbstractFile) => {
        if (file.path === normalizePath(this.settings.syncFilePath)) {
          void this.refreshViews();
        }
      })
    );
    this.registerEvent(
      this.app.vault.on("create", (file: TAbstractFile) => {
        if (file.path === normalizePath(this.settings.syncFilePath)) {
          void this.refreshViews();
        }
      })
    );

    this.addSettingTab(new BestToDoSettingTab(this.app, this));
  }

  onunload(): void {
    // Obsidian detaches the registered view and events itself.
  }

  /** Reads and parses the sync file; throws SyncContractError on refusal. */
  async readSyncFile(): Promise<SyncFile> {
    const path = normalizePath(this.settings.syncFilePath);
    const adapter = this.app.vault.adapter;
    if (!(await adapter.exists(path))) {
      throw new SyncContractError(
        `"${path}" was not found in this vault. Point the BestToDo sync ` +
          "folder into the vault, or set the file path in the plugin settings."
      );
    }
    const contents = await adapter.read(path);
    return parseSyncFile(contents);
  }

  /** Vault-relative path of the change journal: same folder as the sync
   * file, so pointing `syncFilePath` at the right place is the only setting
   * needed for both tiers. */
  private journalPath(): string {
    const syncPath = normalizePath(this.settings.syncFilePath);
    const slash = syncPath.lastIndexOf("/");
    const dir = slash === -1 ? "" : syncPath.slice(0, slash);
    return normalizePath(
      dir ? `${dir}/${CHANGE_JOURNAL_FILE_NAME}` : CHANGE_JOURNAL_FILE_NAME
    );
  }

  /**
   * Appends one operation to the change journal (Tier 3). Reads the current
   * journal first — appending, not overwriting, so any op still unread by
   * the app (it only imports on resume) survives alongside this one. An
   * unreadable existing journal starts fresh rather than blocking the tap;
   * the app treats a malformed journal as a skip on its own side, so a
   * corrupt file wouldn't have made progress anyway.
   */
  async appendChangeOp(op: ChangeOp): Promise<void> {
    const path = this.journalPath();
    const adapter = this.app.vault.adapter;
    let journal = emptyJournal(this.settings.deviceId);
    if (await adapter.exists(path)) {
      try {
        journal = parseJournal(await adapter.read(path), this.settings.deviceId);
      } catch {
        // Unreadable journal: fall through with the fresh empty one.
      }
    }
    await adapter.write(path, serializeJournal(appendOp(journal, op)));
  }

  async activateView(): Promise<void> {
    const { workspace } = this.app;
    const existing = workspace.getLeavesOfType(VIEW_TYPE_BESTTODO);
    let leaf: WorkspaceLeaf | null;
    if (existing.length > 0) {
      leaf = existing[0];
    } else {
      leaf = workspace.getRightLeaf(false);
      if (leaf === null) {
        new Notice("Could not open the BestToDo view.");
        return;
      }
      await leaf.setViewState({ type: VIEW_TYPE_BESTTODO, active: true });
    }
    void workspace.revealLeaf(leaf);
  }

  async refreshViews(): Promise<void> {
    for (const leaf of this.app.workspace.getLeavesOfType(
      VIEW_TYPE_BESTTODO
    )) {
      const view = leaf.view;
      if (view instanceof BestToDoView) {
        await view.refresh();
      }
    }
  }

  async loadSettings(): Promise<void> {
    this.settings = { ...DEFAULT_SETTINGS, ...((await this.loadData()) ?? {}) };
    if (!this.settings.deviceId) {
      this.settings.deviceId = generateDeviceId();
      await this.saveData(this.settings);
    }
  }

  async saveSettings(): Promise<void> {
    await this.saveData(this.settings);
    await this.refreshViews();
  }
}

class BestToDoSettingTab extends PluginSettingTab {
  plugin: BestToDoPlugin;

  constructor(app: App, plugin: BestToDoPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();
    new Setting(containerEl)
      .setName("Sync file path")
      .setDesc(
        "Vault-relative path to besttodo_tasks.json (the file BestToDo's " +
          "synced mode writes). Default: vault root. Checking a task off " +
          "here writes to besttodo_changes.json in the same folder — no " +
          "separate setting for it."
      )
      .addText((text) =>
        text
          .setPlaceholder(DEFAULT_SETTINGS.syncFilePath)
          .setValue(this.plugin.settings.syncFilePath)
          .onChange(async (value) => {
            this.plugin.settings.syncFilePath =
              value.trim() === "" ? DEFAULT_SETTINGS.syncFilePath : value.trim();
            await this.plugin.saveSettings();
          })
      );
  }
}
