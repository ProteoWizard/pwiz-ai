# --fdrbench-pass is a bitmask tested with ==, so `both` silently emits only pass 2

## Branch Information
- **Branch**: `Skyline/work/20260912_osprey_fdrbench_pass_bitmask` (`C:\proj\pwiz-work1`, off
  master `7af9eb0ea5`)
- **Base**: `master`
- **Created**: 2026-08-21 (analysis); started 2026-09-12
- **Status**: In Progress - **decided 2026-09-12 (Brendan): option (1), the streamed pass-1
  emitter.** Not the hard-fail stopgap (2) and not document-only (3). Design below.
- **GitHub Issue**: [#4507](https://github.com/ProteoWizard/pwiz/issues/4507) - the same
  fix seen from the memory side: `--fdrbench-pass 1` is the last first-pass consumer forcing
  the O(files) resident pool, and the `fdrbench-pass1` ratchet token exists for it
- **Module**: `osprey`
- **PR**: (pending)
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

- [x] Decide between the options above - **(1), Brendan 2026-09-12**. The recommendation for
      (2)-then-(1) was not taken: the stopgap would have to be undone by the real fix.
- [ ] ~~If (2): reject `both` in `ParseFdrBenchPass`...~~ not chosen
- [x] Streamed pass-1 emitter (2026-09-12, see the Progress Log). The five consumers no longer
      test the pass at all: pass selection is `PathForPass`'s job, which always honoured the
      mask, and the resident-pool question is answered without it
- [x] ~~Delete the "or `both`" claim from `WriteFdrBenchPass1IfRequested`'s doc-comment~~ -
      moot, the claim is true now
- [ ] Stellar A/B byte-identical (running); `regression.ps1 -Dataset Stellar`;
      `regression-parallel.ps1 -Dataset All`; `/code-review max`; PR closing #4507

## Notes

- Nothing here affects the TDP-43 run of 2026-08-21, which passes `--fdrbench-pass 2`
  explicitly and reads pass-1 FDP from `--model-diagnostics` as designed.
- The equality test is ESSENTIAL as the resident-pool gate today. Any change to it has to
  carry the pool question with it; they cannot be separated.

## Design (2026-09-12, read off master `7af9eb0ea5`)

The code has moved since the analysis above, in this fix's favour. The `.1st-pass.fdr_scores.bin`
sidecar is now written from pass 1 with all its columns final (#4633), and the experiment-scope
columns live once per entry_id in `FdrExperimentAccumulator` (#4486). So every input the pass-1
emitter needs is on disk or in an O(distinct) map by the time the projection path reaches
`WriteExperimentSidecar`, and nothing needs a resident `FdrEntry`.

**What the pass-1 TSV needs per row**, from `FdrBenchInputWriter.WritePeptideInput`:
`IsDecoy`, `EntryId` (library lookup for peptide/protein), `ModifiedSequence`, `Charge`,
`Score`, `EffectiveRunQvalue(level)` (per-run mode) and `EffectiveExperimentQvalue(level)`
(per-precursor mode). Sources on the projection path:

| field | source |
|---|---|
| EntryId, Score, RunPrecursorQvalue, RunPeptideQvalue | `FdrScoreRecord` from the per-file sidecar |
| ModifiedSequence, Charge, IsDecoy | `ParquetScoreCache.ReadFdrStubScalars` (parquet-row order) |
| ExperimentPrecursorQvalue, ExperimentPeptideQvalue | `experiment.Records[entryId]` |

`StreamFirstPassFileScores` already joins the first two per file in parquet-row order; the
callback just drops `charge`. Extending it to pass `charge` is the whole streaming source.

**Order and ties.** Per-precursor dedup keeps min q, ties broken by STRICTLY greater score, so
the first-seen row wins an exact tie and the result is order-dependent. The resident path walks
`perFileEntries` in list order and entries in parquet-row order; the projection path walks
`projections.PerFile` in the same order (the protein-FDR comment records that this keeps the
best-scores insertion order identical). Same order, same winner. Output is then sorted by
(modseq, charge) ordinal, so the sort is a total order and the only order-sensitivity is the tie.

### Changes

1. **`FdrBenchInputWriter`**: factor the row formatting, dedup and sort out of the
   `FdrEntry`-list overload into a core that takes a lightweight row
   (`EntryId, ModifiedSequence, Charge, Score, RunQ, ExperimentQ`) streamed per run. The
   existing overload becomes an adapter (`FdrEntry` -> row), so both paths run ONE formatting
   and dedup implementation and byte-identity holds by construction, not by parallel code.
2. **`FirstPassFdrTask`**: a streamed `WriteFdrBenchPass1IfRequested` on the projection path,
   after `WriteExperimentSidecar` (experiment q final) and before `CompactFromSidecars`
   (pre-compaction pool = the projection = the sidecar records). Per file:
   `StreamFirstPassFileScores` -> skip decoys -> join `experiment.Records` -> row. Same
   pairing manifest, same log lines, same `[STAGE-WALL] fdrbench-pass1`.
3. **Remove the `FdrBenchPass == 1` term** from the five gates: `FirstPassFdrTask`
   `needsResidentFirstPassPool`, `PerFileScoringTask.PreCompactionPoolReason`,
   `NeedsResidentPool`, `ResidentPoolTrigger`, `LibraryFragmentRelease.LegAdmitsRelease`. The
   resident-path emitter stays as-is for the `projection-off` A/B oracle.
4. **Shrink the ratchet**: drop `fdrbench-pass1` from `ResidentPaths.KNOWN_UNFIXED` (and the
   constant), update the `OspreyEnvironment` doc example and `ResidentPoolGuardTest`'s pins.
5. **Runner + docs**: the NOTE in `OspreyDatasetRun.psm1` ("the pass-1 pool is not emitted off
   the projection path") and the TDP-43 README paragraph that documents the `both` bug as a
   feature both become false and go. The SEA-AD default `'both'` becomes honest.
6. **Tests**: `FdrBenchInputWriterTest` - the row overload matches the entry overload on the
   same data for both modes, both levels, and an exact-score tie; `ResidentPoolGuardTest` -
   `--fdrbench-pass 1` no longer needs the pool.

### Oracle

`--fdrbench-pass 1` on the RESIDENT path is the pre-existing emitter, so the byte-identity
test is a Stellar A/B, no golden needed:
`OSPREY_FDR_PROJECTION=0 OSPREY_ALLOW_UNFIXED_RESIDENT=projection-off` + `--fdrbench p1.tsv
--fdrbench-pass 1` (master or branch, same code) against the branch's default path with the
same flags; then `both` on the branch must yield `.pass1` == that and `.pass2` == a pass-2-only
run. Also once with `--fdrbench-per-run`. That is the does-it-fix test and runs BEFORE the
regression gates (which do not pass `--fdrbench` at all). Then `regression.ps1 -Dataset
Stellar` and `regression-parallel.ps1 -Dataset All` for nothing-broke.

Open: whether to add a gate mode that passes `--fdrbench ... both` on the cold leg and
asserts both files exist. Goldens for the TSVs are probably too large to commit; existence +
row-count sanity may be the right size.

## Progress Log

### 2026-09-12 - Implemented on `pwiz-work1`; unit gate green; Stellar A/B running

All six design items are in, uncommitted on `Skyline/work/20260912_osprey_fdrbench_pass_bitmask`
(`C:\proj\pwiz-work1`, 9 files, +590/-178):

* `FdrBenchInputWriter`: new `Row` struct + `PeptideInputSink` (push-based: `Add(run, row)`,
  `Commit()`; per-run mode writes as rows arrive, per-precursor folds into the O(distinct)
  best-row map). The `FdrEntry` overload is now a thin adapter over the sink, so both paths
  share one dedup/sort/format implementation. Disposing an uncommitted sink discards the temp
  (`FileSaver` semantics).
* `FirstPassFdrTask`: `StreamFirstPassFileScores` gained a `caller` prefix for its error
  messages and passes `charge` to the callback; new `WriteFdrBenchPass1FromSidecarsIfRequested`
  (projection twin of the resident emitter, same log lines, `[STAGE-WALL] fdrbench-pass1`),
  called after `WriteExperimentSidecar` and before `CompactFromSidecars`, AND on the
  compaction-gate resume path (loading the experiment map from the sidecar) so a resumed run
  writes the same file a cold one does - a gap the resident `Rehydrate` never closed.
* The `FdrBenchPass == 1` term is gone from all five gates; `ResidentPaths.FDRBENCH_PASS1` and
  its `KNOWN_UNFIXED` entry are gone (fifth shrink of the ratchet); `PROJECTION_OFF`'s doc no
  longer says it is blocked on #4507.
* Tests: `FdrBenchInputWriterTest` gained `SinkMatchesEntryOverloadByteForByte` (both modes x
  three levels, on data with a peptide-q != precursor-q entry and an exact (q, score) tie
  whose winner shows only in the protein column) and `AbandonedSinkLeavesNoFile`;
  `ResidentPoolGuardTest` swaps its exemplar to the non-Percolator trigger and pins that both
  `1` and `both` now stream; `LibraryFragmentReleaseTest` pins that both selections admit the
  release.
* `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 593/593, 0 warnings (one
  pre-existing `System.Math` qualifier became redundant with the new `using System;` and was
  fixed).
* ai side: the runner's two yellow banners (resident-pool WARNING for `1`, pass-2-only NOTE
  for `both`) removed; TDP-43 and SEA-AD READMEs rewritten to describe the defect as history
  and how to tell an old run from a fixed one by its bench file set.

**Byte-identity A/B in flight** (`ai/.tmp/sessions/20260912-e12121ed/Run-FdrBenchAB.ps1`,
runs under `D:\test\osprey-runs\_scratch\fdrbench-ab-20260912\`, exe snapshot
`_bin\fdrbench-ab-20260912`): eight cold Stellar legs - StellarLibDecoy resident vs streamed
pass 1 (per-precursor and per-run), `both` vs the single-pass files, plain Stellar resident vs
streamed - compared by SHA-256. ~4-5 min per leg.

Noticed on the way, not changed: the emitter reads each file's sidecar into a
`Dictionary<uint, FdrScoreRecord>` (`StreamFirstPassFileScores`), the same per-file
allocation shape #4657 describes for the co-assignment panel. At 3 files it is nothing; at
446 it is the same ~230 MB of LOH garbage per file. Fixing it belongs with #4657.
