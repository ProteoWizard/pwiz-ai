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
