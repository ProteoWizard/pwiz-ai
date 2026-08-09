# PR description draft - #4486 Stage 7 memory and reporting

**PROVISIONAL - do not open the PR from this yet.** Per Brendan (2026-08-08) this is ONE PR
covering Stage 7 memory AND reporting, so the sections marked `TODO(stage7-work)` must be
filled in once the pass-2 competition work lands. See the parent TODO for the ordered plan.

Title: `osprey: Streamed the --task SecondPassFDR reconciled-input load`
(retitle once the Stage 7 memory work is in - something like
`osprey: Bounded and instrumented the Stage 7 join`)
Labels: `osprey`, `performance`

---

## Summary

* Added five post-GC memory probes to Stage 7. It had ONE pre-GC probe and zero
  `LogManagedHeapAfterGcIfEnabled` calls (Stage 5 has 6, Stage 6 has 5), so
  `OSPREY_LOG_MEMORY=1` could not produce a Stage 7 live number no matter who set it -
  which is why #4486 went three months on `--memstamp` figures alone
* Streamed the `--task SecondPassFDR` reconciled-input load. It reloaded every input's
  full PRE-compaction stub list before compacting - 2.07 GB/file, ~194 GB projected at
  82 files - while the bounded `HydrateCompactedStreaming` it needed already served
  every other reconciled-bundle path
* Root cause was a proxy: `PreCompactionPoolReason` tested `!NoJoin` as a stand-in for
  "will `FirstPassFdrTask` run here", which is false for exactly this task
  (`IsIncluded` requires `!ExpectReconciledInput`). It now asks `IsIncludedFor`, so the
  membership rule has one definition and cannot drift again
* Retired the `hpc-merge` token: nothing on that node reads the pre-compaction pool -
  the frozen `transfer-compete` / `protein-compact` competition streams off each file's
  `.1st-pass.fdr_scores.bin` scalars, and the resident load pulled PIN features that
  `HydrateRescoreBundleIfPresent` then nulls unread

TODO(stage7-work): bullets for the pass-2 competition re-keying and the progress reporters.

## Measured - HPC join node

Same 16-file SEA-AD Astral rig, same Stage 1-5 artifacts, two pinned binaries differing
only in the streaming change.

| files | peak private | pre-GC managed at S7 entry | live (post-GC) | spectra |
|---|---|---|---|---|
| 4 | 18.80 -> 15.96 GB | 15.05 -> 6.90 | 5.19 / 5.19 | 52,084 both |
| 8 | 29.25 -> 19.90 GB | 9.87 -> 8.10 | 5.94 / 5.96 | 54,432 both |
| 16 | 45.73 -> 25.88 GB | 39.64 -> 9.79 | 7.53 / 7.56 | 59,102 both |

Peak-private slope **2.06 -> 0.75 GB/file** (8->16). Peak -43% and pre-GC managed -75% at
16 files; Stage 7 **32% faster** (7:19 -> 5:00) because it stops reading and discarding
~52x the surviving rows. Live set and output identical at every point.

## Measured - straight-through, 82 files

Stages 5-7 in one process (4:26:08, exit 0), current defaults, Stage 1-4 reused.

* The per-file stages are bounded: Stage 6 held a ~4 GB managed floor / ~17 GB private for
  2 h 47 m, ending at `[MEM reconciliation-resident] 2.90 GB (files=82,
  file_parallelism=1)` - against #4526's 28.17 GB for the resident handoff.
* The JOIN stages are not. Stage 5's compaction + planning sustains ~29 GB holding
  86.18 M survivors, and Stage 7's pass-2 competition climbs monotonically
  **+0.214 GB/file** to the run-wide peak (56.8 GB managed / 63.7 GB private;
  `peak_paged` 63.92 GB, i.e. commit at the 64 GB line at 82 files).

TODO(stage7-work): the after numbers for the same run once the competition is re-keyed.

**Earlier drafts of this description claimed "Stage 7's OWN cost is 0.001 GB/file ... there
was never a lever inside SecondPassFdrTask". That was WRONG** and is corrected on the issue
(comment 5229971150). It came from post-GC probes firing at substep BOUNDARIES; the
competition allocates and releases between them, so the phase looked free. Do not
reintroduce that claim.

See #4486

## Test plan

- [x] `regression.ps1 -Dataset All` - byte-identical on every mode and dataset, 44/44,
      including all four mode 3 (HPC 4-task chain) legs, which run `--task SecondPassFDR`
      and are the direct oracle for the load change
- [x] `Build-Osprey.ps1 -RunTests -RunInspection` - 576 tests, 0 errors, 0 warnings
- [x] `ResidentPoolGuardTest.TestResidentPoolGuardError` - verified RED against master's
      predicate and GREEN with the fix, not merely asserted
- [x] Memory A/B on the HPC arm, post-GC probes rather than `--memstamp`
- [ ] TODO(stage7-work): 82-file Stage-7-only A/B on the `stage5to7-82f-4486` rig (~26 min
      per arm), showing the competition flat in file count
- [ ] TODO(stage7-work): re-run `regression.ps1 -Dataset All` after the competition change

One defect found and fixed mid-branch that byte-parity structurally could not catch:
dropping `ExpectReconciledInput` from `NeedsResidentPool` made the LEAN counts-only load
reachable on a merge whose inputs lack a `.reconciliation.json` (one partially copied file
is enough). That path adds EMPTY per-file entry lists, so Stage 7 would have written a
near-empty `.blib` with no error and exit 0. The regression rig always has complete
sidecars, so mode 3 stays green either way. `CanUseLeanProjection` now states the exclusion
on its own reasoning - the same class of mistake as the `!NoJoin` proxy this PR removes.

See ai/todos/active/TODO-20260808_stage7_secondpass_memory.md

Co-Authored-By: Claude <noreply@anthropic.com>
