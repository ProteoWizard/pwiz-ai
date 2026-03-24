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
- [ ] When Settings > name is applied and the only audit log record is the initial settings diff, delete that record and reprocess
- [ ] Unblocks clean new-document behavior for tutorials

### CLI: `--new` without path in UI mode
- [ ] Allow `--new` without a file path when running against a live Skyline instance via RunCommand
- [ ] Keep `--new` without path as an error in CLI mode (SkylineCmd/SkylineRunner)

### CLI: Settings arguments
- [ ] `--settings-name=<name>` - use saved settings by name
- [ ] `--settings-add=path/to/file.skys` - add settings from file
- [ ] `--settings-conflict-resolution=<overwrite|skip>` - conflict handling for --settings-add

### MCP Tools
- [ ] `skyline_new_document(uiMode?, startSettings?)` - create new blank document
- [ ] `skyline_get_ui_mode()` - return current UI mode
- [ ] `skyline_set_ui_mode(mode)` - set UI mode
- [ ] `skyline_get_undo_redo()` - return full undo/redo stack
- [ ] `skyline_set_undo_redo_position(index)` - navigate undo/redo stack

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

### 2026-03-24 - Session Start

Starting work on this issue.
