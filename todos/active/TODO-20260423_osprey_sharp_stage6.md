# TODO-20260423_osprey_sharp_stage6.md — Phase 4 Stage 6: refinement parity

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4
> umbrella, Stages 6-8). The umbrella is the authoritative plan;
> this file tracks the Stage 6 branch, progress log, and PR links.

## Branch Information

- **pwiz branch**: `Skyline/work/20260423_osprey_sharp_stage6` (not yet created — branch fresh off `master` when Stage 6 walk starts, after the streaming-port PR merges)
- **osprey branch**: TBD (created only if a parity-critical upstream port needs landing)
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-04-23
- **Status**: Pending (prerequisites shipping; Stage 6 walk starts in next session)
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **PR**: (pending)

## Scope

Covers Priorities 1-3 of the umbrella TODO:

1. **Upstream resync delta catalog**: scan `maccoss/osprey:main`
   for commits since the last review (2026-04-21 session caught
   up to `885339b`). Disposition each as parity-critical port /
   Stages 1-5 drift / out-of-scope. Dump to
   `ai/.tmp/stage6_upstream_delta.md`.
2. **Multi-file Stage 5 validation**: extend the single-file
   Stellar Stage 5 parity (already bit-identical at 462,802 rows /
   34,158 precursors / 30,712 peptides / 5,471 protein groups) to
   3-file Stellar + Astral. Exercises best-per-precursor
   subsampling across files + experiment-level FDR compaction,
   neither of which single-file touches.
3. **Stage 6 refinement parity**: multi-charge consensus leader
   pick + cross-run RT reconciliation + second-pass re-score at
   locked boundaries + re-trained Percolator SVM. Add the three
   new diagnostic dumps per the umbrella (`OSPREY_DUMP_CONSENSUS`
   / `OSPREY_DUMP_RECONCILIATION` / `OSPREY_DUMP_REFINED_FDR`,
   each with matching `_ONLY` early-exit), mirroring the Stage 5
   four-dump pattern that shipped in PR #18 / pwiz #4160.

## Gate for PR

Bit-identical cross-impl parity on Stellar + Astral, single-file
and 3-file, through end-of-Stage-6. `Compare-Percolator.ps1`
extended (or a sibling harness script added) for consensus +
reconciliation dump comparisons. Stages 1-5 parity gates
(`Test-Features.ps1` 21/21 @ 1e-6 + end-of-Stage-5 Percolator
dump byte-identical) must still hold.

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4
  umbrella plan (Stages 6-8 in detail).
- `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`
  — Stage 5 precedent: one-commit-per-logical-change, bisection-
  to-ULP discipline, four-dump diagnostic harness +
  `Compare-Percolator.ps1`.
- `ai/docs/osprey-development-guide.md` — HPC flags, env-var
  reference, bisection methodology, determinism patterns,
  steel-thread parity doctrine.
- `C:\proj\osprey\CLAUDE.md` — Rust-side project overview and
  critical invariants.

## Progress log

### Session 1 (2026-04-23) — Pre-requisites shipped; Stage 6 not yet started

Session focused on getting everything lined up for a clean Stage 6
kickoff in a new session. Three pre-requisite PRs landed or are in
review:

1. **Stage 5 dump text format** (merged pwiz #4163, commit
   `80f5341bc`). See
   `ai/todos/completed/TODO-20260423_ospreysharp_dump_format.md`.
2. **Upstream resync delta catalog**: shipped to
   `ai/.tmp/stage6_upstream_delta.md`. Eight commits from
   `885339b..2b73ba8`; no outstanding ports other than the reconciliation
   gate broadening which is natural Stage 6 walk work.
3. **Percolator streaming path port**: required for Astral byte-
   parity. Split into its own branch + TODO because it is not
   Stage 6 itself, just the last Stage 5 prerequisite. See
   `ai/todos/active/TODO-20260423_ospreysharp_percolator_streaming.md`.
   When that PR merges, Stellar + Astral are both 3/3 byte-identical
   on all four Stage 5 dumps and Stage 6 can begin.

**Actual Stage 6 walk (Priority 3 of the umbrella) has not started
in this session.** The branch `Skyline/work/20260423_osprey_sharp_stage6`
should be (re-)created fresh off `master` once the streaming port
PR merges. The next session picks up from there.

**Path-normalization follow-up** (`LibraryIdentityHash` slash-
direction issue): deferred to a later PR; hitting it only when the
CLI is invoked with mixed slash styles, so Compare-Stage5 is
unaffected.
