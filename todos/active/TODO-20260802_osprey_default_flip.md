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

## Progress Log

### 2026-08-02 - Implemented; gates green pending the re-baseline

C# 573/573 unit tests, ReSharper inspection 0 warnings / 0 errors. Rust: all crate tests green,
`cargo fmt --check` and `clippy -D warnings` clean.

Still to run: the golden re-baseline, the perf gate, and the cross-impl comparison.
