# Running the protein-best / SEA-AD tests on another machine

Companion to TODO-20261030_osprey_scoring_library.md (written 2026-11-08 on MACS2). For a session on an i9 (or any
second machine) picking up the `--protein-best` branch and the per-file scoring performance work.

## Code

- pwiz branch `Skyline/work/20261108_osprey_protein_best` (pushed, no PR yet), on top of #4950
  (`Skyline/work/20261028_osprey_diann_fdr_gap`, c0c2bcd43c). Tip 1cbe1463bd.
- Build: `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot <checkout>` (Release, net10.0). Gate:
  `-Configuration Debug -RunTests -RunInspection` (683/683, 0 inspection at the tip).
- Copy the Release output folder to a snapshot dir and run from there (MACS2 used `_bin\n1108-pbfix`), so a rebuild
  cannot change a run in flight. The version string must be clean (built after the commit).

## Data

- **mzML** (82 SEA-AD Astral files) and their `.spectra.bin`: see `ai/scripts/Osprey/SEA-AD/README.md` (lab share
  `\\gs-ddn2\maccoss-vol1\...\SEA-AD\Astral-DIA\mzml`, or re-convert the .raw from Panorama). Copy to a local SSD.
- **Library**: download the r=1.0 entrapment drop `target+decoy+entrapment-20260817` (README, "Entrapment
  libraries", Panorama), then derive the size-weighted split; only the pairing manifest and `assign.tsv` change, the
  12.4 GB TSV is hard-linked:

```
python ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py --library-dir <...>\target+decoy+entrapment-20260817 `
    --out-dir <...>\target+decoy+entrapment-20260817-split-sized --in-targets 0.5 --size-weighted
```

  Verified on MACS2: both files byte-identical to the library every run below used. The split is 1:1 entrapment to
  targets (r = 1.0), half on target proteins, half on their own: 6.18M precursors per file with decoys, about 1.7x
  the work of a 10% + 10% split.

## The experiment settings every SEA-AD arm used

Environment (cleared and set per arm; `Run-SeaAd.ps1` strips some levers, so set these inside the arm loop):

```
OSPREY_XIC_FRAGMENTS=12  OSPREY_LOESS_BANDWIDTH=0.10  OSPREY_MIN_RT_TOLERANCE=1.0  OSPREY_TC_HALF_WINDOW=0.40
OSPREY_CORR_FRAGMENT_TOLERANCE=7  OSPREY_REF_XIC=corr  OSPREY_LOCAL_RT_TOLERANCE=15
OSPREY_FDR_SEED=1  OSPREY_FEATURE_MASK=none  OSPREY_RECON_REFIT=off
GBDT: OSPREY_FDR_MODEL=gbdt OSPREY_GBT_OOF=1      SVM: OSPREY_FDR_MODEL=svm
```

`--protein-best` is on by default; `Run-SeaAd.ps1 -ProteinBest off` turns it off (empty passes nothing, for older
builds). With it off and GBDT, the MACS2 "off" arms also set `OSPREY_GBT_PREFILTER_SIZE=200000` (two-round, no column).

## Reproduction check (do this first)

Osprey is bit-identical across machines and thread counts, so the matched 3-file arms must reproduce MACS2's
FDRBench byte for byte:

```
pwsh -File ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -Threads <n> -NumFiles 3 `
    -IncludePattern 'A01_005|A06_010|A10_014' -Pass2Mode transfer -FdrBenchPass both -Tag pb-gbdt `
    -DataDir <mzml> -LibraryDir <split-sized> -RunsRoot <runs> -Exe <snapshot>\Osprey.exe
```

Later arms on the same files: add `-LinkFrom <first run dir>` (hard links; scoring is skipped as "outputs valid").
Read them with:

```
python ai/scripts/Osprey/SEA-AD/tools/split_calibration.py --lib-dir <split-sized> --osprey <run dir> ...
```

Expected (precursors at reported q 1% with true on-target FDP, and found at true FDP 1%):

| arm | q 1% kept (FDP) | at FDP 1% |
|---|---|---|
| GBDT, protein-best on, pass 2 | 73,978 (0.91%) | 74,643 |
| GBDT, protein-best off, pass 2 | 66,937 (0.63%) | 69,837 |
| SVM, protein-best on, pass 2 | 64,415 (0.85%) | 65,722 |
| DIA-NN 2.7.0 NN (same peptides, its own split draw) | 75,125 (0.59%) | 78,668 |
| DIA-NN --no-nn | 56,662 (0.42%) | 62,472 |

DIA-NN rows need its own library and assignment (`--diann <report.parquet> --diann-assign <A2-sized.assign.tsv>
--diann-n-target 1129657`); a Carafe TSV that still holds Osprey's decoys is searched by DIA-NN as targets.

## Performance: where to start

- One file, `--task PerFileScoring`, A10_014, 72 threads, nothing else on the machine: 456 s total; coelution
  scoring 316 s (4.40M candidates, 13,945 cand/s), library load 53 s, parquet write 57 s, RT calibration 28 s.
  Per-window 30 / 113 / 226 s (min / median / max; slowest m/z 437.9, 48,339 candidates) over 167 windows.
- The window loop (`ScoringPipeline.cs` ~277) is one `Parallel.For` over windows, nothing parallel inside a window,
  so a file cannot finish faster than its largest window, and threads idle in the tail. Spectra stream per window
  (`StreamingWindowSpectraProvider`), so memory is about `--threads` windows' spectra.
- MACS2 runs used no parallel files (`parallelfiles=0`). Do not use parallel files yet: narrow the per-file cost first.
- Profile: `ai/scripts/Osprey/Profile-Osprey.ps1 -OspreyArgs <args> -ScopeToMainSearch -Exe <snapshot exe> -TopN 60
  -OutputPath <x>.dtp` (sampling; the build carries JetBrains.Profiler.Api). On MACS2 the dotTrace CLI global tool is
  2026.2.1 but the installed Reporter.exe is 2022.1, which cannot read the snapshot ("Reporter.exe did not generate
  report"); use a Reporter from the same version (NuGet `JetBrains.dotTrace.CommandLineTools.windows-x64`) or open
  the .dtp in a current dotTrace GUI. MACS2's snapshot: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-timing\
  profile-full.dtp` (+ .0000-.0003), A10_014, full settings, 64 threads.
- Single-setting ablations not yet measured (each drops one switch from the set above, same file and task): XIC 12
  -> 6, no CORR_FRAGMENT_TOLERANCE, no REF_XIC, no LOCAL_RT_TOLERANCE, all off, and the 26.1.1.301 build, which
  separates code growth from settings growth.

## Still to run (good use of a second machine)

- Regression at the tip for StellarLibDecoy and Astral (`pwiz_tools/Osprey/regression-parallel.ps1 -Dataset
  StellarLibDecoy,Astral`); Stellar and StellarGenDecoyEntrap passed on MACS2.
- The 82-file arms on links to a scored baseline (`-Task FirstPassFDR -LinkFrom <82-file run>` for first-pass
  variants, ~30 min each; full pass-2 arms ~4-6 h): GBDT protein-best + transfer, transfer only, SVM on/off. The
  MACS2 82-file baseline (GBDT, protein-best off, protein-compact) reads q 1% -> FDP 1.29% in pass 2.
- DIA-NN 82 files on the same split peptides (MACS2 timed DIA-NN only on the unsplit library: 5.9 min/file).

## Machine-sharing check

Before timing anything: `quser` and `tasklist /v /fi "imagename eq Osprey.exe"` (the session column names the
owner; another user's processes cannot be stopped). On MACS2 the night of 2026-11-08 another user's two Osprey jobs
used ~26 cores from 19:42, so that night's wall times are inflated.
