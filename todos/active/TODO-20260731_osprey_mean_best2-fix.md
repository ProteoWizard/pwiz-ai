# Osprey: fix the defects a post-merge code review found in mean(best-N)

## Branch Information
- **Branch**: `Skyline/work/20260731_osprey_mean_best2-fix` (C:\proj\pwiz, off master d030522344)
- **Base**: `master` (d030522344)
- **Module**: `osprey`
- **Created**: 2026-07-31
- **Status**: In Progress
- **Fixes**: defects in [#4509](https://github.com/ProteoWizard/pwiz/pull/4509) (merged 2026-07-31)
- **PR**: (pending)
- **Requester**: Brendan (Osprey developer) - NO credit line.

Naming note: `ai/WORKFLOW.md` Workflow 3a says to add a "Bug Fixes" section to the ORIGINAL TODO
rather than create a new one. Brendan explicitly asked for a `-fix` TODO alongside the `-fix`
branch, which also satisfies the dated-TODO-matches-branch rule; the completed TODO for #4509 gets
a pointer here instead of being reopened.

## Why this exists

#4509 merged **without an AI code review** - Copilot declined on a quota limit, and the
`/code-review max` run that day covered the session's `ai/` scripts, not the PR branch. A
retrospective `max` review of the merged commit found **15 findings**, several of them real
correctness bugs. This TODO fixes them.

**Nothing here affects the default path.** The review confirmed every new branch is gated on
`MeanBestN >= 2` with `effScores == scores` when off, so master's byte-identity (18/18 TeamCity
legs on #4509) is untouched. Every defect below is reachable only with
`OSPREY_EXPERIMENT_AGG=mean-best-<N>` set.

**Prior measurements are unaffected.** The 35-cohort mean-N series and the 2026-07-31 PICK_LDA
cells all read the pass-1 experiment `fdpView`, written at FirstJoin before any pass-2 code runs.

## Findings being fixed

Severity order, review's numbering in brackets.

1. **[1] Pass-2 frozen modes overwrite the reported experiment q with MAX-aggregated values.**
   `StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` (:236) still reduces per base_id by
   max and was never updated. `Pass2FdrSidecar.cs:605` calls it and then overwrites
   `ExperimentPrecursorQvalue`. Under `protein-compact` it is worse than a no-op: off-stratum
   survivors keep pass-1 mean-best-N q while on-stratum survivors get MAX q, so **one reported
   column mixes two aggregation schemes**. Verified independently by tracing :605 -> :613.
2. **[2] No pass discriminator on the shared experiment-QMap primitives**, so the pass-2 retrain
   re-aggregates the post-reconciliation survivor pool, where the premises break: gap-fill rows are
   appended (inflating a group's observation count with fabricated detections, inverting the
   reproducibility metric) and the decoy floor comes from the compaction-enriched survivor decoys
   rather than the full null.
3. **[3] `OSPREY_EXPERIMENT_AGG` is absent from `FirstJoinTask.ValidityKey`.** A warm rerun in the
   same output dir with the flag flipped reuses the previous mode's cached pass-1 results, skips
   `FirstJoinTask.Run` entirely (so the typo warning cannot fire either), and is recorded as a
   clean A/B point. Same silent-corruption class the #4509 warning was added to prevent, on a much
   likelier trigger.
4. **[4] Streaming vs resident floor are different estimators.** Interpolating uniformly inside a
   0.001 bin vs between two observed values - they disagree by ~5.8e-4 on this PR's own fixture and
   can never agree. Worst case: scores `>= RANGE_MAX` are counted in `_count` but placed in no bin,
   so if over half the decoys exceed 100 the bin walk falls off the end and returns **+100 as the
   floor - above every real score, converting the intended demotion into a promotion**.
   `OSPREY_MEANBEST2_FLOOR_PCT` gets no [0,100] validation.
5. **[5] `StreamingDecoyFloor.Add` casts a possibly-NaN double to an int bin index.** TFM-divergent:
   net472 yields `int.MinValue` -> `_bins[-2147483648]` throws mid-Stage-5; net8.0 saturates to 0,
   silently counting the NaN as -100.0. The house pattern already exists in
   `FeatureContributions.cs:190/262-269`.
6. **[6] `MeanBestNAcc.Add` has no NaN handling** and, unlike the MAX aggregation it replaces, is
   not structurally NaN-immune: a NaN lands in the top slot, breaks the ascending invariant, can
   never be evicted, and evicts a real score. Every row of that base_id then aggregates to NaN, the
   target silently loses its competition, and in `AccumulatePeptideReps` a NaN first-representative
   can never be replaced - stranding a whole peptide.
7. **[7] The N=4 parity fixture is arithmetically degenerate.** `nObs = n + rng.Next(nFiles - n + 1)`
   with `nFiles = 4, n = 4` is `4 + rng.Next(1)` == 4, so `_len` fills without ever entering the
   `else if (score > _top[0])` eviction branch. The top-N eviction - the new algorithm - has **no
   independent value oracle anywhere**, and the N=2/3 parity tests cannot catch a wrong-element
   eviction because both sides call the same struct.
8. **[11] The new tests read ambient `OSPREY_MEANBEST2_*` env vars** through uninjectable
   `static readonly` fields, so they fail on the machine running a floor sweep. Precedent for the
   fix is `UseFdrProjection { get; set; }` in the same file.
9. **[12] The floor has zero streaming/resident parity coverage by construction** (all three
   fixtures give every group >= N observations, so the `(n - _len) * floor` term is multiplied by
   zero on both sides), and `BuildPepWinnerMap` is never asserted in mean-best mode.
10. **[9][13][14] Doc/naming defects**: `OSPREY_MEANBEST2_FLOOR_MEAN` silently shadows an
    explicitly-set `..._PCT`; the `MeanBest2*` names and the `TargetDecoyCompetition` spec still
    describe N=2 only; the flag doc claims a protein max roll-up that does not exist (protein q
    moves via `ProteinFdrEngine.RunSecondPass`'s `EffectiveExperimentQvalue` gate instead).

## Deferred to a separate PR

- **[15] Resident-path memory/perf**: `ComputeBaseIdMeanBestN` builds a `List<double>` of every
  decoy row (~2.15 GB at 82 files) and full-sorts it to read one percentile, allocates a
  `double[len]` aggregate (~2.75 GB), and is invoked twice per pass on identical arrays. Wants a
  bounded selection and a single threaded-through aggregate, plus a `Test-PerfGate.ps1` run - too
  much to fold into a correctness fix.
- **Conventions bundle**: a braceless `for` with a 9-line body in `FdrTest.cs:2174`
  (`STYLEGUIDE.md:65`), `--` used as an em-dash in 10 added comment lines (`STYLEGUIDE.md:254`).
  Folding these in if the diff stays small.

## Tasks

- [ ] [3] Fold `OSPREY_EXPERIMENT_AGG` into `FirstJoinTask.ValidityKey`
- [ ] [5] NaN + negative-bin guard in `StreamingDecoyFloor.Add`
- [ ] [6] NaN guard in `MeanBestNAcc.Add`
- [ ] [4] Overflow bin + percentile-range validation in the streaming floor
- [ ] [1][2] Scope mean-best-N to the FIRST pass; refuse the combination that would mix schemes
- [ ] [11] Make the floor toggles injectable so tests do not read ambient env
- [ ] [7] De-degenerate the N=4 fixture + add an eviction value oracle
- [ ] [12] Floor-path parity coverage (groups with < N observations) + assert the PEP map
- [ ] [9][13][14] Doc + shadowing fixes
- [ ] Gates: Build-Osprey -RunTests -RunInspection, then `regression.ps1 -Dataset All`

## Regression Test

Flag-off byte-identity must hold exactly as before (`regression.ps1 -Dataset All`). The new
coverage is flag-ON: eviction oracle, floor-path parity, PEP map assertion, and NaN robustness.

## Progress Log

### 2026-07-31 - Branch created

Off master `d030522344` (the #4509 squash). Review output and full triage in the conversation of
2026-07-31; the merged TODO is `ai/todos/completed/TODO-20260728_osprey_mean_best2.md`.
