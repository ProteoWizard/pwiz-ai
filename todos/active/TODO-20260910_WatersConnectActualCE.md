# Update CE optimization workflow to read actual CE values for waters_connect data

## Branch Information
- **Branch**: `Skyline/work/20260910_WatersConnectActualCE`
- **Base**: `master`
- **Created**: 2026-09-10
- **Status**: In Progress
- **GitHub Issue**: [#4346](https://github.com/ProteoWizard/pwiz/issues/4346)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `pwiz2`

## Objective

Update the collision energy (CE) optimization workflow to read actual CE values from waters_connect data,
rather than relying on CE step increments encoded as product m/z shifts in methods/data.

The issue's second request (reduce the product m/z step to 0.001 Da) is dropped by agreement with the
developer: once the exported waters_connect method carries the real product m/z, there is no mass change.

Source: waters_connect Skyline integration feedback (2026-06-17), item 6. Jira: INFMTD-306.

## Design

* **Export**: waters_connect methods get the real product m/z for every CE step (no 0.01 Da per-step
  shift); CE per step is already the actual value. Only step 0 is flagged as the quant ion.
* **Reader (C++)**: waters_connect MRM channels expose their CE as `MS_collision_energy` on the
  chromatogram precursor activation (never read before).
* **Import**: before the loader runs, waters_connect data (detected by the `MS_waters_connect` software
  CV term, so msconverted mzML behaves the same as live server data) has channels with identical
  precursor/product m/z and distinct CE sorted by CE and their product m/z shifted by
  `ChromatogramInfo.OPTIMIZE_SHIFT_SIZE` per step. The Skyline loader (`ChromDataProvider`) is unchanged.
* **Backward compatibility**: old files acquired with shifted product m/z have a unique Q3 per channel,
  so nothing is shifted and they load exactly as before.

## Tasks

- [ ] C++: parse `msTechnique.fragmentationProperties.collisionEnergy` in `WatersConnectData.ipp`,
      store on `UnifiChromatogramInfo`, set `MS_collision_energy` in `ChromatogramList_UNIFI.cpp`
- [ ] C#: `MsDataFileImpl.IsWatersConnectFile` + product m/z shift in `GetChromatogramMetadata`
      (math in a pure helper `WatersConnectCeSteps`)
- [ ] Export: waters_connect product m/z unshifted, quant ion only on step 0
- [ ] Unit test for the shift math (regression test)
- [ ] Extend `WatersConnectMethodExportTest` with a CE optimization export
- [ ] Import tests with new-style and old-style waters_connect runs (data requested from Waters)
- [ ] Regenerate `Reader_UNIFI_Test.data` reference mzML if the live reader test can be run

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Test (shift math), TestFunctional (export, import)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-10 - Session Start

Explored export (`WatersMassListExporter.WriteTransition`, `Export.cs:4697` shifts product m/z per step)
and import (`ChromDataProvider.SetOptStepsFromProductMz`; waters_connect reader never reads CE).
Agreed design with the developer: shift applied before the loader, gated on the waters_connect software
CV term; test data (new-style and old-style CE optimization runs) requested from the Waters team.
