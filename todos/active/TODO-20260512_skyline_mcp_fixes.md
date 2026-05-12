# TODO-20260512_skyline_mcp_fixes.md

## Branch Information
- **Branch**: `Skyline/work/20260512_skyline_mcp_fixes`
- **Base**: `master`
- **Created**: 2026-05-12
- **Status**: In Progress
- **PR**: (multiple - each item lands as its own PR cherry-picked from this branch)

Umbrella TODO covering 6 independent fixes from the 2026-05-12 Seattle Claude Code
Meetup demo. Each item will be cherry-picked to a short-lived branch and land as
its own PR. Approach priority (user-confirmed 2026-05-12):

1. **Item 2** - `.sky.zip` open via `--in=` (highest priority, user-facing bug)
2. **Item 1** - Report-from-definition pivot bug ("appeared so broken we couldn't use them")
3. **Items 3/7** - File-path variants for FASTA/CSV inline-text tools
4. **Item 8** - RunCommand discoverability (after 3/7 so cross-references are consistent)
5. **Item 4** - Save document clarity
6. **Item 5** - Multi-Skyline-install support (new feature)

## Progress

- [x] Item 2: `.sky.zip` open via `--in=` (committed on branch)
- [x] Item 1: Report-from-definition pivot bug (committed on branch)
- [x] Items 3/7: File-path replacement for FASTA/CSV (uncommitted on branch)
- [ ] Item 8: RunCommand discoverability
- [ ] Item 4: Save document clarity
- [ ] Item 5: Multi-Skyline-install support
- [ ] Item 9 (new): JsonServer MessageDlg capture (record to buffer, return to caller)
- [ ] Item 10 (new): CI for SkylineMcp.sln (currently only Skyline.sln is built by CI)

### Item 2 - completed 2026-05-12

`SkylineWindowDocumentOperations.OpenDocument` in `JsonToolServer.cs` now
calls the existing `SkylineWindow.LoadFile(path)` (Skyline.cs:363) instead
of `OpenFile(path)`. `LoadFile` already dispatches to `OpenSharedFile`
(.zip/.sky.zip), `OpenSkypFile` (.skyp), or `OpenFile` (.sky) by extension,
and additionally handles URI/UNC paths and `.skyd` -> `.sky` mapping. This
is the same entry point StartPage and Skyline command-line startup use,
so the MCP path now matches the rest of the application.

Regression test added to `JsonToolServerTest.TestDocumentOperations`:
shares the open document as `.sky.zip`, calls `--in=<that.sky.zip>`, and
verifies the extracted `.sky` path is opened with the correct
MoleculeGroupCount round-trip. Test passes under `TestJsonToolServer`.

Files modified:
- `pwiz/pwiz_tools/Skyline/ToolsUI/JsonToolServer.cs`
- `pwiz/pwiz_tools/Skyline/TestFunctional/JsonToolServerTest.cs`

### Item 1 - completed 2026-05-12

Root cause: with select `[ProteinName, PeptideModifiedSequence,
ReplicateName, TotalArea]`, `ColumnResolver` resolved row source to
`Precursor` but picked **different** Results dictionaries for the two
result columns:
- `ReplicateName -> Peptide.Results!*.Key.ReplicateName` (Peptide's dict)
- `TotalArea -> Results!*.Value.TotalArea` (Precursor's dict)

`FindDeepestSublist` then chose `Peptide.Results!*` as the SublistId
(deepest collection lookup), but `Results!*` does not start with
`Peptide.Results!*`, so `TotalArea` stayed pivoted across the
Precursor's Results dictionary while `ReplicateName` correctly
iterated. With `pivot_replicate: false` the failure mirrored: SublistId
overridden to `Results!*` and `ReplicateName` got pivoted instead.

Both paths had 1 collection step, so the existing `IndexColumn`
preference for "fewer collection steps" couldn't disambiguate. The
first-found-wins tie-breaker happened to register the longer
`Peptide.Results!*.Key.ReplicateName` path before the shorter
`Results!*.Key.ReplicateName` from the row source itself.

Fix: tie-break `IndexColumn` on `PropertyPath.Length` (shorter wins)
when collection step counts are equal. This keeps related result
columns rooted in the same `Results!*` dictionary, matching what the
GUI Report Editor generates when the user clicks columns within the
same PrecursorResult / PeptideResult section.

Regression test added in `TestReportFromDefinition`: select includes
`ReplicateName` + `TotalArea`, asserts exactly the 4 selected columns
appear (no per-replicate suffixes) and row count is
`peptides * replicates`. Covers both default and `pivot_replicate: false`.

Files modified:
- `pwiz/pwiz_tools/Skyline/Model/Databinding/ColumnResolver.cs`
- `pwiz/pwiz_tools/Skyline/TestFunctional/JsonToolServerTest.cs`

### Items 3/7 - completed 2026-05-12

First place the MCP tool surface intentionally diverges from the
underlying `IJsonToolService` API. The interface keeps the in-memory
text form (`InsertSmallMoleculeTransitionList(string textCsv)`,
`ImportFasta(string textFasta, ...)`) - other programmatic consumers
already have their payloads in memory and shouldn't have to write a
temp file. The MCP tools now take file paths instead, because for an
LLM the cost is in tokens, not memory:

- `skyline_import_fasta(fastaPath)` -> internally calls
  `RunCommand("--import-fasta=" + fastaPath)`.
- `skyline_insert_small_molecule_transition_list(csvPath)` -> internally
  calls `RunCommand("--import-transition-list=" + csvPath)`.

Routing through `RunCommand` (rather than reading the file inside the
MCP server and forwarding to the existing API) is deliberate: parse
errors flow through Skyline's Immediate Window, which the JsonServer
already tees back to the tool response. The LLM sees errors as text in
the tool result instead of as a modal MessageDlg the user has to copy
out for it. The new tool descriptions explicitly mention which CLI flag
is used so the LLM can reason about discrepancies if any appear.

Tests updated:
- `SkylineMcpTest.cs`: writes the test FASTA to a temp file and passes
  the path via the new `fastaPath` MCP parameter.
- `JsonToolServerTest.cs`: unchanged - still exercises the in-memory
  `ImportFasta(textFasta, ...)` and `InsertSmallMoleculeTransitionList`
  paths, proving the underlying API remains intact.

Also folded in: `SkylineConnection.cs` was missing
`ReorderElements(string[])`, an interface member that Nick Shulman
added to `IJsonToolService` more recently. The `SkylineMcp.sln` build
had been broken since that commit landed; this surfaces Item 10
(CI gap) below.

Files modified:
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs`
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineConnection.cs`
- `pwiz/pwiz_tools/Skyline/TestFunctional/SkylineMcpTest.cs`

### Item 9 (new): Capture MessageDlg / AlertDlg shown during a JsonServer request

When an `IJsonToolService` call shows a `MessageDlg` or `AlertDlg`
(e.g., a domain-level error that the existing API renders to the
user instead of throwing), the message is invisible to the caller.
Today the human has to copy/paste the dialog into the LLM
conversation, which loses stack-trace context if an exception drove
the dialog.

Proposed enhancement: while a JsonServer request is in flight,
intercept alert dialogs and append their text (and any associated
exception/stack) to a request-scoped buffer that is returned to the
caller in the JSON-RPC response (probably alongside the `_log` field,
or as a `_alerts` field). The dialog should still appear to the
user, but the caller no longer needs the human as a copy/paste
courier.

### Item 10 (new): CI for SkylineMcp.sln

Currently CI only builds the ProteoWizard core and `Skyline.sln`.
`SkylineMcp.sln` (and its dependencies on `SkylineTool.csproj` via
`SkylineMcpServer`) is not built in CI. The `IJsonToolService`
interface drift that broke `SkylineConnection` could have been caught
at the commit that added `ReorderElements` if CI built this solution.
Add a CI step that runs `MSBuild SkylineMcp.sln /p:Configuration=Release /restore`.
Note: `dotnet build` chokes on `SkylineTool.csproj`'s mix of old
`ProjectStyle` plus `PackageReference` for `System.Text.Json` 8.0.5;
MSBuild resolves the package correctly.

## Purpose

Collect issues, gaps, and improvements discovered while preparing the 2026-05-12
Seattle Claude Code Meetup demo with the Skyline AI Connector. Two areas of code
are in scope:

- `C:\proj\pwiz\pwiz_tools\Skyline\Executables\Tools\SkylineMcp\SkylineMcpServer`
  — the MCP server (stdio) that AI clients talk to.
- `C:\proj\pwiz\pwiz_tools\Skyline\ToolsUI\JsonToolServer.cs` — the named-pipe
  endpoint inside the running Skyline that the MCP server calls.

Items below are independent. Each can land on its own PR.

---

## 1. Fix replicate-pivot bug in `skyline_get_report_from_definition`

**Symptom.** With a `select` that includes both `ReplicateName` and a per-result
column like `TotalArea`, the MCP returns the wrong shape regardless of
`pivot_replicate`:

- Default (`pivot_replicate` unset): rows multiply to 5,250 (peptides × replicates),
  but each row has 42 `<ReplicateName> TotalArea` pivoted columns *and* a single
  `ReplicateName` value — the data is self-contradictory.
- `pivot_replicate: false`: rows are 5,250 with a single `TotalArea` column
  (correct), but `ReplicateName` is now pivoted into 42 identical-string columns
  per row.

What the LLM expected was a true long format: 5,250 rows with four single
columns (`ProteinName`, `PeptideModifiedSequence`, `ReplicateName`,
`TotalArea`).

**Important diagnostic.** When the same selection is built by hand in Skyline's
Report Editor, the result is the expected long format. So the bug is in the
MCP-side translation of the JSON `select` array into a `ReportDefinition`,
**not** in the underlying report engine. That points debugging at the
SkylineMcpServer report-definition handling code.

**Workaround used during demo.** Post-process the MCP output with a small
PowerShell script that drops the redundant pivoted columns and reconstructs a
single `Replicate` column from row position. Not something a typical user can
do, so the demo arc uses the built-in `Peptide Peak Areas` report
(`skyline_get_report`) instead, which produces clean wide format that R can
`pivot_longer()`.

**Note.** Brendan: *"The code to support the MCP report generation is one of the
more complex areas of the MCP support."* Worth a careful walkthrough before
patching.

---

## 2. `.sky.zip` should open directly via `--in=`

**Symptom.** Calling `skyline_run_command` with
`--in="path/to/file.sky.zip"` fails with a misleading dialog:

```
Failure opening ...Rat_plasma.sky.zip.
The file you are trying to open ... does not appear to be a Skyline document.
Skyline documents normally have a ".sky" or ".sky.zip" filename extension and
are in XML format.
```

Stack trace shows `XmlException: Data at the root level is invalid. Line 1,
position 1.` — Skyline is trying to parse the zip's raw bytes as XML instead of
unzipping first.

**Significance.** `.sky.zip` is the official Skyline sharing format. Tutorial
data ships as `.sky.zip`. Asking the LLM to extract before opening turns a
one-step demo into a janitorial multi-step exercise.

**Workaround used during demo.** Pre-extract the `.sky.zip` to a folder using
`Expand-Archive`, then open the inner `.sky` file. Works, but is the kind of
plumbing step we want to avoid making LLMs perform.

**Likely fix.** Detect `.sky.zip` extension (or zip magic bytes) in the open
path before the XML parser is reached. The GUI File → Open already handles
`.sky.zip` correctly, so the logic exists; the CLI/MCP path needs the same.

---

## 3 & 7. File-path variants for inline-text tools

**Symptom.** Two MCP tools take their primary payload as inline text:

- `skyline_import_fasta` (`textFasta` parameter)
- `skyline_insert_small_molecule_transition_list` (`textCsv` parameter)

When the LLM uses these, it must regenerate the full payload token-by-token
into the tool call. For APOB (4,563 amino acids ≈ 5 KB of sequence text) plus
APOA1 and APOE, this took ~60–90 seconds of model output time in the demo
recording. That dominated the otherwise-fast import beat.

**Workaround used during demo.** Camtasia 8× speed-up on this segment of the
recorded video. Functional but reveals the tool design rather than hides it.

**Fix.** Accept either inline text *or* a file path on each tool. Suggested
signatures:

```
skyline_import_fasta(textFasta?: string, fastaPath?: string)
skyline_insert_small_molecule_transition_list(textCsv?: string, csvPath?: string)
```

Implementation note (Brendan's suggestion): make these thin wrappers around
the existing CLI flags via `skyline_run_command` — `--import-fasta=path` and
`--import-transition-list=path` already exist and work. Routing through
RunCommand has a nice secondary benefit: dedicated MCP tools and CLI flags
stay behaviorally identical by construction.

Alternative implementation: load the file into memory inside SkylineMcpServer
and call the existing JsonToolServer method. Either works.

**Tool description update.** When the file-path variant lands, add a hint to
the description: *"For large inputs, prefer the path form to avoid
regenerating the full payload into the tool call."*

---

## 4. Save document — clarity, not implementation

**Status.** Brendan believes `skyline_run_command --out=path` already works for
saving the current document. The LLM didn't discover this during the demo and
reported "no save tool exists." That's a discoverability problem, not a
functionality gap.

**Fix.** One of:

1. **Document it more prominently.** Add a saving example to
   `skyline_run_command`'s tool description (e.g., `--out="path/to/save.sky"`).
2. **Add a dedicated `skyline_save_document(filePath)` tool** as a thin wrapper
   around the CLI flag. Costs little and matches the LLM's mental model of
   "there's a tool for this verb."

Recommend doing both — option 1 is essentially free, option 2 makes the LLM's
first-pass tool search succeed.

---

## 5. Multi-Skyline-install support

**Need.** Today the LLM cannot:

- Enumerate which Skyline releases are installed (Skyline, Skyline-daily,
  Skyline Administrator at `C:\Program Files\Skyline`).
- Launch a new Skyline instance from MCP. The demo required the human to
  manually open a third Skyline window for the "new instance arrives" beat.

**Suggested new tools.**

- `skyline_list_installed()` — return name, version, executable path, and
  install scope (user / system / Administrator) for each detected install.
- `skyline_start_instance(release: string)` — launch a new instance of the
  named release, return the new process ID once it connects.

**Design note.** The connection-file scan logic
(`~/.skyline-mcp/connection-*.json`) already enumerates running instances; the
"installed but not running" enumeration is a separate Windows-registry /
filesystem walk. Plan accordingly.

---

## 8. RunCommand discoverability for LLMs

**Observation.** `skyline_run_command` is the most powerful tool in the
SkylineMcpServer surface — it exposes the full SkylineCmd CLI, including
operations no dedicated tool wraps. But during the demo, the LLM consistently
picked the dedicated tools (`skyline_import_fasta`, etc.) over RunCommand even
when RunCommand would have been faster (item 3/7).

The reason isn't ignorance — the LLM is doing the right thing given the tool
list:

- `skyline_import_fasta`'s description starts with *"Import protein sequences
  in FASTA format..."* — exact-match for the LLM's intent.
- `skyline_run_command`'s description starts with *"Run a command line against
  the running Skyline instance..."* — generic, doesn't surface what's
  available.

**Two cheap improvements** in the tool descriptions themselves:

### 8a. Cross-reference dedicated tools to RunCommand

In each dedicated-tool description, append a hint that the LLM should prefer
RunCommand for large inputs. Example for `skyline_import_fasta`:

> "Import protein sequences in FASTA format. ... For large sequences or to
> avoid regenerating the full text into the tool call, prefer
> `skyline_run_command` with `--import-fasta=path`."

Same pattern for `skyline_insert_small_molecule_transition_list` →
`--import-transition-list=path`.

(This item dovetails with 3/7 — once those are implemented, the dedicated
tools accept a path directly and the cross-reference is less needed. But until
then, the hint is useful.)

### 8b. Make RunCommand's description surface its menu of capabilities

Replace the generic blurb with a description that enumerates 3–5
representative things the LLM can do through it that *aren't* available as
dedicated tools. Examples:

- `--import-fasta=path` (FASTA import from file)
- `--import-transition-list=path` (CSV transition list from file)
- `--refine-cv-remove-above-cutoff=N` (refinement operations)
- `--report-name="..." --report-file=path` (built-in report export)
- `--out=path` (save current document)
- `--help` (full list)

Then the LLM browsing tools sees RunCommand as a *menu of power*, not a single
generic blurb.

**Bonus.** The CLI help docs are already exposed through the MCP — so an LLM
that's been prompted to "explore" can discover the menu via
`--help`. Worth noting that fact in the description so the LLM knows the
discovery path exists.

---

## Priority

Rough ordering for post-meetup work, if all items can't be addressed at once:

1. **Item 2 (`.sky.zip` open)** — high-visibility user-facing bug.
2. **Items 3/7 (file-path variants)** — eliminates the worst LLM latency in
   typical demos.
3. **Item 1 (report pivot)** — current workaround (use built-in reports) is
   acceptable for now; fix when revisiting the report-definition translation.
4. **Item 8 (RunCommand discoverability)** — pure tool-description edits,
   trivial; ship as soon as 3/7 lands so 8a is consistent with the new
   signatures.
5. **Item 4 (Save clarity)** — at minimum 4.1 (description update), 4.2
   (dedicated tool) is optional but cheap.
6. **Item 5 (multi-install support)** — new feature, lower priority than
   bugfixes, but solves a real demo gap.
