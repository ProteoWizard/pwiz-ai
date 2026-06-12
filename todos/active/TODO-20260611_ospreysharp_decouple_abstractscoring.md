# TODO-20260611_ospreysharp_decouple_abstractscoring.md

Decompose the `AbstractScoringTask` god-class (2177 LOC) incrementally, the
first PR series off the 2026-06-10 OOP review
([`TODO-ospreysharp_oop_review_findings.md`](../backlog/TODO-ospreysharp_oop_review_findings.md),
rec #1). Each stage is structural-only and gated on byte-parity + perf.

## Branch Information

- **Branch**: `Skyline/work/20260611_ospreysharp_decouple_abstractscoring`
- **Base**: `master`
- **Created**: 2026-06-11
- **Status**: Stage 1 MERGED; Stages 2-4 pending (umbrella TODO stays active)
- **PR (Stage 1)**: [#4290](https://github.com/ProteoWizard/pwiz/pull/4290) (merged 2026-06-11 as `f4a05f0`)
- **Branch (next stages)**: new `Skyline/work/...` per stage off the merged master

## Standing gates (every stage)

Both must pass before each commit; see `ai/scripts/OspreySharp/PRE-COMMIT.md`:
- **Pre-commit**: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection` (zero-warning).
- **Correctness**: `pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar` (committed C# golden + resume, 1e-9).
- **Performance**: `ai/scripts/OspreySharp/Test-PerfGate.ps1 -Dataset Stellar` (A/B vs pinned pwiz-perfbase; total-only fail at 4%).
  - Both gates were stood up + validated this session (perf gate A/A on a quiet
    machine; see [[feedback_ospreysharp_csharp_regression_gate]]).

## Key finding (corrects the parent TODO's rec #1 framing)

The review called "make `_ctx` `private readonly` + ctor-injected (mirror
`Calibrator`)" a low-risk first step. Tracing the code shows it is **not** low
risk, and the framing was off:
- `OspreyTask.Run(ctx)` / `Rehydrate(ctx)` take `ctx` as a **call-time
  parameter**; the driver constructs a task once, then calls Run *or* Rehydrate.
  That is why the 3 subclasses each reassign `_ctx = ctx` at **both** entry
  points. `readonly` ctor-injection therefore requires changing task
  construction in the driver, not a mechanical field-modifier swap.
- It is **3 subclasses**, not 4: `FirstJoinTask`, `PerFileScoringTask`,
  `PerFileRescoreTask` share the base `internal _ctx`. `Calibrator` is a
  **standalone** collaborator (no base) that already ctor-injects correctly;
  `MergeNodeTask : OspreyTask` (not AbstractScoringTask) has its own mutable
  `_ctx`. So Calibrator is a pattern reference, not a drop-in template for the
  inherited field.

=> `_ctx` injection is promoted to its own designed stage (Stage 3), after the
lifecycle is decided (construct-with-ctx vs. a set-once guard).

## Stage 1 -- dead code + math relocation (this commit)

Lifecycle-independent, behavior-identical, lowest-risk first cut at the
god-class. `AbstractScoringTask.cs`: -99 / +3 lines.
- [x] New `OspreySharp.Core/TotalOrder.cs`: the IEEE-754 total-order helpers
  (`Key`/`Comparer`/`Greater`) relocated out of AbstractScoringTask, which held
  **two copies** of the same bit transform (the FDR-ranking comparer + the
  main-search `Greater` tie-break). DRY'd via a shared `Key`; arithmetic
  verbatim, so cross-impl parity is unaffected. Mirrors the `FragmentMath`
  relocation precedent.
- [x] Deleted the two confirmed-dead private methods (`TheoreticalIsotopeEnvelope`,
  `CosineSimilarity`) -- zero callers tree-wide (grep-confirmed; they survived
  because the inspection profile disables unused-private-member warnings, see
  [[reference_ospreysharp_inspection_gate_coverage]]).
- [x] Removed a misplaced `Score a single library entry candidate` doc comment
  that was dangling above `TotalOrderGreater` (would have caused CS1587 once the
  method beneath it was deleted).
- [x] Updated the 2 call sites to `TotalOrder.Greater` / `TotalOrder.Comparer`.

**Validation (all green)**: pre-commit (382 tests, incl. `TestStableSortOnApexRanking`
+ `TestApexTieBreakLastWins`; zero-warning inspection); `regression.ps1 -Dataset Stellar`
mode-1 (golden) + mode-2 (resume) PASS at 1e-9 (blib byte-identical); `Test-PerfGate
-Dataset Stellar` total -0.1% (no regression); fresh-context self-review clean
(independently verified `TotalOrder` parity vs Rust `f64::total_cmp` across edge cases);
Copilot reviewed 2/2 files, no comments.

## Progress Log

### 2026-06-11 -- Stage 1 merged
PR #4290 merged (squash) as `f4a05f0`. Shipped the `TotalOrder` relocation + dead-code
removal; behavior-identical (byte-parity + perf gates green). Both standing gates
(`regression.ps1`, `Test-PerfGate.ps1`) were also stood up + validated this session and
are now the per-stage gate for the rest of this work. Stages 2-4 deferred to the night
session (planned separately); each lands as its own PR off the merged master.

### 2026-06-12 (night session) -- Stage D: OspreyPeakData relocation shipped; CoelutionScorer BLOCKED (handoff)
Branch `Skyline/work/20260611_ospreysharp_relocate_peakdata` (base = Stage C branch, stacked),
commit `07b8056ead`. **Shipped:** relocated `OspreyPeakData` (an `IOspreyDetailedPeakData` adapter)
from the exe Tasks layer down to `OspreySharp.Scoring` (correct layering + enables the scorer move).
Its own PR. **The CoelutionScorer extraction itself is BLOCKED and handed off** -- it is NOT a clean
structural-only move tonight.

**Groundwork already established (do not re-derive):**
- Call graph: base `RunCoelutionScoring` (AbstractScoringTask ~131) -> `ScoreWindow` (~428) ->
  `ScoreCandidate` (~605). ONE composition point (`RunCoelutionScoring`), shared by both subclasses
  via inheritance. `Calibrator` does NOT call them. Plan's D1/D2 subclass-slice is therefore moot.
- `ScoreWindow`/`ScoreCandidate` call NO other AbstractScoringTask *instance* methods (only each other).
- `ctx` is used only for `LogInfo` -- 9 sites, all in `ScoreCandidate` -> swap for an injected
  `Action<string> logInfo`. `CoelutionScorer` should hold NO `PipelineContext`.
- Two private members move WITH `ScoreCandidate`: `const string DIAG_PEPTIDE` (~525) and
  `BuildOverridePeaks(...)` (~535-602). Both Scoring/Chromatography-reachable (not blockers).
- Intended shape: `public class CoelutionScorer` in `OspreySharp.Scoring`, ctor `(Action<string> logInfo)`;
  `ScoreWindow` public, `ScoreCandidate` private; instantiate once in `RunCoelutionScoring`.

**THE BLOCKER (needs a user architecture decision):** `ScoreCandidate` makes ~10 calls into
`OspreyDiagnostics` -- a `public static` class in the **exe project** (`OspreySharp/OspreyDiagnostics.cs`,
namespace `pwiz.OspreySharp`), unreachable from `OspreySharp.Scoring`. Methods: `ShouldDumpSearchXicFor`,
`WriteSearchXicDump`, `WriteCwtPathRow`, `WriteMpInputsRow`, `ShouldDumpMpFor`, `WriteMpDump`, plus a
direct `StreamWriter` dump block. This is OOP-review **rec #3 (diagnostics-bleed)**, which this series
marked out of scope. Options (user picks):
1. **Relocate `OspreyDiagnostics` (+ `OspreyFileDiagnostics` sink) to a Scoring-reachable project** --
   largest move; this IS doing rec #3.
2. **Inject `IScoringDiagnostics` (the ~6 dump methods) into `CoelutionScorer` with a no-op default**;
   the exe wires the `OspreyDiagnostics`-backed impl. Cleanest DI; fits the codebase's no-op-default
   posture. CAVEAT: the dump paths are debug-only (`OSPREY_DIAG_*`) and NOT exercised by the 1e-9
   regression gate -- verification needs a manual diagnostics-on run, so it can't be fully auto-gated.
3. **Split `ScoreCandidate`**: pure-compute core moves, diagnostic-emitting tail stays in base --
   changes the validated method boundary; splits an 825-line parity-critical method; higher risk.
Recommendation: option 2, likely as its own supervised PR (define `IScoringDiagnostics` + back it with
`OspreyDiagnostics` first), then the verbatim ScoreWindow/ScoreCandidate move on top. Full sub-agent
detail: `ai/.tmp/agent-stageD-status.md`.

### 2026-06-12 (night session) -- Stage C pushed (PR #4293, OPEN, not merged)
Branch `Skyline/work/20260611_ospreysharp_remove_ambient_ctx` (base = Stage B branch, **stacked**),
commit `4e23ff6022`. Removed the ambient mutable `_ctx` field from `AbstractScoringTask` +
`MergeNodeTask` and threaded the `ctx` that already arrives at `Run`/`Rehydrate` through every
helper that used it (~30 methods, 5 files, +229/-228). Same object flows -> behavior-identical;
`Calibrator` (already `private readonly`, ctor-injected) untouched. Folded in the deferred Stage-A
class-summary doc fixes. Mechanical edits delegated to a sub-agent; parent independently re-ran
pre-commit (382 pass + zero-warning), `regression.ps1 -Dataset Stellar` mode1+mode2 PASS @1e-9
(blib byte-identical), `Test-PerfGate` total +2.0% median PASS. Fresh-context self-review CLEAN
(hand-verified the two parity-gate-invisible classes: no different-ctx-object; all error-path
`ExitCode` writes preserved). Stage D stacks on this.

### 2026-06-12 (night session) -- Stage B pushed (PR #4292, OPEN, not merged)
Branch `Skyline/work/20260611_ospreysharp_extract_fragment_xics` (base = Stage A branch, **stacked**),
commit `2cf772314a`. Extracted three stateless fragment helpers (`ExtractTopNFragmentXics`,
`ExtractFragmentXics`, `CountTop6Matches`) + the `CAL_TOP_N_FRAGMENTS` constant into a new
`OspreySharp.Scoring/TopFragmentExtractor.cs`. Target project is Scoring (not Core's FragmentMath):
the methods depend on `ScoringMath`/`SpectralScorer` (Scoring) + `XicData` (Chromatography), which
Core cannot reference. Rewired call sites in AbstractScoringTask (incl. an internal bare-name
`CountTop6Matches` call the pre-commit build caught) + Calibrator. Left `s_calXcorrScorer` in place
(deferred; not used by movers, has a test invariant). `AbstractScoringTask` -231 lines. Gates green:
pre-commit 382 pass + zero-warning; `regression.ps1 -Dataset Stellar` mode1+mode2 PASS @1e-9 (blib
byte-identical); `Test-PerfGate -Dataset Stellar` total -1.7% median PASS. Stage C stacks on this.

### 2026-06-12 (night session) -- Stage A pushed (PR #4291, OPEN, not merged)
Branch `Skyline/work/20260611_ospreysharp_relocate_decoy_gen` (base `master`), commit
`cedaec225b`. Relocated decoy generation (`GenerateDecoys` -> `DecoyGenerator.
GenerateAllWithCollisionDetection`, plus private `BuildDecoyFromSequence`) into the
existing `OspreySharp.Scoring/DecoyGenerator.cs` -- NOT a new `LibraryPrep` type (the
night-session plan placed it next to the existing reverse/cycle + remap/recalc helpers).
Ambient `_ctx` logger -> injected `Action<string>`. `AbstractScoringTask` -122 lines.
Gates green: pre-commit 382 pass + zero-warning; `regression.ps1 -Dataset Stellar` mode1+mode2
PASS @1e-9 (blib byte-identical); `Test-PerfGate -Dataset Stellar` total +1.9% median PASS.
Perf baseline `pwiz-perfbase` advanced to `f4a05f0` for this stage series. Self-review +
Copilot pending. **Bottom of the stacked series; do NOT merge overnight.** Stages B-D stack
on this branch. (Plan's Stage A/B/C/D == this TODO's Stage 2/3/4 numbering.)

## Staged plan (subsequent PRs on this branch / night session)

- **Stage 2 -- relocate decoy generation**: move `GenerateDecoys` /
  `BuildDecoyFromSequence` (~88 LOC) to a `LibraryPrep` type. Needs the logger
  (`_ctx`) passed in rather than ambient -- a stepping stone toward Stage 3.
- **Stage 3 -- `_ctx` decoupling (designed)**: decide the task lifecycle, then
  make the base context non-ambient (ctor-injected or set-once-guarded) across
  the 3 subclasses. This is the review's real dominant-debt item.
- **Stage 4+ -- extract `CoelutionScorer`** (rec #1 full): pull `ScoreWindow` +
  `ScoreCandidate` (~825 LOC) into a composed, dependency-injected collaborator.

## Follow-ups surfaced during the night session (backlog, not this series)

- **Consolidate the triplicated top-N fragment select + closest-peak-by-m/z loop.** After Stage B,
  the pattern lives in `TopFragmentExtractor.ExtractTopNFragmentXics` + `.ExtractFragmentXics` and is
  open-coded a third time in `Calibrator.CollectMs2FragmentErrors`. A shared
  `SelectTopFragmentIndices` + XIC-probe helper would DRY all three. Parity-sensitive (stable
  tie-break) so it needs its own gated PR. (Flagged by Stage A + Stage B fresh-context self-reviews.)
- **Relocate `s_calXcorrScorer`** (the calibration unit-resolution `SpectralScorer`) out of
  `AbstractScoringTask` into a shared XCorr-resources holder. Deferred from Stage B (not used by the
  moved methods; has a `CalibrationTest` bin-config invariant to preserve).

## Relationship to other work

- Parent: [`TODO-ospreysharp_oop_review_findings.md`](../backlog/TODO-ospreysharp_oop_review_findings.md)
  (backlog epic; consumed PR-by-PR, not moved wholesale).
- All structural changes gated on byte-parity ([[feedback_ospreysharp_csharp_regression_gate]],
  [[feedback_bit_parity_tolerance]]); do not loosen tolerances.
- One turn of the recurring blind-OOP-review cadence
  ([[project_osprey_organic_growth_needs_iterative_oop_review]]).
