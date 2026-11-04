# TODO-20261103_osprey_stage7_fragments.md

## Branch Information
- **Branch**: (none yet - measurement and design only; `Skyline/work/20261103_osprey_stage7_fragments` if implemented)
- **Base**: `master` (049d045e98)
- **Created**: 2026-11-03
- **Status**: In Progress - 82-file SEA-AD measurement running
- **GitHub Issue**: [#4577](https://github.com/ProteoWizard/pwiz/issues/4577)
- **Module**: `osprey`
- **PR**: (none - no PR until the measurement is read)

## Objective

Re-measure the library-fragment retained set through Stage 7 on the 82-file SEA-AD cohort at master
049d045e98, then design how the retained set can narrow at the Stage 6 -> 7 boundary (#4577). Implement
only if the structure is clear and output-locked by the golden.

## Measurement

- Exe: snapshot `D:\test\osprey-runs\_bin\agentD-049d045e98` (master 049d045e98, Release).
- Command: `Run-SeaAd.ps1 -Exe <snapshot>\Osprey.exe -LogMemory -LinkFrom <2026-10-15 a1a2 run> -Tag agentD4577 -Fresh`
  (libdecoy r=1.0, protein-compact, `--timestamp --memstamp`, OSPREY_LOG_MEMORY=1, threads 30, mdiag on).
  `Run-SeaAd.ps1` had no `-LogMemory` switch although the module supports it and `Run-Chs.ps1` exposes it;
  added it (the release lines are `LogTag.Mem` and print only with OSPREY_LOG_MEMORY=1).
- The -LinkFrom source's Stage 1-4 caches were NOT valid for this build: Osprey re-scored all 82 files
  (so this is a from-scratch Stage 4 as well; the link saved nothing). Other agents' builds and gates ran
  on the box at the same time, so wall times are not comparable with earlier runs; memory is.
- Run dir: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactagentD4577-20261103_131639`
  (`run.log` there).

(results below when the run completes)

## Design notes (code reading at 049d045e98)

- Stage 7's release (`SecondPassFdrTask.ReleaseUnscorableLibraryFragments`, SecondPassFdrTask.cs:987) no
  longer folds the reported pool; it reads the analysis-wide first-pass retained summary
  (`ScoringTaskShared.ReadRetainedBaseIdsOrFail`). On a straight-through run that is the same set Stage 5
  applied to the same library instance, so it frees zero by construction; it earns its place only on the
  HPC `--task SecondPassFDR` leg, where it is the only release.
- The only post-Stage-6 reader of `LibraryEntry.Fragments` is the blib write:
  `BlibOutputWriter.PrepareSpectra` -> `BlibSpectrum.FromLibraryEntry` (BlibSpectrum.cs:80) over
  `bestByPrecursor`, built by `SecondPassFdrTask.CollectPassingEntries`, which skips `entry.IsDecoy` and
  keeps only passing (modseq, charge). Protein FDR, reports, FDRBench/entrapment pairing and pass-2
  diagnostics read identity fields or precursor m/z only. Every other `.Fragments` reader is Stage 4/6
  scoring, calibration, training evidence or per-file diagnostics.
- So at the 6 -> 7 boundary the set Stage 7 needs is: targets (not `IsDecoy`) whose base_id is in the
  retained set; and after Stage 7's FDR, only the `bestByPrecursor` EntryIds (51-59K spectra).
- Size of the lever (estimate, to be checked against the run's post-GC probes): `LibraryFragment` is a
  struct of double Mz + float intensity + annotation, ~14.6 fragments per entry (90.3M peaks / 6.18M
  entries), so ~0.4 KB per entry: ~0.3 GB for ~749K paired decoys, ~0.6 GB for all ~1.5M retained
  entries, against a Stage 7 p10 floor measured at 28.7 GB in 2026-08.

## Resume here (2026-11-03 14:16, agent D handed back before the run finished)

The run is still going in the run dir above. When `run.log` shows `DONE ... exit=0`:
1. `grep -a "MEM library-fragments\|library-fragments-released\|MEM stage7-fragments-released\|\[TASK\]" run.log`
   gives the 5->6 line (scope rescore-gap-fill) and the 6->7 line (scope retained-summary). The code predicts
   the second frees 0: on straight-through runs it reads the same summary Stage 5 applied.
2. `python C:\proj\ai\scripts\perfviz.py run.log --files 82` gives the SecondPassFDR peak and p10 floor.
3. Compare the ~0.4 GB decoy / ~0.7 GB all-retained fragment estimate with that floor. If the lever is about
   1-3% of the floor, record that #4577 is low value and point at #4486, then post a status comment on #4577.
   If it is larger, implement the entry-level predicate `!IsDecoy && retained(base)` at SecondPassFdrTask.cs:1014
   (also the load-time skip on --task SecondPassFDR) and update SubsetPipelineTest.AssertFragmentRelease (asserts
   Stage 7 released 0) and regression.ps1's Test-LibraryFragmentRelease mode-6 checks. Gate: Stellar + StellarLibDecoy.

## Measurement read (2026-11-03 18:55, parent night session)

Run finished 18:50, exit 0, 5:33 wall. Release lines: 5->6 freed 4,667,143 of 6,175,389 (754,359
base_ids retained); 6->7 freed 0 (same 754,359 retained). perfviz managed p10/p50/peak, private peak:
PerFileScoring 7.6/11.6/25.0 (29.6); FirstPassFDR 7.5/13.8/29.7 (38.9); PerFileRescoring 5.8/7.8/14.2
(18.0); SecondPassFDR 4.4/5.7/8.6 (13.6). Managed heap entering Stage 7 post-GC 3.53 GB; working set
after the empty release 10.66 GB.

Decision: DEFER. The 0.4-0.7 GB lever is 10-15% of the Stage 7 floor but 2% of the run peak, which is
Stage 5 (38.9 GB private). Stage 7 no longer sets the machine requirement. Worth doing only for a
standalone `--task SecondPassFDR` node. Status comment posted on #4577; no branch, no PR.
