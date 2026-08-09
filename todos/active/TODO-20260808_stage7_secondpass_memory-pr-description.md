# PR description draft - #4486 Stage 7 memory and reporting

**READY, pending `/code-review max`** (user-invoked; Claude cannot run it). Every
`TODO(stage7-work)` marker is filled and `regression.ps1 -Dataset All` is 44/44 green on the
branch as of 2026-08-09.

Title: `osprey: Bounded and instrumented the Stage 7 join`
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

* Made the pass-2 competition emit per file instead of retaining per-observation results.
  Its roll-up was already bounded - per-base_id bests, a per-entry_id best-run-q floor - but
  it returned three whole-run `(file, entry_id)`-keyed dictionaries and built three more to
  feed them. Six such structures at ~200 B/observation x 86.6 M observations account for the
  measured +0.214 GB/file with no unexplained remainder. Run q is now written onto each
  file's already-resident entries as that file finishes; experiment q and PEP are derived
  per entry from O(distinct) state (`StreamedCompetitionState`), so neither is materialized
  at all - `survivorExpQ` was provably `max(baseIdExpQ[bid], minRunQ[eid])`, which has no
  fileKey term
* Fused the frozen-model feature scoring into that same streamed loop. It was a separate
  whole-run pass that loaded every file's reconciled PIN features and stashed all of their
  scores (~3.8 GB at 82 files); it is per file by nature, so this bounds it AND removes one
  full pass over the reconciled parquets
* Reported progress through the two silent per-file loops after the competition - the
  2nd-pass sidecar write (~4.8 GB across 82 files) and the reload that follows it. They were
  the only reporting gap over 30 s left in the stage
* Asserted the distinct-file-key invariant the per-file emit depends on. Two `--input-scores`
  paths in different directories can share a stem (`RescoreHydration.PreCompactionTallies` is
  index-keyed for exactly that reason) and every per-file structure here is name-keyed; the
  same guard already sits at the head of `PercolatorScorer.ScoreProjectionAndComputeFdrInPlace`

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

## Measured - after, 82-file `--task SecondPassFDR` (the fix)

Stage 7 alone on the `stage5to7-82f-4486` rig, 24:47, exit 0. Post-GC probes:

| probe | managed |
|---|---|
| `stage7-inherited` | 25.97 GB |
| `stage7-fragments-released` | 23.74 GB |
| `stage7-pass2-scored` | **23.73 GB** |
| `stage7-protein-fdr` | 23.73 GB |
| `stage7-blib-written` | 23.73 GB |

The competition enters and leaves at 23.7 GB, against the baseline's monotonic
41.0 -> 56.8 GB. **Deliberately corroborated by a second instrument**, because boundary
probes alone are exactly what produced this issue's retracted claim: the in-phase
`--memstamp` series across the competition reads
`4% 41.6 | 12% 33.0 | 19% 37.1 | 26% 42.2 | 34% 42.7 | 41% 50.6 | 48% 24.1 | 56% 31.8 |
63% 33.6 | 70% 37.2 | 78% 42.6 | 85% 43.2 | 92% 46.7 | 100% 42.0` GB - a sawtooth with
floors at 33.0 / 24.1 / 31.8 / 33.6, flat rather than rising. Both instruments agree.

Output identical to the recorded baseline: 37,078 library spectra from 3,037,028 passing
entries. Stage 7 wall 1486.8 s (baseline 1588.0 s).

Reporting, same rig with the reporters in: `gaps >= 30s : 0 OK` (max 27 s), where the
pre-fix run had one 38 s gap immediately after `[STAGE-WALL] second-pass-fdr`.

**Scope, stated plainly**: this bounds the pass-2 COMPETITION. The Stage 6 -> 7 whole-run
survivor buffer this issue's title names is untouched and still grows ~0.196 GB/file (load
phase, measured +195 MB/file here against the documented 0.197). That remains the 500-file
wall and is not claimed as fixed.

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
- [x] `Build-Osprey.ps1 -RunTests -RunInspection` - 577 tests, 0 errors, 0 warnings
- [x] `ResidentPoolGuardTest.TestResidentPoolGuardError` - verified RED against master's
      predicate and GREEN with the fix, not merely asserted
- [x] Memory A/B on the HPC arm, post-GC probes rather than `--memstamp`
- [x] 82-file Stage-7-only run on the `stage5to7-82f-4486` rig showing the competition flat
      in file count, corroborated by the in-phase `--memstamp` series (post-GC boundary
      probes alone cannot support this claim - that is how the retracted one was made)
- [x] Reporting verified empirically after the change: `gaps >= 30s : 0` via
      `ai/scripts/perfviz.py`, not asserted from the diff
- [x] `regression.ps1 -Dataset All` re-run after the competition change - 44/44, exit 0

One defect found and fixed mid-branch that byte-parity structurally could not catch:
dropping `ExpectReconciledInput` from `NeedsResidentPool` made the LEAN counts-only load
reachable on a merge whose inputs lack a `.reconciliation.json` (one partially copied file
is enough). That path adds EMPTY per-file entry lists, so Stage 7 would have written a
near-empty `.blib` with no error and exit 0. The regression rig always has complete
sidecars, so mode 3 stays green either way. `CanUseLeanProjection` now states the exclusion
on its own reasoning - the same class of mistake as the `!NoJoin` proxy this PR removes.

See ai/todos/active/TODO-20260808_stage7_secondpass_memory.md

Co-Authored-By: Claude <noreply@anthropic.com>
