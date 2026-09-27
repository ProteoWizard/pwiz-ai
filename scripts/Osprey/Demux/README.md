# ZT Scan demultiplexing scripts

These scripts measure the SCIEX ZT Scan transmission and compare DIA-NN searches of demultiplexed
output. They support `pwiz_tools/Osprey/docs/22-demultiplexing.md` ("The per-channel
demultiplexer") and TODO-20260923_osprey_demux.md. They need Python with numpy, pandas, pyarrow
and pyteomics.

| Script | What it does |
|---|---|
| `Measure-ZtScanKernel.py <run.mzML> <out_prefix> [rt_min rt_max]` | Measures the quadrupole transmission from the data. The probes are intense MS1 peaks, whose own m/z survives unfragmented in every encoded bin that transmits them. Writes `<out_prefix>.profile.tsv`, the kernel `Osprey.DemuxTool --kernel` reads. |
| `Measure-ZtScanEdges.py <raw.mzML> <report.parquet> <library.parquet> [n] [frac]` | An independent check from DIA-NN identifications: where each precursor's fragments start and stop along the sweep, relative to the precursor m/z. |
| `Compare-ZtScanSlices.py --rt <lo> <hi> <arm>=<report.parquet> ...` | Per arm and run: target precursors at 1% and the entrapment FDP. Then the replicate CV of `Precursor.Quantity`, per arm and on the set every arm shares. For a whole run, pass `--rt 0 30`. |
| `Region-Gains.py <base report.parquet> <arm report.parquet>` | Target precursors gained or lost, by precursor m/z and retention time. |

The kernel used so far is `D:\test\osprey-runs\ztscan\kernel\A1_rt3-8.profile.tsv`, measured on
the A1 run at 3-8 min, from an mzML of the centroided spectra. Entrapment ids carry `_p_target`
in `Protein.Ids`, as in the Carafe library these searches used.
