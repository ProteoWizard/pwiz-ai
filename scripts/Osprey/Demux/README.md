# ZT Scan and staggered demultiplexing scripts

Research scripts for the per-channel demultiplexer (`pwiz_tools/Osprey/docs/22-demultiplexing.md`,
"The per-channel demultiplexer"; TODO-20260923_osprey_demux.md). They drive `Osprey.DemuxTool`, search
its output with DIA-NN, and hold the Python prototypes the C# was built from.

## Setting up a machine

- **Data roots:** the *data root* holds the vendor files and the *run root* everything written. Set
  them per machine with the environment variables `DEMUX_DATA_ROOT` and `DEMUX_RUN_ROOT`, read by
  `Demux-Roots.ps1` (dot-sourced by every driver) and `demux_roots.py` (imported by the Python
  scripts). Unset, they are the original machine's `D:\demux-test-data` and `D:\test\osprey-runs`.
  On SCARFELL the data root is `Z:\demux-test-data` on the network share, and the run root is local
  at `C:\temp\osprey-runs`, because a whole-run demux writes about 20 GB of mzML per run and DIA-NN
  reads it back. Finished arms move to `Z:\test\osprey-runs`, which also holds the original machine's
  outputs. The inputs kept under the run root (the library and the mzML below) are copied there
  from Z:. The files needed:

  | Path | Size | What |
  |---|---|---|
  | `<data root>\ZenoTOF8600-ZTScan\250814_ZTScan_100spd_A_{1_A1,2_D1,3_G1}.{wiff2,wiff,wiff.scan}` | about 8.7 GB each | ZT Scan runs (`.wiff2` for the tool, `.wiff` for DIA-NN; both use the `.wiff.scan`) |
  | `<data root>\Eclipse-staggered\Ecl_2022_0705_Beads_EV13_SAXN_12mz_10.raw`, `..._EV14_SAXN_12mz_17.raw` | 1.2 GB each | Orbitrap staggered runs (the `.mzML` beside them, 2.3 GB each, are msconvert's demultiplexed reference) |
  | `<data root>\Eclipse-staggered\carafe_spectral_library+decoy+entrapment.tsv` | 12.7 GB | their Carafe library |
  | `<run root>\ztscan\library\ztscan_carafe_lib.parquet` | 0.7 GB | the ZT Scan DIA-NN library (Carafe, with `_p_target` entrapment) |
  | `<run root>\ztscan\mzml\*.mzML` | about 21 GB each | msconvert's vendor-centroided mzML of the ZT Scan runs, read by the slice runners and the Python prototypes |

  The `.wiff.dia` and `.wiff.dia.quant` files beside the ZT Scan data came from a collaborator and
  are not needed.
- **The tool:** build the branch with the vendor readers,
  `pwsh -File ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot <checkout> -VendorReader -Configuration Release`,
  and copy `pwiz_tools/Osprey/Osprey.DemuxTool/bin/x64/Release/net10.0` to a snapshot folder
  (`<run root>\_bin\<tag>`), so a running job never locks the build tree. The `.wiff2`
  reader's SQLite natives are staged into its `wiff2` subfolder by the build.
- **DIA-NN 2.3.2** (`C:\DIA-NN\2.3.2`) searches mzML as installed. To read the SCIEX `.wiff`, copy the
  install to `<run root>\_bin\diann-2.3.2-sciex` and copy into it every DLL whose name contains
  `Clearcore` or `Sciex` from `pwiz-sharp\vendor-assemblies\Sciex\vendor_api\ABI` (the DIA-NN README's
  instruction, with that folder standing in for a ProteoWizard install). DIA-NN does not read `.wiff2`.
- **DIA-NN splits its command line at `--`**, so no path it is given may contain `--` (a session
  scratch path like `D--Dev` does).
- **Pin DIA-NN's settings on demultiplexed files:** `--window 6 --mass-acc 17 --mass-acc-ms1 19` for
  whole runs (the acquired A1 run's own choices). Left to choose, DIA-NN measures narrower peaks on a
  demultiplexed file and picks a smaller window and wider tolerance, which cost about 5% of the
  identifications.
- Python: numpy, pandas, pyarrow, scipy, scikit-learn, pyteomics, psims.

## Drivers (PowerShell)

`pwsh -File` cannot pass an array: give lists comma-separated.

| Script | What it does |
|---|---|
| `Run-CsSlices.ps1 -Exe <tool> -Layouts centered:7,centered:5 [-Extra '<tool flags>'] [-Suffix _x]` | The tool on the slice (sweeps 247-371, 500-700 m/z) of the three runs' mzML, one DIA-NN arm per layout: `slices\cs_<layout><suffix>` and `slices\diann\cs_<layout><suffix>`. |
| `Search-Slices.ps1 -Arm <name> -Mzml <a,b,c> [-Extra '<DIA-NN flags>'] [-ScanningSwath]` | One DIA-NN search, the same library and flags as every arm, into `slices\diann\<arm>`. |
| `Search-Wiff.ps1 -Arm <name> -Runs <stems> [-Extension .wiff] [-Extra '<DIA-NN flags>']` | DIA-NN `--scanning-swath` on the vendor `.wiff` (needs the SCIEX DLL copy above), into `ztscan\diann\<arm>`. |
| `Run-FullZtScan.ps1 -Layout centered:5` | Whole runs from `.wiff2`, one after another, then a three-run search. |
| `Run-FullC7Posmz.ps1` | Whole runs from `.wiff2` in parallel with centered:7 and `--position-mz`, then a three-run search at pinned settings. |
| `Run-SliceArm.ps1 -Exe <tool> -Name <arm> [-Flags '<tool flags>'] [-DiannExtra '<DIA-NN flags>']` | One slice arm from the mzML with its own flags and optional pinned DIA-NN settings; arms are independent, so several can run at once. The pinned slice settings are `--window 6 --mass-acc 14 --mass-acc-ms1 17`. |
| `Run-WiffSliceArm.ps1 -Exe <tool> -Name <arm> [-Flags ...] [-DiannExtra ...] [-ScanningSwath]` | The same, read from the `.wiff2` (needed for `--centroid events`; `--raw --centroid events` is the undemultiplexed control). Slow: the SDK reads profile at about an hour per replicate for the slice. |
| `Run-FullArm.ps1 -Exe <tool> -Name <arm> [-Flags ...]` | Whole runs from `.wiff2`, the three in parallel, then a three-run search at the whole-run pinned settings. About 3.5 h of demux on an idle machine, then about 2 h of search. |
| `Run-EclipseSearch.ps1 -Name <arm> -Tool <tool>` | The Eclipse runs through `--scheme staggered`, then an Osprey search. |
| `Run-TimingAB.ps1 -Old <tool> -New <tool>` | Two tool builds on the same short range, timed, outputs diffed (`Diff-Mzml.py`). |

## Analysis

| Script | What it does |
|---|---|
| `Compare-ZtScanSlices.py --rt <lo> <hi> <arm>=<report.parquet> ...` | Targets at 1% and entrapment FDP per arm and run, then replicate CV per arm and on the shared set. For whole runs, `--rt 0 30`. |
| `Region-Gains.py <base report> <arm report>` | Targets gained or lost by precursor m/z and RT. |
| `Lost-Precursors.py` | Precursors one arm finds and another misses. |
| `Compare-DemuxParity.py` | Spectrum-level agreement of two demultiplexed mzML files (keyed on scan and `demux=k`). |
| `Measure-ZtScanKernel.py <run.mzML> <out_prefix> [rt_min rt_max]` | The quadrupole transmission from MS1 probes; writes the kernel the tool reads. |
| `Measure-ZtScanEdges.py`, `Measure-ZtScanTransmission.py` | Checks of the kernel from identified precursors' fragments. |
| `ids_summary.py [--rt lo hi] <arm>=<report> ...` | Target precursors and peptides per run with their entrapment FDP, and peptides found in every run and in any run. |
| `paired_cv.py --rt <lo> <hi> <arm>=<report> ...` | Arms compared precursor by precursor (median paired change in CV, share improved), on those every arm finds in every run. A median CV alone moves with DIA-NN's choices. |
| `region_cv.py`, `abundance_cv.py <arm>=<report> ...` | Whole-run CV by RT and m/z cell, and by abundance quartile. |
| `peak_stats.py <n> <label>=<mzML> ...` | Peaks per spectrum and the share under 1 and 5 ions, over the same spectra of several slice files. |
| `ion_response.py <acquired mzML>` | The histogram of the smallest centroid intensities (the vendor centroids are quantized in steps of about 50, never under 100). |

Profile data (dump a sweep with `Osprey.DemuxTool --raw --profile --cycles c:c --mz lo:hi`):

| Script | What it measures |
|---|---|
| `grid_check.py <profile.mzML>`, `grid_compare.py <ref> <other> ...` | Whether the TOF profile is one uniform grid in sqrt(m/z), within a sweep and across sweeps and runs (it is: step 9.786595e-5). |
| `peak_shape.py <profile.mzML>` | The TOF peak's width in samples by m/z, and its average shape. |
| `centroid_check.py`, `profile_events.py <profile> <vendor>` | What vendor centroiding keeps of the profile: intensity shares, and profile peaks kept and dropped by size. |
| `single_hits.py`, `single_hit_ppm.py <profile> <vendor>` | Whether the dropped single-sample events land on real fragments (against an m/z-shifted control), and at what ppm. |
| `calibration_offset.py <profile> <vendor mzML>` | The m/z offset between profile peaks and vendor centroids, per run. |
| `joint_prototype.py <profile> <vendor mzML> <report> <library> --cycles c0 c1 --mz lo hi` | Joint demultiplexing and centroiding (A kron B) against the channel and per-sample solves, scored by placement on identified precursors. |

`kernels/A1_rt3-8.profile.tsv` is the kernel every run so far used (A1, 3-8 min, 10,168 probes);
`kernels/A1_calibrated.tsv` is the fragment-based one, by m/z range.

## Python prototypes

Each reads the msconvert mzML directly; `ztscan_real.py` holds the shared reader, channel finder and
writer. Bin centers are the spectra's reported isolation targets (393.43972 + 1.181433 b); FIRST in
`ztscan_real.py` is bin 0's lower edge, not a center.

| Script | What it tests |
|---|---|
| `demux_model.py` | The simulation behind the solver and layout choices (peptides in a realistic background, Poisson counts). |
| `ztscan_real.py` | The first real-data prototype (per-sweep, separable), writing slice mzML. |
| `anchored_prototype.py` | Library candidates' fragments extracted with the candidate's exact transmission column, against the acquired spectra and the blind demux, under the same scoring. |
| `position_test.py` | How precisely a fragment's Q1 profile gives its precursor m/z with no candidate. |
| `pairs_test.py` | Complementary b/y pairs: presence, the precursor mass they give, and the competition for a partner. |
| `kernelpos.py`, `kernelpos2.py` | Placing each channel's sources once per block (the C# `--source-positions`), with the placement check. |
