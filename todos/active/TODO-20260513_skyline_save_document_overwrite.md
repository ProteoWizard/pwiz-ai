# skyline_save_document with filePath doesn't save - needs --save alongside --out

## Branch Information

- **Branch**: `Skyline/work/20260513_skyline_save_document_overwrite`
- **Base**: `master`
- **Created**: 2026-05-13
- **Status**: In Progress
- **GitHub Issue**: [#4205](https://github.com/ProteoWizard/pwiz/issues/4205)
- **PR**: (pending)
- **Test Name**: TestSkylineMcp
- **Fix Type**: failure
- **Failure Fingerprint**: `2ca33b43531f349c`

## Objective

`TestSkylineMcp` is failing on all 7 Nightly x64 machines as of 2026-05-13,
introduced by PR #4201 (commit `97149c0b4`). The failing assertion compares the
document path after a save-as call: expected `SkylineMcpTest2.sky`, actual
`SkÿlineMcpTest.sky` — the path didn't move to the new save-as target.

Issue title repeats the AI-generated analysis from the nightly-review post,
which **turned out to be wrong**. The real cause and fix are below.

## Tasks

- [x] Reproduce locally (run TestSkylineMcp with Loop > 1 — passes iteration 1,
  fails iteration 2)
- [x] Read CommandArgs/CommandLine save path and confirm the "needs --save"
  claim is incorrect
- [x] Identify real cause: stale `SkylineMcpTest2.sky` from prior iteration
  triggers the overwrite-existing guard at `CommandLine.cs:548`, save returns
  false silently, DocumentFilePath stays at the previous path
- [x] Make test deterministic across iterations (pre-delete + cover both
  overwrite paths)
- [x] Expose the overwrite behavior on the MCP tool so the LLM can confirm
  with the user before clobbering files
- [x] Verify with 5-iteration loop: all pass
- [ ] Commit, push, open PR

## Progress Log

### 2026-05-13 - Findings

**The issue's "needs --save alongside --out" analysis is incorrect.**

`CommandArgs.cs:291` defines `Saving` as a computed getter:

```csharp
public bool Saving
{
    get { return !String.IsNullOrEmpty(SaveFile) || _saving; }
    set { _saving = value; }
}
```

`--out=PATH` sets `SaveFile` via `ARG_OUT` (line 182-183), which makes the
`Saving` getter return true. So `--out=PATH` alone *does* trigger the
`commandArgs.Saving` block at `CommandLine.cs:545`. Adding `--save`
alongside would have been redundant.

**The real cause is the overwrite-existing guard at `CommandLine.cs:548`:**

```csharp
if (!commandArgs.OverwriteExisting &&     // --overwrite was not passed
    commandArgs.Saving &&                  // SaveFile is set
    commandArgs.SaveFile != commandArgs.SkylineFile && // no --in, so SkylineFile == null
    File.Exists(commandArgs.SaveFile))     // file already exists
{
    _out.WriteLine(... FileAlreadyExists ...);
    return false;
}
```

The MCP `skyline_save_document` tool was sending `--out=PATH` only — never
`--overwrite`. So on the first test iteration `SkylineMcpTest2.sky` did not
exist, the guard didn't fire, save proceeded, DocumentFilePath updated, test
passed. On the second iteration the leftover `SkylineMcpTest2.sky` from
iteration 1 was still present (TestResults dir is not cleaned between
iterations), so the guard fired, `SaveFile()` returned false, and
`DocumentFilePath` stayed at the value from the prior save-in-place. That
prior value is the Unicode `SkÿlineMcpTest.sky` — which is why the failure
message looked like a Unicode round-trip bug.

The expected/actual mismatch in the failure report is *file identity*
(test-1 file vs test-2 file), not corruption of `ÿ`. The Unicode survives
the round trip correctly.

### 2026-05-13 - Fix

1. **`SkylineMcpServer/Tools/SkylineTools.cs`** — add a `bool overwrite =
   false` parameter to `skyline_save_document`. When true, the tool passes
   `--overwrite` alongside `--out=PATH`. Description updated to explain the
   safety pattern: the default false makes the LLM see an "already exists"
   error so it can confirm with the user before clobbering.

2. **`SkylineMcpTest.cs`** — three updates:
   - Pre-delete `SkylineMcpTest2.sky` before the save-as assertion so the
     existing test stays deterministic across iterations.
   - New assertion: save-as to an existing file without `overwrite=true`
     returns a response containing "already exists" and leaves
     `DocumentFilePath` unchanged.
   - New assertion: same call with `overwrite=true` succeeds and updates
     `DocumentFilePath` to the new path.

3. **`SkylineAiConnector.zip`** — rebuilt with the new MCP server code so the
   installed tool the test launches runs the new behavior.

### 2026-05-13 - Verification

5-iteration loop (`Run-Tests.ps1 -TestName TestSkylineMcp -Loop 5`): all
passes succeed. 4 save operations × 5 iterations = 20 save operations with
zero failures.

## Related

- Issue analysis lesson: nightly-review AI-generated root-cause text should be
  treated as a hypothesis, not a conclusion. The phrasing "Root Cause" gave
  the wrong claim too much weight. Verifying against the actual code path
  caught the error before applying the wrong fix.
- TODO item 4 (Save document) in
  [`TODO-20260512_skyline_mcp_fixes.md`](../../backlog/brendanx67/TODO-skyline_mcp_fixes.md):
  this PR addresses the regression introduced by that item's implementation.
