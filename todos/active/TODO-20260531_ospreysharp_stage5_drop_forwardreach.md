# TODO: Remove Stage 5's forward-reach into Stage 7 (drop the vestigial 2nd-pass overlay)

**Status**: In progress (PR open; review chain underway)
**Branch**: `Skyline/work/20260531_ospreysharp_stage5_drop_forwardreach` (pwiz)
**PR**: [#4262](https://github.com/ProteoWizard/pwiz/pull/4262)
**Created**: 2026-05-31
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\Tasks\FirstJoinTask.cs` (C#-only)

## Objective

`FirstJoinTask` (Stage 5) reached *forward* to `MergeNodeTask` (Stage 7): inside
`ReloadSecondPassOverlay` it did `_ctx.GetTask<MergeNodeTask>()` and borrowed
`mergeNode.ValidityKey(_ctx)` + `.Name` to validate the `.2nd-pass.fdr_scores.bin`
sidecars before overlaying them onto the post-compaction entries. That gave Stage 5
knowledge of a stage that runs after it. Remove the reach so Stage 5 holds zero
forward knowledge.

## Provenance

This is the original **PR-D** from the Tasks-layer decomposition program
(`ai/todos/backlog/brendanx67/TODO-ospreysharp_task_layer_decomposition.md`). PR-D was
first framed as "Stage 7 owns its 2nd-pass rehydrate; relocate the overlay from Stage 5
into Stage 7." On investigation (2026-05-31, after the reconciled-parquet split #4261
merged) the relocation turned out to be unnecessary:

**MergeNodeTask already fully owns the 2nd-pass rehydrate.** It (a) runs 2nd-pass
Percolator when any 2nd-pass sidecar is missing, and (b) re-overlays the 2nd-pass
sidecars onto the shared entry buffer (`MergeNodeTask.cs:391`) before protein FDR and
the blib write. So FirstJoin's overlay was **vestigial**:
- Straight-through and `ProteinFdr==null`: no 2nd-pass sidecar exists (they are only
  ever written by MergeNode, only when `ProteinFdr.HasValue`), so FirstJoin's overlay
  was a no-op.
- `ProteinFdr.HasValue` + sidecars-exist (resume / `--join-at-pass=2`): FirstJoin's
  overlay applied 2nd-pass scores, but MergeNode's own overlay re-applied the same
  bytes before any consumer, and Stage 6 is a no-op once a 2nd-pass sidecar exists
  (`PerFileRescoreTask` early-returns on `anyPass2Present`) -- so nothing between
  Stage 5 and Stage 7 ever consumed FirstJoin's overlay.

So the fix is a **clean deletion**, not a relocation: remove
`FirstJoinTask.ReloadSecondPassOverlay` (128 lines) and its call site. Stage 5 then
references `MergeNodeTask` nowhere for the reach. (The remaining FirstJoin<->MergeNode
link is the opposite, correct direction: MergeNode calls a static FirstJoin helper for
its own 2nd-pass Percolator -- Stage 7 depending on Stage 5.)

## Tasks

- [x] Delete `ReloadSecondPassOverlay` + its call; replace the call site with a
  breadcrumb explaining Stage 7 owns the rehydrate.
- [x] Pre-commit gate (build OK, inspection 0/0, 352 tests pass).
- [ ] **Tier 2 (critical)**: `Compare-Stage7-Rehydration-Strict-CSharp.ps1` Stellar --
  the `--join-at-pass=2` mode where the deleted overlay actually fired. Must stay
  bit-identical at every boundary (this is the load-bearing proof for the deletion).
- [ ] Tier 1: `Compare-EndToEnd-Crossimpl.ps1` Astral `-SkipRust` (1e-9).
- [x] PR #4262 + Copilot (positive overview, no findings) + `/pw-self-review`
  (no Critical/High/Medium; deletion confirmed output-preserving in every mode).
  Ready for human merge.

## Verification

The straight-through gates (pre-commit, Tier 1) only confirm the no-op modes. **Tier 2
is the real test** -- it walks the in-memory vs HPC sidecar+rehydrate chain through
`--join-at-pass=2`, exactly the mode where FirstJoin's overlay used to fire; if MergeNode
truly subsumes it, Tier 2 stays bit-identical at the Stage 7 + blib boundary.

## Notes / out of scope

- The `GetTask<T>()` service-locator stays -- its backward (upstream) pulls are correct
  ordering; only the forward reach was the problem.
- Deferred (per user, until true HPC testing): the pre-existing no-work-file
  `--join-at-pass=2` strict reconciled-input gate behavior (from #4261 review).
- Latent hardening (surfaced by #4262 self-review, PRE-EXISTING, not a regression):
  MergeNode's 2nd-pass overlay (`MergeNodeTask.cs:404`) loads a present-but-stale/
  corrupt 2nd-pass sidecar with only a `File.Exists` check + warning -- no
  validity-key check (the deleted FirstJoin overlay had `TaskValiditySidecar.IsValid`,
  but it never affected final output since MergeNode's overlay was authoritative).
  `missingPass2` (`:154`) counts only ABSENT sidecars, so a corrupt-but-present one
  isn't recomputed. Consider a 2nd-pass validity-key check in MergeNode when real HPC
  testing begins.

## Progress Log

### 2026-05-31 - PR #4262 opened, gates + reviews green

Deleted the vestigial overlay (commit d35a2b3579). Pre-commit (352 tests, 0/0),
Tier 2 rehydrate parity (Stellar `--join-at-pass=2`, bit-identical at every boundary --
the load-bearing proof), Tier 1 Astral straight-through 1e-9 all PASS. Copilot: positive
overview, no findings. `/pw-self-review`: no Critical/High/Medium; independently
confirmed output-preserving across all modes (shared-buffer model, MergeNode's `:404`
overlay + `missingPass2` recompute subsume it, nothing consumes the overlay between
Stage 5 and Stage 7, dead 1st-pass fallback, self-consistency). One Low (lost
`ExitCode=1` guard, superseded by recompute) + the pre-existing corrupt-sidecar note
above. No follow-up commit needed. Ready for human merge.
