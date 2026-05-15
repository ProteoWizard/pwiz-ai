# Skyline MCP Server and JsonToolServer - Follow-up Work (round 2)

## Purpose

Carryover items from `TODO-20260512_skyline_mcp_fixes.md` (Seattle Claude Code
Meetup demo follow-ups). The first round of fixes shipped on
`Skyline/work/20260512_skyline_mcp_fixes`:

- Item 2 - `.sky.zip` open via `--in=` (route through `SkylineWindow.LoadFile`)
- Item 1 - Report-from-definition pivot bug (`ColumnResolver.IndexColumn` tie-break)
- Items 3/7 - File-only `skyline_import_fasta` / `skyline_insert_small_molecule_transition_list`
- Item 4 - `skyline_save_document(filePath = null)`
- Item 8 - `skyline_run_command` description as menu-of-power + wrapper cross-refs

The items below were either deferred (Item 5) or surfaced during the round-1
work (Items 9, 10).

Items are independent. Each can land on its own PR.

---

## 5. Multi-Skyline-install support

**Split into its own active TODO 2026-05-13:**
`ai/todos/active/TODO-20260513_skyline_mcp_multi_install.md`. Two new
MCP tools land there: `skyline_list_installed()` and
`skyline_start_instance(release)`. Items 9 and 10 below remain in
this backlog file for separate PRs.

---

## 9. Capture MessageDlg / AlertDlg shown during a JsonServer request

**Need.** When an `IJsonToolService` call shows a `MessageDlg` or `AlertDlg`
(e.g., a domain-level error that the existing API renders to the user
instead of throwing), the message is invisible to the caller. Today the
human has to copy/paste the dialog text into the LLM conversation, which
loses any stack-trace context if an exception drove the dialog.

**Proposed enhancement.** While a JsonServer request is in flight,
intercept alert dialogs and append their text (and any associated
exception / stack) to a request-scoped buffer that is returned to the
caller in the JSON-RPC response. Probably alongside the existing `_log`
field, or as a new `_alerts` field. The dialog should still appear to
the user (so the human stays in the loop visually), but the caller no
longer needs the human as a copy/paste courier.

**Implementation sketch.** A `MessageDlg.Shown` / `AlertDlg.Shown` hook
that, when `JsonToolServer._currentRequestId` is non-null, captures the
dialog's title + text + ToString of any associated exception into a
thread-local list. The response builder reads and clears that list at
response time. Care needed for dialogs that show during background
loaders started by a request - the request-scope boundary may need to
extend until the LongWaitDlg or background task finishes.

**Why now.** Multiple round-1 items routed through `RunCommand` exactly
because errors there flow through the Immediate Window tee. Anything
that still goes through the direct `IJsonToolService` API surface
(many tools do) bypasses that path and lands as a modal dialog.

---

## 10. CI for SkylineMcp.sln

**Need.** Currently CI only builds the ProteoWizard core and `Skyline.sln`.
`SkylineMcp.sln` (and its dependencies on `SkylineTool.csproj` via
`SkylineMcpServer`) is not built in CI.

**Evidence this matters.** During round-1 work an `IJsonToolService` interface
member (`ReorderElements`) was added in a recent commit, but the
implementing class `SkylineConnection` in `SkylineMcpServer` was not
updated. The `SkylineMcp.sln` build was broken from that commit until
the round-1 fix landed. CI would have caught this at the original commit.

**Fix.** Add a CI step that runs:

```
MSBuild SkylineMcp.sln /p:Configuration=Release /restore
```

**Tooling caveat.** `dotnet build SkylineMcp.sln` chokes on
`SkylineTool.csproj`'s mix of old-style `ProjectStyle` plus
`PackageReference` for `System.Text.Json` 8.0.5. MSBuild resolves the
package correctly. Use MSBuild, not `dotnet build`, in CI for this
solution.

**Scope ambiguity.** Is the SkylineAiConnector.zip artifact regeneration
something CI should also enforce? Today the zip is checked into the
repo and regenerated on each MCP server change. If CI builds the
solution, the zip in the workspace will differ from the committed zip
on every change - need to decide whether CI uploads the new zip or
just verifies the build succeeds.

---

## Priority

- **Item 10** is cheapest and prevents the kind of interface drift that
  round-1 had to repair incidentally. Fix first.
- **Item 9** unlocks better LLM error feedback across the entire
  `IJsonToolService` surface, not just the RunCommand-routed tools.
  Medium effort.
- **Item 5** has been split into its own active TODO
  (`TODO-20260513_skyline_mcp_multi_install.md`).
