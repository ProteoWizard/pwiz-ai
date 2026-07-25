# Osprey: decide the fate of generated (reverse) decoys -- calibrate or hard-gate

## Branch Information
- **Branch**: `Skyline/work/20260725_osprey_gendecoy_decision`
- **Base**: `master`
- **Created**: 2026-07-25
- **Status**: In Progress
- **GitHub Issue**: [#4465](https://github.com/ProteoWizard/pwiz/issues/4465)
- **PR**: (pending)
- **Requester/Reporter**: none (raised internally by the Osprey developers; no credit line)

## Objective

Osprey can build its own decoys ("gendecoy", mechanical sequence reversal) when the
library has none, or use library-supplied decoys from a predictive model ("libdecoy":
Carafe / Prosit / AlphaPeptDeep). The FDRBench entrapment oracle shows gendecoy is
badly miscalibrated -- ~12-16% true FDP at a claimed 1% q on Stellar/Astral -- while
libdecoy is near-calibrated at ~0.8-1.3%.

Decide whether the generated decoys can be fixed so they match the target false
distribution, or whether in-tool decoy generation is a dead end -- in which case Osprey
should always require decoys from a predictive model, and the gendecoy option is removed
or hard-gated.

Do NOT turn the option off before this decision is made.

Compounding finding: `pwiz_tools/Osprey/regression.ps1` never passes
`--decoys-in-library` (verified on master 2026-07-25), so BOTH regression datasets
(Stellar + Astral) exercise only the miscalibrated generated-decoy path. The libdecoy
path we actually recommend has no regression coverage at all, and FDR-change impact
numbers measured on the regression are exaggerated.

Osprey is not yet public -- removing or hard-gating a miscalibrated decoy mode is cheap
now and expensive once external users depend on it.

## Tasks

- [ ] Measure whether a re-predicted (rather than reversed) decoy closes the calibration
      gap on the FDRBench entrapment oracle
- [ ] If it closes: ship the better generator and keep the gendecoy option
- [ ] If it does not: hard-gate or remove in-tool decoy generation and require
      library-supplied decoys -- emit a clear error rather than silently producing
      anti-conservative q-values
- [ ] Either way: move the Osprey regression off the gendecoy `stellar` dataset onto the
      libdecoy path (`--decoys-in-library`)

### Candidate salvage angles (from prior notes)

- [ ] Honest MS1 power for foreign/predicted decoys (existing night-session run-book)
- [ ] Decoy-quality alarms / null-alignment diagnostics -- a decoy-independent `f_false`
      null plus a paired-coin alarm would make this failure visible rather than silent
- [ ] Re-predicting decoy spectra and RT from the same predictive model instead of
      mechanical sequence reversal (most promising structural fix)

## Gate

The FDRBench entrapment oracle is the arbiter, not cross-implementation parity. See the
"FDRBench entrapment validation" section of `ai/docs/osprey-development-guide.md` and
`ai/scripts/Osprey/Run-FdrBench.ps1` (`-DecoySource Library|Generated` is exactly this
comparison).

Standing Osprey gates still apply to any code change:
- correctness: `pwiz_tools/Osprey/regression.ps1`
- perf: `ai/scripts/Osprey/Test-PerfGate.ps1`
- pre-commit: `Build-Osprey.ps1 -RunInspection -RunTests`

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Test | TestData | Osprey regression harness (regression.ps1)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Note: the decision itself is measurement-driven (FDRBench entrapment oracle), not
unit-testable. The concrete testable deliverables are (a) whichever code change the
decision produces -- a better generator, or a hard-gate error path -- and (b) the
regression harness gaining libdecoy coverage. Record red->green evidence here for
whichever lands.

## Progress Log

### 2026-07-25 - Session Start

Starting work on this issue. Branch created off master at 099ec2d5d. Confirmed
`regression.ps1` on master contains no `--decoys-in-library` / `DecoySource` reference,
so the gendecoy-only regression coverage claim in the issue holds.

### 2026-07-25 - The libdecoy/gendecoy A/B already IS the scope-item-1 experiment

**The decoy sequences are identical between the two modes.** Compared every decoy
sequence in the Stellar Carafe pairing manifest
(`D:\test\osprey-runs\stellar-libdecoy\osprey_library_db_pairing.tsv`) against what
`DecoyGenerator.GenerateAllWithCollisionDetection` would produce for the same targets:

```
target   -> decoy  : 218,871 pairs -- 218,805 reversed + 66 cycled, 0 mismatch (100.0000%)
p_target -> p_decoy: 218,871 pairs -- 218,797 reversed + 74 cycled, 0 mismatch (100.0000%)
```

Exact agreement on all 437,742 pairs, including the 140 that fall through to the
cycling fallback. Carafe uses the same C-term-preserving reversal Osprey does.
(Script: scratchpad `check_decoy_sequences.py`; the production path builds
`new DecoyGenerator()` = `Enzyme.Trypsin`, so `DetectEnzyme` is not involved.)

Consequence: **the existing libdecoy-vs-gendecoy FDRBench comparison already holds the
decoy sequence set exactly constant**, so the ~12-16% vs ~0.8-1.3% gap is attributable
entirely to how the decoy's spectrum and RT are produced -- which is precisely what
scope item 1 asks to measure. It does not require building a new re-predicted decoy
library with Carafe.

| | decoy sequence | fragment m/z | relative intensity | RT |
|---|---|---|---|---|
| gendecoy (Osprey) | reverse / cycle | recomputed, b<->y swap | **copied from target fragment** | **copied from target** |
| libdecoy (Carafe) | *identical set* | model-predicted | model-predicted | model-predicted |

The named structural weakness: an Osprey generated decoy is a deterministic function of
its target in intensity and RT space -- not an independent draw from the false
distribution. `DecoyGenerator.cs:385-386` copies `target.RetentionTime` /
`target.RtCalibrated`; `DecoyGenerator.cs:625` copies `frag.RelativeIntensity`.

### 2026-07-25 - The same pattern exists in Skyline-mProphet (verified in code)

Skyline generates decoys in-tool the same way, so a "gendecoy is a dead end" verdict in
Osprey is also a verdict about Skyline's mProphet decoys:

* `Model/DecoyGenerator.cs:241` -- decoy transitions are built with `nodeTran.QuantInfo`,
  which carries `TransitionLibInfo` (rank + intensity), so **decoy transitions inherit
  the target transition's library intensity verbatim**.
* `Model/DecoyGenerator.cs:203` -- the decoy precursor inherits `nodeGroup.LibInfo`.
* `Model/DecoyGenerator.cs:114` -- the decoy peptide inherits `nodePep.ExplicitRetentionTime`.
* Open / unverified: how a decoy's *iRT-predicted* RT is derived at scoring time.
  `Irt/IrtDbManager.cs:231` only establishes that decoys are excluded from the
  regression fit. Nail this down before filing the Skyline issue.

Conditional deliverable (Brendan, this session): if Osprey retires or hard-gates
gendecoy, **file a new Skyline issue to make it possible to avoid generated decoys in
Skyline-mProphet** (i.e. accept decoys supplied by a predictive model). Not yet filed --
gated on the Osprey decision.

### Open sequencing question

The 12-16% figure predates the intensity-feature root cause
(`fix/intensity-feature-log-conditioning`, currently checked out in `C:\proj\osprey`;
un-logged `peak_apex`/`area`/`sharpness` z-score to 100-300 and hijack the pass-1 SVM
top band). Judging decoy *construction* on top of known-broken feature conditioning
risks attributing the gap to the wrong cause. Decide whether to re-baseline gendecoy
with that fix in before ruling on salvage-vs-dead-end.
