# Osprey: flipped the pass-2 and peak-pick defaults, added the I/L decoy gate

## Branch Information
- **Branch**: `Skyline/work/20260802_osprey_default_flip` (C:\proj\pwiz)
- **Rust branch**: `feature/decoy-il-gate-and-default-flip` (C:\proj\osprey, off `origin/main`)
- **Base**: `master`
- **Created**: 2026-08-02
- **Status**: In Progress
- **GitHub Issue**: [#4484](https://github.com/ProteoWizard/pwiz/issues/4484) (umbrella),
  [#4515](https://github.com/ProteoWizard/pwiz/issues/4515) (the I/L half)
- **Module**: `osprey`
- **PR**: (pending)

Consumes the remaining tasks of `TODO-20260727_osprey_pass2_fdr_default.md` (whose branch was
spent on PR #4487) and the "Osprey I/L gap" task of `TODO-20260801_decoy_similarity_gate.md`.
The two are batched deliberately: each on its own would force a golden re-baseline, and one
re-baseline is cheaper than two.

## The decision (Brendan, 2026-08-02)

Accept two defaults Mike prefers, **with reservations recorded rather than resolved**, because
both are undoubtedly better than the current default and they unblock removing pass-2 Percolator:

```
OSPREY_PICK_LDA=1
OSPREY_PASS2_QVALUE=protein-compact
```

Mike and Brendan agree pass-2 Percolator was a mistake and cannot be part of the solution: **the
linear model trained by the 1st-pass SVM must remain the model for pass 2.** Retraining it on the
compaction-depleted pool is anti-conservative - 1.57% true FDP at a nominal 1% on Stellar libdecoy
entrapment against 0.92% for the 1st-pass q, and ~9% on the 82-file SEA-AD set.

The reservations are real and stay on the record. `protein-compact` is target-conditioned
(the >=2-peptide stratum gate reads only target peptides; decoys ride in by base_id) and measured
anti-conservative at scale - 1.51% true FDP at 82 files, and slightly LESS sensitive than pass 1
(37,232 vs 37,676 @ 0.92%). `PICK_LDA` measured a small effect of INCONSISTENT SIGN across seven
A/B cells (-3.5% to +1.8% at matched true FDP). Neither is claimed to be the final algorithm; both
remain togglable, and the goldens are expected to be re-baselined again when they are refined.

The argument for the learned pick beyond Mike's preference: an additive linear model over
standardized terms is the direction Dario Amodei took for Skyline mProphet with
`LegacyScoringModel`, and a three-way product of three features whose combination in log space was
never established is unlikely to be the end state.

### A FALLING ID COUNT IS NOT A REASON TO HOLD (Brendan, 2026-08-03)

Raised when the re-baseline showed the gendecoy set accepting 27% fewer precursors. Answered, and
the answer is standing policy for this branch - do not re-open it each time a count drops:

> "Pass 2 Percolator has to go. It was over optimistic and produced a truly broken FDP v. q value
> curve. While I am not positive protein-compact will be our final Pass 2 method, but we can't sit
> on 'percolator' unwilling to change because counts go down."

Two things follow. **The comparison axis is the FDP-vs-q CURVE, not the count** - a mode that
accepts more at a nominal 1% while measuring 1.5-2.6% true FDP is not winning, it is miscalibrated,
and counting its acceptances rewards the miscalibration. **And the bar for protein-compact is
"better than percolator and honest about its limits", not "final"** - it ships togglable, its
reservations stay on the record above, and the goldens are expected to move again when it is
refined.

So no 82-file confirmation is required before the PR on the strength of a count drop. The 3-file
caveat still applies to any POSITIVE claim about magnitude; it does not turn a count decrease into
a blocker.

## What changed

### Osprey C# (pwiz)

1. **Protein-compact stratum persisted** (prerequisite, golden-neutral). The frozen 2nd-pass modes
   need the trained 1st-pass model on a distributed `--task SecondPassFDR` merge node;
   protein-compact ALSO needs `ProteinCompactStratum`, which was never persisted - so with
   protein-compact as the default, every merge-node run and `regression.ps1` mode 3 would fail
   fast. The base ids now ride in the existing `<stem>.1st-pass.model.json` as an optional
   additive property (no `SchemaVersion` bump, matching the `ExperimentAgg` precedent), written
   sorted so the artifact is stable. One file, one relay hop, one reload site - `regression.ps1`
   needed no change because the model sidecar relay already carries it.
2. **`percolator` pass-2 mode REMOVED.** An unrecognized `OSPREY_PASS2_QVALUE` is now a startup
   ERROR, raised in `Program.cs` before the pipeline runs rather than at the merge node, so a
   stale script fails in seconds instead of after Stage 1-5.
3. **`OSPREY_PASS2_QVALUE` defaults to `protein-compact`**; `transfer` and `transfer-compete`
   remain opt-in.
4. **`OSPREY_PICK_LDA` defaults ON**, `=0` opts out so the A/B stays available.
5. **I/L-normalised collision rejection in decoy generation.**

### Rust osprey

Same four behavioral changes (2-5). Rust has no `transfer` mode, which is pre-existing.

## The I/L gate

I and L have identical residue masses (113.08406), so a decoy differing from a real target only by
I<->L is precursor-mass-identical AND produces an identical b/y ladder - indistinguishable by mass
spectrometry. It is not a valid null: it is detected wherever its target twin is.

**The fragment-overlap gate cannot catch this**, and that is the point worth keeping: the overlap
gate compares a candidate to its OWN source target, while a collision is an isobaric match to a
DIFFERENT one. An exact-string audit therefore reports 0 for every library and misses the
population entirely. Simulating Osprey's own gendecoy path over the 1,390,979-target Astral set
with the overlap gate ON: **0 exact collisions, 742 I/L-isobaric ones (0.0534%)** - e.g.
`AAEESLR -> LSEEAAR`.

The normalised check SUBSUMES the exact one (a sequence without isoleucine normalises to itself),
so it replaces rather than supplements it. Carafe already shipped this (`fe25b55`); this closes
the same gap in both Osprey implementations.

**Both new tests assert the independence property** - the overlap gate PASSES a candidate the
collision index rejects - rather than just the rejection, because a test of the rejection alone
would pass equally well if the two checks were redundant.

## Findings from doing the work

### The pass-2 TODO's `applyExperimentAgg` prediction is WRONG

`TODO-20260727` states that removing the `percolator` retrain "deletes `applyExperimentAgg`
entirely". It does not. Removing the percolator MODE does not remove the 2nd-pass RETRAIN, which
is still reachable through `OSPREY_PROTEIN_COMPACT_RETRAIN=1` (the frozen-vs-retrain A/B) and as
`transfer`'s fallback. `applyExperimentAgg` remains `passLabel == FIRST_PASS_LABEL` at three
`PercolatorEngine` sites. Deleting it would mean deleting the retrain code outright and losing the
A/B, and would diverge from Rust, which keeps the same lever. Not done.

### mean(best-N) now collides with the DEFAULT mode

`Pass2FdrSidecar.cs` refuses `protein-compact` when pass 1 ran under `OSPREY_EXPERIMENT_AGG=mean-best-N`,
because the reported column would carry two statistics (on-stratum max-aggregated, off-stratum
mean(best-N)). That refusal was written when protein-compact was opt-in. As the DEFAULT it means
**every mean(best-N) run aborts unless it also sets `OSPREY_PASS2_QVALUE=transfer`.**

`TODO-20260727` predicted this case would DISAPPEAR once percolator was gone - true only if the
default became `transfer`. Under a `protein-compact` default it lands instead.

**Decision (Brendan, 2026-08-02): let it fail.** Sweep scripts add `OSPREY_PASS2_QVALUE=transfer`.
The error already names that as the fix, and a loud failure beats an effective default that
silently depends on which aggregation arm pass 1 used.

### A pre-existing test was passing vacuously

`DecoyConstructionTest.GenerationNeverEmitsARejectedCandidate` built targets with NO fragments.
`GenerateAllWithCollisionDetection` skips a fragment-less entry outright, so the assertion held
over an EMPTY decoy list - it would have passed with the gate deleted. Found because the new I/L
test asserted a decoy count and got 0. Both tests now set fragments and assert the count.

## Tasks

- [x] Persist the protein-compact stratum in the 1st-pass model sidecar (golden-neutral)
- [x] Remove the `percolator` pass-2 mode; unrecognized value aborts at startup
- [x] Flip `OSPREY_PASS2_QVALUE` to `protein-compact`
- [x] Flip `OSPREY_PICK_LDA` on
- [x] I/L-normalised collision rejection, C# and Rust, with independence tests
- [x] Golden re-baseline - **DONE and VERIFIED 26/26**, committed as `7e91b26e0` (45 files, all
      under `osprey-regression.data`, nothing stray). The first capture (`4a067fa8b`) went stale
      when `1e90d5453` and `03f31954a` landed after it; this is the re-capture, verified before
      committing.
- [x] Review finding #3: key the resume cache on the flipped defaults (`cb9b68c60`). Landed
      BEFORE the verify so one run covers both, per Brendan.
- [x] Review findings #5 / #6: pin both levers in every measurement runner (`ai` `4edbe2d`),
      including `Run-FdrBench.ps1`, which was stamping the wrong mode into `metrics.csv`.
- [x] `Test-PerfGate.ps1 -Dataset Stellar` - **PERF GATE PASSED**, no total-wall regression.
      Verdict: `ai/.tmp/perf-gate/20260804-023223Z/verdict.md`; log
      `ai/.tmp/perfgate-stellar-20260803.log`. The feared cost did not appear.

      | stage | baseline med | branch med | median delta | per-rep | gate |
      |---|---|---|---|---|---|
      | stage1to4 | 1:12 | 1:12 | +3.2% | +0.7, +4.4, +3.2 | ok |
      | stage5 | 1:14 | 1:02 | -16.2% | -14.9, -16.4, -16.2 | info |
      | stage6 | 12.1s | 10.2s | -15.7% | -21.5, -12.4, -15.7 | ok |
      | stage7 | 35.6s | **3.2s** | **-91.0%** | -90.9, -91.0, -91.4 | info |
      | blib | 3.5s | 2.5s | -35.0% | -35.0, -42.9, -28.6 | info |
      | **total** | 3:19 | 2:32 | **-23.5%** | -23.5, -17.3, -23.9 | ok |

      **DO NOT quote -23.5% as this PR's speedup.** `pwiz-perfbase` is pinned at `f4de68645`
      (2026-07-08, #4378) and the branch carries **53 Osprey commits** since that pin, so these
      deltas are "branch vs a month-old baseline", not the isolated effect of this change set.
      The gate's job is to detect a REGRESSION introduced by the branch, and it found none;
      that is the whole claim it supports.

      The stage-7 collapse (35.6s -> 3.2s, consistent across all three reps) is CONSISTENT with
      deleting the 2nd-pass Percolator retrain - Stage 7 no longer trains an SVM, it runs a
      frozen-model competition - but this measurement does not isolate it. If a precise number
      is ever wanted, the clean A/B is `OSPREY_PROTEIN_COMPACT_RETRAIN=1` against the default on
      the SAME branch binary, which is ~6 minutes on Stellar. Not run; the PR does not need it.

      `stage1to4 +3.2%` is below the 5% heavy-stage WARN line and rep 2 was noisy on BOTH legs
      (124.7s branch / 119.5s baseline against ~70s elsewhere), which is why the gate uses paired
      per-rep deltas.
- [ ] Memory band (`--timestamp --memstamp` + `ai/scripts/perfviz.py`) - **OBSERVATION, NOT A
      GATE, and DELIBERATELY NOT RUN for this PR.** Note `regression.ps1` does pass
      `--timestamp --memstamp` on every leg, but it tees each leg to a log inside that leg's run
      directory, and run dirs self-clean at `KeepRunDirs=0` - so a normal gate run leaves NO
      memstamp trace behind. Harvesting one needs a dedicated run with BOTH `-KeepOutput` and
      `-KeepRunDirs N`. Not worth it here: every regression dataset is 3 files, which structurally
      cannot speak to an O(files) accumulation, so the trace would be decoration rather than
      evidence. The real measurement already exists at 163 files in #4526. Stage 5/6 memory accumulation is already known, already measured, and tracked in
      [TODO-20260731_osprey_bounded_stage5_handoff.md](TODO-20260731_osprey_bounded_stage5_handoff.md)
      ([#4526](https://github.com/ProteoWizard/pwiz/issues/4526)) - the `CompactedEntries` buffer
      held across all of Stage 6, found from the `--memstamp` and env-var-gated runs, 90.2 GB
      private at 163 files. **Brendan, 2026-08-03: not expected to be fixed before this change
      set merges, and it does not affect the golden re-baseline.** That work is SEQUENCED AFTER
      this merge - it is waiting on percolator's removal, because the only pass-2 mode that
      plausibly needs the whole pool resident is the one being deleted. So a memory-band trace
      here is for the record; do NOT re-diagnose it, and do NOT hold the PR on it.
- [x] `Compare-EndToEnd-Crossimpl.ps1` on Stellar + Astral - **RE-RUN 2026-08-03 evening after
      both correctness fixes**, since the earlier PASS (119,088) predated them. `OVERALL: PASS`,
      bit-parity at 1e-9: `rust=117783 cs=117783 delta=0`, Stage 7 protein FDR PASS, blib content
      PASS. Both implementations moved 119,088 -> 117,783 (-1.1%) INDEPENDENTLY, which is the
      evidence that the C# and Rust changes are the same change rather than two that resemble
      each other. Walls: Rust 26:27, C# 13:50. Log `ai/.tmp/crossimpl-astral-20260803.log`.
      **The stale-binary guard fired on the first launch** (Release exe 31 s older than a CRLF
      normalisation of the new test file) and refused rather than reporting a false divergence -
      third time that guard has earned its keep in this series.
- [x] Docs: `docs/12-second-pass-fdr.md` + `docs/07-fdr-control.md` in `5848c69d5`; the remaining
      four in `d8aee4ba0` - `20-command-line.md` (env-var table listed `percolator` as a valid
      `OSPREY_PASS2_QVALUE` and described the pick model as opt-in), `06-peak-detection.md`
      (selection precedence, the env-var table, and the Rust-divergence note all said "off by
      default"), and `peak-model-training.md`, whose caveat had PREDICTED this exact re-baseline
      ("flipping it on by default is a separate, coordinated golden re-baseline ... cross-impl
      parity re-confirmed on Stellar + Astral") and now records that it happened.
      `README.md` needed no change. Note `--fdr-method percolator` is the pass-1 FDR ENGINE and is
      untouched - only the pass-2 `OSPREY_PASS2_QVALUE=percolator` MODE was removed, and conflating
      the two would be an easy and wrong edit.
- [x] `ai/docs/osprey-development-guide.md` env-var policy - **was already done** in `90e9e87`
      ("Changing or REMOVING an env var needs no deprecation ceremony"), with the
      `OSPREY_PASS2_QVALUE=percolator` removal as its worked example. Checkbox was stale.
- [ ] `/code-review max`, then open the PR; ask before triggering TeamCity Perf/Regression

## Regression Test

The primary verifier is the committed C# golden, re-baselined here. **The stratum-persistence
commit was proven golden-neutral BEFORE anything was flipped** - `regression.ps1 -Dataset Stellar`
passed all five checks (mode1 vs golden, mode2 resume x2, mode3 HPC chain, mode4 warm) - so the
entire re-baseline delta is attributable to the flips and the I/L gate, not to the plumbing.

Unit coverage added:
- `FirstPassModelIoTest` - stratum round-trips as a SET, is written in ascending order, and is
  absent (not empty) on a pre-stratum sidecar.
- `DecoyConstructionTest.CollisionCheckRejectsADecoyIsobaricToADifferentTarget` and its Rust twin
  `test_collision_check_rejects_a_decoy_isobaric_to_a_different_target`.

## BLOCKER: mode 3 (HPC chain == straight-through) fails under protein-compact

**The golden re-baseline is NOT safe to take yet.** `regression.ps1` mode 3 is a
SELF-CONSISTENCY check - the HPC 4-task chain must reproduce the straight-through run - so a
re-baseline cannot fix it; it would freeze the divergence into the committed baseline.

It passed on master and passes with the stratum-persistence commit alone. With
`protein-compact` as the default it fails on **exactly one precursor** (`DAADLLSPLALLR2`, 12
issues, all the same precursor): the straight-through run takes its best spectrum from file
_21, the HPC chain from file _22, on near-identical q (1.515e-4 vs 1.032e-4).

### Narrowed by experiment (Stellar 3-file, `-SkipResume -SkipWarmRerun`)

| pass-2 mode | stratum? | q source | mode 3 |
|---|---|---|---|
| `transfer` | no | pass-1 q carried through, every survivor | **PASS** |
| `transfer-compete` | no | frozen full-population competition, every survivor | **PASS** |
| `protein-compact` | **yes** | frozen competition CONSTRAINED to the stratum | **FAIL** |

Both neighbours pass, and the only difference in `ComputePass2TransferCompeteFull` between
transfer-compete and protein-compact is `stratumBaseIds` being non-null. **Stratum membership
for one base_id differs between the in-process path and the merge node.**

### Hypotheses raised and REFUTED against source - do not re-run these

1. **The stratum is mutated after publication.** No: `_proteinCompactStratum` is written once
   (`FirstJoinTask.cs:1751`) and thereafter only `.Contains`-tested (:957) or passed by
   reference (:1989).
2. **The learned pick causes it.** No: mode 3 fails identically with `OSPREY_PICK_LDA=0`.
3. **HashSet enumeration order leaks into the result.** No: `StreamingFdr` only ever
   `.Contains`-tests the stratum (:211, :235); it never iterates it. Set order cannot reach
   the output.
4. **Pass-1 q itself diverges between straight-through and the HPC chain**, masked by
   transfer-compete rewriting every survivor. No: `transfer` carries pass-1 q through for
   EVERY survivor and mode 3 PASSES.

### 5. REFUTED by measurement: the stratum differs between the paths

Instrumented with `-KeepOutput` (run `regression-20260802_171101`), reading
`Stellar/straight/straight.log`, `Stellar/chain/phase2_firstjoin/phase2.log` and
`Stellar/chain/phase4_mergenode/phase4.log`:

| path | proteins >=2 | stratum base_ids | detected peptides |
|---|---|---|---|
| straight-through | 4178 | **165006** | 31018 |
| HPC phase 2 (FirstJoin) | 4178 | **165006** | 31018 |
| HPC phase 4 (merge node, reloaded) | - | **165006** | - |

Reconciled survivors 994,899 and mapped survivors 984,531 in BOTH paths.

**The persisted stratum round-trips exactly, so the sidecar work is correct and is NOT the
cause.** This also kills the threshold-amplification story an earlier revision of this file
recorded as the leading mechanism: `DetectedPeptides` is identical (31,018 both paths), so no
protein sits astride the >=2 gate differently. Do not revive that explanation.

### What the divergence actually IS (measured from the two blibs)

Queried both retained blibs for the precursor (`ai/.tmp/probe-precursor.ps1`, diagnosis only):

| file | straight-through | HPC chain |
|---|---|---|
| `..._20.mzML` | RT 23.10, score 0.00 | RT 23.10, score 0.00 |
| `..._21.mzML` | RT 23.08, score 0.00, **bestSpectrum=1** | RT 23.08, score 0.00 |
| `..._22.mzML` | **RT NULL, score 1.00** | RT 23.01, score 0.00, **bestSpectrum=1** |

Per the blib schema (`docs/08-blib-output-schema.md`), a NULL `retentionTime` means the
precursor did NOT pass RUN-level FDR in that file. So the real difference is narrow and
specific: **`DAADLLSPLALLR2` fails run-level FDR in file _22 under the straight-through run and
passes it in the HPC chain.** Everything else - the experiment-level best-run flip, the
RefSpectra RT/score rows - follows from that one run-level q.

### Where it must be

Run-level q under protein-compact comes from the STRATUM-FILTERED per-file competition, which is
the one code path exclusive to the failing mode (`StreamingFdr.cs:207-213` builds a filtered
`allIdx`, then `CompeteFromIndices` + `ComputeConservativeQvalues` over that subset; :221 drops
non-survivors). `transfer` and `transfer-compete` never build that filtered list, which is
consistent with both passing.

Note the difference is q=1.00 vs q~1e-4, NOT a near-tie - so this is a survivor/winner
membership difference, not float drift.

### 6. FALSE ALARM, recorded so nobody repeats it: "the pipeline is nondeterministic"

Two independent straight-through runs of the SAME config produce blibs with the same byte
LENGTH but different SHA-256. That is true of the branch AND of unmodified master
(`pwiz-work1` at the same base commit `9804e9015`), and it is **benign**: run
`ai/.tmp/compare-determinism.ps1`, which applies the regression comparator
(`BlibGolden.ps1::Compare-BlibFull`, the same function mode 3 uses) instead of a hash, and both
pairs report **PASS - identical at gate tolerance**.

The byte differences are SQLite page layout and sub-tolerance float noise the comparator
deliberately ignores. **Do not use SHA-256 as a determinism oracle for a blib** - it is stricter
than the gate and reports differences the project has decided are not differences. An earlier
revision of this file concluded from hashes alone that the pipeline was nondeterministic and
that the golden was therefore meaningless. That was wrong.

### Leading mechanism (consistent with every measurement so far)

protein-compact is the ONLY mode whose per-file run-level competition runs over a
stratum-FILTERED subset (`StreamingFdr.cs:207-213` builds `allIdx` by filtering;
transfer-compete passes all `m` rows, transfer never competes at all). A small difference
between the straight-through per-file scalars and the ones the phase-1/3 workers wrote - one
that a full-population competition absorbs below the 1e-9 gate - can cross the q <= 0.01 line
inside a much smaller population, flipping an entry between passing and failing run-level FDR.

This fits everything measured: stratum identical, survivor counts identical, both neighbouring
modes passing, the observed delta being q=1.00 vs ~1e-4 (a threshold crossing, not drift), and
only ONE precursor affected.

**If it holds, it is a property of the chosen default, not a plumbing bug**: protein-compact
amplifies HPC-vs-straight differences that other modes absorb. That matters well beyond this
PR, because production runs the HPC path at 82-200+ files while every gate here is 3 files.

### 7. REFUTED by measurement: the two paths feed the competition different data

Run `regression-20260802_175634`, comparing the straight leg against
`chain/phase3_rescore_*_22` for the divergent file:

| artifact | result |
|---|---|
| `<stem>.1st-pass.fdr_scores.bin` | **byte-identical** (28,973,852 both) |
| `<stem>.scores-reconciled.parquet` | **byte-identical** (216,039,569 both) |
| `<stem>.reconciliation.json` | **byte-identical** (9,869,663 both) |
| `<stem>.1st-pass.model.json` | **byte-identical** (`2f1f7b60ad05c74140eb...`) |
| file order into the competition | **identical** (_20, _21, _22 in both logs) |

So the pass-2 competition receives byte-identical scalars, the byte-identical frozen model, an
identical stratum (165,006), identical survivor counts (994,899 / 984,531), and the files in the
same order - and still produces a different run-level q for ONE precursor in file _22. The
"per-file scalars differ" mechanism recorded above is therefore also wrong.

### State of the search space

ELIMINATED by measurement, all of it: the persisted stratum (round-trips exactly), the pick
model (fails with it off), HashSet enumeration order (never iterated), pass-1 q (transfer
passes), run-to-run nondeterminism (both paths pass the gate comparator against themselves),
differing scalars / model / file order (byte-identical), and `DetectedPeptides` (31,018 both).

STILL TRUE: only `protein-compact` fails; `transfer` and `transfer-compete` pass. The single
code path exclusive to the failing mode remains the stratum-FILTERED `allIdx` in
`StreamingFdr.cs:207-213` and the off-stratum `continue` in the map-back
(`Pass2FdrSidecar.cs:709-713`).

The remaining difference between the paths that has NOT been ruled out is the in-memory
`perFileEntries` survivor buffer - built by in-process compaction on the straight path and
adopted from the rehydrated bundle on the merge node. Its ORDER WITHIN A FILE is not pinned by
anything measured so far, and `CompeteFromIndices` resolves ties by first-seen (strict `>`),
so a different within-file order can flip a tie. Why that would bite only the stratum-filtered
competition is the open question.

### ROOT CAUSE (found 2026-08-02 by instrumentation, run `regression-20260802_185015`)

**Stage-6 rescore results are not written back onto the in-memory `FdrEntry` in the
single-machine (straight-through) path.** Traced state on ENTRY to pass 2, before pass 2 does
anything:

| entry | straight-through | HPC chain |
|---|---|---|
| _22, eid 23645 | `runQ=1 expQ=1 **score=0**` | `runQ=9.672115291614276E-05 expQ=1.03e-04 **score=5.680917117486129**` |
| _22, eid 23646 | `runQ=1 expQ=1 **score=0**` | `runQ=0.448749033296407 expQ=0.4696 **score=-4.97294527889444**` |
| _20 / _21, eid 23645 | score 2.4067663392525698 / 4.04961448118585 | IDENTICAL |

`score` is exactly 0 and q exactly 1 - the never-detected sentinel - so those entries reach
pass 2 UNSCORED in the straight-through path and SCORED in the chain. eid 23646 is unscored in
all three files straight-through and scored in all three in the chain.

**The HPC path is correct by accident of architecture**: its phase-3 workers persist scores to
the reconciled parquet and the merge node re-reads them, so the round trip through disk repairs
what the in-process path drops. The single-machine path therefore UNDER-REPORTS - it loses
precursors the HPC path keeps.

**Pass 2 is innocent.** The competition itself was proven identical in both paths (same frozen
scores to full precision, same stratum, same `inAllIdx=False`, same "NOT A WINNER").

**Pre-existing, and masked by every other mode.** `percolator` retrains and recomputes every q;
`transfer-compete` rewrites every survivor; `transfer` re-maps moved peaks through the score->q
table. All three overwrite the stale sentinel. `protein-compact` is the only mode that
PRESERVES pass-1 q for OFF-stratum survivors (the `continue` at `Pass2FdrSidecar.cs:709-713`),
and base_id 23645 is off-stratum - so it is the first mode honest enough to report the defect.

This is why the earlier default hid it, and it is a real argument that the gate did its job:
the flip did not break HPC/single-machine comparability, it REVEALED that the single-machine
path was already wrong.

### The exact line, and why it is not simply a bug

`PerFileRescoreTask.OverlayRescoredEntries` (`:1285-1309`) DELIBERATELY resets
`Score = 0.0` and every q-value to `1.0` for every entry Stage 6 rescored (consensus,
reconciliation and gap-fill targets), on a documented contract:

> "Mirror Rust's to_fdr_entry semantics: post-rescore stubs carry default Score (0.0),
> q-values (1.0), and Pep (1.0). Percolator (Stage 7, second-pass FDR) recomputes these from
> the new Features."

That contract is satisfied by `percolator` (retrains), `transfer-compete` (rewrites every
survivor) and `transfer` (re-maps moved peaks). **It is violated by exactly one case**:
`protein-compact`'s OFF-stratum survivors, which are deliberately NOT recomputed so they can
"keep their already-passing 1st-pass q" - a q the overlay has already destroyed.

The measurements fit exactly: eid 23645 kept a real q in _20 and _21 (never rescored) and got
`1` in _22 (rescored). The HPC chain escapes only because its merge node re-hydrates
pre-reset values from the parquet.

**So neither path is right by design.** The chain accidentally matches protein-compact's
intent; the straight path faithfully reports a sentinel that was never meant to be read.

Note the reset exists for Rust parity, so changing it is not free.

### FIXED 2026-08-02 - mode 3 PASSES

Commit `8796e7a13`. Changed peaks are admitted into the same competition the on-stratum members
get, so they earn a q from their recalculated composite score instead of inheriting one or
keeping the sentinel.

```
straight-through wall 02:53; blib 25,395,200 bytes
HPC chain wall 03:33;        blib 25,395,200 bytes
Stellar mode3 (HPC chain == straight): PASS
Stellar mode1 (vs golden): FAIL (78)   <- the expected re-baseline, not a defect
```

**The signal is `survivorScoreOverride`**, keyed `(fileKey, entryId)`. An override exists only
for peaks re-scored against the reconciled features, so its presence IS "this peak changed" -
and being ENTRY-ID keyed it means the same thing in-process and on a merge node. That is what
the failed first attempt lacked; it was already a parameter of the function.

Admission is BY BASE_ID so a target and its paired decoy always enter together - a lone target
would auto-win its competition and inflate the null.

Unchanged off-stratum peaks still ride through on their 1st-pass q, so **single-hit proteins
stay detectable exactly as protein-compact intends**. Only peaks whose evidence actually
changed are re-competed.

Direction of the result confirms the reasoning: the blib is SMALLER than the stale-q chain
produced (25,395,200 vs 25,636,864). The _22 peak that had been inheriting q=9.67e-05 now
competes on its recalculated score (-6.679) against its paired decoy (-5.729), loses, and is
rejected for a real reason instead of accepted for a stale one.

Gate: 573/573 unit tests, inspection 0 warnings / 0 errors.

### Brendan's framing, worth keeping (2026-08-02)

> "I definitely do not think you can pass through a q value from a prior peak to a changed peak
> with a different score... The peptide experiment-wide q value can get passed through, but not
> a run-level q value for a peak that has changed... those per-run changed peaks need both
> recalculated composite scores and re-competition through transfer-compete to have any chance
> at a valid q value."

That is the rule the fix implements. It also explains why this went unnoticed: the correction
usually REJECTS a poor peak rather than promoting one, so it removes IDs rather than adding
them - an invisible loss in single-computer runs, which is all Mike runs.

### Rust mirror + cross-impl re-run: PASS (2026-08-02, AFTER the mode-3 fix)

maccoss/osprey `753bdea` on `feature/decoy-il-gate-and-default-flip`.

```
precursors: rust=29329  cs=29329  delta=0
Stage 7 protein FDR (per-col 1e-9): PASS
Blib content (SQL row+col 1e-9):    PASS
OVERALL: PASS -- bit-parity at 1e-9 on Stellar 3-file
```

**A partial mirror FAILED first, and the failure is instructive.** Porting only the admission
filter gave `rust=29481 cs=29329, delta=-152` - Rust kept 152 precursors C# now rejects, because
its map-back was still passing stale q through for changed peaks. The fix has TWO halves and
both must land:

1. admit changed peaks into the competition (`pass2_qvalue.rs`)
2. write them the q they earned instead of skipping them (`pipeline.rs` map-back)

The cross-impl gate caught the half-port immediately, which is exactly what it is for.

### Cross-impl gate: PASS (2026-08-02, BEFORE the mode-3 fix)

`Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar`, both sides rebuilt first:

```
precursors: rust=29606  cs=29606  delta=0
Stage 7 protein FDR (per-col 1e-9): PASS
Blib content (SQL row+col 1e-9):    PASS
OVERALL: PASS -- bit-parity at 1e-9 on Stellar 3-file
```

**The two default flips and the I/L gate are correctly mirrored.** Note the gate compares the
two STRAIGHT-THROUGH paths, so it does not exercise the merge node where the mode-3 defect
lives - and both sides land on the same 29,606 precursors, which means **Rust carries the same
defect**. That follows from the reset's own docstring ("mirror Rust's to_fdr_entry semantics"):
the post-rescore zeroing is Rust's contract, so protein-compact's off-stratum read is broken
identically in both implementations. It only SHOWS in C# because only C# has an HPC chain in
this gate. For Mike, that is the clearest framing: the gap is in the shared design, not in the
C# port.

Also worth keeping: the gate REFUSED to run first, on a stale C# binary (source edited after
the exe was built). That guard works and saved a false divergence report.

### ATTEMPTED FIX THAT FAILED - do not repeat as written

Extending the stratum with rescored base_ids (option 1) was implemented and made mode 3
**WORSE: 12 issues -> 30**. Reverted.

Cause: the rescored set was derived from `ReconciliationActions`, which is keyed
`(FileName, Index)` - and `FirstJoinTask` documents that those keys "get rebuilt to
post-compaction indices" on the bundle path. The same key therefore resolves to a DIFFERENT
entry on the two paths, making the extension itself path-dependent - precisely the property the
fix was supposed to avoid. The gap-fill half was fine (`GapFillTarget.TargetEntryId` is
path-independent); the reconciliation half poisoned it.

**Any retry must key off ENTRY IDs only, never indices.** That question is now ANSWERED, and
the answer blocks option 1 as chosen: `ReconcileAction`
(`Osprey.FDR/Reconciliation/ReconcileAction.cs:31`) is a discriminated union carrying NO entry
id - entry identity exists only in the `(FileName, Index)` dictionary key. Only
`GapFillTarget.TargetEntryId` is entry-id-keyed. So "compete the rescored off-stratum
survivors" requires FIRST adding entry ids to the reconciliation byproduct (and to
reconciliation.json, which is byte-compared against Rust) - a bigger and riskier change than
the fix it enables.

**Option 2 has a clean implementation path, which changes the cost comparison.** Add
`FdrEntry.Pass1RunPrecursorQvalue`, defaulted to NaN:
* `OverlayRescoredEntries` stashes the pre-reset run q into it before zeroing.
* protein-compact's off-stratum branch reads
  `double.IsNaN(e.Pass1RunPrecursorQvalue) ? e.RunPrecursorQvalue : e.Pass1RunPrecursorQvalue`.

Both paths then yield the same pass-1 q: on the straight path overlaid entries carry the
stashed value and untouched ones fall back to their intact q; on the merge node nothing is
overlaid, so everything falls back to the rehydrated q - which IS the pass-1 value. It adds a
field rather than changing the Rust-parity reset, so no other mode moves.

The trade remains the one in the option list: option 2 reports a q computed from features
Stage 6 has since replaced. That is a statistics question for Brendan and Mike, not an
implementation one.

### Fix options (unmeasured, in preference order)

1. **Source the off-stratum pass-1 q from the sidecar** rather than the mutated in-memory
   entry. Surgical, confined to the one mode that reads it, and it is what the HPC path
   already effectively does - so it should CLOSE the mode-3 gap rather than move it.
2. Have protein-compact recompute q for off-stratum survivors too. Simple, but defeats the
   mode's design (report = pass1 U stratum passers).
3. Preserve pass-1 q through the overlay. Smallest diff, but it changes a contract held for
   Rust parity and would affect every mode.

### Decision needed before fixing

The fix is in the Stage-6 rescore write-back on the in-process path, and it is
**science-affecting, not plumbing**: repairing it makes single-machine runs retain precursors
they currently drop, which changes reported output for every mode, not just protein-compact. It
also almost certainly changes the golden again. Scope it deliberately - on this branch or its
own issue - rather than folding it into the default flip silently.

**If it proves stubborn, there is a decision rather than a fix**: `transfer` passes mode 3
today, and was Brendan's own strong lean in TODO-20260727 on validity grounds. Shipping
`protein-compact` as the default REQUIRES HPC-vs-single-machine comparability, because
production runs the HPC path at 82-200+ files while every gate here is 3 files. That is
Brendan's call with Mike, not an implementation detail.

**GOTCHA that cost a full run**: `-KeepOutput` retains a run dir at the END of its own run, but
the NEXT run's `Remove-StaleRunDirs` deletes it unless that run also passes `-KeepRunDirs N`.
Pass both, every time, or the artifacts vanish before they can be compared.

Then decide: fix here, or re-baseline with mode 3 knowingly red and fix in a follow-up. That is
Brendan's call, not an implementation detail - it is the difference between shipping a default
whose HPC and straight-through paths agree and one whose paths are known not to.

## Progress Log

### 2026-08-03 (evening) - RE-CAPTURE DONE, and the two fixes CUT MEASURED PASS-2 FDP IN HALF

All four goldens re-captured, none REFUSED, `data dir unchanged across run` on all three
read-only data folders. Log: `ai/.tmp/regression-creategolden-20260803.log`.

| dataset | wall | blib, stale golden | blib, new |
|---|---|---|---|
| Stellar | 03:14 | 25,395,200 | 25,407,488 |
| StellarLibDecoy | 04:23 | 25,681,920 | 25,178,112 |
| StellarGenDecoyEntrap | 04:04 | 28,598,272 | **20,328,448 (-29%)** |
| Astral | 12:23 | 97,013,760 | 95,924,224 |

Stellar reproduces the 25,407,488 this file predicted for "+ experiment q carried" EXACTLY, which
is the check that the capture came from the intended code.

**The -29% on the gendecoy set is not a loss, it is the defect being removed.** The entrapment
diagnostics say what happened, and PASS 1 IS BYTE-IDENTICAL on every metric in both entrapment
datasets - as it must be, since neither fix touches pass 1. Everything below moved in PASS 2 only:

| pass-2 experiment | StellarLibDecoy stale | LibDecoy new | GenDecoyEntrap stale | GenDecoy new |
|---|---|---|---|---|
| reportedQ | 0.00998 | 0.00974 | 0.00943 | 0.00996 |
| **combinedFdp (TRUE)** | **1.52%** | **0.61%** | **2.61%** | **1.33%** |
| pairedFdp | 1.38% | 0.55% | 2.61% | 1.33% |
| accepted | 29,921 | 29,445 | 31,779 | 23,116 |

**On the libdecoy set - the healthy comparator - pass 2 moved from ANTI-CONSERVATIVE to
CONSERVATIVE for a 1.6% cost in IDs.** 1.52% true FDP at a nominal 1% became 0.61%, while accepted
fell only 29,921 -> 29,445. And it still ADDS over pass 1: 29,445 against pass 1's 26,788 (+9.9%)
while measuring BELOW the line. That is the calibration claim this branch was justified on, and it
is now supported on the entrapment oracle rather than argued from mechanism.

The gendecoy set pays more (accepted -27%) and lands at 1.33%, still above nominal. Two things
about that are already on the record and both apply: gendecoy is known to inflate FDR relative to
libdecoy independently of anything here, and 3 files is the cohort size prior work showed to be
misleading. Read it as consistent with the libdecoy result, not as an independent one.

**This also quantifies the signal defect for the first time.** The old predicate admitted most of
the survivor pool into the stratum competition; the correction removes those admissions, and the
FDP measurement is what they were costing. Nothing else in the branch could produce a pass-2-only
move of this size with pass 1 held byte-identical.

**Finding #3 FIXED - `cb9b68c60`.** Brendan's call was to land it BEFORE the verify so one run
covers both. Neither flipped default reached any validity key, so a run under the new defaults
computed the SAME key as a directory recorded under the old ones and the resume driver adopted the
old arm's artifacts as the new arm's result.

* Both suffixes are UNCONDITIONAL, which is the opposite of the `ExperimentAgg` suffix beside them.
  That one is empty for its default arm because its default arm's output never changed; these two
  arms' outputs DID, so emitting nothing for the new default is exactly what makes a post-flip key
  equal a pre-flip one. The one-time cost - every pre-flip directory invalidated, Stage 1-4 re-run
  on a warm re-run or `-LinkFrom` - is the correct outcome, since those artifacts were picked by a
  different model.
* The pick went in the BASE key (it happens in Stage 4 and everything downstream inherits the peak
  it chose, so a task added later carries it without knowing); the pass-2 mode went only on the
  three tasks whose output it changes, so a mode switch does NOT discard Stage 1-4 parquets that
  cannot have moved.
* Retires the standing "use a FRESH `--output-dir` per mode" LIMITATION in the `Pass2QValue`
  remarks - this is the sidecar tagging they deferred.
* **No Rust mirror is needed**: `maccoss/osprey` has no validity-key or resume-sidecar system at
  all (grep finds nothing), consistent with the HPC chain and resume driver being C#-only.
* Guarded by `TaskValidityKeyTest`, which states the wiring as a RULE rather than a list - every
  canonical task must carry the pick, only per-file scoring is exempt from the pass-2 mode - so a
  task added later is covered. It has to be a unit test: the byte-identity gate always runs in a
  fresh output directory and structurally cannot see this class of defect.

**Two ReSharper warnings were already red on the branch and are now fixed.** `StreamingFdr.Admit`
carried two dead null guards (`ConditionIsAlwaysTrueOrFalse`, always-false and always-true) that
came in with `8796e7a13` on 2026-08-02. They are NOT from this session's work, and the "0 warnings"
recorded for that commit did not reproduce - worth knowing before trusting a green gate quoted from
an earlier entry. Gate now: **574/574 tests, 0 warnings / 0 errors.**

**Findings #5 / #6 FIXED** in `ai` `4edbe2d`, plus the same defect found in a third place:

* `OspreyDatasetRun.psm1` exports `OSPREY_PICK_LDA` in both directions and always exports
  `OSPREY_PASS2_QVALUE`. Leaving a lever unset stopped being neutral when the defaults flipped -
  it now SELECTS the new default, which is why both arms of a pick A/B had become the same run.
* `Run-FdrBench.ps1` had the same defect and it was worse there, because that script stamps
  `metrics.csv`: a cell run after the flip was labelled `pass2_qvalue=percolator` while executing
  protein-compact. It now sets both levers explicitly and stamps both (`pick_lda` is new).
* `percolator` is out of every ValidateSet in the runner chain, so a stale caller fails at
  parameter binding in a second instead of after Stage 1-5. `Run-CohortArms.ps1` no longer bakes
  the token into run-directory names, and `mbn_surface.py` reads the mode as a token so the
  existing percolator arms still harvest.

**VERIFY GREEN: `Osprey regression PASSED`, 26/26.** Goldens committed as `7e91b26e0`.

```
Stellar               mode1 PASS  mode3 PASS  mode4 PASS  mode2 x2 PASS
StellarLibDecoy       mode1 PASS  mode1b PASS (+FDR sanity bounds PASS)  mode3 PASS  mode4 PASS  mode2 x2 PASS
StellarGenDecoyEntrap mode1 PASS  mode1b PASS (+FDR sanity bounds PASS)  mode3 PASS  mode4 PASS  mode2 x2 PASS
Astral                mode1 PASS  mode1b PASS (+FDR sanity bounds PASS)  mode3 PASS  mode4 PASS  mode2 x2 PASS
```

Three things this run establishes that the capture alone could not:

* **Mode 3 is green on all four datasets INCLUDING Astral**, so the shipping baseline and the
  HPC 4-task chain describe the same pipeline at the same time. It never reads the golden - it
  compares the chain against the straight-through run of the same session - which is exactly why
  a re-baseline could not have papered over it.
* **The mode 2 / mode 4 cache expectations still hold under the new validity keys.** `cb9b68c60`
  changes what invalidates a cached artifact, and `regression.ps1` asserts which tasks were
  SKIPPED versus RAN; both resume checks and the warm re-run passed on every dataset. The keys
  are consistent within a session, which is what makes that true - and the run confirms it rather
  than assuming it. (`regression.ps1` sets neither flipped env var, so every leg and every HPC
  phase shares one arm.)
* **The tier-2 FDR sanity bounds passed in the VERIFY run, not only at capture.** Tier 2 is a
  FIXED bound a re-baseline cannot move, so it is the independent check that the flips did not
  walk calibration out of range.

`data dir unchanged across run` on all three read-only data folders. Log:
`ai/.tmp/regression-verify-20260803.log`.

### 2026-08-03 - EXPERIMENT-Q CARRY-THROUGH landed both sides; cross-impl PASS

pwiz `03f31954a`, maccoss/osprey `e64dceb`. Cross-impl Stellar: **rust=29364 cs=29364 delta=0**,
Stage 7 and blib content both PASS at 1e-9.

**The defect (Brendan's diagnosis, and it is stronger than the review's).** protein-compact folded
off-stratum changed peaks into the CROSS-FILE experiment accumulator but admitted them only in the
files that changed them. That is not merely asymmetric - it is **guaranteed to understate**:

> "the changed values cannot by definition be the maximum peak. So, the maximum before they are
> changed cannot have come from a changed peak." - Brendan

Reconciliation anchors on the best-scoring peak and corrects the others TOWARD it, so a changed
peak never supplied the experiment maximum. Maxing over changed observations alone can therefore
only land below the true experiment-wide score, inflating those peptides' q and DROPPING them -
breaking the "re-scoping only adds, never drops" assertion in the direction that silently loses IDs.

**The fix deletes bookkeeping rather than adding it.** By the same anchor argument the pass-1
experiment q cannot have been invalidated, so it is CARRIED, not recomputed - the invariant
`transfer` already applies and #4438 validated. Off-stratum peaks no longer enter the experiment
accumulator at all; only their RUN-level q is refreshed, from the competition they were admitted to.
The pass-1 value comes from the sidecar because the post-rescore overlay zeroed the in-memory copy.

**A REJECTED alternative, recorded so it is not revived**: `max(pass1_max, max(changed scores))`.
I argued pass1_max would be contaminated by the changed peak's own stale score; that was WRONG, for
the reason above - a changed peak was never the max. But the option is still pointless, because by
the same argument the max cannot move, so it collapses to "carry the pass-1 value". And taking the
max over changed peaks ALONE is the worst option available: guaranteed to understate.

| build | Stellar blib | vs golden |
|---|---|---|
| golden (old signal, recomputed exp q) | 25,395,200 | - |
| signal fix only | 25,194,496 | 51 issues |
| **+ experiment q carried** | **25,407,488** | **60 issues** |

**Output GROWS, which is the confirming direction** - "these were being wrongly dropped" predicts
exactly that.

**The cross-impl gate caught my half-port.** An intermediate state removed the accumulator entry in
Rust without supplying the carry, and Rust dropped 619 precursors against C# (rust=28745 cs=29364,
Stage 7 FAIL). Mirror BOTH halves of a pass-2 change before running the gate.

**SYMMETRY SCOPE (Brendan, 2026-08-03)**: only the RESULTS need to match. C# stashes just the
off-stratum changed set while Rust reads the file's map and filters at use - a residency difference,
not a result difference, and not something the gate needs to police. We are not matching C# for
memory bounding or HPC readiness on the Rust side.

**STILL OPEN, explicitly not settled: how ON-STRATUM changed peaks get their experiment q.** Their
pass-1 value was zeroed by the same overlay, and the replacement comes from the stratum competition.
Brendan is willing to review it, with this framing recorded as stated:

> protein-compact is **not claimed to be fully valid**. It is much improved on pass-2 Percolator,
> and whether it can be made fully valid may take time and considerably more proof.

Do not present the existing FDP measurements as settling that question.

**Next session handoff**: read `ai/.tmp/handoff-20260803_osprey_default_flip.md` before starting.

### 2026-08-03 - SIGNAL FIX LANDED both sides; goldens now stale BY DESIGN

pwiz `1e90d5453`, maccoss/osprey `fa5af6c`. The admission signal is now a frozen-model score that
differs BIT-EXACTLY from the entry's 1st-pass sidecar score, replacing "present in
survivorScoreOverride".

**Why that discriminator and not another guess**: `Pass2FdrSidecar.AssignPerRunQ` already uses it
to separate `Moved` from `Unchanged`, and documents why it is reliable - an unchanged survivor's
reconciled features ARE its Stage-4 features (`ReconciledParquetWriter` streams unchanged rows
through untouched) and the sidecar score came from those same features under the same averaged
model, so the recomputation is bit-identical. It also needs NO new plumbing (both values were
already in that loop) and stays entry-id keyed, which is the property the earlier
`(FileName, Index)` attempt violated when it made mode 3 worse (12 -> 30 issues).

| gate | result |
|---|---|
| C# build + tests + ReSharper inspection | 573/573, 0 warnings / 0 errors |
| Rust `fmt` + `clippy -D warnings` + tests | clean |
| Stellar straight-through vs the old-signal golden | **51 issues**, blib 25,395,200 -> 25,194,496 |
| Cross-impl Stellar WITH the fix | **PASS** - rust=29108 cs=29108 **delta=0**, Stage 7 + blib at 1e-9 |

**The delta=0 is the load-bearing evidence** - two independently written implementations, given the
same bit-exact discriminator, land on the same 29,108 precursors having both moved -221 from the
pre-fix 29,329. A half-mirrored port shows up here immediately; it did exactly that once at
delta=-152.

**Review finding #2 resolved as a side effect, without touching the map-back.** Both defects were
the same wrong predicate seen from two sides. With the fix:

| population | behaviour |
|---|---|
| off-stratum, unchanged | not admitted -> absent from `runQ` -> keeps its pass-1 q, **not dropped** |
| off-stratum, changed | admitted -> competes -> earns a q, or loses and keeps the overlay's q=1 (a real rejection) |
| on-stratum | unchanged |

That restores the documented contract that re-scoping "only adds, never drops an already-passing
peptide".

**THE COMMITTED GOLDENS ARE NOW STALE BY DESIGN.** `4a067fa8b` captured output from the old
signal; the branch now produces different output, so `regression.ps1` mode 1 is red until a
re-capture. That is expected, not a regression - but it means the branch must NOT be left in this
state, and the re-baseline has to be redone (capture + full verify, ~100 min).

**Process note worth keeping**: I verified the mode-3 fix originally by trusting the comment that
named the signal, rather than reading the producer that fills it. The comment was wrong. When a
fix turns on "X IS the signal for Y", read the code that POPULATES X, not the code that consumes
it.

### 2026-08-03 - `/code-review max`: top finding CONFIRMED in mechanism, REFUTED in severity

The review's #1 finding claims `survivorScoreOverride` is not a "Stage 6 changed" signal, and
concludes protein-compact's stratum constraint is therefore "silently dissolved" so the mode-3 fix
made it behave as transfer-compete over the decoy-depleted pool - i.e. the exact population this
branch deletes `percolator` to avoid. That would invalidate the re-baseline. **Verified both
halves before acting; they land differently.**

**CONFIRMED by source - the premise in the code comment is false.** `StreamingFdr.cs:205` states
"the override exists only for peaks re-scored against the reconciled features". The producer does
no such filtering: `Pass2FdrSidecar.cs:549-577` iterates EVERY entry in `perFileEntries` - which
the code itself labels "every post-reconciliation entry" - and scores each one whose identity
resolves. And the path helper falls back to the ORIGINAL parquet when no reconciled one exists:

```csharp
string reconciled = ReconciledPathFromScoresPath(scoresPath);
return File.Exists(reconciled) ? reconciled : scoresPath;   // ParquetScoreCache.cs:1399
```

So a file with no Stage-6 work still contributes all of its survivors. `changedBaseIds` is NOT
"changed peaks", and the comment asserting it is must be corrected.

**REFUTED by measurement - the constraint is NOT dissolved.** Same build, straight-through only,
Stellar:

| arm | blib | mode 1 vs the protein-compact golden |
|---|---|---|
| default (`protein-compact`) | 25,395,200 | **PASS**, exit 0 |
| `OSPREY_PASS2_QVALUE=transfer-compete` | **24,670,208** | **FAIL - 55 issues** |

**This is dispositive.** If `Admit()` were effectively always true AND the map-back `continue`
never fired, protein-compact would be BYTE-IDENTICAL to transfer-compete. It is not - 725 KB and
55 precursor-level issues apart, against 78 for the whole original percolator->protein-compact
golden move. At least one of the two constraints is doing real work. The transfer-compete arm also
reproduces its own 2026-08-02 pre-fix measurement (24,670,208) exactly, which is the control: the
mode-3 fix left the mode that ignores the stratum untouched, as it must.

**Net position**: a real but BOUNDED defect. The admitted population is wider than the comment
claims and wider than intended, sitting between "stratum U genuinely-changed" and "everything" -
magnitude not yet quantified, which needs instrumentation (`allIdx.Length` against `m`) rather
than an A/B. It needs a precise fix keyed off a genuine changed-set - `combinedTargets`
(`PerFileRescoreTask.cs:1279-1291`) and `PerRunClass {Unchanged,Moved,GapFill}` both already exist
- plus the corrected comment. **The golden stands** (arm 1 reproduced it exactly), and the claim
that mode 3 passed for the wrong reason is not supported, because dissolution was the proposed
mechanism and dissolution did not happen.

**Method note worth keeping**: the A/B that settled this needed no code change and took 4 minutes,
because the committed golden IS one arm of the comparison. When a review alleges "mode X secretly
behaves as mode Y", running Y against X's golden answers it directly.

### 2026-08-03 - STEP 3 GREEN: `Osprey regression PASSED`, 26/26. RE-BASELINE COMPLETE.

Committed as `4a067fa8b` (47 files, all under `osprey-regression.data`, nothing stray).

```
Stellar               mode1 PASS  mode3 PASS  mode4 PASS  mode2 x2 PASS
StellarLibDecoy       mode1 PASS  mode1b PASS (+FDR sanity bounds PASS)  mode3 PASS  mode4 PASS  mode2 x2 PASS
StellarGenDecoyEntrap mode1 PASS  mode1b PASS (+FDR sanity bounds PASS)  mode3 PASS  mode4 PASS  mode2 x2 PASS
Astral                mode1 PASS  mode1b PASS (+FDR sanity bounds PASS)  mode3 PASS  mode4 PASS  mode2 x2 PASS
Osprey regression PASSED
```

**Mode 3 passes on all four datasets against the newly captured baseline** - the check that was
broken before `8796e7a13`, now green at Astral scale (chain 14:48) as well as Stellar. That was
the point of running it last rather than treating the capture as the finish line: the baseline
that ships and the HPC path that production uses are now proven to describe the same pipeline at
the same time.

Also worth keeping: **the FDR sanity bounds passed on every entrapment dataset in the VERIFY run,
not just at capture.** Tier 2 is a fixed bound that a re-baseline cannot move, so this is the
independent check that the flips did not quietly walk calibration out of range - `MaxPass1Fdp`
0.02 on the gendecoy set, `MaxAbsTilt` 0.5 on Astral.

The run also reports `data dir unchanged across run` for all three read-only data folders, so
nothing in the shared test-data drop was mutated.

### 2026-08-03 - STEP 2 DONE: all four goldens CAPTURED, none refused

```
Stellar               straight-through wall 03:57; blib 25,395,200   golden CAPTURED
StellarLibDecoy       straight-through wall 04:34; blib 25,681,920   golden CAPTURED
StellarGenDecoyEntrap straight-through wall 04:02; blib 28,598,272   golden CAPTURED
Astral                straight-through wall 12:37; blib 97,013,760   golden CAPTURED
```

**Every blib is byte-size identical to the corresponding straight-through leg of the pre-capture
`-Dataset All` run**, and Astral additionally matches the C# leg of this morning's cross-impl
comparison (97,013,760). The code has not moved since `8796e7a13`, so that is the expected result
and its absence would have been the signal.

**No dataset was REFUSED**, which is worth stating for `StellarGenDecoyEntrap` specifically: it is
the dataset carrying the entrapment diagnostics and the one whose pass-1 combined FDP rose to
1.535% from 1.448% in the earlier golden diff. Tier 2 runs BEFORE anything is written, so that
calibration was judged against `MaxPass1Fdp = 0.02` and accepted rather than blessed by default.

**WORKING TREE STATE**: `pwiz_tools/Osprey/osprey-regression.data/**` now holds the new goldens
UNCOMMITTED, deliberately. They are not committed until step 3 verifies them - a half-captured or
unverified baseline in git is indistinguishable from a legitimate one later, which is the failure
`-CreateGolden`'s own tier-2 ordering exists to prevent one level down. Docs were committed
separately (`d8aee4ba0`) so the golden commit stays a pure data change.

**Launch gotcha that cost ~86 minutes, recorded so it is not repeated**: `Start-Process` does NOT
inherit PowerShell's `Set-Location` as the child's working directory, so a RELATIVE script path
(`./pwiz_tools/Osprey/regression.ps1`) fails instantly with "is not recognized as the name of a
script file" and the run never starts. Use an absolute script path AND `-WorkingDirectory`.

### 2026-08-03 - STEP 1 GREEN: Astral cross-impl PASSES at bit-parity

```
Rust wall: 30:14; precursors: 119088; blib: 96,624,640
C#   wall: 15:17; precursors: 119088; blib: 97,013,760
precursors: rust=119088  cs=119088  delta=0
Stage 7 protein FDR (per-col 1e-9): PASS
Blib content (SQL row+col 1e-9):    PASS
OVERALL: PASS -- Rust and C# end-to-end in-memory bit-parity at 1e-9 on Astral 3-file
```

**The correctness gate is now satisfied at 6x the Stellar scale** (119,088 precursors against
29,329), which is what the golden is about to be captured from. Both binaries were rebuilt first,
so the stale-binary refusal - which has produced false divergence reports twice in this series -
is ruled out.

**The differing blib BYTE counts are not a divergence.** The comparator does a SQL row+column
comparison at 1e-9, not a byte comparison, and this series already established that two runs of
the SAME configuration produce blibs differing in bytes but identical at gate tolerance (SQLite
page layout and sub-tolerance float noise). Do not re-litigate that from a hash.

This clears steps 2 and 3. Golden capture launched immediately after.

### 2026-08-03 - AGREED GATE ORDER before the re-baseline (Brendan)

> "Cross-tool comparison is a correctness check. So, I would prefer to have to passing before a
> golden rebaseline. Then a golden rebaseline allows us to make the final check for straight
> through matching HPC 4-task processing, which was broken before. That should be the final test."

1. **`Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral` must PASS.** Stellar passed twice (before
   the mode-3 fix at delta=0/29,606, and after it at delta=0/29,329, both bit-parity at 1e-9), but
   **Astral was never run** - and a golden captured from code not cross-validated at the larger
   dataset would freeze any divergence into the baseline. Correctness gate, so it comes first.
   Neither binary may be stale: the script refuses rather than reporting a false divergence, and
   it has fired for that reason before. Rebuild BOTH (`Build-OspreyRust.ps1`, and Release for C#).
2. **`regression.ps1 -Dataset All -CreateGolden`.** Refreshes the blib golden AND the mode1b
   diagnostics golden in one pass. Tier 2 runs BEFORE anything is written and a failure writes
   NOTHING, so an out-of-bounds calibration cannot be silently blessed. Note it runs only the
   straight-through leg per dataset - modes 2/3/4 are skipped - which is exactly why step 3 exists.
   `regression.ps1` has **no `-Exe` parameter**, so it runs from the build tree and locks
   `Osprey.exe` for the duration; do not try to build during it.
3. **`regression.ps1 -Dataset All` as the FINAL test.** Mode 1 and 1b should now be green against
   the new baseline, and **mode 3 (HPC 4-task chain == straight-through) is the critical one**,
   because that is what was broken before `8796e7a13`.

**Why mode 3 still has to run after the re-baseline even though it passed last night**: it never
reads the golden - it is a self-consistency check between the HPC chain and the straight-through
run of the same session, which is precisely why a re-baseline could not have papered over it. What
the final run buys is the two artifacts agreeing at the same time: the baseline that ships and the
HPC path that production uses, every mode green simultaneously.

### 2026-08-03 - RE-BASELINE UNBLOCKED: SHIP #2 was reverted, so nothing else changes sequences

The re-baseline was deferred on the reasoning that SHIP #2 (the set-wise isobaric shadow gate)
"changes generated decoy sequences exactly as the I/L gate did, so re-baselining first would cost
a second re-baseline". **Brendan decided on 2026-08-03 to REVERT SHIP #2** - it is shelved in
Carafe, unshipped, and explicitly NOT ported to Osprey C# or Rust. See the DECISION entry in
[TODO-20260801_decoy_similarity_gate.md](TODO-20260801_decoy_similarity_gate.md).

**So there is no second sequence-changing change coming, and the golden re-baseline can be taken
now** on what this branch already contains: the I/L gate (SHIP #1, which is KEPT and unaffected)
plus the two default flips plus the mode-3 fix. All four datasets are green on every
self-consistency mode; only mode 1 and 1b are red, which IS the re-baseline.

**DECIDED 2026-08-03 (Brendan): KEEP the existing Stellar library. Do NOT replace it.**

> "We will keep the old Stellar library containing decoys and entrapment peptides from before our
> Carafe decoy/entrapment filtering work."

**This supersedes the "RE-BASELINE ACTION: replace the libdecoy test library first" entry below** -
that action is cancelled, not deferred.

Facts established while settling it, since a later reader will otherwise re-open the question:
* **Two of the four datasets DO consume a full quartet library** - `StellarLibDecoy`
  (`DecoysInLibrary`) and `StellarGenDecoyEntrap` (same library, `StripDecoys`), both from
  `stellar-libdecoy/libdecoy-entrapment.zip`. The manifest holds 218,871 each of target,
  p_target, decoy and p_decoy, and library ProteinIDs carry both `decoy_` and `_p_target`
  decorations. `Stellar` and `Astral` carry neither, which is the half that is genuinely immune.
* The library files date from **Jun 30**, so they do predate the Carafe gate work.
* A swap could not have reused the Astral entrapment libraries built for the SHIP #2 work - those
  are 1.39M-peptide human builds and this is hela-filtered, so it would have needed a fresh
  Stellar Carafe run.
* **Keeping it has a second benefit worth naming**: the per-dataset tier-2 bounds
  (`MaxPass1Fdp = 0.02` for the gendecoy dataset, justified in-comment by "generated decoys
  measure ~1.5% on unit-resolution Stellar") stay calibrated against the library they were
  measured on. A swap would have required re-justifying them, not just re-running.

### 2026-08-03 - `-Dataset All` FINISHED: every self-consistency mode green on all four datasets

The run that was in flight at the previous session's end completed. **Mode 3 passes on ASTRAL
too**, not only Stellar - the mode-3 fix holds at the larger dataset, which is the one that
matters, since production runs the HPC path at 82-200+ files.

| dataset | mode 1 (golden) | mode 1b (diagnostics) | mode 2 resume | mode 3 HPC chain | mode 4 warm |
|---|---|---|---|---|---|
| Stellar | FAIL (78) | - | PASS | **PASS** (03:34) | PASS |
| StellarLibDecoy | FAIL (78) | FAIL (18) | PASS | **PASS** (07:45) | PASS |
| StellarGenDecoyEntrap | FAIL (78) | FAIL (18) | PASS | **PASS** (05:14) | PASS |
| Astral | FAIL (82) | FAIL (8) | PASS | **PASS** (15:31) | PASS |

The mode 1 / 1b failures ARE the pending re-baseline - they are the committed goldens, taken
before the flips. Nothing else is red. Log: `ai/.tmp/regression-all.log`.

### 2026-08-02 (late) - mode 3 FIXED both sides; re-baseline now blocked only on SHIP #2

**All code complete and green except the golden re-baseline.** pwiz `8796e7a13`, maccoss/osprey
`753bdea`.

| gate | result |
|---|---|
| `regression.ps1` mode 3 (HPC == single-machine), Stellar | **PASS** |
| Cross-impl C# <-> Rust, Stellar | **PASS** - delta=0 precursors, Stage 7 PASS, blib PASS, 1e-9 |
| C# unit tests + ReSharper inspection | 573/573, 0 warnings / 0 errors |
| Rust `fmt` + `clippy -D warnings` + tests | clean |
| `regression.ps1 -Dataset All` | IN FLIGHT at session end; Stellar + StellarLibDecoy mode 2/3/4 PASS, mode 1 + 1b FAIL (the expected re-baseline) |

Note `mode1b` (diagnostics spot checks vs golden) also needs re-baselining - it is a separate
golden from the blib one.

**FIRST ENTRAPMENT-ORACLE SIGNAL, and it is mildly UNFAVOURABLE - measure it properly before
the PR.** `StellarGenDecoyEntrap` mode 1b (the entrapment-validated gendecoy set), branch vs the
master golden:

| diagnostic | golden (master) | this branch |
|---|---|---|
| nTarget | 246,962 | 246,993 (+31) |
| nDecoy | 247,073 | 247,102 (+29) |
| pass1 experiment accepted | 28,703 | **28,612 (-91)** |
| pass1 combinedFdp | 1.448% | **1.535%** |
| pass1 reportedQ | 0.00972 | 0.00975 |

The +31/+29 is the I/L gate working as designed - the retry rescues peptides the old one-shot
collision check dropped, matching Carafe's "net target count actually RISES by 753".

**But accepted falls 91 while true FDP rises ~0.09 points - both axes move the wrong way.**
Retiring percolator was justified on CALIBRATION, so this cell deserves an honest answer rather
than a hand-wave. Caveats: it is a golden DIFF with FOUR variables moving at once (pass-2
default, pick model, I/L gate, mode-3 fix) on 3 files, which is exactly the cohort size prior
work showed to be misleading (3-file protein-compact read 0.90% and calibrated where 82-file
read 1.51% and anti-conservative). So it is a flag, not a verdict.

**CORRECTED (Brendan, 2026-08-02): this cell is NOT an argument against either default, and the
comparison above is methodologically weak.** It compares at NOMINAL q, not at matched TRUE FDP -
the exact mistake this TODO warns about elsewhere. The two arms accept different numbers of
targets, so their FDPs sit at different points on their own curves, and a nominal-q comparison
rewards whichever arm is more miscalibrated. Against a percolator baseline that is backwards:

> "Percolator was just not valid. Period. It was somewhat gated by Pass 1 Percolator and then a
> q value < 1% cut-off which failed to hold as data set size increased." - Brendan

So "worse than the master golden" carries no calibration information here, because the golden IS
percolator. Any real assessment needs disc @ matched TRUE FDP from `Run-FdrBench.ps1`, one
variable at a time (`OSPREY_PICK_LDA=0` isolates the pick, `OSPREY_PASS2_QVALUE=transfer-compete`
isolates the stratum) - not a golden diff.

Also relevant to reading this cell at all: **gendecoy is known to inflate FDR relative to
libdecoy**, so `StellarGenDecoyEntrap` carries that inflation independently of anything in this
branch.

### ~~RE-BASELINE ACTION: replace the libdecoy test library first~~ - CANCELLED 2026-08-03

**SUPERSEDED. Brendan decided on 2026-08-03 to keep the existing Stellar library** - see the
"DECIDED 2026-08-03" block above. The 2026-08-02 reasoning is kept below because it is the record
of why the question was raised, not because it is the current instruction.

*Original entry (Brendan, 2026-08-02):*

The library the libdecoy regression dataset currently uses is **no longer one Carafe would
generate** - it predates the Carafe gate work (overlap gate, bounded retry, I/L collision
rejection). Re-baselining against it would freeze a library that no longer represents production
input.

**Replace it as part of the re-baseline**, so the new golden is taken against a library that
matches what Carafe now produces. Candidates are the delivered builds at
`D:\test\AstralTest-TargetDecoyLibraries\` (see the delivered-libraries table in
TODO-20260801_decoy_similarity_gate.md); note SHIP #2 may change what "current" means again, so
sequence this AFTER SHIP #2 lands, with the library swap and the golden move in one step.

**The re-baseline is deliberately NOT taken.** It is now blocked on SHIP #2 from
[TODO-20260801_decoy_similarity_gate.md](TODO-20260801_decoy_similarity_gate.md), which the
other machine pushed at 21:44 - it changes generated decoy sequences exactly as the I/L gate did,
so re-baselining first would cost a second re-baseline. Same batching logic that put the I/L gate
in this branch.

**SHIP #2 in one line**: the overlap gate's defect is its SCOPE, not its metric - it compares a
candidate only to its OWN paired target. Widen to set-wise against ALL targets, rejecting where
precursor mass is ISOBARIC (few ppm) AND fragment overlap > 0.70. It SUPERSETS the I/L gate
already shipped here (an I/L twin is isobaric with overlap 1.000). Three constraints carried from
that TODO: implement as RETRY not removal or the quartets break and `r` silently rescales; any
k-mer index must be built on I/L-NORMALISED sequences; and set-wise is a different cost class
(1.39M x 1.39M) so it needs a real index and will be visible to the perf gate.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260802_osprey_default_flip.md` before starting work.

### 2026-08-02 - Implemented; gates green except mode 3, which blocks the re-baseline

C# 573/573 unit tests, ReSharper inspection 0 warnings / 0 errors. Rust: all crate tests green,
`cargo fmt --check` and `clippy -D warnings` clean.

**Measured cost of the flip on Stellar 3-file** (straight-through blib bytes; the golden is the
master cell):

| `OSPREY_PASS2_QVALUE` | pick | blib | vs master |
|---|---|---|---|
| `percolator` (master / golden) | off | 30,597,120 | - |
| `transfer` | off | 26,628,096 | -13% |
| `transfer` | on | 26,963,968 | -12% |
| `transfer-compete` | on | 24,670,208 | -19% |
| **`protein-compact` (shipped default)** | **on** | **25,636,864** | **-16%** |
| `protein-compact` | off | 10,231,808 | **-67%** |

The shipped default is **-16%**, the direction expected when an anti-conservative retrain is
replaced by a calibrated frozen competition. **Caveat: 3 files is the misleading cohort size** -
3-file protein-compact previously read 0.90% and calibrated where 82-file read 1.51% and
anti-conservative. Treat these as a smoke test, not as the production effect.

The last row is not a shipped combination, but its size is worth recording: turning the pick off
under protein-compact costs two thirds of the output, while under transfer it costs nothing.
That interaction is the same threshold-amplification described above - the pick changes
first-pass detections, which move proteins across the >=2 gate, which moves whole proteins'
peptides in and out of the competition.

Still to run: the golden re-baseline (BLOCKED on mode 3), the perf gate, the memory-band check,
and the cross-impl comparison.
