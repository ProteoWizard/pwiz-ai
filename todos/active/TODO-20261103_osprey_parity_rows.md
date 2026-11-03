# TODO-20261103_osprey_parity_rows.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_parity_rows`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: In Progress
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
- [ ] regression-parallel.ps1 -Dataset All (`ai/.tmp/sessions/20261103-agentB/regress-all.log`)
- [ ] /code-review medium, triage
- [ ] Push TODO, open PR

## Progress Log

### 2026-11-03 (night session, agent B)
- Implemented the Done list above.
