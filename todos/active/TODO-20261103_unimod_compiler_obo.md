# TODO-20261103_unimod_compiler_obo.md

## Branch Information
- **Branch**: `Skyline/work/20261103_unimod_compiler_obo`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: In Progress
- **GitHub Issue**: [#4980](https://github.com/ProteoWizard/pwiz/issues/4980) (roadmap step 1 and the enforcement comment)
- **Module**: `skyline`
- **PR**: [#4990](https://github.com/ProteoWizard/pwiz/pull/4990)
- **Worktree**: `C:\proj\wt-unimodgen` (night-session agent C, wave TODO-20261103_osprey_backlog_round2)

## Objective

Make `pwiz/data/common/unimod.obo` the UniMod source of record for Skyline: `UniModCompiler`
reads the obo (not the 2023 `unimod.xml`), the Mascot `get_params.pl` and ProteinPilot inputs stay
as the overlay they are, `UniModData.cs` is regenerated, and a Skyline test holds the table to the
obo (ids, six-decimal masses, sites/terminus, explicit exclusion list).

## Tasks

- [x] Compiler: `UniModOboReader.cs` reads the obo into the existing `mod_t` model (bricks expanded,
      UniMod element order, specificities split at `spec_N_group`, neutral losses parsed)
- [x] Compiler: paths found from the exe location (old relative paths no longer resolved under the
      SDK-style `bin\Debug\net10.0-windows` output); exit code 1 on error; no "Press enter"
- [x] Compiler: hidden entries for every obo id no Mascot entry matched (Mascot-style names, one per
      site group, terminal specificities one each, protein-terminal skipped)
- [x] Compiler: `KEEP_STRUCTURAL_TITLES` overlay for NEIAA:2H(5), TMAB:2H(9) (order artifact, see below)
- [x] `Build-Skyline.ps1 -Target UniModCompiler` added in pwiz-ai
- [x] Regenerated `UniModData.cs`: 1172 -> 1554 ids, 6 obo ids excluded (protein-terminal only)
- [x] `TestUniModAgreesWithObo` in `Test/UniModTest.cs`
- [x] Build, run TestUniMod (updates UniModStaticList.xml / UniModHeavyList.xml; run twice), new test
- [x] CodeInspection, Test.dll, 56 modification-related functional/tutorial tests
- [ ] TestData.dll on a vendor-enabled build (running at PR time; see Progress Log)
- [x] README + CV-update procedure docs (compiler README, build/CvGen/Program.cs, pwiz/utility/README.md)
- [x] /code-review medium (triage below)
- [x] PR #4990 opened 2026-11-03

## Decisions (for Brendan to revisit)

- Verifier reads the obo directly instead of through `Pwiz.Data.Common.Unimod`: Skyline's test
  projects do not reference pwiz-sharp's Common, and the shared reader keys specificities by the
  `spec_N` number, which the obo repeats for every site of a site group, so it keeps only the last
  site (Phospho spec_1 is T then S; the reader keeps S only). Worth fixing in the shared reader
  (roadmap step 2); not done here because Osprey and BiblioSpec read it.
- unimod.xml was not in record order (NEIAA:2H(5) 212 preceded NEIAA 211; TMAB:2H(9) 477 preceded
  476), so the compiler had carried those two as structural mods with full formulas. In obo order
  they would become isotope labels of their parent, losing their own neutral losses and reordering
  the parent formula string. Kept structural via an explicit overlay.

- The verifier computes each formula's mass with UniMod's element masses (a table in the test, from
  unimod.xml's umod:elements), so it checks the formula's atoms. With Skyline's own element masses
  (`BioMassCalc`) about 50 entries miss the published six-decimal value by 1-26e-6 Da: iTRAQ4/8plex,
  TMTpro, mTRAQ 13C/15N (heavy-isotope masses), metal cations (Na, K, Fe, Ni, Cu, Zn), Br, I, Se,
  Hg (2.6e-5), Mo. So the issue's "equals UniMod's published value by construction" holds for
  CHNOPS only; roadmap step 3 (one element table) is where that gets decided.
- A "six-decimal match" is |mass - published| <= 0.5e-6 (plus 1e-9), not Math.Round equality, which
  rounds midpoints to even (Hex(3) failed on that).

## /code-review medium (2026-11-03, 10 findings)

Fixed:
- ListEquals accepted a shorter loss list as a prefix match; now requires equal counts (strict
  compare; verify regeneration leaves the listed Mascot entries unchanged)
- Output written to UniModData.cs.tmp and moved into place on success, so an exception no longer
  leaves a truncated UniModData.cs in the source tree
- Generated names checked against the template's hard-coded names (Label:13C(6) (C-term K) ...),
  which would otherwise throw a duplicate key in UniMod's static constructor
- Per-residue fallback now also covers a site group rejected as impossible (label atoms)

Dropped:
- Hex (W) / Malonyl (K) gained neutral losses: obo-driven (UniMod edited them after 2023); stated in the PR
- More hidden entries change mass matching for imports: the intended effect of naming every id; the
  test sweep is the check
- ContainsSite takes the first matching spec's losses: existing compiler behavior for every listed
  entry; changing it would move Mascot-listed entries
- Shared Pwiz.Data.Common.Unimod keeps one site per spec_N: recorded under Decisions; out of scope
  (Osprey and BiblioSpec read it)
- Obo field order assumptions: the obo is UniMod-generated with a fixed order; a change throws
  rather than silently misparsing in the common case
- A name in both [MODS] and [HIDDEN_MODS] would be reported unmatched: no such name today

## Progress Log

### 2026-11-03
- Baseline: the unchanged compiler, run against unimod.xml, reproduced the committed UniModData.cs
  except the order of the trailing "Unused code" comments (culture sort; now ordinal).
- Obo with the Mascot lists only: the diff was 2 obo-driven neutral-loss additions (Hex (W) H8C4O4;
  ID 747 (K) CO2, both modified in UniMod after 2023) plus the NEIAA/TMAB order artifact.
- First sweep (no-vendor build): CodeInspection, Test.dll pass; 55/56 modification tests pass;
  TestMs1Tutorial and 50 TestData.dll tests failed, all vendor-file imports, and the TestData run
  hung at a Waters IMS test (killed). Cause: the worktree has no Directory.Build.user.props, so
  Build-Skyline.ps1 built in no-vendor mode. Rebuilt with -VendorLicenses: TestMs1Tutorial and
  TestCommandLineNoJoin pass (C:\proj\ai\.tmp\sessions\20261103-agentC\rerun-vendor.log).
  Environmental, not UniMod.
- Code-review fixes regenerate an identical UniModData.cs.
- Pass `-VendorLicenses` to every Build-Skyline.ps1 call in a fresh worktree.
