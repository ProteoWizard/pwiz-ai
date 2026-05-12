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

- [ ] Item 2: `.sky.zip` open via `--in=`
- [ ] Item 1: Report-from-definition pivot bug
- [ ] Items 3/7: File-path variants for FASTA/CSV
- [ ] Item 8: RunCommand discoverability
- [ ] Item 4: Save document clarity
- [ ] Item 5: Multi-Skyline-install support

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
