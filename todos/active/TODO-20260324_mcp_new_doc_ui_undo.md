# Skyline MCP: New document, UI mode, undo/redo tools + CLI settings arguments

## Branch Information
- **Branch**: `Skyline/work/20260324_mcp_new_doc_ui_undo`
- **Base**: `master`
- **Created**: 2026-03-24
- **Status**: In Progress
- **GitHub Issue**: [#4090](https://github.com/ProteoWizard/pwiz/issues/4090)
- **PR**: (pending)

## Objective

Add 5 new MCP tools (new document, UI mode get/set, undo/redo get/set position), enhance the CLI with settings management arguments and pathless `--new`, and fix the audit log behavior when applying saved settings to a new document.

## Tasks

### Smarter Settings > name (audit log fix)
- [x] When Settings > name is applied and the only audit log record is the initial settings diff, delete that record and reprocess
- [x] Unblocks clean new-document behavior for tutorials

### CLI: `--new` without path in UI mode
- [x] Allow `--new` without a file path when running against a live Skyline instance via RunCommand
- [x] Keep `--new` without path as an error in CLI mode (SkylineCmd/SkylineRunner)

### CLI: Settings arguments
- [x] `--settings-name=<name>` - use saved settings by name
- [x] `--settings-add=path/to/file.skys` - add settings from file
- [x] `--settings-conflict-resolution=<overwrite|skip>` - conflict handling for --settings-add

### MCP Tools
- [x] `skyline_new_document(uiMode?, startSettings?)` - create new blank document
- [x] `skyline_get_ui_mode()` - return current UI mode
- [x] `skyline_set_ui_mode(mode)` - set UI mode
- [x] `skyline_get_undo_redo()` - return full undo/redo stack
- [x] `skyline_set_undo_redo_position(index)` - navigate undo/redo stack

### Dirty document protection (emerged from testing)
- [x] `IDocumentOperations.Dirty` property (false in CLI, delegates to `SkylineWindow.Dirty` in UI)
- [x] `--discard-changes` CLI argument
- [x] `--new` and `--in`/`--open` via RunCommand fail with actionable error when document is dirty

### Testing
- [x] `TestJsonToolServer`: UI mode (get/set across all modes, errors), undo/redo (full cycle with `UndoManager`/`Document` state validation), dirty document protection (--new blocked, --in blocked, --discard-changes succeeds)
- [x] `TestJsonToolServerSettings`: Audit log reset (File > New with non-default settings + reset to defaults = 0 entries, reset with non-defaults = 1 entry)
- [x] `ConsoleNewDocumentNoPathTest`: --new without path fails in CLI mode
- [x] `ConsoleSettingsArgumentsTest`: --settings-name, --settings-add errors, --discard-changes accepted
- [x] `TestSkylineMcp`: Tool count updated 38 → 43

### Code quality
- [x] `implicit operator string` on `CommandArgs.Argument` (eliminates `.ArgumentText`/`.ToString()`)
- [x] `params string[]` on `JsonToolServer.RunCommand`/`RunCommandSilent` (cleaner test call sites)
- [x] `--settings-add` processing moved to pre-document section (alongside `--report-add`)

## Key Files
- `Model/Undo.cs` - UndoManager, UndoRestore(index), UndoDescriptions, RedoDescriptions
- `CommandArgs.cs` - CLI argument definitions (ARG_NEW at line 186)
- `CommandLine.cs` - CLI execution (NewSkyFile, NewDocument)
- `JsonToolServer.cs`, `IJsonToolService.cs` - Server-side tool implementations
- `SkylineMcpServer/Tools/SkylineTools.cs` - MCP tool definitions
- `Test/UndoManagerTest.cs` - Existing undo/redo tests

## Implementation Order
1. Smarter Settings > name (audit log fix)
2. CLI: `--new` without path in UI mode
3. CLI: settings arguments
4. `skyline_new_document` (depends on 1-3)
5. UI mode tools (get/set) - independent
6. Undo/redo tools (get/set position) - independent

## Progress Log

### 2026-03-24 - Implementation

All items implemented and tests passing:

**Audit log fix** (`Skyline.cs`):
- Added `ResetInitialAuditLogEntry()` - when Settings > name is applied to an empty document with only the initial `start_log_existing_doc` audit entry, strips the log and recomputes from the new settings. If new settings match defaults, audit log is clean.
- Called from `SelectSettingsHandler.ToolStripMenuItemClick` after successful settings change.

**CLI changes** (`CommandArgs.cs`, `CommandLine.cs`):
- `ARG_NEW` now has `OptionalValue = true` - `--new` without path creates new document via UI in live Skyline mode; returns error in CLI mode.
- Added `ARG_SETTINGS_NAME`, `ARG_SETTINGS_ADD`, `ARG_SETTINGS_CONFLICT_RESOLUTION` with `SettingsConflictAction` enum.
- Added `AddSettings()` and `ApplySettings()` methods to CommandLine.
- `SkylineWindowDocumentOperations.NewDocument` handles null path gracefully.

**IJsonToolService** (`IJsonToolService.cs`, `JsonToolModels.cs`):
- Added `GetUiMode()`, `SetUiMode(mode)`, `GetUndoRedo()`, `SetUndoRedoPosition(index)`.
- Added `UndoRedoInfo` and `UndoRedoEntry` model classes.

**JsonToolServer** (`JsonToolServer.cs`):
- Implemented all 4 new methods. UI mode uses `Program.ModeUI` / `SetUIMode`.
- Undo/redo uses `GetUndoManager()` (new public accessor on SkylineWindow).
- Index convention: negative = undo, positive = redo.

**MCP tools** (`SkylineTools.cs`, `SkylineConnection.cs`, `SkylineJsonToolClient.cs`):
- Added 5 tools: `skyline_new_document`, `skyline_get_ui_mode`, `skyline_set_ui_mode`, `skyline_get_undo_redo`, `skyline_set_undo_redo_position`.
- Updated `EXPECTED_TOOL_COUNT` from 38 to 43 in test.

**Tests passing**: TestSkylineMcp, TestJsonToolServer, TestJsonToolServerSettings, UndoRedoMultiTest, UndoTransactionTest, AuditLogSavingTest.

### 2026-03-25 - Testing and dirty document protection

**Dirty document protection** (emerged from review of `NewDocument(true)` force-overwriting unsaved work):
- Added `IDocumentOperations.Dirty` property: `false` in CLI mode, `Program.MainWindow.Dirty` in UI mode
- Added `--discard-changes` CLI argument
- `CommandLine.Run` checks `Dirty` before `--new`/`--in`/`--open`; blocks with actionable error message ("Use --save, --out, or --discard-changes") unless `--discard-changes` is supplied
- Gives LLMs clear feedback instead of silent data loss or a blocking dialog

**Tests added** to `JsonToolServerTest.cs`:
- `TestUiMode`: get/set through proteomic/mixed/small_molecules on blank document, error on invalid/none
- `TestUndoRedo`: full undo/redo cycle validating `SkylineWindow.Document` identity (`AreSame`), `UndoManager.UndoCount`/`RedoCount`, settings values, document path — all cross-checked between server response and SkylineWindow state
- Dirty protection: `--new` blocked, `--in` blocked (both verify `AssertDocumentUnchanged`), `--discard-changes` succeeds

**Tests added** to `JsonToolServerSettingsTest.cs`:
- `TestAuditLogResetOnSettingsChange`: exercises `RunCommand("--new")` (pathless) and `ResetInitialAuditLogEntry` — verifies File > New with non-default settings + reset to defaults = 0 audit entries, reset with non-defaults = 1 entry

**Tests added** to `CommandLineTest.cs`:
- `ConsoleNewDocumentNoPathTest`: `--new` without path errors in CLI mode
- `ConsoleSettingsArgumentsTest`: `--settings-name=Default` applies, nonexistent name errors, nonexistent .skys file errors, `--discard-changes` accepted

**Code quality improvements:**
- `implicit operator string` on `CommandArgs.Argument`: allows `CommandArgs.ARG_SAVE` where `string` is expected
- `params string[]` on `JsonToolServer.RunCommand`/`RunCommandSilent` via explicit interface implementation: `server.RunCommand(ARG_NEW, ARG_DISCARD_CHANGES)` instead of `server.RunCommand(new[] { ... })`

**Coverage**: 85.8% overall on MCP server code (up from 82.4% at Phase 2 PR). JsonToolServer at 90.7%.

**All 6 tests passing**: TestJsonToolServer, TestJsonToolServerSettings, TestSkylineMcp, ConsoleNewDocumentNoPathTest, ConsoleSettingsArgumentsTest, AuditLogSavingTest.
