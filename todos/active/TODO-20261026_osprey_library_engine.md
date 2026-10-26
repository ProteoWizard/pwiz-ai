# TODO-20261026_osprey_library_engine.md

## Branch Information
- **Branch**: `Skyline/work/20261026_osprey_library_engine`, cut from the head of
  `Skyline/work/20261024_osprey_search_tuning` (PR #4914, PR 2) at f7731c2c1a. Stacked: once #4914
  squash-merges, the update is `git merge origin/master`, never a rebase (version-control guide, the
  squash-merged-parent case)
- **Base**: PR #4914's branch, then `master`
- **Created**: 2026-10-26
- **Status**: Design walk-through with Brendan (interactive session of 2026-10-26); no code yet
- **GitHub Issue**: (none)
- **Module**: `skyline` (with an Osprey / CarafeSharp change for the precursor-table input)
- **PR**: (pending)
- **Checkout**: `C:\proj\pwiz`
- **Continues**: `TODO-20261024_osprey_search_tuning.md` (PR 2), whose "PR 3" section is the agreed direction

## Goal

PR 3 of the Skyline-Osprey integration: Osprey's package becomes the engine package. Build Library's
AlphaPeptDeep/Carafe path downloads the Osprey package at first use (the Osprey Search location) and
predicts the library by running `Osprey.exe` out of process through the wizard's ProcessRunner, log tee,
rollover and `OspreyProgressMonitor`; Skyline stops shipping `torch\cpu` (256 MB), the pretrained models
(25 MB) and TorchSharp, which #4849 put into the installer (daily zip 94 MB -> about 195 MB).

## Survey (2026-10-26, read-only agent, verified by hand where it matters)

- **Build Library predicts the document's exact precursors.** `AlphapeptdeepLibraryBuilder`
  (`Model\Lib\AlphaPeptDeep`) writes `input.tsv` (sequence, mods, mod_sites, charge) from the document
  plus the iRT standard peptides (`AbstractDeepLibraryBuilder.GetPrecursorTable`), then predicts in
  process with `Ms2Model` / `RtPredictorLoader` / `CcsModel` directly (NCE 30, Lumos hard-coded), writes
  its own speclib TSV, fits iRT, and runs BlibBuild + BlibFilter. It bypasses CarafeSharp's
  `LibraryGenerator` entirely.
- **Osprey's library phase predicts from a FASTA only.** `--task PredictLibrary` needs `--fasta` and `-o`,
  no raw data (`Program.cs:981-986`); `LibraryBuildWorkflow.PhaseTask` builds a `PredictLibraryTask`
  over an in-memory digest (`LibraryPeptides.Build`), and `LibraryGenerator.Run` lists peptidoforms from
  bare sequences through `PeptideIsoformGenerator` (global fixed/variable modifications) and charges
  from a charge range. There is no precursor-table input anywhere in CarafeSharp or Osprey, so the plan
  as written cannot reproduce Build Library's "exactly these precursors, these modification sites, these
  charges". The output lands at `<out>.predicted.blib` with decoys and DecoyPairs always on.
- **TorchSharp reaches Skyline through CarafeSharp.Models** (`Skyline.csproj:315-319`: the
  `LibTorchRuntimeLayout.targets` import, the CarafeSharp.Models and .Proteome project references, the
  model Content items at 322-337). `CarafeSharp.Proteome` has no TorchSharp and must stay: `CarafeModelFile`
  (manifest reading in `EditCarafeModelDlg`, `CarafeModelChoice`, the tuning test), `CarafeCommandLine.ARG_*`
  (`OspreyHelpers.AppendLibraryBuildArgs`), `Enzyme`, `ModificationTable`.
- **Use GPU depends on in-process CUDA detection.** `UseGpuDriver` (`SettingsUI`) probes
  `TorchRuntimes` (a `CarafeSharp.Models.LibTorchRuntimes`): `CudaInstaller` reads `torch\*.packages.txt`
  from Skyline's bin, `GetCudaUnavailability`, `IsCudaInstalled`, `InstallCuda`. Without `torch\` in the
  bin the reason becomes `no_package_list`. Osprey has `--install-cuda-runtime --torch-runtimes <dir>`
  (`OspreyCommandArgs.cs:222-227`).
- **Osprey's package already carries everything**: `Osprey.csproj` imports the same targets and sets
  `UseCarafeModels=true`; `package.ps1` zips a self-contained net10.0 publish (156 MB).
- **Install seam**: `SkylineFiles.EnsureOspreyInstalled` (3884-3910) is private to `ShowOspreySearchDlg`;
  `OspreyHelpers.CreateDownloadInfo` checks the versioned path, not the registration (the stale
  registration finding of PR 1).
- **Tests on the in-process path**: `TestAlphaPeptDeepBuildLibrary` (TestPerf, Rat_plasma.sky, with and
  without iRT against reference blibs), `TestCarafeModelBuildLibrary` (TestPerf, pasted peptides, a legacy
  `.carafemodel`), `AlphaPeptDeepUseGpuTest` (TestFunctional, fake CudaDriver), the unit tests
  `AlphapeptdeepLibraryBuilderTest` and `AbstractLibraryBuilderModificationSupportTest`; the Osprey seam
  is `OspreySearchTest.EnsureOsprey` (`SKYLINE_TEST_OSPREY_EXE`, the sibling build, or the pinned download).

## Design points (to settle with Brendan before coding)

1. **The precursor-table input** - the one that decides the shape of the PR (open)
2. **Use GPU and CUDA install without TorchSharp in Skyline** (open)
3. **Framework-dependent vs self-contained package** (open)
4. **Which tests move to the download seam** (open)

## Tasks

- [ ] Design settled (above)

## Progress Log

### 2026-10-26 - Branch cut, survey

Branch cut from PR 2's head after Brendan approved #4914's squash-merge (waiting on its re-run checks;
auto-merge is disabled on the repository). Survey as above; the precursor-table gap found and verified in
`LibraryGenerator.Run` and `PredictLibraryTask`.
