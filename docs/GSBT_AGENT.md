# Game Save Backup Tool — Agent Manual

**Version:** aligns with `agentDocumentation.notebookVersion` from `gsbt help --ai` (currently 2026-11-23.1)

**Audience:** AI agents and automation (Cursor, Codex, Claude Code, Antigravity, scripts).  
**Humans:** use `gsbt help` or `gsbt gui`.

This is the **one document** to load and retain. You do **not** need `gsbt help --ai` on every user message.

---

## Platform filenames (same content)

If your tool expects a specific name, **copy this file verbatim** — do not paraphrase:

| Platform / convention | Filename or path |
|----------------------|------------------|
| **Universal (default)** | `src-winui/docs/AGENTS.md` |
| **GSBT-branded** | `src-winui/docs/GSBT_AGENT.md` (identical copy) |
| **Installed CLI** | `%LocalAppData%\Game Save Backup Tool\docs\AGENTS.md` |
| **Cursor** | `.agents/skills/gsbt-cli/SKILL.md` (skill wrapper; points to this file) |
| **GitHub raw** | `https://raw.githubusercontent.com/Xeworth/gsbt-releases/main/docs/AGENTS.md` |

After copying, **lock this manual in session memory**. Only re-run `gsbt help --ai` when `notebookVersion` changes.

---

## One-time bootstrap (per session)

1. **Read this file** (you are here).
2. Run **`gsbt help --ai` once** and retain:
   - `agentDocumentation` — paths and `notebookVersion`
   - `agentNotebook` — product facts, migrate safety, compression behavior
   - `commands`, `recommendedFlow`, `postReinstallFlow`
3. Run **`gsbt status --ai`** before the first command that changes backups, the catalog, or settings.

**Refresh `help --ai` only when:** GSBT was updated, `notebookVersion` changed, or you hit an unknown error code / JSON shape.

---

## Golden rules

| Do | Don't |
|----|--------|
| `gsbt <command> … --ai` for every automated step | `gsbt cli` (human REPL only) |
| Parse **one** final JSON object from **stdout** | Treat stderr progress as success/failure |
| Watch **stderr** during backup/compress/migrate/scan | Assume hang when stdout is quiet |
| `migrate --dry-run` before `migrate --yes` | Skip preview on post-reinstall restores |
| `catalog import` before migrate on a fresh PC | Invent save paths from the web |
| User approval for `--replace`, `--replace-all`, destructive restore | Overwrite without consent |
| Dry-run + plain-language risk summary before restore/migrate | “Something went wrong” with no reason or next step |

---

## Operating mindset

Act as a **data preservation specialist**. Integrity beats speed.

- Ambiguous request → `gsbt status --ai`, then propose a plan. Do not start copying files.
- Risky steps (`restore`, `migrate`, catalog `--replace`, `--replace-all`): preview where supported, explain what will be overwritten, and obtain explicit authorization unless the user already authorized this specific scope. Do not ask again for approval already given. Catalog import has no dry-run flag: inspect the export and save a catalog export before replacement.
- Never invent save paths, never create empty folders so a command “succeeds,” never register whole drives or system directories.

## Read `status` before mutating

| Field | How to use it |
|-------|----------------|
| `install.guiInstalled` | CLI-only vs full install. Automate with `--ai` either way; do not drive the GUI. |
| `catalogCount` | Scope. Large catalogs: target by index or name unless the user asked for everything. |
| `backup.path` / `backup.configured` | Confirm this destination matches the user before backup or compress. If unset: `gsbt settings backup-path` after they approve, or `--path`. |
| `backup.retention` | Keep-N setting (runs kept per game). Not a live count of folders on disk. |
| `manifest.valid` | If `false`, warn that the game database may be stale before `scan`. |

If the user gives a **relative** path, resolve it against the current working directory and verify it exists before passing it to GSBT.

## Targeting games

From `gsbt list --ai`, treat `games[]` as the index.

1. Exact name match
2. Partial / fuzzy match — if more than one candidate, **ask**
3. Numeric index when the user gave one

`backupable` / `compressible` are the eligibility gates. After `scan --ai`: `detectedCount` = installed titles detected; `scannedCount` = titles checked this run, including titles without a resolved save location. Backup from **`gsbt list found --ai`** and its eligibility flags, not from scan counts alone.

Numeric targets use the most recently listed filter and rebuild the catalog view at execution time. Row numbers can change after a scan, import, GUI edit, or another CLI session. List immediately before using numbers, check the names, and prefer a unique quoted name for a later operation. There is no stable-ID or frozen-snapshot guarantee.

Name collision (two “Delta Force” rows, legacy vs reboot): ask which edition and check path/size before backup.

---

## `--ai` mode contract

- **`--ai`** implies machine JSON on stdout and **non-interactive** behavior (no prompts).
- **Progress** = newline-delimited JSON on **stderr** (`"type": "progress"`).
- **Success** = final stdout JSON with `"success": true` (plus command-specific fields).
- **Common errors:** `confirmation_required` → inspect a dry-run and obtain any missing authorization before adding `--yes`; migrate `index_missing` → inspect the source, then use `--smart-match` and/or import the catalog. An error is never permission to bypass confirmation.
- Missing arguments and parser errors return `success: false`, `error.code: "invalid_arguments"`, and exit 1. `cli` and `gui` reject machine mode without opening an interactive interface. Root `--ai`, machine `--help`, and machine `--version` return JSON.

**Exit codes — translate and act:**

| Code | Meaning | Agent action |
|------|---------|--------------|
| `0` | Success | Confirm what finished (paths, `runId`, bytes when present). |
| `1` | User/config (path, flags, empty catalog) | Quote the error; ask the user to correct it. Do not dump diagnostics yet. |
| `2` | Runtime / internal | Run `gsbt diagnostics --ai` and report a concrete next step. |
| `3` | Unsafe restore target | Do not retry blindly; explain the target is blocked. |
| `4` | Insufficient space | Name the target drive; suggest freeing space. |
| `5` | Integrity / snapshot verification failed | Treat the archive/run as untrusted until verified. |
| `6` | Restore failed; rollback succeeded | Reassure: live data was put back. |
| `7` | Restore/rollback needs manual recovery | **Urgent.** Point the user at leftover folders / migrate-safety copies. |
| `8` | Partial success | List which games/files failed. |
| `130` | Canceled | Acknowledge; inspect the final result because already-completed items may remain. |

**Progress event fields (stderr):** `command`, `phase`, `message`, `percent`, `heartbeat`, `elapsedSeconds`, `plateauSeconds`, `knowledgeRef`, `agentHint`, `timestampUtc`.

Cancel an active command with **Ctrl+C**. Cancellation stops before the next safe boundary; it does not roll back items that already completed.

The terminal scan, backup, compression, verification, restore and migration commands use cancellation tokens. The desktop application's double-Esc compression safeguard does not apply to CLI Ctrl+C.

---

## Surfaces (who uses what)

| Surface | Command | User |
|---------|---------|------|
| **Agent automation** | `gsbt <cmd> --ai` | Agents, CI |
| **Human shell** | `gsbt cli` | Humans — type `list`, `backup` without `gsbt` prefix |
| **GUI** | `gsbt gui` | Humans — WinUI desktop |

All surfaces share the same catalog and settings.

---

## Workflows

### Routine backup

```bat
gsbt status --ai
gsbt scan --ai
gsbt list --ai
gsbt backup --ai
gsbt verify --ai
gsbt compress --ai
```

Add `scan --full --ai` when games are missing. Targets: `backup 1,3`, `backup "Game Name"`. Empty selection = all backupable rows. After backup, confirm `bytesCopied` / `runId` from stdout. Retention rotation is automatic — do not delete old runs by hand unless the user asks.

### Post-reinstall / new PC

```bat
REM Old machine first:
gsbt catalog export --ai

REM New machine:
gsbt status --ai
gsbt catalog import "C:\path\gsbt-catalog-export.json" --ai
gsbt migrate --source "D:\Backups" --dry-run --ai
gsbt migrate --source "D:\Backups" --yes --skip-existing --ai
gsbt list --ai
```

- Source can be a **backup folder** or **`Backups_*.7z`** archive.
- Without `gsbt-backup-index.json`: add `--smart-match` (and explain weaker matching).
- `--replace-all` only with explicit user approval.
- Registry-only saves are skipped. `NeedsPath` rows need catalog import or user path fixes.
- On exit 7 or any recovery warning, preserve every reported safety/rollback path and stop automatic retries. Do not delete `.gsbt-restore-*`, `stage`, or `rollback` directories to tidy up a failed restore.

### Single-game restore

```bat
gsbt list --ai
gsbt restore 2 --dry-run --ai
gsbt restore 2 --snapshot latest --yes --ai
```

After dry-run, explain the target and overwrite risk. Obtain any missing user authorization before `--yes`; do not repeat a confirmation already granted for this same operation.

### Custom folder (maps, mods, profiles, non-game data)

```bat
gsbt add custom "Descriptive Name" "C:\verified\existing\folder" --ai
gsbt backup "Descriptive Name" --ai
```

Folder must exist on disk. Never register whole drives, `Windows`, `Program Files`, caches, or credential stores.

If the user names a folder that is **not** in `gsbt list --ai`, search the list first. If it is still missing, explain the folder scope and obtain any missing authorization before `add custom`. A request to register and back up that exact folder already supplies this authorization.

---

## Command reference

| Task | Command |
|------|---------|
| Capabilities + live notebook | `gsbt help --ai` |
| Environment | `gsbt status --ai` |
| Discover games | `gsbt scan [--full] [--refresh-manifest] --ai` |
| List catalog | `gsbt list [found\|not-found\|all] --ai` |
| Backup | `gsbt backup [targets] [--path DIR] --ai` |
| Compress | `gsbt compress [targets] --ai` |
| Verify | `gsbt verify [targets] [--full] --ai` |
| Restore | `gsbt restore <game> [--dry-run] [--yes] --ai` |
| Migrate | `gsbt migrate --source <path> [--dry-run] [--yes] --ai` |
| Export catalog | `gsbt catalog export [path] --ai` |
| Import catalog | `gsbt catalog import <path> [--replace] --ai` |
| Settings | `gsbt settings [show\|backup-path\|compression …] --ai` |
| Diagnostics | `gsbt diagnostics [--output file] --ai` |
| Install GUI | `gsbt get gui --ai` (when CLI-only install) |

**Migrate flags:** `--source`, `--dry-run`, `--yes`, `--smart-match`, `--skip-existing`, `--replace-all`.

**Catalog import:** default merge; `--replace` overwrites entire catalog (needs user approval).

---

## Compression progress (do not panic)

Chunky mode may **plateau** at one percentage (often ~75% or 99%) while 7-Zip works. This is **not** a hang.

- **New `percent` on stderr** = forward progress.
- **`heartbeat: true`** every ~15s = GSBT is still alive at the same %. Tell the user a large chunk is still processing — do not report an error.
- **`knowledgeRef`** on events: `compression.chunky-large-batch-plateau`, `compression.archive-finalization`, `compression.progress-plateau`.
- **99% heartbeat** = archive finalization; wait for final stdout JSON.
- **Failure** only after explicit error, cancel, or final JSON with `success: false` — not from plateau alone.

Smooth mode usually advances more gradually; heartbeats are rarer.

## Release behavior and privacy

- Public Windows builds store backups locally. Cloud sign-in and upload are unavailable.
- **Keep this application online** controls desktop network features. Explicit CLI `scan --refresh-manifest` and `get gui` can access the network regardless of that desktop toggle. Ordinary local backup, compression, verify and restore need no network.
- `status --ai` and command results contain local paths. Diagnostics export is redacted, but inspect it before sharing. Never post raw status, catalog exports, credentials, or personal paths to public services.
- `get gui` accepts a local installer for offline use. Automatic GitHub downloads check asset size and SHA-256 when supplied by the release metadata. Explicit custom URLs require `--allow-custom-host`; older releases or custom sources without a digest cannot provide that checksum assurance. Obtain authorization to install and verify the source before invoking it.

---

## Product scope

GSBT is optimized for **game saves** but supports **any user-selected folder** via `add custom`: maps, mods, campaigns, emulator saves, editor projects, app profiles.

**Not supported:** live database export, VM snapshots while running, source control, backing up entire user profiles or system directories without explicit user scope.

---

## Missing saves / research workflow

1. `gsbt scan --full --ai` and `gsbt list all --ai`
2. Research in order: **PCGamingWiki** → official docs → store/platform docs → forums (corroborate only)
3. Search by game title + edition + data type — **never** include user's Windows name or private paths in web queries
4. Verify candidate folder **exists locally** with plausible data
5. Explain evidence; get approval; `gsbt add custom … --ai`; `gsbt backup … --ai`

**Never** invent paths, create empty folders to pass validation, or claim a folder exists without checking.

**Example (Warcraft III custom maps):** campaign saves may be absent while `Documents\Warcraft III\Maps` still matters — confirm Classic vs Reforged and OneDrive redirection; separate custom entries per folder the user values. Sources: PCGamingWiki (Reforged / RoC), Blizzard editor documentation.

**Example (name collision):** “Back up Delta Force” with two catalog rows — ask reboot vs legacy, then verify the folder size/path locally before backup.

---

## Data locations (Windows)

| What | Path |
|------|------|
| Install | `%LocalAppData%\Game Save Backup Tool\` |
| CLI + agent manual | `%LocalAppData%\Game Save Backup Tool\docs\AGENTS.md` |
| Settings | `%AppData%\Game Save Backup Tool\winui\winui_settings.json` |
| Catalog | `%AppData%\Game Save Backup Tool\winui\game_save_data.json` |
| Backup index | `gsbt-backup-index.json` inside backup root |
| Catalog export schema | `gsbt.catalog.export/v1` |
| Migrate safety snapshots | `%LocalAppData%\Game Save Backup Tool\gsbt\migrate-safety\` |

---

## Migrate safety (agents)

- Pre-restore safety copies go to a **persistent** migrate-safety root (not temp `.7z` extract staging).
- A safety copy is needed when existing live data would be replaced; an empty/new target has no original data to snapshot. Use the returned safety/recovery paths rather than guessing their names.
- Restore transactions sit beside the target on the same drive. Failed rollback or safety-copy finalization can leave recoverable originals there; preserve them and report the path.
- `.7z` sources are extracted to temp staging; staging is deleted after migrate completes.
- Migrate uses **replace** mode without requiring an existing live checkpoint (post-reinstall).
- Dry-run JSON includes per-game `status`, `targetPath`, `selected`, `note`.

---

## Maintainer note (humans editing this repo)

- **User-facing agent text:** edit this file, copy to `GSBT_AGENT.md` beside it, rebuild CLI so install `docs\AGENTS.md` updates.
- **Embedded runtime facts:** edit `src/GSBT.Cli/AgentKnowledge/gsbt-agent-notebook.json` and bump `notebookVersion`.
