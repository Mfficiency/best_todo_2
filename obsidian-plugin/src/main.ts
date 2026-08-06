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
import { SyncContractError, SyncFile, parseSyncFile } from "./model";
import { BestToDoView, VIEW_TYPE_BESTTODO } from "./view";

interface BestToDoSettings {
  /** Vault-relative path to the synced JSON file (default: vault root). */
  syncFilePath: string;
}

const DEFAULT_SETTINGS: BestToDoSettings = {
  syncFilePath: "besttodo_tasks.json",
};

/**
 * BestToDo Tasks — Tier 2 of the Obsidian integration
 * (.claude/notes/obsidian-integration.md): a strictly read-only view over
 * the `besttodo_tasks.json` file that the app's synced mode writes into a
 * folder routed into this vault. The app overwrites the file atomically on
 * every sync, so re-reading on Obsidian's file-change event is always safe.
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
          "synced mode writes). Default: vault root."
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
