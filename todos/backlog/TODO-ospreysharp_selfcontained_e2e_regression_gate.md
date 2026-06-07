# TODO: OspreySharp self-contained end-to-end regression gate (rename/reframe off the cross-tool script)

**Status**: Backlog (not started)
**Priority**: Medium-High — this is the gate we run most; ergonomics + correct framing matter
**Type**: Test infrastructure / developer ergonomics
**Source**: 2026-06-06 discussion during the diagnostics-DI PR — the de-facto primary
regression gate is a repurposed cross-tool script, which is awkward to name/reason about
now that the need is "keep OspreySharp's own output stable while we reorganize the code."

## Problem

The going-forward need is a **same-impl** regression: as we refactor OspreySharp
(diagnostics DI, calibrator extraction, modular scoring, etc.), confirm the C#
pipeline still produces the **same output it produced before** — end-to-end, including
the sidecar-write → rehydrate (resume / HPC-chain) paths. Cross-tool comparison against
Rust is still wanted, but **infrequently** (it's the "have we drifted from Rust?" check,
not the per-change gate).

Today that need is met only in pieces, and the piece we actually run as the fast gate is
the wrong shape conceptually:

| Script | Self-contained? | Shape | "Expected" is |
|--------|----------------|-------|---------------|
| `Test-Full-Regression` -> `Test-Snapshot` | yes (no Rust) | **stage-isolated** freeze-and-march (`--task` / `--input-scores <frozen.parquet>` + `OSPREY_*_ONLY` exits) | frozen OspreySharp snapshot |
| `Compare/Compare-EndToEnd-Crossimpl.ps1 -SkipRust` | no (needs cached Rust) | **straight-through end-to-end**, multi-file, fast | cached **Rust** blib |
| `Compare/Compare-StraightThroughResume-CSharp.ps1` | yes | cold vs warm **resume** (sidecar write->rehydrate) | warm == cold (self-consistency); RED by design today (resume-RT bug) |
| `Compare/Compare-Stage7-Rehydration-Strict-CSharp.ps1` | yes | in-memory vs HPC-chain (per-phase sidecar/rehydrate) | in-memory == HPC-chain (self-consistency) |

The wart: the fast straight-through gate we lean on (`Compare-EndToEnd-Crossimpl
-SkipRust`) **borrows Rust as the "expected"** (a cached `rust/output.blib`) and lives in
the cross-tool `Compare/` folder with a cross-tool name. Its origin was cross-tool
comparison; we've repurposed it as the C# regression by freezing one side. Meanwhile the
genuinely self-contained gate (`Test-Snapshot`) is **stage-isolated** (per-stage process
restarts + `OSPREY_*_ONLY` dump overhead) and slow (~70 min full), which is *why* the
straight-through `-SkipRust` became the de-facto gate (see the regression-gate memory).

So: the gate we run is named/shaped as a cross-tool comparison; the self-contained one is
slow and stage-isolated; resume coverage is a third self-consistency script that's red by
design. None is cleanly "the OspreySharp end-to-end regression."

## Desired end state

A cleanly-named, **self-contained**, **straight-through end-to-end** OspreySharp
regression that:

1. Runs the **full pipeline in one straight-through pass** (not stage-isolated) — fast,
   like the `-SkipRust` run (~minutes Stellar single, ~17 min Astral 3-file), and
   exercises the multi-file reconciliation / consensus-RT / multi-charge / gap-fill
   machinery that single-file misses (default the real gate to `-Files All`).
2. Compares against a **frozen OspreySharp expected** (a cold straight-through run on a
   known-good commit), not a Rust reference. Capture via a `-CreateExpected`-style mode
   like `Test-Snapshot`'s `-CreateSnapshot`, recording source commit + binary SHA-256 in
   a manifest.
3. Adds a **resume leg**: a warm re-run that skips valid stages and drives the
   sidecar-write -> rehydrate paths, also compared against the same frozen expected
   (folds in `Compare-StraightThroughResume-CSharp`'s coverage). This is the part that
   guards the worker/HPC-chain output, which a single cold run does not.
4. Is the **primary gate**, named `Test-*` at the top level (e.g. `Test-EndToEnd.ps1`, or
   a new straight-through mode of `Test-Full-Regression`). `Compare/Compare-*-Crossimpl`
   reverts to the **occasional cross-tool** check (run after scoring/calibration changes
   or on a cadence, not per-change).

## Design considerations / open questions

- **Keep the stage-isolated walk as a bisection drill-down, not the gate.** `Test-Snapshot`
  localizes a failure to a stage; that's valuable when the straight-through gate goes red.
  Reframe it as the "where did it diverge?" tool, with the straight-through gate as the
  fast first-line check.
- **Comparators already exist** and are reusable: `Compare-Blib-Crossimpl.ps1` (SQL
  row+col 1e-9), `parquet_diff.py --tolerance 0`, `Compare-Stage7-Crossimpl.ps1`. The new
  gate is mostly orchestration + an expected-capture mode, not new comparison code.
- **Resume leg depends on a known bug.** `Compare-StraightThroughResume-CSharp` is red
  today by design (straight-through-resume 1st-pass RT bug,
  `ai/todos/backlog/TODO-ospreysharp_straightthrough_resume_1stpass_rt.md`). The resume
  leg of the new gate will be red until that fix lands; gate it as expected-fail / xfail
  with a pointer, or sequence this TODO after that fix. Decide which.
- **What is "expected"** — blib only, or blib + key per-stage artifacts (Stage 5
  fdr_scores, Stage 6 reconciled parquet, Stage 7 protein-fdr tsv)? Blib is the product;
  the per-stage artifacts localize drift. Probably capture both; gate on blib, report
  per-stage.
- **Diagnostics dumps as expected.** Note that `Test-Snapshot` currently doubles as the
  dump-byte-stability check (its `OSPREY_*_ONLY` isolation emits the dump TSVs and
  compares them). A straight-through gate won't emit those dumps unless asked. Decide
  whether dump byte-stability stays the stage-isolated tool's job, or the new gate adds an
  optional `-d`/env dump-capture-and-compare leg.
- **Migration of docs + memory.** Once the clean gate exists, update
  `ai/scripts/OspreySharp/{README,PRE-COMMIT}.md`, the `osprey-development` skill, and the
  three OOP-review TODOs (they currently name `Compare-EndToEnd-Crossimpl -Files All
  -SkipRust` as the C#-refactor gate), and update/retire the
  `feedback_ospreysharp_csharp_regression_gate` memory (its `-SkipRust` preference is a
  workaround for the absence of this clean gate).

## Relationship to other work

- Supersedes the day-to-day use of `Compare-EndToEnd-Crossimpl -SkipRust` as the C#
  refactor gate (the diagnostics / calibrator / scoring TODOs currently cite it).
- Pairs with `TODO-ospreysharp_straightthrough_resume_1stpass_rt.md` (the resume leg goes
  green when that bug is fixed).
- Builds on the existing `Test-Snapshot.ps1` machinery (capture-baseline + per-stage
  comparators); this is a reframe + a straight-through mode + a resume leg, not a rewrite.
