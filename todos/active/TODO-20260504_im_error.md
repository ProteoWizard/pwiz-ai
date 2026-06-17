# TODO-20260504_im_error.md

## Branch Information
- **Branch**: `Skyline/work/20260504_im_error`
- **Base**: `master`
- **Created**: 2026-05-04
- **Status**: Code complete; preparing PR (local prep + self-review before push)
- **GitHub Issue**: [#4183](https://github.com/ProteoWizard/pwiz/issues/4183)
- **Source Issue**: [skyline.ms #774](https://skyline.ms/home/issues/issues-details.view?issueId=774)
- **PR**: [#4301](https://github.com/ProteoWizard/pwiz/pull/4301) (opened 2026-06-14, base master)
- **HEAD**: `35447af24` (2nd master sync, 0 behind origin/master as of 2026-06-13). Commits
  since 1st merge: `3754a390b` (apex-of-valid + scale source + decode guard), `07f4ea1ef`
  (Full Scan CCS-error target + golden refresh), `35447af24` (merge origin/master, 9 commits,
  no conflicts). Post-merge green: apex-of-valid + v19-compat unit tests, FullScanGraphTest,
  IonMobilityTest. Full fr suite running separately (developer) to surface other stale goldens.

## Objective

Add a precision/error sense to ion mobility filtering during chromatogram extraction,
parallel to the existing mass-error machinery on the m/z dimension.

Per JohnF (skyline.ms #774): the intensity center of gravity of IM values across the IM
extraction band, compared against the target IM, surfaced to the user. Originally framed
as **% error in IM/CCS**; see design pivot below.

## Design pivot (2026-05-08, commit `d20822236`)

The model was inverted from storing **per-peak/per-time error percentages** to storing
**absolute observed IM (raw units) and observed CCS (sq Å)**, with the error percent
**derived at report time** in `TransitionResult`. Rationale:

- Storing the absolute observed value is more useful and future-proof (graphs, QC) than a
  pre-divided percentage, and lets the target change without recomputing the cache.
- **Per-scan reduction** = center-of-gravity over the **linear bin index** of the
  (IM → summed intensity) histogram, not a raw average of IM values. This avoids the
  non-linear-IM averaging trap (e.g. 1/K0), where averaging mobility values directly is
  not physically meaningful.
- **Per-peak reduction** = COG over the RT-index across the peak window.
- **Target CCS** comes from the active reader's IM→CCS converter applied to the target IM,
  not from a stored `CollisionalCrossSectionSqA`.

## Surfaced columns (Document Grid, `TransitionResult`)

- **Observed Ion Mobility** (raw units) — `ObservedIonMobility`
- **Observed CCS** (sq Å) — `ObservedCcs`
- **Ion Mobility Error Percent** — derived: `100 * (observed - target) / target`
- **CCS Error Percent** — derived likewise against converter-derived target CCS

Plus: **observed IM visualized in the Full Scan graph** (commit `a080538e7`).

**Important user-facing caveat**: `ObservedCcs` only populates when the source file exposes
the vendor IM→CCS conversion. Open formats (mzML, mz5) do not, so Observed CCS / CCS Error
will be blank for those — by design, asserted in the functional test.

## Scope

**In scope (done):**
- Data path: extraction → cache → ChromPeak / TransitionChromInfo → Document Grid columns
- Cache format bump v19 → v20 (per-time-point observed IM stored as scaled integers;
  `ChromPeak` struct 52 → 60 bytes); v19 caches still load (compat test)
- idotp quality guards on observed-IM extraction (isotope-envelope + tiered windowed)
- FAIMS gate (no spurious values when the filter is a single CV, not a scanned band)
- Tests across drift time, 1/K0, FAIMS CV

**Deferred (track separately):**
- Graph panes parallel to `MassErrorHistogramGraphPane`, `MassErrorPeptideGraphPane`,
  `MassErrorReplicateGraphPane` (i.e. `IonMobilityErrorHistogramGraphPane` etc.)
- AutoQC tracking utility (called out in PR description as motivation)

## Implementation status

### Phase 1 — Accumulation [DONE]
- [x] `IntensityAccumulator` reduces per-scan IM via COG over linear bin index
- [x] Wired from `SpectrumFilterPair`; gated on non-FAIMS and IM filter present

### Phase 2 — Per-spectrum delivery [DONE]
- [x] `ExtractedSpectrum` carries observed IM; `SpectrumFilterPair.FilterSpectrumList` populates

### Phase 3 — Persistence [DONE]
- [x] `ChromCollector` / `TimeIntensities` carry observed-IM lists; transforms preserve them
- [x] Cache v19 → v20; protobuf field 6 reused as `observedIonMobilities` (float)
- [x] `ChromData.Interpolate` rebuilds from `RawTimeIntensities` so observed IM survives
- [x] Per-peak observed IM/CCS on `ChromPeak`; per-peak COG-RT-index over the window
- [x] `TransitionChromInfo.ObservedIonMobility` / `ObservedCcs`; `Equivalent`/`EquivalentTolerant` extended
- [x] CCS computed at peak detection via the active reader's converter

### Phase 4 — Reporting [DONE]
- [x] `ObservedIonMobility`, `ObservedCcs`, `IonMobilityErrorPercent`, `CcsErrorPercent` columns
- [x] Captions + tooltips in resx/Designer (English; ja/zh-CHS handled by translators)
- [x] Observed IM visualized in Full Scan graph
- [x] Regenerated report column reference docs

### Phase 5 — Tests [DONE]
- [x] `IntensityAccumulatorTest` — COG weighted-mean reduction
- [x] `ChromPeakTest` — observed IM/CCS round-trip, scale helpers, v19 cache compat, interpolate/truncate preserve
- [x] `ChromTransitionTest` — missing-observed-IM flag
- [x] `IonMobilityUnitTest.TestFaimsGateSuppressesObservedIonMobilityTracking`
- [x] Functional `IonMobilityTest` — observed IM populates after IM-filtered reimport
- [x] `PerfMeasuredInverseK0` — observed IM assertion on real 1/K0 data
- Verified green this session: build (Debug x64), IntensityAccumulator, FAIMS gate, v19 compat,
  functional IonMobilityTest

### Phase 6 — Release notes [N/A on branch]
- Skyline release notes are generated at Skyline-daily release time from commit messages
  (per ai/docs/release-guide.md) and posted to the skyline.ms wiki/announcements — there is
  no per-feature release-notes file in the repo. Ensure the squash-merge commit message is
  user-facing and descriptive; that is the release-note source material.

## Self-review + master sync + bug fixes (2026-06-10/11)

- Merged `origin/master` (branch was 61 behind). One conflict, `ChromCollector.cs`,
  resolved by combining master's `_ownsTimes` single-time-mode guards with this branch's
  observed-IM handling. Merge commit `7e7ae6650`. Built + tested green.
- `/pw-self-review` (fresh-context agent) ran clean-scoped against `origin/master...HEAD`.
  Findings and disposition:
  - **[HIGH] scale-0 corruption (real, fixed).** Per-time observed-IM encode scale was
    sourced from the optional CCS converter (`_ionMobilityConverter?.IonMobilityUnits`),
    which is null for IM data with no vendor CCS calibration (mzML/mz5). Fix: capture the
    data reader's units (`provider.IonMobilityUnits`) into `_ionMobilityUnits` and scale
    from that; converter remains optional and only gates observed *CCS*. Added a `scale==0`
    decode guard in `TimeIntensitiesGroup` (zero scale → null, never NaN/Inf).
  - **Per-peak reduction bug (found via test-first, fixed).** Strengthening the functional
    assertion to reject non-finite/zero observed IM turned `IonMobilityTest` red: per-peak
    observed IM was read at the intensity **COG-RT** scan, which (with background
    subtraction) can land on a shoulder/gap scan whose per-scan observed IM is 0/NaN even
    when the peak has valid IM. Per Pratt: *IM is only observable at the RT peak apex.* Fix:
    read observed IM at the **apex-of-valid** - the highest-intensity scan that carries a
    valid (>0) observed IM - so a gap at the literal max scan can't suppress an otherwise-
    measurable IM; report **null** (never a fabricated 0) only when no valid IM exists in the
    window. Extracted into testable `ChromPeak.ApexObservedIonMobility(...)`. Mass error still
    uses the intensity-weighted mean (unchanged, now its own loop). Red→green confirmed;
    apex-vs-COG rationale (SNR, interference robustness, physical meaning) discussed/defended.
  - **[MEDIUM] report vs Full Scan tooltip target CCS** — per Pratt, library/explicit CCS is
    ground truth, so `TransitionResult.CcsErrorPercent` (stored CCS) is correct; the Full
    Scan tooltip's `converter(targetIM)` target should be aligned to it. **Still TODO.**
  - [LOW] `MissingObservedIonMobility` flag written but never read — defer.

### Tests added/changed this session
- `IonMobilityTest`: assertion now requires observed IM finite & positive (the red→green
  verifier for the apex-reduction bug).
- `ChromPeakTest.TestObservedIonMobilityZeroScaleDecodesToNull`: decode guard verifier.
- `ChromPeakTest.TestApexObservedIonMobilityOfValid`: apex-of-valid reduction (normal,
  gap/NaN at max → fallback to strongest valid scan, none-valid → null, windowing).

## Full Scan tooltip CCS target + property-sheet golden (2026-06-12)

- **[MEDIUM] fixed.** Per Pratt: the "error" is observed vs *what we were told to filter on*.
  Target CCS = the given library/explicit CCS (ground truth); if only IM was given, no CCS
  error. Both `GraphFullScan` spots (dotted-line tooltip + properties pane) now compute CCS
  error against the given CCS (`imFilter`/`chromInfo.IonMobility.CollisionalCrossSectionSqA`),
  matching `TransitionResult.CcsErrorPercent`, instead of `converter(targetIM)`.
- **`FullScanGraphTest` golden updated** (`ObservedIonMobility` now populates for the Waters
  mzML data: 3.45/3.381/5.727 msec, each inside its IM filter range and near target - real-
  data confirmation of the scale fix; no `ObservedCcs` since the format has no CCS converter).
- **`FullScanGraphTest` was already red on the branch** (verified at pre-merge tip
  `b1764e48c`, merge `7e7ae6650`, and post-fix `3754a390b`): the branch's own observed-IM
  Full Scan feature (`a080538e7`) added `ObservedIonMobility` and shifted the precursor
  `PeakRetentionTime` to 32.95 but never updated this golden. NOT a merge effect and NOT my
  fix - the golden was stale (33.03) since `a080538e7`. (An earlier confident "the merge
  shifted RT" guess was wrong; values were verified across all three commits.) My fix's only
  effect here: the *product* pane's observed IM now appears (3.45) where it was suppressed.
- **Open:** other branch functional tests may be similarly red from the observed-IM feature
  without golden updates - a broader sweep is warranted before the PR.

## Self-review v2 + SONAR fix (2026-06-13/14)

- Fresh `/pw-self-review` on the full `origin/master...HEAD` diff confirmed the apex-of-valid,
  Full Scan CCS-target, and v19/proto/concurrency fixes correct.
- **Honesty correction:** the scale-SOURCE change (`_ionMobilityConverter?.IonMobilityUnits`
  → `provider.IonMobilityUnits`) is a **no-op** - both resolve to
  `_ionMobilityFunctionsProvider?.IonMobilityUnits ?? none`. The real "0 observed IM" fix was
  apex-of-valid. Verified `MsDataFileImpl.IonMobilityUnits` (line 722) reports real units
  independent of CCS conversion, and the extraction path always has a `DataFileInstrumentInfo`
  (`SpectraChromDataProvider.cs:133`), so converter-less mzML IM data already gets the right
  scale - the first review's "scale-0 HIGH" was a false alarm. Keep the change (clearer intent)
  + decode guard (backstop); make the PR description accurate rather than rewrite the commit.
- **Resolved the long-standing pre/post-cache question:** the per-peak `ChromPeak` reduction
  reads the **in-memory** `InterpolatedTimeIntensities` (`PeakIntegrator.cs:84/101`), not a
  cache round-trip. So the decode guard (cache-path only) does NOT mask anything at peak level.
- **[MEDIUM] SONAR fixed.** `trackIonMobility` excluded only FAIMS, so Waters SONAR
  (`waters_sonar`, m/z filtering on IMS hardware) was tracked and surfaced a meaningless
  per-peak ObservedIonMobility (in-memory, so the scale-0 guard didn't hide it). Fix: gate
  extraction on `RawTimeIntensities.IsTrackedObservedIonMobilityUnit(units)` (true only for
  drift time / 1-K0 - same source of truth as the cache scale), so FAIMS, SONAR, none, unknown
  are all excluded and the extraction gate can't disagree with the scale. Units come from the
  data file, so robust without a CCS converter.
  - Tests: predicate added to `ChromPeakTest.TestObservedIonMobilityScaleHelpers`;
    `PerfWatersSonarTest` now asserts no transition carries observed IM (nightly perf verifier).
  - Verified: build, scale-helpers + FAIMS-gate unit tests, IonMobilityTest, FullScanGraphTest
    all green (drift path unbroken). Committed `c1acdb2bc`.
  - **`PerfWatersSonarTest` red→green PROVEN on real Waters SONAR data**: pre-fix gate surfaced
    5 spurious observed-IM values (Actual:5 ≠ 0 → red); fixed gate → 0 (green, 6.7s).

## PR #4301 + Copilot round 1 (2026-06-14)
- Pushed; opened [#4301](https://github.com/ProteoWizard/pwiz/pull/4301) (base master). Branch
  later got a GitHub "Update branch" master-merge (`e0395aab9`); pulled + rebuilt green.
- Copilot review (9 comments, no low-confidence section). Addressed in `845f207ce`:
  - CacheFormat v20 history comment (observed IM/CCS, not "ion mobility error")
  - TimeIntensities.ObservedIonMobilities doc comment (FAIMS + SONAR + non-tracked units)
  - PauseAndContinueForm no-link visibility reset (reused-instance label bug)
  - 3 threads replied + resolved; 6 ja/zh-CHS auto-generated-help comments replied with the
    translation-process rationale and left unresolved for the human reviewer.
- Fresh Copilot re-review requested after the fix commit.

## Copilot round 2 (2026-06-14, commit `1b5b7329d`)
- 2nd review (developer-requested) found 3 NEW real findings, all fixed:
  - **CI-breaker:** `PerfMeasuredInverseK0.cs:126` had a `PauseTest()` - forbidden outside
    TestFunctional.cs by CodeInspectionTest (Level.Error). Switched to
    `PauseForManualTutorialStep()` (sanctioned wrapper; keeps the instructions).
  - Full Scan properties pane set `PeakRetentionTime` even for an empty chrom info (showed a
    misleading 0) - now guarded on `!chromInfo.IsEmpty`.
  - Properties pane re-ran the vendor CCS conversion - now reads stored
    `TransitionChromInfo.ObservedCcs`, matching the Document Grid.
- **Process miss (owned):** I had not run `CodeInspection` before opening the PR; it would
  have caught the PauseTest. Confirmed it failed (1 failure), fixed, now green. Added
  CodeInspection to the pre-PR gate ([[feedback_run_codeinspection_pre_pr]]).
- 3 threads replied + resolved; Copilot re-requested.

## Stream read/write symmetry fix (2026-06-15, commit `0f71bd5b0`)
- Both my self-review v2 and Copilot flagged the legacy interpolated-stream asymmetry:
  `WriteToStream` skips null mass-error/observed-IM arrays per transition, but `ReadFromStream`
  read one for every transition when the group flag was set → desync on a *mixed* group.
- Per Pratt's suggestion: **`ReadFromStream` now honors the per-transition `MissingMassErrors`
  / `MissingObservedIonMobility` flags** (previously write-only), symmetric with the write skip.
  Backward-compatible (uniform groups have no Missing flags → unchanged). The dead flags are
  now read.
- Added `ChromPeakTest.TestInterpolatedTimeIntensitiesMixedGroupStreamRoundTrip` -
  **red→green proven** (pre-fix: transition after the gap was corrupted). Verified: build,
  new test, ChromTransition flag tests, CodeInspection, IonMobilityTest all green.
- 3 Copilot stream threads replied + resolved; Copilot re-requested.
- Also pending in the working tree (NOT mine - Pratt's ReSharper cleanups, build clean):
  redundant `(Label)` cast in `PauseAndContinueForm.cs`; redundant `null` arg in
  `IntensityAccumulatorTest.cs`.

## Remaining before merge
- [ ] Address any further Copilot findings on re-review
- [ ] Produce Release/test build for the requesting user
- [ ] Consider no-converter IM test data to red→green the scale-source fix directly
      (current functional data has a converter, so that fix is verified by code + the
      decode-guard unit test, not yet by an end-to-end no-converter import)
- [ ] Push branch (fast-forward over stale remote)
- [ ] Open PR (`Fixes #4183`) → Copilot review → `/pw-respond`
- [ ] Produce Release/test build for the requesting user

## Decisions Log
- **2026-05-04**: Algorithm = intensity-weighted COG of IM across the extraction band.
- **2026-05-04**: Compute CCS during extraction (file present), not at report time.
- **2026-05-04**: Defer graph panes until the data path lands.
- **2026-05-08**: **Pivoted** to absolute observed IM/CCS storage; error % derived at report
  time. Per-scan COG over linear bin index (not raw IM average) to avoid non-linear-IM
  (1/K0) averaging. Target CCS from active reader's converter. (commit `d20822236`)

## Notes
- Long-standing request (skyline.ms #774, opened 2021-03-04 by Brian Pratt).
- POST-RELEASE PATCH phase: enhancement is master-only, no cherry-pick.
- IMoffset branch (`wip/im-window-offset`) is conceptually related (IM filter window
  machinery) but does not overlap with this error-measurement work.
