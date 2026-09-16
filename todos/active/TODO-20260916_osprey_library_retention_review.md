# Library retention, rehydration and spectrum dropping need an end-to-end review

## Branch Information
- **Branch**: `Skyline/work/20260916_osprey_library_retention_review`
- **Checkout**: `C:\proj\pwiz-work1` (C:\proj\pwiz is occupied by open PR #4660)
- **Base**: `master` (at `7993a4ef55`, which includes #4662)
- **Created**: 2026-09-16
- **Status**: In Progress
- **GitHub Issue**: [#4650](https://github.com/ProteoWizard/pwiz/issues/4650)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

End-to-end review of library retention, rehydration and spectrum dropping, which are
spread across four stages with no single owner. A 446-run CHS job shows Stage 7 spends
**11 minutes and peaks at 41.5 GB** rebuilding every run to recompute a retained set
Stage 5 already computed and already persisted to disk, then releases **nothing**.

Not a correctness problem: output is correct and the run completed. This is memory
shape and wasted work.

### Evidence (from the issue)

446-run CHS cohort, straight-through Stages 5-7, 13.5 h.
Run directory: `D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-stages567-n4646`

```
04:07:44 (Stage 5)  Released library fragments for 4924513 of 6175389 entries
                    (625620 base_ids retained for rescore + gap-fill)
12:20:11 (Stage 7)  Released library fragments for       0 of 6175389 entries
                    (625620 base_ids retained for the reported pool)
```

Stage 7's `stage7-pool` is flat at 4.69 GB, so this is **not** the survivor pool
(#4486's streamed join is working). The spike is the first `StreamFiles` pass: 446 runs
rebuilt from their reconciled parquets one at a time and dropped, purely to collect
base_ids. Managed heap climbs 6.4 -> 36.2 GB with no collection, then one GC drops it to
5.4 GB — ~86% uncollected garbage, ~31 GB allocated to produce a 2.5 MB answer that was
already on disk.

## Review scope (from the issue)

1. Who owns the retained-base_id set, and can it cross a stage boundary in-process
   instead of being recomputed?
2. Is the reported pool provably a subset of the rescore+gap-fill set, or must Stage 7
   recompute?
3. Can fragment retention end before protein FDR, so only the blib write holds spectra?
4. On `--task SecondPassFDR`, can the library read skip unneeded spectra outright (the
   previously-dropped filter), now that the cost is a 41.5 GB peak rather than a 10 s load?
5. Does anything still need a reload at Stage 7 at all, and if so can it wait until just
   before the blib write?

## Shape of the fix (design call already recorded on the issue — do not re-litigate)

Stage 5 already persists the answer: `FirstPassFdrTask.WriteRetainedBaseIdSummary`
(`FirstPassFdrTask.cs:2276` -> `:2614`) writes `out.1st-pass.retained_base_ids.bin`
(2,502,512 bytes = 625,620 base_ids x 4 + 32-byte header on this cohort).
`ScoringTaskShared.ReadRetainedBaseIds` / `ReadRetainedBaseIdsOrFail` already read it
from four call sites.

* Replace the pool walk at `SecondPassFdrTask.cs:996` with
  `ScoringTaskShared.ReadRetainedBaseIdsOrFail(ctx.Config)`.
* **Delete** the `BuildRetainedBaseIds(IEnumerable<KeyValuePair<string, List<FdrEntry>>>)`
  overload — after the change its only remaining reference is a unit test.
* **Fail loudly when the sidecar is absent; do NOT fall back to the walk.** Osprey is
  pre-release, so there is no backward-compatibility burden, and an absent sidecar
  indicates Stage 5 output corruption; the remedy is re-running at least
  `--task FirstPassFDR`. Extend `ReadRetainedBaseIdsOrFail`'s `InvalidDataException`
  message to name that remedy.
* The sidecar is readable *before* the library load, so a `--task SecondPassFDR` leg can
  hand the retained set to `RetainFragmentsFor` — the hook that today has only a
  declaration and a pass-through and **nothing assigning it** — and never allocate the
  4.92 M spectra it would immediately release.

Precedent one function away: the doc on `ReadRetainedBaseIds` already says absence "is
FATAL to the caller and must not fall back to rebuilding the union from every run's
`reconciliation.json` ... precisely the O(files) pre-pass this artifact exists to
delete". Stage 7's pool walk is that same pre-pass in different clothes.

## Tasks

- [ ] Read the four stages end-to-end and answer review questions 1-5 in the TODO
- [ ] Confirm whether the reported pool is provably a subset of the rescore+gap-fill set
- [ ] Replace the Stage 7 pool walk with `ReadRetainedBaseIdsOrFail`
- [ ] Delete the `BuildRetainedBaseIds(IEnumerable<KeyValuePair<...>>)` overload
- [ ] Extend the `InvalidDataException` message with the re-run remedy
- [ ] Wire `RetainFragmentsFor` on the `--task SecondPassFDR` leg so the library never
      allocates droppable spectra
- [ ] Build + inspection + tests (`Build-Osprey.ps1 -RunInspection -RunTests`)
- [ ] `regression.ps1` green
- [ ] `/code-review max` before opening the PR

## Regression Test

**Built-in oracle** (from the issue): any correct version must still log
`625620 base_ids` and `Released ... 0 of 6175389` on the 446-file bed, so it is checkable
at 3 files in `regression.ps1` and at 446 in the run log without writing a new comparison.

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test | regression.ps1 mode
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-16 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1` off master
`7993a4ef55` (includes #4662, merged 2026-09-16 02:30 UTC). `C:\proj\pwiz` was left
alone because PR #4660 is still open there.
