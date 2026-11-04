# TODO-20261103_mztab_unimod_obo.md

## Branch Information
- **Branch**: `Skyline/work/20261103_mztab_unimod_obo`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: Completed
- **GitHub Issue**: [#4980](https://github.com/ProteoWizard/pwiz/issues/4980) (roadmap step 1, BiblioSpec half)
- **Module**: `pwiz`
- **PR**: [#4991](https://github.com/ProteoWizard/pwiz/pull/4991) (merged 2026-11-03)
- **Worktree**: `C:\proj\wt-unimodgen` (night-session agent C; second branch after #4990)

## Objective

Move BiblioSpec's `MzTabReader` off its own read of `pwiz/data/common/unimod.xml` onto
`Pwiz.Data.Common.Unimod` (the embedded unimod.obo), as `DiaNNSpecLibReader` and `TSVReader`
already are, so BiblioSpec has one UniMod source.

## Tasks

- [x] `MzTabReader.TryGetUnimodMonoMass` via `Unimod.Modification(CVID)`; `LoadUnimod` (XmlReader
      over unimod.xml) removed
- [x] `BlibBuild.csproj` no longer copies unimod.xml next to BlibBuild.exe
- [x] `Skyline/Executables/Installer/build.ps1` no longer requires unimod.xml in the stage
- [x] `MzTabReaderTests.MzTab_UnimodIds_ResolveFromObo` (no mzTab golden input exists anywhere in
      the tree, so the lookup is pinned directly: Carbamidomethyl, Oxidation, UNIMOD:2086 which is
      in the obo but not the 2023 xml, and an unknown id)
- [x] Build-BiblioSpec.ps1 -RunTests: 143 passed (C:\proj\ai\.tmp\sessions\20261103-agentC\blib-tests2.log)
- [x] Review: the session cwd had moved to C:\proj\ai, where /code-review is blocked, so a fresh
      general-purpose reviewer agent reviewed `git diff origin/master...HEAD`. One finding, fixed:
      UNIMOD:0 (the obo root node, mass 0) would have been accepted as a modification where
      unimod.xml had no record 0. Checked clean: the id->CVID arithmetic, the masses (same published
      values), no other unimod.xml consumer in output dirs, definite assignment, cost of the linear
      lookup (microseconds per mod; DIA-NN and TSV pay the same)
- [x] PR opened (see Branch Information)

## Decisions (for Brendan to revisit)

- `pwiz/data/common/unimod.xml` stays in the tree: on master, `UniModCompiler` still reads it until
  #4990 merges. After #4990 nothing reads it (grep of the tree: only MzTabReader, BlibBuild.csproj,
  the installer stage check and the compiler referenced it) and it can be deleted.
- Behavior: masses are the same published delta_mono_mass values; ids added to UniMod since 2023
  (38) now resolve instead of skipping the PSM with "Unrecognized Unimod ID". The reader no longer
  warns about a missing unimod.xml (it cannot be missing).

## Progress Log

### 2026-11-03
- Branch cut from origin/master after #4990 was pushed.

### 2026-11-03 - Merged

PR #4991 merged as commit de6beefa92. Shipped: MzTabReader resolves UNIMOD ids through Pwiz.Data.Common.Unimod; BlibBuild and the installer stage no longer carry unimod.xml; MzTabReaderTests. Follow-up: with #4990 also merged, nothing in the tree reads pwiz/data/common/unimod.xml and it can be deleted.
