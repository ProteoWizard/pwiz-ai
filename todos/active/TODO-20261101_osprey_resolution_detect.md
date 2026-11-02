# TODO-20261101_osprey_resolution_detect.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_resolution_detect` (worktree `D:\Dev\pwiz-resolution`)
- **Base**: `master` (cut at 728ff3a131)
- **Created**: 2026-11-01
- **Status**: In Progress (overnight autonomous session)
- **GitHub Issue**: [#4893](https://github.com/ProteoWizard/pwiz/issues/4893)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Detect `--resolution` (unit vs HRAM) from the data so a user need not know their instrument
class: an ion trap (Stellar) must search as `unit`, Orbitrap / Astral / TOF as `hram`. The explicit
flag stays and overrides detection. The resolved mode must reach the search settings hash exactly
as the explicit value does.

## Design (as built)

- **Statistic**: the 1st percentile (`SPACING_QUANTILE = 0.01`) of the m/z gaps between adjacent
  centroids, pooled over the first MS2 spectra in acquisition order until 10,000 gaps or 1,000
  spectra. HRAM when below `HRAM_MAX_SPACING = 0.2` m/z, else unit. Needs >= 100 gaps to decide.
- **Measured** (full regression data): Stellar 0.444-0.449 m/z (48-49 spectra), Astral
  0.029-0.031 m/z (91-131 spectra). Margin about 2.2x on the unit side, 6x on the HRAM side.
- **Cost**: 10-30 ms from a `.spectra.bin`, 60-210 ms from a multi-GB mzML (read with
  decode threads = 1; the search's 8-thread read-ahead made it ~1 s).
- **Default**: `--resolution auto` (restored value), the default. `hram` / `unit` override.
- **One route**: `OspreyConfig.ApplyResolutionMode` sets the mode and the unit tolerances for both
  the explicit and the detected route, so `SearchIdentity` cannot differ between them.
- **Spectra cache**: not keyed by resolution (settings-independent by design, see
  `OspreyConfig.CacheDir`); the cache holds decoded spectra, so it is correct to share it and it
  is the preferred detection source.
- **HPC**: nodes with spectra (cache, else source) measure; FDR nodes handed only scores files read
  the mode whose `SearchParameterHash` matches the scores file's `osprey.search_hash`.
- **Mixed inputs**: decided from the first input; every other input is measured and a warning
  names each that measures differently. All scored at the first's mode.
- **Undecidable** (too few peaks, or no spectra and no scores file): HRAM, the previous default,
  with a warning.

## Tasks

- [x] Read issue, ResolutionStrategy, BinConfig, ToConfig, SearchIdentity, SpectraCache
- [x] Measure the statistic on Stellar / Astral caches (python probe) and pick the threshold
- [x] `ResolutionDetector` (Osprey.IO), `SpectraCache.VisitMs2Spectra`, `SpectrumFileReader.VisitMs2Spectra`
- [x] `OspreyConfig.ApplyResolutionMode`, `--resolution auto` default, Program logging + `[PATH] resolution`
- [x] `SubsetPipelineTest.TestSubsetResolutionDetection`
- [x] Docs: help text, docs/20-command-line.md, resolution rows of docs 02/03/04/06/14/17, CommandLine.html
- [x] regression.ps1 `-DetectResolution` switch
- [x] Gate: build + tests + inspection (647/647, zero inspection warnings)
- [ ] Regression Stellar + Astral (explicit) vs golden; then detected
- [ ] /code-review medium, triage
- [ ] PR

## Notes for Brendan

- Overlap check: `TODO-20261101_osprey_resume_validity` (D:\Dev\pwiz-resume) also works on validity
  keys. This branch does not change the `SearchParameterHash` recipe, only how `ResolutionMode`
  is set before it is computed, so a conflict is not expected.

## Progress Log

### 2026-11-01
- Implemented detection; `TestSubsetResolutionDetection` passes (8 s).
- First gate: `TestCommandLineErrors` failed - a `--task ModelDiagnostics` command line whose
  mzML is a placeholder crashed in detection (XmlException) before its designed error. Fixed:
  an unreadable source measures nothing (the task that reads it reports why). Second gate green.
- Committed 587087ceca. Running regression Stellar (explicit) next.
