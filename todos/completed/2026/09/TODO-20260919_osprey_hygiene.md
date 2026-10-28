# TODO-20260919_osprey_hygiene.md - Osprey hygiene bundle from the 2026-09-18 issue audit

## Branch Information
- **Branch**: `Skyline/work/20260919_osprey_hygiene` (checkout `C:\proj\pwiz-work1`)
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619)
- **Module**: `osprey`
- **Status**: Completed
- **PR**: [#4690](https://github.com/ProteoWizard/pwiz/pull/4690) (merged 2026-09-20 as `f6a36077b1` into `Skyline/work/20260612_net8_port`)

## Why

The 2026-09-18 audit of the 47 open `osprey` issues (closed 10, re-scoped 16; record in
`ai/.tmp/sessions/2026-09-18-osprey-issue-audit/`) and the same-day memory review left a
set of small, low-risk items that belong in one PR rather than one issue each.

## Scope

1. **`regression.ps1` output retention** (Brendan's 2026-09-10 rule, decision 2026-09-18):
   clean BEFORE a run, never after. Final design after review: a local run retains its
   PRODUCTS (`<dataset>\straight`, chain phase 3/4 outputs, `chain\logs`, comparison
   inputs) via `Remove-Scratch`; the HPC chain's staged input copies and consumed phase
   dirs go through `Remove-Staging` and are kept only by `-KeepOutput` (they were 69% of a
   retained Stellar run: 19 GB -> 5.7 GB). `-KeepRunDirs` (default 1) is applied by the
   NEXT run's prune, only `run.complete`-stamped dirs count, a dir stamped with the
   current shell's PID is not live, and the keep defaults to 0 when not retaining.
   `-TeamCity` implies `-CleanOutput`; `regression-parallel.ps1` forwards the switches
   with keep = dataset count. Documented in `docs/19-testing.md`.
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
- [x] `/code-review max 4690` - 15 findings, all fixed or answered (second commit)
- [x] TeamCity Perf/Regression on `pull/4690` with the agent pin - build #257 SUCCESS on c8c5612b6c

## Progress

- 2026-09-19: branch created; items 1-6 applied (item 6 also fixed five adjacent stale PercolatorEngine citations); build/tests/inspection green; Stellar gate PASSED; PR #4690 opened against the port branch.
- 2026-09-19 (later): /code-review max returned 15 confirmed findings; the big ones were that retention also kept the staged input copies, the two-lane runner would prune three of four dataset dirs, a long-lived shell's runs were never prunable, fragments displaced complete sets, and the report writers adopted FileSaver's contract without its catch. All addressed in c8c5612b6c (three writers: regression scripts by me, report writer + docs 00/08/14/DIVERGENCES, doc citations + TeamCity docs); Stellar gate PASSED again on the final tree; PR body corrected (reports are default-on, not opt-in).
- Found in passing, not fixed: docs/16 still cites PerFileRescoreTask lines from before the rescore split (`:1306-1315`); the guide's "Validation before pushing to a PR" section in ai/docs still says pwiz has no Osprey CI. OspreyConfig.cs doc comments advertised --no-protein-report / --no-summary-report that were never registered (comments corrected; decide whether to register the flags).

### 2026-09-20 - Merged

PR #4690 merged as commit `f6a36077b1` into `Skyline/work/20260612_net8_port` (the PR's
base, per the current Osprey convention of targeting the .NET 10 port branch rather than
master). TeamCity Perf/Regression build #257 was SUCCESS on `pull/4690` before the merge.
Nothing from the six-item scope was deferred. This work reaches `master` when the port
branch (#4619) merges. Two small follow-ups noted above (stale docs/16 citation, the
unregistered report-off flags) were left as-is rather than expanded into this PR.
