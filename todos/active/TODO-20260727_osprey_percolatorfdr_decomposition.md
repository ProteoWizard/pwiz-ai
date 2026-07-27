# Osprey: decompose PercolatorFdr.cs into training / scoring / TDC-FDR / diagnostics collaborators

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_percolatorfdr_decomposition`
- **Base**: `master` (1c1ae8532)
- **Created**: 2026-07-27
- **Status**: In Progress
- **Worktree**: `C:\proj\pwiz`
- **GitHub Issue**: [#4468](https://github.com/ProteoWizard/pwiz/issues/4468)
- **PR**: (pending)
- **Requester/Reporter**: none - filed by Brendan, an Osprey developer, so no credit line

## Objective

`pwiz_tools/Osprey/Osprey.FDR/PercolatorFdr.cs` is a god class mixing SVM training
orchestration, model application / population scoring, target-decoy FDR math, and
Stage-5 diagnostic dumps. Break it into collaborators. Structural only - the output
must stay byte-identical.

Re-measured on this branch against master 1c1ae8532 (matches the issue):

| | lines |
|---|---|
| `PercolatorFdr.cs` | **4,778** |
| `Osprey.FDR` assembly, all `.cs` | 13,260 |
| share of assembly | **36%** |

## Constraint

The only real constraint is **byte-identical output** against the committed golden.
The giant Rust-shaped methods are porting residue and can be decomposed freely
(see [[feedback_refactor_gate_output_not_structure]] - Rust retirement unlocks
nothing here, the gate was always output).

## Gates (both required before PR)

- **Correctness**: `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar`
  (`-Dataset All` before merge). NOTE: regression.ps1 cannot run concurrently -
  shared Release dir + SQLite.Interop.dll lock.
- **Perf**: `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar`
- **Pre-commit**: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`

## Survey of the current file (line numbers on master 1c1ae8532)

Public types that are already separable data holders (lines 49-343):
`PercolatorConfig`, `PercolatorEntry`, `PercolatorResult`, `PercolatorResults`.

Responsibility clusters inside the static `PercolatorFdr` class:

| Cluster | Representative members | Rough span |
|---|---|---|
| Training orchestration | `RunPercolator`, `TrainFold`, `TrainFoldGbt`, `GridSearchC`, `SelectPositiveTrainingSet`, `FindBestInitialFeature`, `CalibrateScoresBetweenFolds`, `TrainProgressReporter` | 344-902, 2106-2650 |
| Model application / scoring | `ScorePopulationAndComputeFdr`, `ScoreProjectionAndComputeFdrInPlace`, `RunStreamingFirstPass`, `ScoreWithFoldModel`, `ScoreStandardizedRow`, `AverageGbtScore`, `ScoreProjectionRowsGbt` | 903-2105, 2546-2650 |
| TDC / FDR math | `CompeteAll`, `CompeteFromIndices`, `CompeteFromDicts`, `ComputeConservativeQvalues`, `ComputeQvalues*`, `CountPassing*`, per-run and experiment q-value families, `StreamingFirstPassQ` | 2684-3350, 3653-4202 |
| Sampling / fold selection | `BestPrecursorPerPeptide`, `CreateStratifiedFoldsByPeptide`, `BuildTrainingSubset`, `SelectBestPerPrecursor`, `SubsampleByPeptideGroup` | 4216-4490 |
| **Stage-5 diagnostic dumps** | `WriteStage5SubsampleDump`, `WriteStage5SvmWeightsDump`, `WriteStage5StandardizerDump`, `WriteStage5PercInputDump`, `EmitFeatureContributions`, `FormatC`, `FormatCGrid` | **4491-4728** |

## Plan - lowest risk first

Ordered so the parity-critical math moves last, per the issue.

1. **Stage-5 diagnostic dumps -> `PercolatorDiagnosticsDump`** (~240 lines, write-only,
   no return values feeding the pipeline). Lowest risk, does not touch computation.
2. **Sampling / fold selection -> its own collaborator.** Pure, deterministic,
   already heavily unit-tested surface (`internal static` helpers).
3. **Training orchestration -> `PercolatorTrainer`.**
4. **Scoring / model application -> `PercolatorScorer`.**
5. **TDC / FDR math -> `TargetDecoyFdr`.** Parity-critical, goes LAST.

Each step: extract, build, run the pre-commit gate, then the Stellar regression to
confirm byte-identical output before starting the next. Do not batch several
extractions before a parity run - that destroys the ability to attribute a break.

## Tasks

- [ ] Step 1: extract Stage-5 diagnostic dumps
- [ ] Step 2: extract sampling / fold selection
- [ ] Step 3: extract training orchestration
- [ ] Step 4: extract scoring / model application
- [ ] Step 5: extract TDC / FDR math
- [ ] Full `-Dataset All` regression + perf gate before PR
- [ ] `/code-review max` before `gh pr create`

Steps 3-5 are large; if the session ends before they are done, the branch should be
left at a green, byte-identical intermediate state rather than mid-extraction.

## Regression Test

- **Test name**: `regression.ps1` (committed C# golden + resume leg, 1e-9) plus the
  Osprey unit suite via `Build-Osprey.ps1 -RunTests`
- **Test project**: Osprey.Test + the standing regression harness
- **Fails on master**: n/a - this is a structural refactor, not a bug fix. There is
  no red-to-green test; the verifier is the inverse, an output-unchanged gate.
- **Passes on fix**: (to verify per step)

No new regression test is added, and that is the correct answer here: the change is
required to alter nothing observable, so the existing byte-identical golden is
exactly the right verifier. A new test asserting new structure would only pin the
refactor's own shape.

## Progress Log

### 2026-07-27 - Session Start

Branch created in `C:\proj\pwiz` (freed by PR #4480 merging). Confirmed the issue's
line counts against master and surveyed the file into the responsibility clusters
above. Starting with the Stage-5 diagnostic dumps.
