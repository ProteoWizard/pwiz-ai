# TODO-20260619_ospreysharp_debt_paydown_pr9.md -- OspreySharp debt-paydown PR 9 (cleanups + retire AbstractScoringTask)

## Branch Information
- **Branch**: `Skyline/work/20260619_ospreysharp_debt_paydown_pr9` (create off master; REBASE onto master after PR 8 lands)
- **Base**: `master` (after PR 8 merges)
- **Created**: 2026-06-19
- **Status**: Completed
- **PR**: [#4319](https://github.com/ProteoWizard/pwiz/pull/4319) (merged 2026-06-20 as a0065b3efa)

### 2026-06-20 - Merged

PR #4319 merged as commit `a0065b3efa`. All four items shipped: Rec 3 (DEBUG shared-buffer
ordering guard), Rec 2 (Stage 5 Percolator diagnostics lifted out of the FDR core), the
AbstractScoringTask retirement (-> `internal static ScoringTaskShared`), and the
self-contained HPC 4-task worker-chain regression leg (mode 3, default-on). All pre-merge
gates green: `-Dataset All` regression modes 1/2/3 (Stellar+Astral byte-identical), strict
HPC comparator boundary-parity, perf gate (+0.5% total), clean fresh-context self-review.
One Copilot comment (duplicate `<summary>` block) fixed in `023dfed85c`. Mode 3 raised the
overnight gate runtime (~35 -> ~64 min on the TeamCity agent); the TC execution timeout was
bumped 60 -> 120 min. Deferred / backlog: (1) osprey FirstJoin `--input-scores` order-
sensitivity is a latent HPC production-parity risk -- mode 3 pins the order, masking it;
needs a follow-up ticket to confirm the orchestrator's ordering guarantee (see
`project_osprey_firstjoin_order_sensitivity`). (2) Per the Notes below, run the FINAL
confirmatory blind `/pw-oop-review`; if clean, declare the OOP debt-paydown arc complete.

> Seeded by the 2026-06-18 blind `/pw-oop-review` (`ai/.tmp/20260618-oop-review-report.txt`,
> Rec 2 + Rec 3 + the AbstractScoringTask open question). The small/low-risk closeout of
> the arc.

## Framing -- output-invariance only; pure code motion + one debug assert
Output-locked by `regression.ps1` @1e-9. See `feedback_refactor_gate_output_not_structure`.

## Work
1. **Rec 2 -- lift the inline diagnostics out of `PercolatorFdr.RunPercolator`.** It reads
   four `OSPREY_DUMP_*` env vars inline and can `Environment.Exit(0)` mid-method. Pass a
   small `PercolatorDiagnosticsConfig` (or reuse the `IScoringDiagnostics` seam) so the FDR
   engine is a pure function of its inputs -- no env sensing, no process exit in the core.
   The Tasks-layer caller decides any early-exit. Consistent with the clean diagnostics seam.
2. **Rec 3 -- guard the shared-mutable-buffer ordering invariant.** `PipelineByproducts`
   ScoredEntries -> CompactedEntries -> RescoredEntries wrap the same `List` and mutate in
   place; safe only because the DAG consumes each milestone before the next mutation. Add a
   DEBUG-time assert that a milestone is consumed before the next in-place mutation, turning
   the documented-but-fragile invariant into a guarded one. (Open Q: if the no-copy hand-off
   is only precautionary, consider immutable snapshots instead -- confirm with Brendan; an
   assert is the low-risk default.)
3. **Retire `AbstractScoringTask`** (Brendan's call; rationale recorded). It is now a
   167-line plumbing-only base: 2 `internal const` (NUM_PIN_FEATURES, BASE_ID_MASK), the
   `internal static s_mzmlReadGate`, `FindNearestMs1`, `ExtractIsolationWindows`, and 3
   one-line forwarders to `ScoringPipeline`. The scoring BEHAVIOR already lives in
   `ScoringPipeline` (composition, PR 7); the base shares only plumbing (statics need no
   inheritance) and is an attractive nuisance for feature-envy. Move the gate + constants +
   `FindNearestMs1` + `ExtractIsolationWindows` to an `internal static` Tasks holder (or
   onto ScoringPipeline where they belong), have `PerFileScoringTask` / `PerFileRescoreTask`
   call `ScoringPipeline` directly (a `private readonly` field preserves bare-name
   ergonomics), and drop the base class (they extend `OspreyTask` directly).
4. **Wire the HPC `--task` worker-chain rehydrate test into the standing cadence**
   (deferred here from PR 8 by Brendan, 2026-06-19). regression.ps1's mode 2 already
   covers in-process straight-through resume; the gap is the 4-task HPC chain. Recommended
   approach (revisit when implementing): add a self-contained **mode 3** HPC-chain leg to
   `regression.ps1` (runs --task PerFileScoring|FirstJoin|PerFileRescore|MergeNode and
   compares the chain blib + reconciled parquets to straight-through), keeping the overnight
   gate free of any ai/ dependency. Alternatives weighed in PR 8 TODO: tctest.bat invoking
   the ai/ comparator (cross-repo coupling) or a separate TeamCity config. PR 8 verified the
   chain manually (Compare-Stage7-Rehydration-Strict-CSharp, all boundaries bit-parity).

## Progress
- **Rec 3 -- DONE** (commit `bb77ce5906`). DEBUG-only guard in `PipelineContext`:
  `Publish` asserts the milestone currently published over a backing list (keyed by the
  `List` reference) was consumed via `TryGet`/`Get` before that same list is re-published
  at a new milestone. Reference-keyed, NOT a static ScoredEntries->Compacted->Rescored
  type order, because the merge path (`PerFileRescoreTask` line ~403) publishes
  `RescoredEntries` directly over the `ScoredEntries` buffer, skipping `CompactedEntries` --
  a static-order assert would false-fire there. Decision on the open Q: kept the **assert**
  (not immutable snapshots); `PipelineByproducts` already documents the no-copy hand-off as
  "load-bearing at Astral scale", which resolves it against snapshots. Validated: Debug
  3-file Stellar straight-through ran clean (no assert), identical blib.
- **Rec 2 -- DONE** (commit `adbbb66d56`). New `PercolatorDiagnosticsConfig` (FDR assembly,
  8 bool gates) on `PercolatorConfig.Diagnostics`; `RunPercolator`'s four inline
  `OSPREY_DUMP_*` env reads + `Environment.Exit(0)` replaced by config-gated dumps + a
  `PercolatorResults.DiagnosticAbort` sentinel. Env sensing moved onto `IOspreyDiagnostics`
  (8 new flags, parsed in `OspreyFileDiagnostics`); `PercolatorEngine.RunPercolatorFdr` now
  returns `bool aborted` and threads the config (incl. the streaming train-only pass); the
  `FirstJoinTask` facade builds the config from `ctx.Diagnostics` and owns the
  `Environment.Exit(0)`. Also added the 8 flags to `OspreyFileDiagnostics.AnyEnabled` (a
  smoke test caught that a lone `OSPREY_DUMP_STANDARDIZER` no longer activated the sink --
  the old inline path didn't depend on the sink). Validated both ways: Stellar regression
  mode 1+2 byte-identical (diagnostics off), and a diagnostics-on run wrote
  `cs_stage5_standardizer.tsv` + aborted exit 0 via the facade.

- **Retire AbstractScoringTask -- DONE** (commit `10a4b24267`). Replaced the 167-line
  plumbing-only base with `internal static ScoringTaskShared` (the mzML read gate, the
  NUM_PIN_FEATURES/BASE_ID_MASK consts, `ExtractIsolationWindows`, `FindNearestMs1`, plus a
  `Pipeline(ctx)` factory). `PerFileScoringTask`, `PerFileRescoreTask`, `FirstJoinTask` now
  extend `OspreyTask` directly and call `ScoringPipeline` through
  `ScoringTaskShared.Pipeline(ctx)`. Net -57 lines. Pure code motion; Stellar regression
  modes 1 & 2 byte-identical. (Decided against the per-task `private readonly` field the TODO
  floated -- tasks are default-constructed, ctx arrives per-call, so a ctx-built field can't
  be readonly; the static factory keeps DRY without inheritance.)
- **Mode 3 HPC chain gate -- DONE** (commit `1b55c29605`). Full Stellar regression green on
  all three modes (1 vs golden, 2 resume, 3 HPC chain), each blib 52,514,816 bytes.
  Added a self-contained `Invoke-HpcChain` that runs PerFileScoring -> FirstJoin
  -> PerFileRescore -> MergeNode with sidecar rehydration between phases and asserts the
  chain blib == straight-through blib at 1e-9 via the existing `Compare-BlibFull` (no ai/
  dependency). Brendan's calls: **blib-only @1e-9** hard gate (not reconciled-parquet SHA;
  that stays in the ai/ strict comparator for red-gate bisection), **default-on for all
  datasets** (added `-SkipHpcChain` for local fast iteration, paralleling `-SkipResume`).
  - **Gotcha found + fixed:** FirstJoin's reconciliation/gap-fill output is **input-file-order
    sensitive**. The first cut iterated a PowerShell hashtable's key order for `--input-scores`,
    which differed from the straight-through's sorted file order and produced a *different*
    (bloated) blib -- a false FAIL. Fixed to feed files in `$inputs.Mzmls` order (the same order
    the straight-through uses). Verified the chain itself is genuinely bit-parity on this build
    by running the ai/ strict comparator (Compare-Stage7-Rehydration-Strict-CSharp): PASS at
    every Stage 5/6/7 boundary. Mode 3 then PASS (chain blib == straight, 52,514,816 bytes).
  - **Backlog candidate (not this PR), sharpened by the self-review:** osprey's multi-file
    FirstJoin reconciliation output depends on `--input-scores` order. mode 3 pins it to the
    straight-through's `$inputs.Mzmls` order, so the gate validates cross-process rehydrate
    parity but **masks the order-sensitivity by construction**. Open question for a follow-up:
    does the production HPC orchestrator guarantee the SAME canonical `--input-scores` order at
    the FirstJoin/MergeNode boundary that the per-file workers were launched in? If a real
    multi-node run can hand FirstJoin a different order, that's a latent production parity bug.
    Follow-up ticket should (a) confirm the orchestrator's ordering guarantee, and if absent
    (b) make FirstJoin order-insensitive or enforce canonical ordering. Not yet known whether
    the in-memory path is itself order-sensitive (would distinguish a general osprey
    determinism property from a chain-only bug) -- needs a shuffled-order in-memory A/B.

## Self-review (fresh-context agent, clean)
Ran `/pw-self-review` on the local branch before opening the PR: "No correctness or parity
defects." Two LOW notes, both non-defects on inspection -- (1) the 4 new `*Only` flags now
contribute to `OspreyFileDiagnostics.AnyEnabled`, which is consistent with how every other
dump's `*Only` already works there and is harmless (no dump fires without the `Dump` flag);
(2) `Invoke-OspreyTaskRun`'s post-`finally` `$exit` check matches the existing
`Invoke-OspreyRun` pattern (a launch throw propagates past it). No code changes taken.

## Out of scope
- The orchestration-monolith decompositions -> PR 8.

## Gates
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar` +
  the HPC/cross-impl gates (`Compare-Stage7-Rehydration-Strict-CSharp.ps1`,
  `Compare-CrossImpl-Reference.ps1`) + `/pw-self-review`.

## Notes
- After PR 9, run the FINAL confirmatory blind `/pw-oop-review`; if clean, declare the
  OOP debt-paydown arc complete.
