# CV Histogram titles missing 'CV' prefix

## Branch Information
- **Branch**: `Skyline/work/20260330_cv_histogram_titles`
- **Base**: `master`
- **Created**: 2026-03-30
- **Status**: In Progress
- **GitHub Issue**: [#4064](https://github.com/ProteoWizard/pwiz/issues/4064)
- **PR**: [#4120](https://github.com/ProteoWizard/pwiz/pull/4120)

## Objective

Fix CV Histogram graph titles to include "CV" prefix:
- "Peak Areas - Histogram" should be "Peak Areas - CV Histogram"
- "Peak Areas - Histogram 3D" should be "Peak Areas - CV Histogram 3D"

## Tasks

- [x] Find where graph titles are set for CV Histogram views
- [x] Fix title strings to include "CV" prefix via controller-aware CustomToString
- [x] Add localized resource strings (en, ja, zh-CHS) matching menu text
- [x] Add histogram/histogram2d sibling co-location (like abundance pair)
- [x] Build and test (AreaCVHistogramTest passes)
- [ ] Create PR

## Progress Log

### 2026-03-30 - Implementation

- `CustomToString()` now takes optional `IController` parameter; returns "CV Histogram" / "CV 2D Histogram" for `AreaGraphController`, plain versions otherwise
- Added resource strings in all 3 locales, verified Japanese/Chinese match menu text
- Added `histogram` <-> `histogram2d` sibling pairing in `GetSiblingGraphType` so separated histograms tab together
