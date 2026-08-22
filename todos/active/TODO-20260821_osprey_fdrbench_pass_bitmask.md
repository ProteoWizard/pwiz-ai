# --fdrbench-pass is a bitmask tested with ==, so `both` silently emits only pass 2

## Branch Information
- **Branch**: none yet - backlog, needs a decision before code
- **Base**: `master`
- **Created**: 2026-08-21
- **Status**: Active (analysis complete, implementation blocked on a product decision)
- **Module**: `osprey`
- **Requester/Reporter**: none - found while preparing the TDP-43 pickrun3 comparison

## The defect, in one sentence

`ParseFdrBenchPass("both")` returns `FDRBENCH_PASS_1 | FDRBENCH_PASS_2` - a **bitmask** -
and every consumer tests it with **`== 1`**, so `both` matches nothing and emits pass 2 only.

Consumers (all `config.FdrBenchPass == 1`):

| file | line |
|---|---|
| `Osprey.Tasks/FirstPassFdrTask.cs` | 377 |
| `Osprey.Tasks/PerFileScoringTask.cs` | 1537, 1949, 2133 |

## The code and its own documentation disagree

* **CLI help** (`OspreyCommandArgs.cs:804`): "both = emit both in one run, writing the
  `--fdrbench` path with `.pass1` / `.pass2` stem suffixes." No `.pass1` file is ever written.
* **The emitter's doc-comment** (`FirstPassFdrTask.cs:1340`): "when `--fdrbench` is set with
  a pass mask that **includes** pass 1 (`--fdrbench-pass 1` or `both`)". Says mask, does `==`.
* **The parse test** (`OspreyCommandArgsTests.cs:99`): "selects the pass(es) as a **bitmask**"
  and asserts `both` -> `PASS_1 | PASS_2`. So the mask is the intended design; the equality
  test in the consumers is the divergence.

## Why the obvious fix is WORSE than the bug

Changing `== 1` to `(FdrBenchPass & FDRBENCH_PASS_1) != 0` would make `both` correct **and**
hand the project an O(files) memory regression at exactly the scale that matters.

That same `== 1` is doing double duty as the **resident-pool gate**. `NeedsResidentPool` /
`CanUseLeanProjection` in `PerFileScoringTask.cs` treat "FDRBench pass 1" as a consumer that
"walks the full pre-compaction `FdrEntry` pool", which grows O(files) - the growth #4488 was
written to bound. The TDP-43 README documents the current behaviour as a FEATURE:

> `2` and `both` are memory-safe - the `both` bitmask (3) never matches that `== 1` test -
> but they emit only the pass-2 TSV.

So today `both` is memory-safe **by accident of a type confusion**. Anyone who "fixes" the
comparison to match the doc-comment converts a silently missing file into an OOM on a
163-file run. **Do not take that fix without doing the streaming work below.**

## Blast radius - this is not a corner case

`ai/scripts/Osprey/Common/OspreyDatasetRun.psm1:248` defaults `FdrBenchPass` to **`'both'`**,
and `Run-SeaAd.ps1` does not override it (only `Run-Tdp43.ps1` does, to `'none'`). **Every
SEA-AD run launched without an explicit `-FdrBenchPass` has requested both passes and
received pass 2 only.**

Consequence worth stating plainly: the independent FDRBench oracle - which
`ai/docs/osprey-development-guide.md` calls the correctness oracle that "wins over parity" -
has never been available for pass 1 at cohort scale. Nobody noticed because
`--model-diagnostics` supplies an internal pass-1 FDP estimate that filled the gap, and that
estimate is what every recent arm has actually been compared on (`tools/pass1_fdp.py`).

## The decision this needs (why there is no code yet)

Three options, and the choice is a product call, not an implementation detail:

1. **Emit pass-1 FDRBench off the streaming projection path.** The real fix. Makes `both`
   honour its contract with no resident pool. Substantial work: the pass-1 emitter currently
   consumes the resident pre-compaction pool, and it would have to become a second streamed
   pass, per the standing "per-file compute -> O(entries) aggregate -> per-file emit" rule.
2. **Hard-fail `both` at argument-parse time** until (1) exists, naming the constraint.
   Matches the recorded "hard fail over warn-and-proceed" preference - a user who asked for
   pass 1 and silently got nothing is the exact case that rule covers. **But it breaks the
   SEA-AD runner's default**, so it must land together with changing that default to `'2'`.
3. **Document only** - correct the CLI help and doc-comment to say `both` currently means
   pass 2, and keep the accidental memory safety. Cheapest, least honest.

Recommendation: **(2) now, (1) when the streamed emitter is worth building.** (2) is small,
removes a silent wrong answer, and the runner-default change is one line. (3) enshrines a
type confusion as documented behaviour.

## Tasks

- [ ] Decide between the options above
- [ ] If (2): reject `both` in `ParseFdrBenchPass` with a message naming the resident-pool
      reason, AND set `DefaultFdrBenchPass = '2'` for SEA-AD in the same change
- [ ] If (1): streamed pass-1 emitter, then restore `both` and make all four consumers test
      the mask rather than `==`
- [ ] Either way, delete the "or `both`" claim from `WriteFdrBenchPass1IfRequested`'s
      doc-comment - it is what would lure the next reader into the unsafe fix

## Notes

- Nothing here affects the TDP-43 run of 2026-08-21, which passes `--fdrbench-pass 2`
  explicitly and reads pass-1 FDP from `--model-diagnostics` as designed.
- The equality test is ESSENTIAL as the resident-pool gate today. Any change to it has to
  carry the pool question with it; they cannot be separated.
