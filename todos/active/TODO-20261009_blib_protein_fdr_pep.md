# TODO-20261009_blib_protein_fdr_pep.md

## Branch Information
- **Branch**: `Skyline/work/20261009_blib_protein_fdr_pep`
- **Base**: `master` (be284d2ab9)
- **Created**: 2026-10-09
- **Status**: In Progress
- **Module**: `pwiz`
- **PR**: #4848 (draft, stacked on #4823; screenshots in pr-assets `pwiz/4848-blib-global-q/`)
- **Checkout**: `I:\git_i\sky_proteinfdr`
- **Related**: `TODO-20261002_osprey_peptide_fdr_pep.md` (Osprey computing the PEPs). The uncommitted
  Osprey writer changes from the abandoned `Skyline/work/20261001_osprey_blib_protein_fdr` branch are
  re-applied in this checkout; they predate the column names below and must be brought in line.

## Objective

Give .blib files places to store **global** (experiment-wide) q-values and PEPs at the precursor,
peptide and protein-group levels, write them from BiblioSpec (DIA-NN first), and read them in
Skyline so it can filter on them. The Osprey writer is secondary and may be handed to someone else.

Why: Skyline has only been filtering on per-run q-values, so as the number of runs in an
experiment grows, the quality of the peptides that get into the Skyline document goes down.
Per-run values are out of scope; no columns are added to `RetentionTimes`.

## Design decisions
- **No schema version bump.** `BlibSchema.CurrentMinorVersion` stays at 11. Readers test for a
  column's presence (`SqliteOperations.ColumnExists` in Skyline) instead of `minorVersion`.
- **Optional columns.** A column is added (`ALTER TABLE ... ADD COLUMN`) only when the reader has
  values for it, so libraries from tools that do not report a value pay no size or read cost.
- **BlibFilter carries the optional columns; BlibBuild merges do not** (changed 2026-10-13 for the
  PD reader, which builds a redundant library). The global values live on `PSM`, a reader sets the
  same values on every PSM of a precursor/peptide, and BlibFilter keeps the chosen spectrum's
  values (`BlibMaker.OptionalColumnsCsv`). A merge does not copy them: a global value from one
  experiment means nothing next to one from another.
- **`Proteins` rows are protein groups**, `accession` = the group's accessions joined by `;`.
- **A named column only when its meaning is certain.** `RefSpectra.score` stays as it is; even
  with a q-value score type it does not say what the q-value is for. `PrecursorQValue` is written
  only when the source value is known to be a global (experiment-wide) precursor q-value.
- **Peptide-level values are separate from precursor-level.** The truth is shared across charge
  states, but the estimates come from different competitions, and the minimum precursor q across
  charge states is not a valid peptide q. Peptide columns are written only by a tool that does a
  real peptide-level competition.

## Columns (all optional)

| Table.Column | Meaning | DIA-NN | Osprey |
|---|---|---|---|
| `RefSpectra.PrecursorQValue` | global precursor q | `Global.Q.Value` | experiment precursor q |
| `RefSpectra.PrecursorPep` | global precursor PEP | - | experiment precursor PEP |
| `RefSpectra.PeptideQValue` | global peptide q | - | experiment peptide q |
| `RefSpectra.PeptidePep` | global peptide PEP | - | experiment peptide PEP |
| `Proteins.QValue` | global protein-group q | `Global.PG.Q.Value` | group q |
| `Proteins.Pep` | global protein-group PEP | - | group PEP |

Proteome Discoverer (2.2+ and filtered .pdResult): `RefSpectra.PeptideQValue`/`PeptidePep` from the
PSM's peptide group (`TargetPeptideGroups.qValue`/`PEP` in 3.x, `Qvalityqvalue`/`QvalityPEP` in
2.x; PD groups I/L-equivalent sequences), `Proteins.QValue` from each master protein's `Expqvalue`
(a 9-byte nullable-double blob), one `Proteins` row per master protein. An entry whose protein
failed PD's protein FDR has no master protein, so no `Proteins` row.

## Progress
- [x] Settle column names (2026-10-09)
- [x] BiblioSpec: optional-column support (2026-10-09, uncommitted). `BlibSchema` column defs +
      `OptionalColumn`; `BlibMaker.AddOptionalColumn` / `GetOptionalColumns`;
      `BuildParser.EnableOptionalColumn` + values on `NonRedundantPSM` / `Protein` (equality stays
      accession-only). Tested through the DIA-NN reader (next step).
- Known, not fixed: a BlibBuild merge of .blib inputs never copies `Proteins` (pre-existing, cpp
  parity). Outside the scenarios this work targets.
- [x] BiblioSpec: DIA-NN reader writes `RefSpectra.PrecursorQValue` (`Global.Q.Value`), a `Proteins`
      row per `Protein.Group` (new: DIA-NN libraries had no Proteins rows before) linked through
      `RefSpectraProteins`, and `Proteins.QValue` (`Global.PG.Q.Value`, optional report column)
- [x] BiblioSpec tests: 8 DIA-NN `.check` files regenerated; verified the only change is the
      PrecursorQValue header + a trailing value equal to `score` on every RefSpectra row. New
      `DiannGlobalValueTests` (TSV + parquet) check Proteins against the report, since the `.check`
      dump has no Proteins section. Full suite 145/145 with `-VendorLicenses`.
- [ ] Skyline (design settled 2026-10-09; the values only decide which precursors enter the document,
      per-run `RetentionTimes` rows and their per-run Q Value stay as they are):
  - [x] Read the columns when present: `BiblioLiteSpectrumInfo.GlobalScores` (`LibraryGlobalScores`,
        new Model/Lib/LibraryGlobalScores.cs), `Library.GlobalQValueLevels` / `GetGlobalScores(LibKey)`
        (kept off `BiblioSpecSpectrumHeaderInfo`, which is saved in .sky)
  - [x] Spectral Library Explorer: "Global cutoff:" label + value dropdown ("Protein q-value",
        "Peptide q-value", "Precursor q-value"; PEP entries can be added later) + cutoff textbox,
        between Add All and Associate Proteins (Nick, 2026-10-11). One FlowLayoutPanel holds Add,
        Add All, label, dropdown, cutoff and Associate Proteins (2b3fd6cf28). The cutoff controls
        start visible in the designer: a control whose handle is first created when it is shown
        moves in its parent's Controls order (seen: hidden-at-design controls laid out in the
        order they were made visible). Form widens if the row would overlap Close (not seen: the
        saved size was wide). Checked live through the AI connector: opening with and without
        global values, and switching between libraries both ways. Empty cutoff = no filter. Filter in `ViewLibraryPepMatching.MatchAllPeptides`
  - [x] Show the values in the property sheet (`SpectrumProperties`, shared by Library Match)
  - [x] "Associate Proteins": decided - use .blib groups only when the library has protein q-values;
        groups are sequence-less peptide lists named by the group; shared peptides follow the
        existing duplicate-protein dialog choice. `ViewLibraryPepMatching.UseLibraryProteinGroups`
  - [x] Functional test (2026-10-14) `TestFunctional/GlobalQValueFilterTest.cs` + `.zip` (3.2 MB,
        inputs copied from BiblioSpec `tests/inputs`; PanoramaWeb data may NOT go in committed tests).
        `TestDiannGlobalQValueFilter` (HeLa diaPASEF report + speclib, built at q <= 0.05 because
        BlibBuild applies the build threshold to DIA-NN's `Global.Q.Value`; precursor and protein
        cutoffs 0.01 both remove entries), `TestPdResultGlobalValues` (PD 3.1 two-file) and
        `TestPdResultLegacyGlobalValues` (PD 2.3): values vs the .blib / the PD tables, offered
        levels, Add All document == passing entries under their library groups. The PD files'
        protein q are all 0, so DIA-NN covers the protein cutoff. Replaced the BiblioSpec
        `PdGlobalValueTests` (Nick: PD FDR tests are Skyline functional tests). -Loop 3 clean.
        Gotchas: OK in Peptide Settings drops doc mods not in the saved mod list, so add library
        mods after building; library protein groups are peptide lists too (the unmatched list is
        told apart by name).
  - [x] Import Peptide Search: q-value filter panel on the FASTA page (`ImportFastaControl`,
        shown when the document's libraries have global q-values). Decided 2026-10-10: NOT a
        persistent setting. `GlobalQValueFilter.FilterDocument` removes failing precursors (and
        peptides left empty) from the newly imported proteins before Associate Proteins, and sets
        AutoManageChildren=false on every peptide/protein that lost children. Shared UI logic in
        `SettingsUI/GlobalQValueFilterControls`
  - [x] Audit log for the q-value filter (2026-10-11): `GlobalQValueFilter` Level/Cutoff tracked,
        as `QValueFilter` on `ViewLibrarySettings` (Add All only; single add logs none) and
        `ImportFastaSettings`. PropertyNames/EnumNames strings added (en only).
        `GlobalQValueFilterControls.Filter` reads it without a message box. TestAuditLogLocalization +
        CodeInspection pass. Committed 7623650be2 (not pushed).
- [x] Osprey writer: re-applied changes renamed (`PrecursorQValue`, `PeptideQValue`, `Proteins.QValue`)
- [x] Osprey writes `RefSpectra.PrecursorPep` (a14d902746, 2026-10-11): the entry's experiment PEP.
      The second-pass sidecar overlay (`FdrScoresSidecar.TryReadOverlay`) never applied the
      experiment record's PEP, so every blib entry had the 1.0 default; it now applies it with the
      q-values. `PeptidePep` and `Proteins.Pep` need b636c35466 (peptide + protein-group PEPs,
      unmerged, Nick: separate PR). 656/656 tests, inspection clean.
- [x] Import FASTA page (265a04ba54): control widened to 572 in the designer (en/ja/zh-Hans),
      "Global cutoff" group box right of Decoys per target, value + cutoff on one row
- [x] Merged PR #4823's branch (36d87e7b9a), then ported b636c35466 parts 1-2 and did part 3 on
      #4823's competition (209c65fcac): second-pass peptide-level competition
      (`StreamedCompetitionState.CompetePeptides`), experiment peptide PEP both passes (experiment
      sidecar v4, 52-byte records), protein-group PEP (`ComputeLibraryGroupPeps`, fitted on all the
      library competition's winners), blib `RefSpectra.PeptidePep` + `Proteins.Pep`. Run PEP (part 4)
      left out. 649/649 tests, inspection clean.
- [x] Stellar natural entrapment with exe `D:\test\osprey-runs\_bin\blib-peps`, output
      `D:\GlobalQValueDemo\Entrapment\stellar-natural\osprey_project_peps\` (check script
      `blib_pep_check.py` in the session scratchpad): all six columns filled; 0 peptides with
      charge states disagreeing on peptide q or PEP. At q <= 0.01 measured FDP: precursor 0.51%,
      peptide 0.53%, protein group 0.72%. PEPs are CONSERVATIVE: sum of PEP over the accepted set
      is 699 / 803 / 75 against ~180 / 166 / 30 false estimated from entrapment (mean PEP ~2% where
      q is 1%), the existing precursor PEP included - a property of PepEstimator, worth telling Mike.
- [x] BiblioSpec: Proteome Discoverer reader (2026-10-13/14) writes `PeptideQValue`, `PeptidePep`
      and `Proteins.QValue` (see the PD note under Columns); global values moved from
      `NonRedundantPSM` to `PSM`; BlibFilter carries the optional columns. 3 PD `.check` files
      regenerated (new columns only).
- [x] Ad hoc real-data check (2026-10-14), PanoramaWeb PD 3.1.1.39
      `240417_P1_Neo_Ecoli200ngHeLa200ng_60SPD_DIA` (5 GPF runs, 1.7 GB, in
      `D:\GlobalQValueDemo\PD\Stellar_EcoliHeLa_3.1\`): BlibBuild 27 s / 899 MB peak, BlibFilter 5 s;
      every peptide value matches PD's peptide groups, all 1218 protein rows are master proteins
      with the exact Exp. q-value. In Skyline (connector): peptide 0.01 Add All = 7943 precursors
      exactly; protein 0.01 = 1016 groups, no precursor under a failing group. PD 3.x inventory
      on PanoramaWeb in `ai/.tmp/sessions/20261014-76d46ce6/pd-panoramaweb-inventory.md` (no
      public PD 3.2 file has its .pdResultDetails). The one PD 3.2.0.196 file (MacCoss fluid assays
      `240109_P1_IO15cm_NeoLC_CSF_60m_2ThGPF.pdResult`, 7.8 GB, in `F:\GlobalQValueDemo\PD\CSF_3.2\`)
      is useless for this: corrupt on PanoramaWeb itself (zeroed pages, byte-identical to the
      server), and it has no TargetPeptideGroups and no Expqvalue/IsMasterProtein; TargetPsms
      still has qValue/PEP. BlibBuild stops cleanly ("database disk image is malformed").
      Nick found an intact 13.0 GB copy (plus a PD 3.1.1.39 `240205_P1_IO15cm_NeoLC_GPF_DIA2Th`)
      in a private MacCoss PanoramaWeb folder: `D:\GlobalQValueDemo\PD\2024-01 CSF methods Thorium\`.
      It has the full 3.2 schema (TargetPeptideGroups qValue/PEP/Confidence, Expqvalue,
      IsMasterProtein); 3.2 renamed nothing the reader uses. BlibBuild (default cutoff) 351 s /
      5.8 GB peak: 242,698 spectra, 12,833 peptides; every peptide value matches PD's group (210
      spectra match only by I/L equivalence), all 1709 protein rows are master proteins with the
      exact Exp. q-value. Note `-c` is a probability: `-c 0.05` means q <= 0.95, not 0.05.
- [x] `/code-review medium` (2026-10-14), fixes in fc0a36dfb7: DIA-NN blank/null
      Global.PG.Q.Value no longer stored as 0; the Import FASTA filter no longer keeps a failing
      peptide's heavy (not-in-library) precursors; library minimizing keeps the global columns and
      library protein groups (Nick); BlibBuild writes no global columns with >1 input and drops
      them on append (Nick; `BlibBuilder.AllowsOptionalColumns`). Dropped: no-FASTA filter
      (by design), re-picking failing charges (nodes are not auto-managed), library not loaded on
      the FASTA page (loaded synchronously), PSM in two PD peptide groups (0 of 275,821). Left for
      PR #4823 (ProteinFdrEngine.cs is identical there): `CountPassingProteinGroups` still uses the
      old competition; unused best-score map in `RunSecondPass`.
- [x] `TestDiannGlobalQValueFilterDocument` (58e2fd0190): `GlobalQValueFilter.FilterDocument`, the
      Import FASTA filter, on a FASTA built from the DIA-NN library's groups with heavy K/R labels;
      covers the heavy-precursor fix. Calls the filter directly: the wizard needs raw files the repo
      does not have for this library. `ImportFasta(..., keepEmptyProteins: false)` avoids the
      empty-proteins prompt that hung the first run.
- [ ] Not this branch: NuGet now flags `System.Security.Cryptography.Xml` 8.0.4 (Sciex reader) as
      high severity and NU1903 is an error, so BlibBuild and a `-VendorLicenses` Skyline build fail
      to restore (2026-10-14). Built locally with `NuGetAudit=false`. Needs a package bump on master.
- [ ] Follow-ups found 2026-10-14 (not on this branch unless Nick says so):
  - Library Explorer's cutoff textbox has no label of its own; the AI connector cannot address it
    by label (the "Global cutoff" label belongs to the dropdown). Nick (2026-10-14): leave the UI
    as it is; the connector reaches it by element path.
  - PD reader stores score 0 for confidence-filtered PSMs (cpp parity, `MSFReader.cs` ~503).
- [x] Refreshed the Osprey regression goldens (2026-10-14, ffcf30eba9; `-Dataset All
      -CreateGolden`, 41 min, FDRBench leg PASS): RefSpectra rows unchanged, 4 new columns,
      Proteins rows are groups (Stellar 5196 -> 4448). Same commit fixed the Osprey build, broken
      by the master merge c1e827e2ee (new first-pass `FeedModelDiagnostics` overload missed the
      `experimentPeptidePep` argument). PR #4823 (open) also changes 4 golden files: after it
      merges, `git merge origin/master` conflicts there - keep this branch's goldens (a superset
      of #4823) or regenerate.
- [x] Committed: BiblioSpec f4cb39b1ea, Skyline a42054cda8, Osprey e5f01ecc0b (2026-10-10, not pushed)

## Real-data validation (2026-10-10, overnight; details in D:\GlobalQValueDemo\Entrapment\RESULTS.md)

- DIA-NN 2.2.0 (C:\DIA-NN\2.2.0) and Osprey on Astral HeLa 3 runs; CarafeSharp (checkout
  I:\git_i\sky_net10_alphapeptdeep, PR #4717) built a natural Arabidopsis entrapment library (r=1).
- DIA-NN global precursor and protein q (our new columns, read through BlibBuild) are calibrated:
  protein 0.90% and precursor 0.84% measured FDP at 1% reported.
- Osprey global precursor q calibrated (0.61% at 1%). Osprey PROTEIN q is broken (all q = 0, 6.7%
  true FDP at every cutoff). Three layers: (1) ProteinFdr pairs decoys by "DECOY_"+sequence, which
  library decoys (--decoys-in-library, the Carafe workflow) do not have, so there are no decoys;
  (2) only groups with a detected target compete; (3) the second-pass pool is compacted, so losing
  decoys are gone. Fix that calibrates (0.82% at 1%): base_id pairing + Savitski picked competition
  over every library protein, scored from FIRST-PASS scores. Uncommitted experiment code in
  ProteinFdr.cs / ProteinFdrEngine.cs / FirstPassFdrTask.cs behind OSPREY_EXPERIMENT_PROTEIN_SCORES /
  OSPREY_EXPERIMENT_PROTEIN_NULL. Belongs in a separate Osprey PR (with b636c35466's peptide-q fix).
- BlibBuild `-c` for q-value inputs is 1 - q: `-c 0` keeps everything, `-c 0.99` is q <= 0.01.
- [x] Osprey experiment code removed from the working tree (2026-10-11): stashed in
      sky_proteinfdr as "OSPREY_EXPERIMENT protein FDR prototype (superseded by PR #4823)". The real
      fix is PR #4823 (`Skyline/work/20261011_osprey_protein_fdr`, TODO-20261011_osprey_protein_fdr.md).
