# TODO-20260618_ospreysharp_debt_paydown_pr7.md -- OspreySharp debt-paydown PR 7 (decompose CoelutionScorer.ScoreCandidate)

## Branch Information
- **Branch**: `Skyline/work/20260618_ospreysharp_debt_paydown_pr7` (created off master @ dc58d41a07, includes PR 6 #4315)
- **Base**: `master` (after PR 6 #4315 merged as dc58d41a07)
- **Created**: 2026-06-18
- **Status**: Completed
- **PR**: [#4316](https://github.com/ProteoWizard/pwiz/pull/4316) (merged 2026-06-18 as 3a6e017b9e)

> PR 7 of the OspreySharp OOP debt-paydown arc. The blind review's Rec 1 headline:
> `CoelutionScorer.ScoreCandidate` (~827 LOC) is the single largest remaining giant.
> Seeded by the 2026-06-17 blind `/pw-oop-review` (`ai/.tmp/20260617-oop-review-report.txt`,
> Rec 1 + the AbstractScoringTask open question).

## Framing -- output-invariance, and this one is parity-SENSITIVE
Pure CODE MOTION, output-locked by the golden. `ScoreCandidate` is the coelution
scoring core -- keep the COMPUTATION whole (do not reorder/restructure math); extract
named collaborators around it by pure motion only. See
`feedback_refactor_gate_output_not_structure` and `feedback_no_unverified_ports`.

## Primary work -- decompose CoelutionScorer.ScoreCandidate
- `CoelutionScorer.ScoreCandidate` lives at `OspreySharp.Scoring/CoelutionScorer.cs`
  (~157; the file is ~1068 lines). The review identified separable phases to extract
  (names indicative, verify in-session): RT-window math, the 3-tier CWT fallback,
  peak ranking (`PeakRanker`), boundary recomputation, stage-6 candidate capture, and
  the `FdrEntry` serialization (`FdrEntryBuilder`). Reduce `ScoreCandidate` to a
  sequencer over those collaborators.
- Each extraction is pure motion: same computation, same output. Decompose for
  readability/maintainability, NOT by restructuring the algorithm.

## Coupled decision -- the AbstractScoringTask fork (review open question)
Before relocating the dedup/scoring helpers, decide the architectural fork:
`AbstractScoringTask` (~629 LOC) shares `RunCoelutionScoring`, `DeduplicateDoubleCounting`,
`DeduplicatePairs` via INHERITANCE. `DeduplicateDoubleCounting` is feature-envy (an
algorithm over library fragments parked on a task base). Decide: move these into a
COMPOSED Scoring-project collaborator (testable in isolation) vs keep inherited.
- If "compose" and the move is large, it can be its own follow-up PR -- record the
  decision here and scope accordingly.

> **DECISION (2026-06-18, developer): COMPOSE, and do it IN PR 7.** Both halves ship
> together: (1) decompose `ScoreCandidate` into Scoring collaborators, and (2) move
> `RunCoelutionScoring` / `DeduplicateDoubleCounting` / `DeduplicatePairs` off the
> `AbstractScoringTask` base into a composed `OspreySharp.Scoring` collaborator,
> severing the `PipelineContext` dependency the same way `CoelutionScorer` already did
> (logging via `Action<string>`, dump sink via `IScoringDiagnostics`; the engine never
> sees `PipelineContext`). Tasks call the collaborator through a thin facade -- mirrors
> the PR 5 PercolatorEngine / PR 6 ProteinFdrEngine pattern. Output-locked by
> `regression.ps1` per commit + the cross-impl reference gate pre-merge.

## Why this is now LOW-RISK (use the safety net)
Decomposing the scorer used to feel like touching the parity core. It is now
well-protected:
- `regression.ps1` (committed C# golden + resume @1e-9) -- proves C# output is
  byte-identical after each commit.
- **`Compare/Compare-CrossImpl-Reference.ps1`** (the cross-impl reference gate built
  2026-06-17, all-green) -- proves no drift from Rust at every stage boundary.
Run BOTH; the combination makes pure-motion extraction of the scorer giant safe.

## Out of scope
- ProteinFdrEngine / RunPercolator -> PR 6.
- Any algorithm change to the scorer (this is decomposition only).

## Gates (standing cadence + emphasis on the cross-impl gate)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + **`Compare/Compare-CrossImpl-Reference.ps1 -Dataset Stellar`** (all boundaries
  green) + `/pw-self-review`, then PR, Copilot, `/pw-respond`.

## Progress (2026-06-18)
Branch `Skyline/work/20260618_ospreysharp_debt_paydown_pr7` off master @dc58d41a07
(PR 6 #4315). Each commit gated: Build Debug -RunInspection 0 warnings (+ -RunTests
390 pass on the structural commits) + `regression.ps1 -Dataset Stellar` byte-identical
(blib 52,514,816, modes 1 & 2).

- **`8714a4a96e`** -- Extracted `BuildFdrEntry` (FdrEntry serialization tail) from
  `ScoreCandidate`. Added behavior-identical explicit null guards the inline flow
  context had supplied (kept inspection at 0).
- **`f2e575f758`** -- Extracted `FindScanRange` (override/normal scan-window),
  `DetectCandidatePeaks` (3-tier CWT/fallback), and `CaptureCwtCandidates` (top-N
  stage-6 input). Dropped the dead `peaksFromCwt` local. The core rank-scoring loop
  was LEFT whole per the parity-sensitive framing (it IS the computation).
- **`2c3db5fabf`** -- Composed `RunCoelutionScoring` / `DeduplicateDoubleCounting` /
  `DeduplicatePairs` out of `AbstractScoringTask` into a new `ScoringPipeline`
  (OspreySharp.Scoring), severing `PipelineContext` (logInfo `Action<string>` +
  `IScoringDiagnostics`, mirroring CoelutionScorer/PercolatorEngine/ProteinFdrEngine).
  Thin `protected` forwarders on the base keep the 6 subclass call sites byte-for-byte
  unchanged. Added `IScoringDiagnostics.DiagSearchEntryIds` (typed `HashSet<uint>` to
  match the existing concrete property -- a single property cannot implicitly implement
  two interface members with differing return types). **Removed the ProfilerHooks
  bracketing from RunCoelutionScoring** (developer-approved: instrumentation only,
  output-invariant; where profiler hooks should live is a future decision -- BACKLOG).
  Full build 390 tests + 0 warnings; Stellar byte-identical.

- **`47f5ec2217`** -- Addressed self-review (removed dead `F10`, fixed the ScoringPipeline
  doc); output-neutral.

Both halves of the developer's "do both in PR 7" decision are done. **PR
[#4316](https://github.com/ProteoWizard/pwiz/pull/4316)** opened. Pre-merge gates ALL
GREEN: `regression.ps1 -Dataset All` (Stellar + Astral, both modes byte-identical);
fresh-context self-review clean (2 LOW fixed); `Test-PerfGate.ps1 -Dataset Stellar`
PASS (total +0.1%, flat); `Compare-CrossImpl-Reference.ps1 -Dataset Stellar` PASS
(all 14 boundaries match the frozen Rust reference). Awaiting Copilot + human review.

## Profiler hooks (not an action item)
RunCoelutionScoring's `ProfilerHooks.*` bracketing (LogMemoryStats / StartMeasure /
SaveAndStopMeasure) was removed when the method moved to OspreySharp.Scoring
(ProfilerHooks + its JetBrains.Profiler.Api dep live in OspreySharp.Tasks). This
stays removed -- no follow-up is scheduled. IF someone later wants to profile scoring
(e.g. chasing a perf regression), reinstate it then via a seam (ctor delegates or an
`IScoringProfiler` mirroring `IScoringDiagnostics`) or by relocating ProfilerHooks.
ProfilerHooks itself is left intact in OspreySharp.Tasks.

## Notes
- Reference set local at `D:\test\osprey-runs\stellar\_crossimpl_reference\`
  (Rust 696c938 / v26.6.1; README inside); regenerate with `Build-CrossImplReference.ps1
  -Force` (needs a built Rust osprey) if missing.
- After PR 7 lands, run the next blind `/pw-oop-review` to re-survey the decomposed
  tree and seed the next batch (this PR + PR 5/6 are the post-06-17 batch).

### 2026-06-18 - Merged

PR #4316 merged as commit 3a6e017b9e (squash). Shipped both halves of the "do both in
PR 7" decision as pure byte-identical code motion: (1) `CoelutionScorer.ScoreCandidate`
decomposed into `FindScanRange` / `DetectCandidatePeaks` / `CaptureCwtCandidates` /
`BuildFdrEntry` (rank-scoring loop left whole), and (2) `RunCoelutionScoring` /
`DeduplicateDoubleCounting` / `DeduplicatePairs` composed off `AbstractScoringTask`
into a new `ScoringPipeline` (OspreySharp.Scoring), severing PipelineContext via the
logInfo + `IScoringDiagnostics` seam, with thin protected forwarders keeping the six
subclass call sites unchanged. Added `IScoringDiagnostics.DiagSearchEntryIds`. Gates:
per-commit build/inspection (0 warnings) + Stellar golden; pre-merge `-Dataset All`
(Stellar + Astral byte-identical) + perf gate (total +0.1%, flat) + cross-impl
reference (14/14 boundaries vs frozen Rust) + fresh-context self-review (clean, 2 LOW
fixed) + Copilot (no comments). **Deferred / not action items:** profiler-hook
placement (removed; reinstate only if scoring profiling is resumed); a dedup tie-break
unit test (self-review follow-up; only needed once the seam gets a second caller).
This completes the PR 5/6/7 post-2026-06-17 debt-paydown batch -- next: a fresh blind
`/pw-oop-review` to seed the following batch.
