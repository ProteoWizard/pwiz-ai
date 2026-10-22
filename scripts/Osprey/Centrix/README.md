# Centrix golden and parity scripts

Tools for keeping Osprey's C# port of Centrix (`pwiz_tools/Osprey/Osprey.Centroid`) faithful to Rust Centrix
(maccoss/centrix). The golden they produce is pinned by `CentrixTest.TestCentrixRustGolden`; how it was made is in
`pwiz_tools/Osprey/Osprey.Test/Data/Centrix/README.md`.

| Script | What it does |
|---|---|
| `slice_mzml.py <source.mzML> <out.mzML> <i,j,...>` | Copies chosen spectra of an mzML byte for byte into a small non-indexed mzML (indices renumbered) |
| `centrix_golden_tsv.py <out.tsv> <input.mzML>=<rust.mzML> ...` | Writes Rust Centrix's centroids as the golden TSV, keyed by input file, MS level and ordinal within the level |
| `fwhm_peaks.py <profile.mzML> [max spectra]` | Isolated-peak widths (FWHM) per MS level, the measurement `CentrixCalibration` makes, as a distribution (quantiles) for checking it |
| `centrix_parity.py <rust.mzML> <csharp.mzML>` | Compares two centroided mzMLs spectrum by spectrum: counts, m/z and intensity differences |

`Osprey.DemuxTool --scheme none --centroid centrix --centrix-sigma S2 --centrix-sigma-ms1 S1` writes the C# side of
a parity comparison. Rust Centrix: build it in WSL (`cargo build --release`; needs `libopenblas-dev`), then
`centrix run -i <in.mzML> -o <dir> --sigma-ms1 S1 --sigma-ms2 S2`, which writes `<dir>/<stem>.centrix.mzML`.
All three scripts need `pyteomics` and `numpy`.
