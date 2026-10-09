# PR draft (not opened) - alternative to #4710

**Title:** `osprey: Added --demux auto, demultiplexing through ProteoWizard's own demultiplexer`
**Label:** `osprey`  **Base:** `master`  **Branch:** `Skyline/work/20261008_osprey_pwiz_demux`

---

## Summary

An alternative to #4710 that reaches the same end with one demultiplexer: ProteoWizard's own
(`SpectrumListDemux`, the C# port of msconvert's `demultiplex` filter), applied while the vendor file is
read, so a staggered-window run goes straight from the vendor file to a demultiplexed
`.demux.spectra.bin` with no mzML. The same model as `msconvert --filter demultiplex` followed by an
mzML search, without the mzML, and the mechanism Skyline can use next.

**ProteoWizard (`pwiz/analysis`, `ProteowizardWrapper`):**
* Fixed the C# NNLS dropping a column that reached the iteration limit (C++ keeps its last feasible
  solution): 26 peaks of up to 5e7 were missing from 23 of 408 spectra on an Eclipse slice; C# and C++
  msconvert now agree peak for peak
* Added `solveThreads=N` to the demultiplex filter: blocks solved ahead in parallel batches, the next
  batch read while this one is solved; output byte-identical at any thread count
* Added `SpectrumListDemux.DetectScheme`, and a `demultiplex` option on `MsDataFileImpl` applied only to
  a multiplexed run; ordinary DIA with margin overlaps is not multiplexed

**Osprey:**
* Added `--demux off|auto`; ported from #4710 (Mike): the option, the `.demux.spectra.bin` header and
  descriptor, validity key, start-up check, and the all-windows fix in `SpectraWindowIndex`
* `--demux off` warns on a multiplexed run instead of refusing it
* About 560 added lines of Osprey product code and 520 in pwiz, in place of #4710's `Osprey.Demux`
  and `Osprey.DemuxTool` (~10k lines)

## Results

Six Orbitrap Eclipse staggered runs (12 Th windows, 2-fold), one Carafe library with 1:1 entrapment,
the same Osprey flags for every arm, experiment level at q <= 0.01:

| Demultiplexing | Precursors | Entrapment FDP | Peptides |
|---|---|---|---|
| ProteoWizard, this PR | 38,088 | 0.47% | 33,464 |
| #4710 default (weighted per-channel) | 36,453 | 0.44% | 32,036 |
| #4710 msconvert-style engine | 35,664 | 0.41% | 31,458 |

Higher in each of the six runs. Vendor file to cache on EV13 (1.24 GB .raw, 32 threads, quiet machine):
40-41 s, against 44.0 s for #4710's default engine, 24.0 s for its msconvert-style engine, and 13.7 s for
a plain read (no demultiplexing).

## Test plan

- [x] pwiz SpectrumListDemux tests (detection, thread-count determinism, NNLS iteration limit, C++ gold)
- [x] Osprey DemuxTest - Eclipse slice fixture from #4710: detection, demultiplexed read equal to
      SpectrumListDemux and to C++ msconvert peak by peak, every cache path
- [x] Build-Osprey.ps1 -RunTests -RunInspection - 657 tests pass, 0 inspection warnings
- [x] regression-parallel.ps1 -Dataset All - 48 PASS / 0 FAIL
- [x] /code-review medium - findings fixed or triaged in the TODO
- [x] Six-run Eclipse searches against #4710's engines (above)

See [TODO-20261008_osprey_pwiz_demux.md](https://github.com/ProteoWizard/pwiz-ai/blob/master/todos/active/TODO-20261008_osprey_pwiz_demux.md) in pwiz-ai/todos

Co-Authored-By: Claude <noreply@anthropic.com>
