# TODO-20261103_osprey_parity_rows.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_parity_rows`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: In Review (PR open; TeamCity Perf/Regression not yet run - parent session queues it)
- **GitHub Issue**: (none - rows of backlog `TODO-osprey_parity_path_retirement.md`)
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `C:\proj\wt-envvar` (night-session agent worktree, round 2 wave B, second branch)

## Objective

Retire the parity-only rows A5 and A9-A18 of the parity-path catalogue: delete each switch's OFF
arm and its tests, keep the Category B diagnostics, verify every row's removal blockers against
current code first. Output unchanged (the OFF arms are not the defaults).

## Done (commit 9fe29f1fb6)

- **A5** `OSPREY_RELEASE_LIBRARY_FRAGMENTS=0`: the switch, its term in `RunsOnThisLeg`, and
  `LibraryFragmentRelease.ValidityKeySuffix` (always empty on the default arm, so no validity key
  changes) with its three call sites; the opt-out tests (LibraryFragmentReleaseTest suffix
  validation, TaskValidityKeyTest `AssertLibraryFragmentArmIsPinnedToThePipeline`). The rationale
  moved from OspreyEnvironment to the LibraryFragmentRelease class doc; the tripwire message no
  longer advises `=0`. Regression mode 6 (release engaged) stays.
- **A9** `OSPREY_LOESS_CLASSICAL_ROBUST=0`: `LoessRegression.Fit` always refreshes residuals;
  `RTCalibratorConfig.ClassicalRobustIterations` deleted (every caller set it true).
- **A14** `OSPREY_BLOCK_READ_MB=0`: `BlockReadStream.OpenRead` always block-reads; the size knob
  stays, clamped to [1, 1024] MB (0 and below now read 1 MB blocks).
- **A15** `OSPREY_BLOCK_READ_GATE=0`: production reads always take the disk gate. The ungated
  branch stays reachable only through the internal `BlockReadStream.Open(path, bytes, gate)` test
  seam, which BlockReadTest uses with `gate: false` throughout.
- **A16** `OSPREY_STUB_IDENTITY=0`: the `== 0` check removed; any value but 2 reads as 1. The `=2`
  verifier is kept (Category B proof harness).
- **A18** (part): `FdrStreamingSink` (never constructed), `PercolatorQValues.ComputeFullPopulationPrecursorFdr`
  (no callers), the stale "DELETE THIS RECOMPUTE" note.
- Docs: 00-pipeline-architecture, 04-calibration, 05-rt-alignment, 10-cross-run-reconciliation,
  Regression/README, Regression/FdrSidecars.ps1 comment; ai DIAGNOSTICS.md and the dev guide's env
  table; the catalogue rows A5, A9, A14, A15 removed, A16/A18 rewritten to what remains.

## Deferred, with the blocker re-verified 2026-11-03

- **A10** `OSPREY_PICK_LDA=0`: Rust `pick_lda.rs` keeps the same legacy arm as an A/B lever, and the
  runners expose `-PickProduct`.
- **A11** `OSPREY_TRAIN_PICK_RUN=0`: read in `PercolatorEngine.cs` / reservoir in `PercolatorScorer.cs`,
  off-limits this round.
- **A12** `OSPREY_MAX_PARALLEL_FILES`: `Test-PerfGate.ps1` still uses it as the cross-binary control.
- **A13** retired-name residue: eight runners' ValidateSets still offer `transfer-compete`; editing
  them while another agent runs a cohort is the risk, and Osprey refuses the value at startup anyway.
- **A17** old-format readers: removing them stops pre-split output directories resuming; next format bump.
- **A18** remainder: `FdrProjectionSet.Builder` (backs a byte-parity test), `RunPercolatorFdr` facade and
  `frozenModel` (PercolatorEngine, off-limits).

## Coordination with PR #4983 (env var catalog)

Both branches edit `OspreyEnvironment.cs` declarations. Whichever merges second deletes the
`EnvVar` declarations of OSPREY_RELEASE_LIBRARY_FRAGMENTS, OSPREY_LOESS_CLASSICAL_ROBUST and
OSPREY_BLOCK_READ_GATE, and changes OSPREY_STUB_IDENTITY's `Values` to `1|2` (and its description).

## Tasks

- [x] Verify each row's blockers against current code
- [x] Remove A5, A9, A14, A15, A16 (=0), A18 (part); tests; docs
- [x] Build-Osprey -RunTests -RunInspection (650/650, 0 warnings; `ai/.tmp/sessions/20261103-agentB/gate5.log`)
- [x] regression-parallel.ps1 -Dataset All: 49 PASS / 0 FAIL / 0 SKIP in 1:20:46 on 9fe29f1fb6
  (`ai/.tmp/sessions/20261103-agentB/regress-all.log`; lane logs
  `pwiz_tools/Osprey/TestResults/regression-lane-*-20261103_143048.log` in the worktree)
- [x] /code-review medium, triage (below); fixes 2db6b5bc0d gated by Build-Osprey 650/650
  (`gate6.log`) - startup refusals and log text only, output-neutral
- [x] Push TODO, open PR

## Progress Log

### 2026-11-03 (night session, agent B)
- Implemented the Done list above.

### /code-review medium (8 findings) - triage
Fixed (2db6b5bc0d):
- `OSPREY_STUB_IDENTITY=0` and `OSPREY_BLOCK_READ_MB<=0` silently ran the default under the retired
  arm's name; now a startup error (`OspreyEnvironment.RetiredReadArmError`), with CommandLineErrorTest cases.
- Stale `ClassicalRobustIterations` line in 05-rt-alignment; stale `_stubIdentity` comment.
- Dead `text != null` check in BlockReadLog; constant `gate {1}` slot in the block-read line
  (the PercolatorEngine copy of the null check is left: off-limits file).
Dropped:
- No escape hatch around the released-fragment tripwire: retiring the =0 arm is the point; an
  under-computed retained set should fail loudly and be fixed in code.
- RunsOnThisLeg and LegAdmitsRelease now overlap: one takes the context, one the config; merging is
  cosmetic.
- The "who wrote it, not the key" reader rule now rests on a hypothetical per-leg term: the rule is still
  the safe one for HPC readers; tightening it to a full key check is a design change, not a removal.
