# Osprey Stage 6: stream PerFileRescore survivors instead of holding all files resident

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_stage6_rescore_streaming`
- **Base**: `master` (at `6d919a080e`, after #4442 merged)
- **Created**: 2026-07-27
- **Status**: In Progress - characterization phase
- **Worktree**: `C:\proj\pwiz` (BRENDANX-UW8)
- **GitHub Issue**: [#4472](https://github.com/ProteoWizard/pwiz/issues/4472)
- **PR**: (pending)
- **Requester/Reporter**: none (Osprey developers; no credit line per version-control-guide
  "Crediting Reporters and Requesters" - role-scoped, Osprey developers are not outside requesters)

## Objective

`PerFileRescoreTask` holds every file's post-compaction survivor `FdrEntry` lists resident
at once (`_perFileEntries`, `PerFileRescoreTask.cs:113`, set from `CompactedEntries` at
`:201`), so Stage-6 resident memory is O(files). This is the last O(files) live structure
between us and a 500-file run on a 64 GB box, now that Stage-5 FirstPassFDR is flat (#4435).

Hold only the bounded cross-file reconciliation state resident and reload each file's
survivors on demand, mirroring the Stage-5 treatment. Byte-identical output is mandatory.

## Scope decision (2026-07-27, Brendan)

Issue #4472 carries THREE pieces. **ONE PR for the issue, covering A+B**; C splits out.

- **A. Stage-6 straight-through** - `_perFileEntries` holds all files' survivors
  (`PerFileRescoreTask.cs:113/201`). Root-caused; lever proposed.
- **B. HPC/resume** - `FirstJoin.Rehydrate` loads the full PRE-compaction pool
  (`FirstJoinTask.cs` ~447/474), forced by `ExpectReconciledInput` on every HPC merge.
  The issue calls this "the FIRST thing to explode at 500 files." Same lever as A; its
  own gate is regression mode2/mode3, plus the `--allow-unbounded-memory` guard interaction
  (the guard currently EXEMPTS `ExpectReconciledInput`; that exemption should close with B).
- **C. Stage-7 SecondPassFDR ~45 GB peak** - SPLIT OUT to [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
  (linked from #4472 so nobody works it thinking it is in scope). The issue states
  its root cause is uncharacterized and that the first step is `[MEM]` probes + dotMemory
  *before choosing a lever*. Folding an undiagnosed peak into a PR whose value is a crisp
  byte-parity gate is how the gate stops being interpretable.

Step carefully in separate commits: characterize -> fix A -> fix B -> gates. Multiple test
runs per step are expected; a red mode2/mode3 should point at ONE lever at a time.

## Characterization first (issue's own step 1)

Do NOT write the fix before the slope is measured. The issue asks for `[MEM]` probes to
confirm `_perFileEntries` - not the Stage-6 transients bounded by #4394 - is the slope
source, and for per-file bytes/row so the 500-file projection is exact.

**Harness**: `--task PerFileRescoring --input-scores <N parquets>` against Stage 1-5
artifacts built once. Two traps, both silent:

- **Pass N files in ONE invocation.** The HPC chain (`regression.ps1:644`) calls this task
  once per stem, so `_perFileEntries` holds exactly ONE file and the band is flat BY
  CONSTRUCTION. Driven that way the harness would show a fix that is not there.
  `--input-scores` accepts a directory / many parquets (`OspreyConfig.InputScores` is a
  `List<string>`; `PerFileScoringTask` loops it), which populates the real multi-file buffer.
- **Clear `*.2nd-pass.fdr_scores.bin` between repeats.** `PerFileRescoreTask.Run:240-248`
  self-gates to a NO-OP when any pass-2 sidecar is present. A repeat run that skips this
  measures nothing and exits 0.

Slope needs no extra generation: vary how many `--input-scores` are passed (4 / 8 / 16)
against ONE set of artifacts.

## Tasks

- [x] Verify issue line refs against master (`:113`, `:201`, `:208`, probe `:593`) - all correct
- [x] Stage the 82-file SEA-AD set locally: 82 mzML + 82 `.spectra.bin`, all caches ACCEPT
- [ ] Add the Stage-6 harness to `ai/scripts/Osprey/SEA-AD/` (shared + portable, per README)
- [ ] Build Stage 1-5 artifacts once for 16 files
- [ ] Measure the resident band at 4 / 8 / 16 files; confirm positive slope in file count
- [ ] `[MEM]` probe to attribute the slope to `_perFileEntries` vs transients
- [ ] Per-file bytes/row -> exact 500-file projection
- [ ] Design the fix: separate bounded cross-file state from per-file survivor reload
      (`ReloadFirstPassSurvivors` already does the per-file reload)
- [ ] Implement; keep the canonical `(EntryId, Charge, ScanNumber, ParquetIndex)` sort

## Regression Test

- **Gate**: `regression.ps1 -Dataset All` byte-identical, mode1/2/3. Reconciliation is
  byte-parity-sensitive; this is THE gate, not a smoke test.
- **Also**: `Build-Osprey.ps1 -RunTests -RunInspection`
- **Memory A/B**: the PerFileRescoring band slope goes to ~0 in file count, as the
  FirstPassFDR band now is. Confirm the 500-file projection clears 64 GB.
- **Fails on master**: (to verify - the slope IS the failure)
- **Passes on fix**: (to verify)

## Progress Log

### 2026-07-27 - Session start (BRENDANX-UW8)

Machine brought up for large-scale Osprey testing:
- Full TeamCity regression green from cold: 18/18 PASS, exit 0, 78 min (`-Dataset All`).
- 82-file SEA-AD set staged locally (324.5 GB mzML + 345.9 GB caches), all 82 caches
  validated ACCEPT against the v4 header + fingerprint rules.
- Confirmed cross-system `.spectra.bin` reuse works: caches written on another machine
  streamed here with no re-parse. Requires v4 exactly + mzML size/mtime match; nothing
  else (not path, machine, or search settings - the cache is settings-independent).
  25 mzML arrived with wrong mtimes from an upload race and were repaired as metadata.
- Library restructured to the SEA-AD README convention
  (`$env:OSPREY_SEAAD_LIB\target+decoy+entrapment\`); `Run-SeaAd.ps1 -WhatIf` resolves clean.

Issue #4472 re-verified against master; scope split recorded above.
