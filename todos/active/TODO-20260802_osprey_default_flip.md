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
- [ ] Golden re-baseline (`regression.ps1 -Dataset All -CreateGolden`)
- [ ] `Test-PerfGate.ps1` + a memory-band check - protein-compact expands the reconciled pool
      (it reported 647,139 rows transfer-compete did not), so this flip has a plausible cost that
      an ordinary default flip would not
- [ ] `Compare-EndToEnd-Crossimpl.ps1` on Stellar + Astral
- [ ] Docs: `docs/12-second-pass-fdr.md`, `docs/07-fdr-control.md` (its pass-2 mode table names
      `percolator` as the default), command-line docs
- [ ] `ai/docs/osprey-development-guide.md`: record that Osprey environment variables are
      developer-side controls for diagnostics and trial algorithms - NOT a user-facing interface,
      so they do not earn the deprecation care a CLI flag would when changed or removed
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

**Still standing from the earlier entry**: the libdecoy regression dataset's library should be
replaced in the same step, since it predates the Carafe gate work. That was sequenced AFTER
SHIP #2 only because SHIP #2 might have changed what "current" meant - it no longer can, so the
candidate is a current Carafe build with the overlap gate and the I/L filter.

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

### RE-BASELINE ACTION: replace the libdecoy test library first (Brendan, 2026-08-02)

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
