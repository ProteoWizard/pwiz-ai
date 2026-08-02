# Osprey: fix the defects a post-merge code review found in mean(best-N)

## Branch Information
- **Branch**: `Skyline/work/20260731_osprey_mean_best2-fix` (C:\proj\pwiz, off master d030522344)
- **Base**: `master` (d030522344)
- **Module**: `osprey`
- **Created**: 2026-07-31
- **Status**: In Progress
- **Fixes**: defects in [#4509](https://github.com/ProteoWizard/pwiz/pull/4509) (merged 2026-07-31)
- **PR**: [#4512](https://github.com/ProteoWizard/pwiz/pull/4512) (open 2026-07-31)
- **Follow-on issue**: [#4511](https://github.com/ProteoWizard/pwiz/issues/4511)
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

- [x] [3] Fold `OSPREY_EXPERIMENT_AGG` into `FirstJoinTask.ValidityKey` (+ floor vars, gated)
- [x] [5] NaN + negative-bin guard in `StreamingDecoyFloor.Add`
- [x] [6] NaN guard in `MeanBestNAcc.Add`
- [~] [4] Overflow bin counted; percentile-range validation INCOMPLETE (see below)
- [~] [1][2] Pass-1 scoping HALF-DONE (projection gated, resident not); protein-compact refused
- [x] [11] Make the floor toggles injectable so tests do not read ambient env
- [x] [7] De-degenerate the N=4 fixture + add an eviction value oracle
- [x] [12] PEP map asserted. Floor-path parity coverage STILL MISSING (see below)
- [~] [9] Both-floors refusal added (gated). [13][14] docs NOT done
- [x] Gates: 566/566, 0 inspection warnings, `regression.ps1 -Dataset All` 18/18

## Regression Test

Flag-off byte-identity must hold exactly as before (`regression.ps1 -Dataset All`). The new
coverage is flag-ON: eviction oracle, floor-path parity, PEP map assertion, and NaN robustness.

## Progress Log

### 2026-08-01 (night session) - all 12 handoff items implemented

Commit `51d66c0b9` (20 files, +1192/-162) on top of `4a0e8cd5d`. Gates: **571/571 tests, 0
inspection warnings.** Handoff for the next session:
`ai/.tmp/handoff-20260801_osprey_mean_best2-fix.md`.

**Phase 1 (correctness)** - all five done. The blocker (item 1) is closed: `applyExperimentAgg`
now threads through the RESIDENT path (`RunPercolatorStreaming` ->
`ScorePopulationAndComputeFdr` -> `ComputeStreamingCompetitionQvalues` -> both full-length
wrappers), gated on `passLabel == FIRST_PASS_LABEL` exactly as the projection path is, so the two
byte-identity oracles agree again under the flag.

**Item 3 got a stronger fix than planned.** Rather than "narrow the check and say it is inferred",
the pass-1 arm is now RECORDED in the 1st-pass model sidecar (`FirstPassModelIO`, new optional
`ExperimentAgg` field) and carried on the `FirstPassPercolatorModel` byproduct, so a merge node
gates on the arm that TRAINED the model instead of its own environment - killing the false
negative (mixed column, no refusal) AND the false positive (stale exported variable aborts a
consistent run). Added WITHOUT bumping `SchemaVersion` on purpose: `FirstPassModelIoTest` pins
that version 2 loads as null, so a bump would make every pre-existing sidecar unreadable, which on
a merge node is the hard fail-fast rather than graceful degradation. Legacy sidecars report null =
UNKNOWN and the refusal falls back to the process env, saying so in the message.

**Item 2**: `transfer-compete` refused alongside `protein-compact`. protein-compact yields a MIXED
column (two aggregations, unauditable); transfer-compete yields a uniformly-MAX column, which is
internally consistent but makes a mean(best-N) run indistinguishable from a default run in its own
output. Both refused; the false comment about "the other frozen modes" corrected.

**Three findings worth keeping** (full detail in the handoff):

1. **The streaming-vs-resident floor bound is `bin width + local decoy spacing`, not bin width.**
   Asserting bin width alone fails by ~18x on a sparse fixture: the resident estimator interpolates
   BETWEEN two observed decoy scores, the streaming one WITHIN one histogram bin, so where decoys
   are sparser than bins the disagreement is set by the DATA SPACING. Production (millions of
   decoys, narrow range, several per bin) does collapse to the bin width. The "~5.8e-4 on this PR's
   own fixture" figure in finding [4] above was a dense-fixture number, not a bound.
2. **Conservative q depends only on the target/decoy SEQUENCE down the ranked list.** An
   aggregation that reorders units without crossing a target past a decoy leaves every q identical -
   so a mean(best-N) fixture that does not force a crossing is VACUOUS. The first version of the
   wrapper/map test was exactly that.
3. **[14] confirmed and fixed: mean(best-N) is NOT rolled up to protein.**
   `ProteinFdr.CollectBestPeptideScores` ranks protein groups by the max RAW per-peptide SVM score
   and never reads the aggregate; the flag reaches protein results only through which peptides
   clear the experiment-q gate. The `EXPERIMENT_AGG_MEAN_BEST_PREFIX` doc comment claimed a protein
   max roll-up that does not exist; comment and `TargetDecoyCompetition` class spec both corrected.

**Testability change to review**: `OspreyEnvironment.MeanBestN` is now a settable property
(env-initialized, mirroring the floor toggles), and `ExperimentAgg` / `ExperimentAggMeanBest` are
COMPUTED from it rather than separately snapshotted - which is what made the validation,
description and validity-key logic testable at all. Nothing in the pipeline writes it.

**Still outstanding**: #4511 items 2/3/4 (gap-fill run-count exclusion, experiment-level q ladder,
resident-path perf) remain by design. `/code-review max` from `C:\proj\pwiz` is the required next
step before merge - it is user-invoked and two prior rounds of it found real bugs every automated
gate missed.

### DECIDED 2026-08-01 (Brendan): ship this PR, defer early-erroring

Confirmed reading of what this PR achieves: the mean(best-N) experiment q is carried through to the
REPORTED output **only under `OSPREY_PASS2_QVALUE=transfer`**, which writes
`entry.ExperimentPrecursorQvalue = rec1.ExperimentPrecursorQvalue` straight from the pass-1
`.1st-pass.fdr_scores.bin` record. The other three modes do not:

| mode | reported experiment q under mean(best-N) |
|---|---|
| `transfer` | mean(best-N), carried through - **the only end-to-end supported mode** |
| `percolator` (default) | MAX - the statistic is silently lost after pass 1 |
| `transfer-compete` | refused by this PR |
| `protein-compact` | refused by this PR |

Making `transfer-compete` / `protein-compact` aggregate-aware is a follow-up sprint (it depends on
the gap-fill run-count exclusion, #4511).

**Brendan proposed erroring at the START of the run for every mode that is not `transfer`,
`percolator` included, so the incompatibility is immediate rather than discovered hours in.
DEFERRED on purpose** - it is not being done in this PR. Two reasons: it would break the existing
mean-N sweep workflow (pass-1 outputs carry mean(best-N) regardless of pass-2 mode, and the
35-cohort series / PICK_LDA cells read the pass-1 `fdpView`, so those scripts would each need
`OSPREY_PASS2_QVALUE=transfer` added), and a new commit invalidates a TeamCity result that took
~4.5h to get an agent.

**It should land AFTER [TODO-20260727_osprey_pass2_fdr_default.md](TODO-20260727_osprey_pass2_fdr_default.md)**,
which retires `percolator`. That is the priority, and it collapses the matrix above from four modes
to two or three, so the erroring becomes a much smaller and less disruptive change.

Implementation notes for whoever writes it (both were established while scoping it):
* It must be TWO-TIER. A startup check can only read THIS process's environment, which on a
  `--task SecondPassFDR` merge node says nothing about what pass 1 did - the exact unsound inference
  this PR removed. So: startup refusal for the straight-through case, with the existing
  provenance-based check (gating on the arm recorded in `<stem>.1st-pass.model.json`) kept as the
  merge-node backstop. Same shape as the `ValidateExperimentAggSettings` double-call already here.
* It must be scoped by `SelectedTask`. `--task FirstPassFDR` stops after Stage 5 and never reaches
  pass 2, so a blanket startup error would refuse a valid FirstJoin-only HPC leg. Same switch as
  `Program.ExperimentAggFileCount`.

### 2026-08-02 - `/code-review max`, master merge, and the final fix round

Brendan ran `/code-review max` (15 findings) and merged #4513 ahead of this PR, which put the branch
in conflict. Both handled:

* **Merged master** (`00cd48c93`). One conflicting file, `Pass2FdrSidecar.cs`: #4513 wrapped the
  streamed competition in a per-file `ProgressReporter` and moved `ReadFile` inside it. Resolved by
  keeping #4513's structure verbatim and hoisting the mean(best-N) refusal above it, so the refusal
  fires before the reporter is constructed.
* **Acted on 4 findings** (`ab8ff4bb5`), chosen on risk/reward rather than count - see
  `ai/.tmp/review-max-4512-triage.md` for the full disposition of all 15.

**Governing principle Brendan stated, now written into `ai/docs/osprey-development-guide.md`:**
environment variables here are **development and diagnostic instrumentation, not a supported user
interface**. Bulletproofing is deferred until a capability is promoted to a command argument (at
which point the env var is typically sunset). That single principle retires five of the fifteen
findings, and it is why `protein-compact` + `OSPREY_PROTEIN_COMPACT_RETRAIN` was fixed as a
DOCUMENTATION correction rather than by adding a guard to the A/B lever.

**A finding that turned out to be narrower than reported, worth remembering:** the review said the
floor path at N=2 - the arm #4484 actually measures - was untested, because the parity fixture gave
every unit the same floor weight. I changed the fixture, then mutation-tested it by shifting BOTH
floor estimators by +7.0, and the parity test **still passed**. The reason is structural: a parity
test compares two implementations against each other and is blind to an error they SHARE. What did
go red was the value-oracle set (`TestMeanBest2AggregationAndFloor`, `TestMeanBest3Aggregation`),
which asserts exact aggregates against a known decoy median and does cover N=2. **So floor
correctness at N=2 was never untested**; the reviewer had examined only the parity test. The fixture
change was kept on the narrower ground that assertion (2) was degenerate at N=2 (one uniform weight
makes the aggregate a monotonic transform, so it could not report even a between-path divergence).

Deliberately NOT done, each a risk/reward call: the parity tests still oracle against test-local
re-implementations (rewiring risks a `CompeteAll` vs `CompeteFromIndices` rabbit hole with no review
left to catch it); `regression.ps1` mode-4 ordering (TeamCity #187 already ran mode 4 green, and its
failure mode cannot produce a false GREEN); and the env-var hardening class above.

### Final state of the night session

Branch pushed as `b1d75bffa` (three of my commits plus a merge of master, which had been merged into
the PR branch remotely while I worked). PR #4512 body updated. **TeamCity Osprey Perf/Regression
triggered on `pull/4512`, build 4118112.**

| Gate (on `b1d75bffa`) | Result |
|---|---|
| Debug build, tests, inspection | 572/572, 0 warnings |
| `regression.ps1 -Dataset Stellar` | PASSED - all five legs incl. the two new ones |
| Flag-ON liveness | mode1 FAIL + mode2/3/4 PASS - the correct pattern |
| **TeamCity Osprey Perf/Regression** | **SUCCESS** - build #187 (4118112), Stellar + Astral + perf |
| **PR #4512 checks** | **18/18 SUCCESS, MERGEABLE, none pending** |

An independent fresh-context review found **no Critical issues** and confirmed the headline claims.
Three of its findings were fixed (`ProgramTests` ambient-environment isolation - a hole this very
branch created by moving the validation into `ValidityArgs`; an ungated `MeanBestN` read in
`RunStreamingFirstPass`; and the missing pass-label mapping test). Four are carried forward in
`ai/.tmp/handoff-20260801_osprey_mean_best2-fix.md` - chiefly **M2**, making `applyExperimentAgg` a
REQUIRED parameter so the compiler forces every call site to state its intent, since a pass-scoped
flag defaulting to "aggregate" is what produced both prior regressions.

**A recurring trap worth internalizing, since it caught me twice tonight**: conservative q is a
function of the target/decoy SEQUENCE down the ranked list and nothing else. An aggregation change
that reorders units without crossing a target past a decoy produces ZERO q difference. Two
separate first-draft fixtures looked like they exercised mean(best-N) and provably did not; both
were caught only by an explicit non-vacuity assertion written into the test. Any future
mean(best-N) fixture needs a deliberate target-crosses-decoy construction, and the test should
assert that it happened.


### 2026-07-31 - PR #4512 open, but DO NOT MERGE YET

Two commits: `c0408d0c2` (the review fixes) and `73af9f8ba` (two default-path regressions in the
first one). Gates green: 566/566, 0 inspection warnings, `regression.ps1 -Dataset All` 18/18.

**A SECOND `/code-review max` on `c0408d0c2` found 15 more findings, including two DEFAULT-path
regressions I introduced** - the first PR (#4509) had none. Both fixed in `73af9f8ba`:

* `ValidityKey` appended `;expagg=max` UNCONDITIONALLY. `NormalizeExperimentAgg` returns the
  constant `"max"` when the variable is unset, so every output directory produced before the commit
  would fail `IsValid` and re-run Stage 5 FDR + protein FDR + compaction - hours at 82 files - to
  reproduce byte-identical output. Now appended only when the aggregation is engaged, and covering
  the floor toggles too.
* The both-floor-flags refusal fired on DEFAULT runs that never read those variables, so an operator
  who left a sweep exported could not run an ordinary analysis. Now gated on `ExperimentAggMeanBest`.
* Also: `MeanBestNAcc.First` had no guard, so a NaN as a base_id's FIRST observation still poisoned
  the group (my own test put the NaN second, so it passed). Infinity excluded too - `0 * Inf` makes
  the missing-run term NaN for even fully-detected groups. `MeanBestFloorOverspecified` made
  computed rather than snapshotted, since the toggles are now settable properties.

**GATE GAP, worth fixing independently**: `regression.ps1 -Dataset All` passed 18/18 on the commit
that had broken warm-resume for every existing output directory, because the gate always uses FRESH
directories. **The byte-identity gate is structurally blind to cache-invalidation regressions.**

### STILL OPEN on this branch - finish before merging

Full detail in [#4511](https://github.com/ProteoWizard/pwiz/issues/4511); the blocker is the first:

1. **The pass-1 scoping is HALF-DONE.** The full-length wrappers
   `PercolatorQValues.ComputeExperimentPrecursorQvalues` / `ComputeExperimentPeptideQvalues` never
   got the `applyExperimentAgg` parameter, so the RESIDENT 2nd pass still re-aggregates. The
   projection path IS gated - so the resident and projection paths, which `Pass2FdrSidecar` treats
   as a byte-identity oracle for each other, now DISAGREE under the flag. This is a correctness bug
   in the fix itself.
2. `transfer-compete` + mean(best-N) is still unguarded (only `protein-compact` is refused), and the
   refusal infers the cached pass-1 arm from the CURRENT process env - wrong on a merge node.
3. `MergeNodeTask` / `PerFileRescoreTask` validity keys not updated alongside `FirstJoinTask`.
4. Streaming floor: `pct >= 100` / `pct <= 0` early returns bypass the new refusals, and the new
   throws abort where the resident twin clamps (single-decoy) - they can kill a multi-hour run at
   the end of Stage 5. Mirror the resident semantics instead of throwing; validate at startup.
5. `FdrTest` still reads ambient env (no `[TestInitialize]`); the missing-run floor still has ZERO
   streaming-vs-resident parity coverage.

### DECIDED with Brendan (design settled, not yet implemented)

* **Gap-fill rows must be EXCLUDED from the aggregation's run count.** Gap-fill changes k, which
  REMOVES A FLOOR TERM - the largest single move the aggregate can make, right at the decision
  boundary. Decoys are not gap-filled, so under mean(best-N) that boost is target-only against an
  unmoved null: systematically anti-conservative. Under max the same asymmetry was near-harmless
  (max ignores weak additions). Once this holds, the protein-compact refusal can be REPLACED by a
  mean-best-N-aware re-competition.
* **An experiment-level score->q ladder sidecar** lets `transfer` work under mean(best-N), whose
  changing k breaks transfer's "experiment q is invariant to reconciliation" premise. It is
  **O(precursors), not O(files x precursors)** - NOT the artifact #4438 removed. Must be **written
  to disk** (the HPC merge node never trained pass 1), **join-wide not per-file** (per-file
  replication would restore the O(files x precursors) footprint on disk), and should carry a
  **provenance header** naming the pass-1 arm + floor mode - which also fixes item 2 above.

**Next session handoff**: For the detailed startup protocol, phase-ordered work plan and gate list,
read `ai/.tmp/handoff-20260731_osprey_mean_best2-fix.md` before starting work. It is scoped for a
`/night-session`: finish #4512 to merge-ready and make mean(best-N) genuinely user-consumable behind
the flag (logging of the active mode, N bounds, docs for all three env vars, floor-path test
coverage, and a warm-rerun regression leg to close the gate gap that hid the last regression).

### 2026-07-31 - Branch created

Off master `d030522344` (the #4509 squash). Review output and full triage in the conversation of
2026-07-31; the merged TODO is `ai/todos/completed/TODO-20260728_osprey_mean_best2.md`.
