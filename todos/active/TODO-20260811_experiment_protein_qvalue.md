# One experiment-wide protein q, written per pass, replacing run/experiment protein q

## Branch Information
- **Branch**: `Skyline/work/20260811_experiment_protein_qvalue`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `Skyline/work/20260808_peak_coassignment_diagnostics` (PR #4558) - **rebase onto
  `master` once #4558 merges**, the same way #4558 was based on #4557
- **Created**: 2026-08-11
- **Status**: In Progress
- **GitHub Issue**: [#4559](https://github.com/ProteoWizard/pwiz/issues/4559)
- **Module**: `osprey`
- **Other labels**: candidate `tech-debt` (this is a naming/structure fix, not a bug fix -
  no reported output moves)
- **PR**: (pending)
- **Requester/Reporter**: none - Osprey developers on Osprey code, no credit line.

## Objective

**Agreed with Brendan 2026-08-12.** Collapse the two per-entry protein q-value fields into
ONE experiment-wide protein q, and write it into BOTH sidecars with the value that pass
computed:

* `RunProteinQvalue` -> `ExperimentProteinQvalue` (C#) / `run_protein_qvalue` ->
  `experiment_protein_qvalue` (Rust), everywhere including the sidecar column name
* 1st-pass sidecar carries the **pass-1** value (unchanged from today)
* 2nd-pass sidecar carries the **pass-2** value (new - today it unconditionally carries the
  pass-1 value)
* the pass-2 value has no consumer yet; that is accepted, and closing the C#/Rust
  `--fdr-level protein` gap is a **separate, later** piece of work

This makes protein q follow the same rule the precursor and peptide q's already follow:
**one field, pass encoded by which sidecar it lives in.**

## Why - the structural defect underneath #4559

Read `ai/todos/completed/TODO-20260809_fdr_sidecar_parity.md` (#4557) first for the sidecar
seeding this builds on.

For precursor and peptide, pass is encoded by **which sidecar**: one `FdrEntry` field,
overwritten per pass, two files. For protein, pass is encoded by **which field**:

| field | what it actually is |
|---|---|
| `RunProteinQvalue` | pass-1 experiment-wide protein q. **Not per-run** - see measurement 3 |
| `ExperimentProteinQvalue` | pass-2 experiment-wide protein q. Written once, **never read in C#** |

So in the 2nd-pass sidecar, `run_protein_qvalue` is the one column that is
**unconditionally a pass-1 value**. The others are pass-2 values, carried from pass 1 only
in specific reasoned cases (off-stratum, or `transfer`'s deliberate carry). The protein
column is carried always - not by decision, but because no pass-2 mode writes it and #4557
seeded it from the 1st-pass sidecar to stop it persisting as a `ResetScores()` default.

**That is why #4559's question was malformed.** "Should a gap-fill entry carry 0.0 or 1.0?"
only arises because a pass-1 quantity is stored in a pass-2 file and then asked what it says
about rows that did not exist in pass 1. Once the 2nd-pass sidecar carries the pass-2 value,
a gap-fill row gets whatever the second-pass protein FDR computes for it - from a pool that
includes it, propagated by sequence like every other row. No special case, and consistent
with what the peptide q already does.

## Measured 2026-08-11 - the evidence the design rests on

Reproduced exactly (133/116/141 = 390). Run log `ai/.tmp/regression-projoff-4559.log`; run
dir `C:\proj\pwiz\pwiz_tools\Osprey\TestResults\regression-20260811_044537` (`-KeepOutput`).
Scripts: `ai/.tmp/analyze-gapfill-protq-4559.ps1`, `ai/.tmp/check-protq-per-run-4559.ps1`,
decoder `ai/.tmp/gapfill-protq-decoder.ps1`.

**1. The diverging population IS the gap-fill population - exactly, not a subset.**

| | count |
|---|---|
| gap-fill records (in 2nd pass, absent from 1st pass) | **390** |
| diverging records | **390** |
| ...straight-through value exactly 1.0 | 390 |
| 1st-pass sidecar `run_protein_qvalue` disagreements | **0** |

**2. The chain assigns the value straight-through ITSELF uses for that precursor.**
`entry_id` is library-derived and stable across files:

| | count |
|---|---|
| diverging entry_ids found in another file's straight 1st-pass sidecar | **390 / 390** |
| chain value MATCHES that established value | **390** |
| chain value DIFFERS | **0** |

**3. `run_protein_qvalue` is per-RUN in name only.** Straight-through 1st-pass sidecars,
no chain involved:

| | count |
|---|---|
| distinct entry_ids | 484,747 |
| appearing in 2+ files | 483,820 |
| ...carrying ONE value across those files | **483,820** |
| ...carrying DIFFERENT values across files | **0** |

## Field inventory - established from the code

Six q-value fields on `FdrEntry` (`:71-76`). Where each is computed:

| field | pass 1 | pass 2 / Stage 7 |
|---|---|---|
| run precursor | per-file TDC | recomputed (`ApplyFileRunQ`) |
| run peptide | per-file: best precursor per peptide (`PercolatorSampling.BestPrecursorPerPeptide:49`) -> TDC -> propagate | recomputed |
| experiment precursor | best obs per precursor across runs -> experiment TDC | on-stratum recomputed; off-stratum carried; `transfer` gap-fill inherits the precursor's cross-file pass-1 value (`AssignPerRunQ:1738`) |
| experiment peptide | same, rolled up | same |
| **run protein** | parsimony over peptides passing RUN-level peptide q -> picked-protein -> propagate by sequence. **Experiment-wide in scope** | **nothing writes it** |
| **experiment protein** | not set (stays 1.0) | set by `RunSecondPass`, **never read in C#** |

Notes that matter for the change:

* `CollectBestPeptideScores` (`ProteinFdr.cs:854`) takes max raw SVM `Score` per sequence over
  ALL files, targets and decoys, with **no q gate**. The detected-peptide set gates which
  peptides enter the parsimony graph, not which scores compete.
* `OSPREY_EXPERIMENT_AGG=mean-best-N` applies to precursor, rolled up by max to peptide, and
  **never to protein** (`OspreyEnvironment.cs:393-404`) - it reaches protein results only
  through which peptides clear the experiment-q gate.
* The protein numbers users see come from `ProteinFdrResult.GroupQvalues` (per GROUP) -
  `OspreyReportWriter.cs:111`, `OspreyFileDiagnostics.cs:1998` - not from either per-entry
  field. **This is why the golden should not move; verify, do not assume.**

## Live consumers - what the rename must not break

The single field is a **Stage-5/6 gate** before Stage 7 overwrites it. All three gates run
BEFORE the second-pass protein FDR exists, so the one-field collapse is safe:

* `FirstPassFdrTask.cs:1420` - resident compaction protein-rescue gate
* `FirstPassFdrTask.cs:2742` - streaming compaction gate, reading it back out of the
  **1st-pass sidecar**. This is why the field must stay in the 1st-pass sidecar.
* `ConsensusRts.cs:249` - consensus RT protein rescue

`ExperimentProteinQvalue` has **zero** read sites in C#. Rust does read it
(`types.rs:1090`, `FdrLevel::Protein`), so this is a feature gap, not dead code in the
shared design.

## Plan

1. **C#**: collapse to one `ExperimentProteinQvalue` on `FdrEntry`; `ResetScores()` drops to
   seven fields. `PropagateProteinQvalues`'s `setRun`/`setExperiment` booleans collapse to
   one write.
2. **C#**: rename the sidecar column and `FdrScoreRecord` member; rename
   `FdrScoresSidecar.PatchRunProteinQvalues` accordingly.
3. **C#**: patch the **2nd-pass** sidecar with the pass-2 value after `RunProteinFdr`
   (`SecondPassFdrTask.cs:197`; the sidecar is written at `:175`, so this is a patch, not a
   reshuffle). `PatchRunProteinQvalues` already takes a `Pass` parameter, streams one record
   at a time and commits atomically - the streaming first-pass path already uses it this way.
4. **C#**: `RestorePass1Scalars` stops seeding the protein q into pass 2 (step 3 supersedes
   it); it keeps seeding `Score` and `Pep`. Fix the now-doubly-wrong comment at
   `Pass2FdrSidecar.cs:560-563`, which claims a gap-fill entry "correctly keeps the defaults,
   which is where the distributed route leaves it too" - measurement 2 refutes that.
5. **Rust**: the same four, in `pipeline.rs` / `types.rs` / `protein.rs`.
6. Rebaseline `mode3` and the cross-impl sidecar leg (the pass-2 protein column legitimately
   changes value); confirm the golden does NOT move.

### Sequencing note - review AFTER the rebase, not before

`/code-review` diffs `master...HEAD`. This branch is based on #4558's tip, so running it now
would review #4558's diff as well as this one - wasted effort and findings that belong to
another PR. Rebase onto master once #4558 merges, THEN review, then open the PR. Same reason
the PR itself should not be opened early (Copilot auto-reviews on open).

### Open implementation questions

* **Version bump?** The layout does not change - same offset, same width - only the pass-2
  column's MEANING does. A v4 -> v5 bump would stop an older reader silently misinterpreting
  it. Leaning yes, but it lands right after #4558's v3 -> v4 bump, so worth a deliberate call.
* **`--fdr-level protein` in C#** is explicitly OUT of scope here (Brendan, 2026-08-12) -
  file it as a follow-up rather than growing this PR.
* **Off-stratum gap-fill experiment q** appears to stay 1.0 in the default mode (no pass-1
  stash). Same shape one level down, adjacent to #4560. UNMEASURED - offered to Brendan, not
  yet taken up.

## The gate found something bigger than #4559 - 2026-08-12

`mode1c` red on the DEFAULT arm, Stellar 3-file
(`ai/.tmp/regression-4559-redcheck.log`):

```
experiment_protein_qvalue is identical to the 1st-pass column on all 331490 shared record(s)
  ... 331501 ... / ... 331518 ...
```

**All 994,509 shared records**, not the 390 gap-fill ones. #4559 reported the sliver where
the two ROUTES disagreed; the column was never a pass-2 value for ANY record, on either
route, on the arm TeamCity actually runs. That is the defect the collapse removes, and it is
why a two-route comparison could not see it - both routes copied the same pass-1 value.

## Red -> green verified on Stellar - 2026-08-12

Same command both times (`regression.ps1 -Dataset Stellar -KeepOutput`, default arm), the
only difference being the fix commit. Logs `ai/.tmp/regression-4559-redcheck.log` and
`ai/.tmp/regression-4559-greencheck.log`.

| leg | before the fix | after |
|---|---|---|
| `mode1c` (new) | **FAIL** - all 994,509 shared records identical to the 1st-pass column | **PASS - 24,805 of 994,509 moved** |
| `mode1` (vs golden) | PASS | **PASS - the golden did NOT move** |
| `mode3` (sidecars ==straight) | PASS - blind to it, both routes copied the same value | PASS (2,443,597 records) |
| every other leg | PASS | PASS |

Two things this pins down:

1. **The change is sidecar-only.** The golden holding across the fix is the evidence that
   gap-fill / protein q on the per-entry field feeds no reported output - predicted from the
   code (Stage 7 reads `ProteinFdrResult.GroupQvalues`, per GROUP), now measured.
2. **`mode3` was green in BOTH runs.** The two-route comparison cannot see this class of
   defect, which is the argument for `mode1c` existing at all rather than extending mode 3.

## State of the branches - 2026-08-12

**C# `Skyline/work/20260811_experiment_protein_qvalue`** (on #4558's tip `5efdb058b7`),
3 commits, each gated (build + 579 tests + zero-warning inspection):

| commit | what |
|---|---|
| `b869b6e2a6` | the field collapse + rename; no computed value changes |
| `b642d4a244` | `Test-Pass2ProteinQvalue` + regression.ps1 `mode1c`; RED as added |
| `032087df19` | `PatchPass2ProteinQvalues` after `RunProteinFdr`; seed drops the protein q |

**Rust `maccoss/osprey` branch `fix/one-experiment-protein-qvalue`**, 1 commit `6183d12`,
`cargo fmt --check` / `clippy -D warnings` / 579 tests all green. LF verified with
`git cat-file blob | tr -cd '\r' | wc -c` = 0.

### Two things found while porting

* **A latent C#/Rust divergence, now removed.** C#'s second-pass `PropagateProteinQvalues`
  passed `(setRun: true, setExperiment: true)`; Rust passed `set_run: false`. So after Stage 7
  C# held the pass-2 value in the run field and Rust held the pass-1 value. Unobservable
  today - `effective_run_qvalue(Protein)` has no caller - but it was a real disagreement that
  every parity gate was green through. The collapse makes it unrepresentable.
* **Rust's sidecar is still v3/60-byte; the C# branch is v4/68-byte.** #4558's Rust twin has
  NOT landed. So the cross-impl sidecar leg cannot be run meaningfully until it does - that
  is a #4522/#4558 dependency, not something this branch should paper over.

## Tasks

- [x] Reproduce the failure on the projection-off arm with `-KeepOutput`
- [x] Establish the mechanism from the code (chain propagates, straight-through does not)
- [x] Measure: diverging set == gap-fill set; chain value == the established peptide value;
      the field is per-run in name only
- [x] Confirm the live consumers and that all three precede Stage 7
- [x] Design agreed with Brendan; 0.0-vs-1.0 framing retired as malformed
- [x] Branch created off #4558's tip
- [ ] C# rename + one-field collapse
- [ ] C# pass-2 sidecar patch after the second-pass protein FDR
- [ ] Rust twin
- [ ] Decide the version-bump question
- [ ] `regression.ps1 -Dataset Stellar`, then `-Dataset All`; golden must NOT move
- [ ] Cross-impl sidecar leg green with both sides changed
- [ ] Rebase onto master when #4558 merges
- [x] File the `--fdr-level protein` C#/Rust gap as a follow-up issue -
      [#4561](https://github.com/ProteoWizard/pwiz/issues/4561)
- [x] Update `docs/08-protein-parsimony.md` + `docs/14-intermediate-files.md` (`bd4c289342`)

## Regression Test

- **Test name**: (pending)
- **Test project**: `Osprey.Test` (`Pass2FdrSidecarTest.cs` exists and `Osprey.Tasks` has
  `InternalsVisibleTo Osprey.Test`, so the seam can be driven directly), plus
  `regression.ps1` mode 3.
- **The guard this needs**: an assertion that the 2nd-pass sidecar's protein column is the
  PASS-2 value, not the pass-1 one. Mode 3 alone cannot see it - it compares the two routes
  against each other, and both would be equally wrong. This is the
  [[feedback_shared_defect_hides_from_parity]] shape: add the missing comparison first,
  prove it red on current code, then fix.
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-08-11 - Session start; reproduced and measured

Filed out of #4557 as a deliberate deferral. Reproduced the 390-record divergence and
established that the chain propagates the ordinary peptide value while straight-through
leaves a `ResetScores()` default.

### 2026-08-12 - Scope changed: this is a naming/structure fix, not a 0.0-vs-1.0 decision

Walking the full q-value inventory with Brendan surfaced that the two protein fields are
pass-1 and pass-2 of the SAME experiment-wide quantity, mislabeled `Run` / `Experiment`, and
that the 2nd-pass sidecar therefore carries a pass-1 value in a pass-2 file. The gap-fill
question dissolves under the fix rather than needing an answer.

Branch recreated off #4558's tip (`5efdb058b7`) rather than master, per Brendan: #4558 is
close to landing and did the same with #4557; rebase onto master when it merges. TODO
renamed from `TODO-20260811_gapfill_run_protein_qvalue.md` to match the new scope.
