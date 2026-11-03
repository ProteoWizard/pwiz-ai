# TODO-20261101_osprey_unimod_shared.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_unimod_shared`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: Completed (merged 2026-11-03 after its Perf/Regression gate, build 4248233, passed).
  The PR is step one of the unification roadmap filed as #4980 (one UniMod source, one element table,
  formula-preserving modifications, a shared lookup layer); the composition-based mass and the MS1
  isotope atoms follow in a later PR on top of this one. Earlier hold note kept below for the record.
- **Hold note (2026-11-02)**: PR #4956 was open and green but not to be merged yet.
  Brendan wants Skyline and Osprey to agree on UniMod before either follows core pwiz: Skyline's
  `UniModData.cs` is generated from a 2023 `unimod.xml` (1,172 ids) while the obo this PR reads is
  from 2026-02 (1,560 ids). Decide first whether UniModCompiler is repointed at the obo and
  Skyline's table regenerated, and whether the UniMod data and lookup move to `pwiz_tools/Shared`.
  Mass analysis (2026-11-02): Skyline never reads UniMod's mass; it computes from the formula with
  element masses that ARE UniMod's element table and rounds to 6 decimals, so it equals the obo's
  `delta_mono_mass` by construction. Osprey takes the obo mass as given. CarafeSharp writes
  alphabase (NIST) masses, about 1e-6 Da off, and its proton is 1.007276467 vs 1.007276.
- **GitHub Issue**: [#4736](https://github.com/ProteoWizard/pwiz/issues/4736)
- **Module**: `osprey`
- **PR**: [#4956](https://github.com/ProteoWizard/pwiz/pull/4956)
- **Worktree**: `D:\Dev\pwiz-unimod` (night-session worktree of `C:\proj\pwiz`)

## Objective

Osprey keeps no UniMod table of its own: ids, titles and masses come from the one copy of UniMod
in the repository, `pwiz/data/common/unimod.obo`, as read by pwiz-sharp's `Pwiz.Data.Common.Unimod`.

## Findings before the change

- The six wrong masses the issue lists were already corrected on master by #4749, which folded
  `DiannTsvLoader.UnimodIdToMass`, `BlibWriter.UNIMOD_MASSES` and the BlibLoader snap list into one
  hand-typed table, `Osprey.Core/UniMod.cs`, typed from Skyline's masses. What remained of #4736
  was the table itself, `DiannTsvLoader.UnimodIdToMass` (a wrapper over it), and a second
  hand-typed table: `ParseModMass`'s names (Oxidation 15.9949, CAM 57.0215, ...) at four decimals.
- Compared every id the table held with unimod.obo: identical except iTRAQ4plex (UniMod:214),
  table 144.102062 (Skyline, from the formula) vs obo 144.102063.

## Choice of source

**Chosen: pwiz-sharp `Pwiz.Data.Common` (unimod.obo, embedded).** Osprey.IO already shipped and
loaded it through ProteowizardWrapper, so the footprint is one ProjectReference on Osprey.Core and a
one-line public `Id` property on `UnimodModification` (the accession number had no public accessor;
`CvLookup.OffsetUnimod` is internal). unimod.obo is the file the C++ side reads and the issue's
own oracle. First touch parses it: ~200 ms once per process (pwiz Common.Tests timing).

**Alternative: Skyline's `UniModData.cs`** (UniModCompiler output) moved or linked into
`pwiz_tools/Shared`. Larger: a generated file plus its generator to relocate, and Skyline's data
is formulas, not masses, so Osprey would also need the formula-to-mass code. Its value is that
it carries Skyline's common/hidden lists and specificities, which Osprey's matching follows. That
convergence (Skyline vs obo, issue item 3) is left to a later change.

## What stays in Osprey

The list a printed mass is snapped to (`UniMod.MATCHED`): ids and specificities in Skyline's
order of preference, no names or masses. Matching a one-decimal mass against all of UniMod would
be ambiguous among dozens of entries; the issue's item 2 idea (snap to any UniMod entry with the
right specificity) changes which modification a BiblioSpec library reads as, so not done here.

## Tasks

- [x] `UnimodModification.Id` in pwiz-sharp, with a test line
- [x] Osprey.Core references Pwiz.Data.Common; `UniMod` built from `Unimod.Modifications`
- [x] `UniMod.Find` resolves any obo id; `UniMod.FindByName` any title (case-insensitive) plus
  the two aliases the name table had (CAM, Deamidation)
- [x] `DiannTsvLoader.UnimodIdToMass` and the name table removed; a named mod takes its UniMod
  id and exact mass
- [x] Reader versions bumped (BlibLoader 5, DiannTsvLoader 5, `TSV_READER_TERM`), with a test
  holding the TSV term literal to the reader version
- [x] Tests: obo masses for 1, 4, 21, 35, 737 and the six once-wrong ids through the writers and
  the DIA-NN reader; a DIA-NN modified sequence with (UniMod:28), (UniMod:214), (UniMod:385); every
  obo modification by id and title
- [x] Gate: Build-Osprey -RunTests -RunInspection (646/646, inspection zero;
  `C:\proj\ai\.tmp\sessions\20261101-unimod\gate2.log`)
- [x] regression.ps1 -Dataset Stellar: PASS, mode 1 vs golden unchanged
  (`C:\proj\ai\.tmp\sessions\20261101-unimod\regression-stellar.log`). Goldens cannot move: the
  stellar, stellar-libdecoy and astral libraries carry only `[UniMod:4]` (checked by grep).
- [x] Review at medium (a fresh reviewer agent over the saved diff: the `/code-review` skill is
  blocked by `Deny-CodeReviewInAiRepo.ps1` because this night session's cwd is pinned to
  `C:\proj\ai`). One finding, fixed: UNIMOD:0 (the ontology root, no composition) read as a
  +0 Da modification; now skipped, with a test. Everything else checked clean (init order,
  title collisions, masses vs the old table, thread safety).
- [x] PR [#4956](https://github.com/ProteoWizard/pwiz/pull/4956) opened 2026-11-01

## Decisions Brendan might revisit

- **Reader-version bump invalidates every cached search.** Both readers moved to 5 because what
  they make of a library changed: iTRAQ4plex by 1e-6 Da, a TSV mod named by title now takes the
  exact mass (was four decimals), and ids outside the old table now load (they refused the
  library before, so no cache existed). For a library using only the common ids (the regression
  and cohort libraries) nothing changes, but its Stage 1-4 outputs re-run once. The alternative
  was not bumping and accepting stale caches for iTRAQ4plex / named-mod libraries.
- Rust Osprey keeps its own (wrong) table; not changed. Parity on the affected ids already
  diverged with #4749; this PR adds iTRAQ4plex (1e-6) and ids outside the old list. No parity
  dataset uses them.

## Progress Log

### 2026-11-01
- Investigated sources, chose Pwiz.Data.Common; implemented; unit tests 646/646, inspection clean
  (log `C:\proj\ai\.tmp\sessions\20261101-unimod\gate1.log`); pwiz Common.Tests Unimod 4/4
  (`C:\proj\ai\.tmp\sessions\20261101-unimod\pwiz-common-test.log`).

### 2026-11-03 - Merged

TeamCity Perf/Regression gate build #354 (4248233) passed on a37a709df1: all four datasets plus the
CarafeSharp pass. PR #4956 merged as commit af5efe8b2b. Shipped: Osprey's UniMod ids, titles and
masses from unimod.obo through Pwiz.Data.Common.Unimod, the private tables gone, reader versions 5.
Issue #4736 closed by the merge. Its items 2-4 (mass matching against all of UniMod, reconciling
Skyline's data with the obo, a tool-docs rule) are now steps of the unification roadmap #4980,
where the next Osprey PR computes modification masses from the obo composition and carries the
atoms into the MS1 isotope distribution.
