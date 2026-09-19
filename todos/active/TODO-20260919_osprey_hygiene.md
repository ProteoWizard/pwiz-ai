# TODO-20260919_osprey_hygiene.md - Osprey hygiene bundle from the 2026-09-18 issue audit

## Branch Information
- **Branch**: `Skyline/work/20260919_osprey_hygiene` (checkout `C:\proj\pwiz-work1`)
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619)
- **Module**: `osprey`
- **Status**: PR #4690 open (base = port branch); local gates green; /code-review and TeamCity pending

## Why

The 2026-09-18 audit of the 47 open `osprey` issues (closed 10, re-scoped 16; record in
`ai/.tmp/sessions/2026-09-18-osprey-issue-audit/`) and the same-day memory review left a
set of small, low-risk items that belong in one PR rather than one issue each.

## Scope

1. **`regression.ps1` output retention** (Brendan's 2026-09-10 rule, decision 2026-09-18):
   clean BEFORE a run, never after. Local runs retain output; `-KeepRunDirs` defaults to 1
   so the startup prune keeps the last set; `-TeamCity` implies cleaning; new
   `-CleanOutput` forces it locally; `-KeepOutput` overrides both. Documented in
   `docs/19-testing.md`.
2. **`regression.ps1` known-resident-gaps row** re-keyed from the closed #4486 to #4665.
3. **`OspreyReportWriter`**: the two opt-in TSV reports now write through `FileSaver`
   (they opened the final path directly with `StreamWriter`, the one durable-artifact
   writer that bypassed the rule).
4. **`Osprey.IO.csproj`**: dropped the `VulnerablePackage` suppression (#4462; Snappier is
   pinned to 1.3.1 on this branch).
5. **Docs** (`pwiz_tools/Osprey/docs`): 03 intensity features are log10(x+1)-conditioned
   and why; 07 "zero is the decision boundary" and "reading the feature-contribution
   table"; 12 #4560 closed by contract; 19 the four datasets and the Stellar-inert decoy
   trap; new 21-user-facing-text.md (the log vocabulary decisions from the 2026-09-09
   readability review) + README row; TEAMCITY-CONFIG.md agent pin, `freeze.settings.error`
   false red, `Assert.Inconclusive` parity tests.
6. **#4494 item 2**: the 36 stale `PercolatorFdr.cs` citations in docs 07/12/16 and
   DIVERGENCES.md refreshed to the post-decomposition files.

Not in scope (each a code change with output effects, kept for their own PRs): #4463
console unique count, #4672 boundary column, BASE_ID_MASK consolidation (#4494 item 4).

## Gates

- [x] `Build-Osprey.ps1 -SourceRoot C:\proj\pwiz-work1 -Configuration Debug -RunTests -RunInspection` - 592/592, zero warnings
- [x] `regression.ps1 -Dataset Stellar` - PASSED; 19 GB run dir retained, prune touched nothing else
- [ ] `/code-review max`
- [ ] TeamCity Perf/Regression on `pull/<N>` with the agent pin (ask first)

## Progress

- 2026-09-19: branch created; items 1-6 applied (item 6 also fixed five adjacent stale PercolatorEngine citations); build/tests/inspection green; Stellar gate PASSED; PR #4690 opened against the port branch.
- Found in passing, not fixed: docs/16 still cites PerFileRescoreTask lines from before the rescore split (`:1306-1315`); the guide's "Validation before pushing to a PR" section in ai/docs still says pwiz has no Osprey CI.
