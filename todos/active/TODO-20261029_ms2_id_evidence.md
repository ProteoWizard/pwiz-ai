# Show all MS/MS ID evidence a precursor uses, and drop outlier IDs when setting the extraction window

## Branch Information
- **Branch**: `Skyline/work/20261029_ms2_id_evidence`
- **Base**: `master`
- **Created**: 2026-10-29
- **Status**: In Progress
- **GitHub Issue**: [#4935](https://github.com/ProteoWizard/pwiz/issues/4935)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Retention time evidence for chromatogram extraction is pooled across all library precursors of a
peptide, but the document shows only the IDs of the precursor displayed. In the DDASearch tutorial
(TestDdaTutorial, MS Amanda 3.0), R.TGEGFLCVFAINNTK.S is held as charge 2 light/heavy, while the
library also holds charge 3 spectra including a false ID at 20.79 min. That single ID:

* Extends extraction in 2_UPS1_300fmol to nearly the whole run, with no ID drawn to explain it
* Is aligned into 1_UPS1_100fmol at 21.3 min, where a one-point M+1 noise spike is integrated

The heavy precursor shows "ID" annotations although only light was identified, has no Library Match
combo, and the Library Match title says "(heavy)" over the light spectrum.

Not known to be a .NET 10 regression: MS Amanda 2.0 -> 3.0 produced the false charge 3 ID.

## Tasks

- [ ] Chromatograms: draw ID and aligned ID lines for every library precursor used as evidence,
      labeled with charge and label type (e.g. "ID 3+"); mark IDs from another form as such
      (e.g. heavy matched to light IDs) rather than as the precursor's own IDs
- [ ] Extraction window (`RetentionTimeFilterType.ms2_ids`): center on the median of ID times and
      drop outliers before extending the range (like RCalcIrt / IrtPeptidePicker); apply the same
      rejection to aligned times
- [ ] Library Match combo: list all spectra of the peptide (all charges and label types), exact
      precursor matches first, for both light and heavy precursors
- [ ] Library Match title: name the label type of the spectrum shown, not the selected precursor
- [ ] Spectral Library Explorer: keep consistent with the Library Match combo change
- [ ] Check behavior on 26.1.1 with this data

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Test | TestFunctional | TestTutorial
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-10-29 - Session Start

Starting work on this issue. Branch created from master at 4f92fe97ba (#4915) in `C:\proj\pwiz`.
