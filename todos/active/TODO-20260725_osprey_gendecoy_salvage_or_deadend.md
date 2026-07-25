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
