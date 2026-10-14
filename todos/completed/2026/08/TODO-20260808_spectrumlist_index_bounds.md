# TODO-20260808_spectrumlist_index_bounds.md

## Branch Information
- **Branch**: `Skyline/work/20260808_spectrumlist_index_bounds` (created 2026-08-08, deleted
  2026-08-10 local + remote)
- **Checkout**: `C:\Dev\quickee`
- **Module**: `pwiz`
- **Base**: `origin/master`
- **Status**: **Completed**
- **GitHub Issue**: (none)
- **PR**: [#4551](https://github.com/ProteoWizard/pwiz/pull/4551) (merged 2026-08-10 as `e96bc8052`)
- **Cherry-pick to release**: not requested

> Written retroactively at completion time - this branch was started without a TODO, so this file
> is the record rather than a running log.

## Objective

Fix the off-by-one in the index bounds guards of the `SpectrumList` / `ChromatogramList` /
`ProteinList` implementations. The guards tested `index > size` instead of `index >= size`, so
`index == size()` passed validation and indexed one past the end. That matters specifically
because `find()` returns `size()` as its not-found sentinel, so the sentinel walked straight
through the check.

Found during a `/code-review max` run on the unordered-m/z work
(see `TODO-20260804_mzml_mz_sort_order.md`), not from a user report - no runtime failure has been
attributed to it. Code inspection was right to flag it regardless.

## What shipped

- **29 guards across 18 files** changed from `>` to `>=`: core msdata readers (mzXML, MGF, MSn,
  BTDX), the vendor spectrum and chromatogram lists (ABI, Agilent, Bruker, Mobilion, Shimadzu,
  Thermo, UIMF, UNIFI, Waters), and `ProteinList_DecoyGenerator`.
- **MGF and MSn `spectrumIdentity()` had no guard at all** - they indexed `index_` unchecked, so an
  out-of-range index read past the end rather than throwing. Guards added to match what the other
  readers already do.
- Completes `18e8ba470` (2009), which applied this same fix to four `spectrum()` methods but not to
  their `spectrumIdentity()` twins, the chromatogram lists, or the text readers.
- Line endings normalized in the three touched files that had mixed endings. This is why the merge
  commit reads 588 insertions / 554 deletions for what is 31 one-character logic edits - review the
  commit with `git diff --ignore-cr-at-eol` to see the real change.

## Verification

- [x] `SpectrumList_mzXML_Test`, `SpectrumList_MGF_Test`, `SpectrumList_MSn_Test`,
      `ProteinList_DecoyGeneratorTest` - extended (not new files) with out-of-bounds assertions,
      each verified red before the fix and green after
- [x] `pwiz/data` and `pwiz/analysis` suites green
- [x] CI green at merge; approved by chambm
