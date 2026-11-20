# TODO-20260707_modSiteLocalization.md

## Branch Information
- **Branch**: `Skyline/work/20260707_modSiteLocalization`
- **Base**: `master`
- **Created**: 2026-07-07
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: [#4391](https://github.com/ProteoWizard/pwiz/pull/4391)
- **Checkout**: `pwiz1`
- **Design plan**: `~/.claude/plans/tranquil-cooking-kurzweil.md` (key decisions embedded below)

## Objective

Modification-localization support: help the user pick the product ions that
distinguish positional isomers of a modified peptide (e.g. one phospho among
several serines). v1 = an **ion-selection assistant**.

## Confirmed design decisions

- **Scope v1** = ion-selection assistant only (#2 isomer deconvolution and #3
  localization scoring are future; leave clean hooks). Method-agnostic. Handle
  **K mods among N sites**, and **multiple ambiguous mod types at once**.
- **Site-determining ion**: a product ion of the current precursor whose
  `inSpanShift = Σ over mods [ mass(m) × (count of m's sites within the fragment
  span) ]` **varies across the isomer set**. Each ion is attributed to the mod it
  resolves.
- **Analytic, non-enumerating interactive path.** Marking a transition
  site-determining and computing its producing-set size factorizes per mod:
  - site-determining ⇔ for some mod, `min(k_m, inside_m) > max(0, k_m − outside_m)`
  - producing-set size = `∏_m C(inside_m, c_m) · C(outside_m, k_m − c_m)`
  Cost **O(L × numMods)** regardless of isomer count. Materialize isomers only for
  future #2/#3; that path is capped (`∏ C(nᵢ,kᵢ)` known up front) + run off-UI-thread
  via `ActionUtil.RunAsync` (NO async/await) + cached by (peptide, mods, settings).
- **Group** = peptides with same unmodified sequence + same *ambiguous*-mod
  composition (a mod is in the key iff C(nᵢ,kᵢ) > 1; determined/fixed mods like
  carbamidomethyl or single-Met oxidation are omitted). One key covers the full
  Cartesian isomer set. Forms differing only by a determined mod **share** a group
  (accepted). No new DocNode type.
- **UI surface**: a new toggle button `tbbSiteDetermining` in the "Pick Children"
  popup (`PopupPickList`), shown only when the precursor's peptide is localizable;
  when on, filters the choice list to site-determining ions (mirrors `tbbFilter`).
- **Reporting (v1 scalar)**: `ModificationLocalizationGroup` (string key) +
  `LocalizationIsomerCount` (int = ∏ C(nᵢ,kᵢ)) on the Document-Grid `Peptide` entity.
  Per-mod one-to-many breakdown is a later, descriptive-only follow-up.

## Key existing code to reuse (paths under pwiz_tools/Skyline)

- `Model/SequenceUtil.cs` `SequenceMassCalc.GetFragmentIonMasses(target, ExplicitSequenceMods)`
  — per-position mod mass already applied; use for exact m/z + collision checks.
- `Model/Transition.cs` `OrdinalToOffset`/`OffsetToOrdinal`/`IonType.IsNTerminal()`.
- `Model/TransitionGroup.cs` transition generation; `CalcTransitionLossesId` span/loss gating.
- `Model/Peptide.cs` `CreateDocNodes` / `ModificationStateMachine` (isomer materialization).
- `Model/DocSettings/Modification.cs` `ExplicitMod{IndexAA,StaticMod}` / `ExplicitMods`.
- `Controls/PopupPickList.cs` (+ `.Designer.cs`, `ControlsResources.resx`) — toggle-button pattern.
- `Controls/SeqNode/SrmTreeNode.cs` `IChildPicker`; `Controls/SeqNode/TransitionGroupTreeNode.cs`.
- `Model/Databinding/Entities/Peptide.cs` — reporting column pattern.

## Task breakdown

- [x] **T1 Analyzer** — `Model/Localization/SiteDeterminingIonAnalyzer.cs` (DONE, built,
      no warnings). API: ctor(SrmSettings, PeptideDocNode); `CanLocalize`, `IsomerCount`,
      `LocalizationGroupKey`, `IsSiteDetermining(Transition)`, `GetResolvedModification(Transition)`,
      `GetProducingSetSize(Transition)`, `GetProducingSetSizeAsInt`, `IsUniqueToPrecursor`.
      Reused `StaticMod.IsApplicableMod`; group key uses ASCII `*` not `×`. csproj updated.
- [x] **T1b Analyzer unit tests** — `Test/SiteDeterminingIonTest.cs` (DONE, PASSES): terminal
      unique run + m/z cross-check, interior non-unique, k=2, two-mod-type, non-localizable.
- [x] **T2 Picker capability** — `ISiteDeterminingIonPicker` added to `SrmTreeNode.cs`
      (IChildPicker untouched); implemented on `TransitionGroupTreeNode` with cached analyzer.
- [x] **T3 PopupPickList button** — `tbbSiteDetermining` toggle added (Designer + code),
      image `Resources.Ions_fragments`, filter in `ShowChoices()`, tooltip string
      `PopupPickList_SiteDetermining_ToolTip` in ControlsResources.resx + .Designer.cs. Builds green.
- [x] **T4 Reporting columns** — `ModificationLocalizationGroup` (string) +
      `LocalizationIsomerCount` (long?) on `Model/Databinding/Entities/Peptide.cs`, shared
      memoized analyzer, small-molecule guarded. Added required entries to ColumnCaptions.resx
      + ColumnToolTips.resx (+ .Designer.cs); ColumnCaptionLocalizationTest passes. Builds green.
- [x] **T5 Functional test** — `TestFunctional/SiteDeterminingIonFunctionalTest.cs` (DONE, PASSES
      en+fr). Added 3 public PopupPickList test hooks. Asserts filtered set == analyzer
      IsSiteDetermining; button hidden for non-localizable peptide.
- [x] **T6 Regression gate** — PASS. Full solution build (41.5s); existing `TestNeutralLoss`
      (PopupPickList) PASS; `ColumnCaptionLocalizationTest` 5/5 PASS; new unit + functional
      tests PASS on committed tree.
- [x] **T7 Commit locally** (no push): `5343ce9888` (T1–T4), `176319bfc1` (T5). Not pushed.

## Progress log

- 2026-07-07: Branch created from master (pwiz1). TODO created. Starting T1 (analyzer).
- 2026-07-07: T1–T4 done, each built green + tested. **Checkpoint commit `5343ce9888`**
  (15 files, +790) — analyzer, picker+popup button, reporting columns, caption entries.
- 2026-07-07: T5 functional test done (PASS en+fr). **Commit `176319bfc1`** (3 files, +241).
- 2026-07-07: **T6 regression PASS** (build + existing pick-list test + caption tests + new
  tests). Feature v1 COMPLETE on branch, NOT pushed. Awaiting dev: self-review / push / PR.

## Post-manual-review fix (2026-07-07) — filter semantics too permissive
- Manual test on real phosphopeptide `K.NDESSSSSIIFAEPTPEK` (5-serine run S4-S8 + T15,
  phospho on S6): the toggle flooded the list (y4-y14 all shown). Root cause: filter used
  `IsSiteDetermining` = "distinguishes ANY pair", which lights up nearly every ion when
  candidates are spread out. Analyzer math is correct; the DEFINITION was wrong for UX.
- The functional test missed it because it was **circular** (filtered set == analyzer's own
  `IsSiteDetermining`). Lesson: assert against independent, hand-picked expectations.
- **Decision:** filter now uses **`IsUniqueToPrecursor`** (producing-set size 1 = ions no
  other placement can produce). Empty is expected for unresolvable placements (e.g. interior
  of a serine run) → show a **"no ions uniquely localize" hint**, not a blank list.
- [x] **F1** Picker predicate → `IsUniqueToPrecursor` in `TransitionGroupTreeNode`. DONE.
- [x] **F2** Empty-state hint label `lblSiteDeterminingEmpty` in `PopupPickList` + resource string
      `PopupPickList_SiteDetermining_NoneFound`; tooltip reworded; test hook `SiteDeterminingEmptyHintVisible`. DONE.
- [x] **F3** Unit test: interior serine-run (AASSSAK) → no unique ion; separated (SAAAAATAAK) → b-ion unique. DONE.
- [x] **F4** Functional test rewritten non-circular (resolvable / unresolvable-empty / non-localizable). DONE.
- [x] **F5** Build + both tests PASS. **Commit `d2079fe383`** (8 files, +253/-59). Not pushed.

## Live verification (Skyline UI driver, 2026-07-07)
- Opened the dev's real doc `V0088-02_Q9BQI3_PRM_phos.sky.zip` in the freshly-built pwiz1 Skyline.
- **Resolvable case CONFIRMED**: `AAIELPSLEVLS[+80]DQEEDR` (phospho S12; candidates S7/S12). Toggling the
  new button reduced the full flooded list (6 precursor isotopes + full b/y ladder) to exactly the
  **y7-y11** series (+ their -98 forms) — precisely the ions containing S12 but not S7, i.e. that
  uniquely localize the phospho. Flood -> clean, correct set.
- Empty case (interior serine of NDESSSSS run) is covered by the passing functional test; a clean live
  screenshot was not captured due to UI-driver coordinate instability on the small popup toolbar button.

## Follow-up on open PR #4391 (2026-07-13)
- Requested: a transition-level boolean Document Grid column flagging whether a transition is
  mod position-specific for its peptide. Confirmed semantics = **unique to this localization**
  (`analyzer.IsUniqueToPrecursor`), matching the Pick Children toggle.
- DONE: `Transition.UniquelyLocalizing` (bool) -> `Precursor.Peptide.IsUniquelyLocalizing(DocNode.Transition)`
  reusing the memoized analyzer; ColumnCaptions/ColumnToolTips entries; functional-test assertion (b3 TRUE, b7 FALSE).
  Built green; caption coverage + functional tests pass. **Commit `5c03faaabf`** (7 files, +92/-2). Local, not pushed yet.
- PR #4391 is OPEN (1 Copilot review present, not merged) -> committed as a NEW commit on the branch.

## Deferred / follow-ups (v1 out of scope, hooks left in place)
- Hover-tip in the popup naming which mod an ion resolves: `GetSiteDeterminingTip` exists but
  is not yet wired into `PopupPickList` tooltips (kept low-risk).
- Per-mod one-to-many `LocalizationGroups` reporting breakdown (v1 ships scalar key + count).
- #2 isomer deconvolution (A·x=observed) and #3 localization scoring — analyzer output feeds both.
- Analyzer instance cached per tree node; not invalidated on in-place doc change (fine for the
  transient popup, revisit if reused elsewhere).
- Ambiguity considers static (structural) mods only; heavy/isotope + crosslinkers excluded.
  Non-disjoint mod site-sets (two mods competing for one residue) noted as an edge to watch.

## Session 2026-11-02 - merge master + Copilot review fixes
- pwiz1 was parked on `Skyline/work/20260820_dpiAwareness` with the uncommitted DPI sweep
  harness. Parked it as `git stash` entry "dpiAwareness local sweep harness WIP (parked
  2026-11-02 for modSite session; never commit)" and moved the four untracked
  `TestFunctional/Dpi*ProbeTest.cs` / `DpiPaneSweepTest.cs` files to
  `ai/.tmp/sessions/20261102-modsite/dpi-probes/` (SDK-style csproj globs would have compiled
  them against the stashed harness). **Restore both when switching pwiz1 back to the DPI branch.**
- Merged `origin/master` (424 commits behind; PR showed CONFLICTING). All 13 conflicts were
  whole-file: master's LF normalization (#4789) + BOM pass + SDK-style csproj conversion. Resolved
  by taking master's files and re-applying the branch delta (`git apply --ignore-whitespace`);
  the three csproj edits are dropped (globs pick up the new files). `git add --renormalize` so the
  branch's files are stored LF like master. Merge commit `14e7697e64` (local, not pushed).
  Branch diff vs master is back to 15 files, +1316/-8.
- Copilot review (2026-07-08) threads, all addressed in the working tree (uncommitted):
  - `MultiplyClamped` overflow: compare `a > MAX_COUNT / b` before multiplying.
  - `Peptide` analyzer memo not document-sensitive: replaced the computed-flag fields with
    `CachedValue<SiteDeterminingIonAnalyzer>` (same `CachedValue.Create(DataSchema, ...)` pattern as
    `Transition._results`), so it recomputes when `SrmDocument.ReferenceId` changes.
  - `lblSiteDeterminingEmpty` missing `AutoSize = false` in the Designer: added.
- Build (net10.0-windows, dotnet) green in 183 s. Tests PASS: TestSiteDeterminingIonAnalyzer,
  TestSiteDeterminingIonFunctional (en + fr), ColumnCaptionLocalizationTest (5), TestNeutralLoss.
  Log: `pwiz1/pwiz_tools/Skyline/bin/staging/Debug/TestSiteDeterminingIonAnalyzer,...,TestNeutralLoss.log`.
- Fix commit `5171e451e0` (local). Still to do: push (merge + `5c03faaabf` UniquelyLocalizing
  column + fixes), resolve the 4 Copilot threads, add the `skyline` label + `skyline:` title prefix
  and the TODO link + UniquelyLocalizing bullet to the PR description, pre-push inspection gate.

## Scope expansion 2026-11-02 (dev decision: same PR, not a follow-up)
Rationale from the dev: without a document-wide way to select unique ions the PR has little
practical use, and the human review (the real time-limiting step) has not happened yet, so one
review of the whole feature is cheaper than two.

### Design (implemented, awaiting build/test)
1. **Targets-tree badge**: `SequenceTree.ImageId.fragment_unique` / `fragment_lib_unique`, built at
   ImageList creation by `AddLocalizingBadge` - a copy of Fragment / FragmentLib with a 5x5 pixel
   "U" (blue, (0,90,200)) in the upper-right corner, set pixel by pixel so it stays crisp at 16 px.
   `TransitionTreeNode.TypeImageIndex` picks it when `IsUniquelyLocalizing`. Decoys never get it.
2. **Analyzer ownership moved to `PeptideTreeNode.SiteDeterminingAnalyzer`** (cached by settings
   reference, reset in `OnModelChanged`); precursor and transition nodes ask the parent. This also
   closes the "analyzer never invalidated" item below. Null when the peptide is not localizable.
3. **Tooltip**: `TransitionTreeNode.RenderTip` gains an optional mod name and adds a
   "Uniquely localizes: <mod>" row (`SeqNodeResources.TransitionTreeNode_RenderTip_Uniquely_localizes`).
4. **Document-wide selection = Transition Settings > Filter > Product ion selection group:
   "Include ions that localize modifications"** (`cbLocalizingIons`). Model:
   `TransitionFilter.IncludeLocalizingIons` ([Track], attr `include_localizing_ions`, ctor param with
   default, `ChangeIncludeLocalizingIons`, Equals/GetHashCode), `DocumentFormat.VERSION_26_12`,
   `Skyline_Current.xsd`, `PropertyNames.TransitionFilter_IncludeLocalizingIons`.
   Auto-pick: `TransitionGroup.GetTransitions` builds one analyzer per precursor (new ctor
   `(settings, Peptide, ExplicitMods)`) when the setting is on, and `TransitionFilter.Accept` gets a
   `localizingIon` flag that bypasses the fragment range (start/end finders and the "m/z > precursor"
   start m/z) but NOT the precursor exclusion window / DIA window. Ion types and product charges
   from the tab still apply (deliberate: the user controls them in the same tab; the tooltip says so).
   `SrmSettingsDiff.DiffTransitions` already keys off `Filter.Equals`, so no change there.
   The settings dialog grew: groupBox1 222->246, tabControlPeptidesSmallMols 331->355 in en + ja +
   zh-Hans resx (the localized resx override sizes, so all three had to move).
5. **Tests**: `TestIncludeLocalizingIonsSetting` in the functional test (range "m/z > precursor":
   b3 absent -> present after the checkbox; every selected ion below precursor m/z is unique; serine
   run gains nothing; tree icon fragment_unique for b3 and plain for b7; `AssertEx.Serializable`).
   `SerializeTransitionFilterTest` gained the attribute round trip.

### 2026-11-02 results
- Build green (net10). Tests PASS: TestSiteDeterminingIonAnalyzer, TestSiteDeterminingIonFunctional
  (en + fr), SerializeTransitionFilterTest, TestNeutralLoss, SchemaDocumentsTest (2),
  DocumentSerializerTest (3), AuditLogListTest (2), TestAutoSelect, ColumnCaptionLocalizationTest (5),
  CodeInspection.
- Round-trip lesson: the functional test's PHOSPHO was a *variable* mod; the second peptide modified
  through EditPepModsDlg kept the variable instance while the document settings held the explicit
  copy, so `AssertEx.Serializable` compared unequal (IsVariable true vs false) with identical XML.
  Pre-existing behavior, unrelated to this PR; the test now uses a plain structural mod.
- The form-screenshot switch of the test wrapper (`-Forms ... -FormScreenshotDir`) does not work on
  master: the runner argument behind it only exists in the uncommitted DPI harness (stashed). The
  icon was verified instead by rendering the exact badge pixel ops in Python
  (session scratchpad `badge_preview.png`).
- Committed 2026-11-02 (each approved by the dev): `297dd16b78` inspection fixes, `868c057d0b`
  badge + tooltip + filter setting + toggle removal, `668ac8242b` Library Match tooltip row,
  `7531719a31` code review fixes. Pushed 2026-11-02 evening on the dev's request together with
  `14e7697e64` (merge of master) and `5171e451e0`. The PR got the `skyline` label, the `skyline:`
  title prefix and a rewritten body. The 4 Copilot threads (MultiplyClamped overflow, two on the
  Peptide entity memoization, the removed pick-list label) were answered and resolved over the
  GitHub API (the harness auto-mode classifier denied that call; it went through once the dev
  switched the session to manual mode and approved it).
- Pre-push gate as run: build + TestSiteDeterminingIonFunctional (en + fr),
  TestSiteDeterminingIonAnalyzer, SerializeTransitionFilterTest, TestNeutralLoss, TestAutoSelect,
  TestLibraryRankedNeutralLosses, CodeInspection; `Build-Skyline.ps1 -QuickInspection` (Skyline +
  Test projects: no findings in PR files; its 423 issues are the known unresolved-symbol noise in
  Shared/* plus pre-existing items; TestFunctional was not in its project set because it picks
  projects from uncommitted changes). `tcinspect.ps1` could not be used: inspectcode exits 4
  right after loading the solution on this machine, before any file output, both before and
  after clearing the stale SkylineTester obj - unexplained, worth a look in a later session.

### Dev review of the first build (2026-11-02, screenshot of the Pick Children popup)
1. **Badge missing in the Pick Children popup.** `TransitionGroupTreeNode.GetPickTypeImage` always
   asked `TransitionTreeNode.GetTypeImage` for the plain icon. Fixed: `GetTypeImage` takes the
   uniqueness flag and the precursor node passes `IsUniquelyLocalizing(child)`. Test: pixel compare
   of the b3 / b7 pick-list images against `fragment_unique` / `fragment` (`AssertSameImage`;
   `ImageList.Images[i]` returns a fresh copy, so reference equality is useless).
2. **Union vs intersection for the filter checkbox - kept union.** `TransitionFilter.Accept` is
   already (exclusion window AND types AND charges) AND (range OR special ions); localizing ions
   join the OR with the special ions. An AND with the range could never add an ion (anything in the
   range is already picked); it would only remove non-unique ions, i.e. an "only localizing ions"
   restriction - a different feature, and empty for non-localizable peptides unless scoped. Can be a
   separate option later if method capacity ever matters.
3. **Pick Children toggle removed (dev decision).** With the badge in the popup and the document
   setting for bulk selection, the toggle only narrowed a long unfiltered list, not worth its
   footprint. `PopupPickList.cs/.Designer.cs` and `ControlsResources.resx/.designer.cs` are back
   at master (also drops the `VisibleChoices` test hook); `ISiteDeterminingIonPicker` deleted from
   `SrmTreeNode.cs`; `TransitionGroupTreeNode` keeps one public `IsUniquelyLocalizing(DocNode)`
   (renamed from `IsSiteDeterminingChoice`; `CanShowSiteDeterminingIons` / `GetSiteDeterminingTip`
   gone). Functional test: the three per-peptide methods now assert on `IsUniquelyLocalizing` and the
   pick-list icons instead of the toggle (`AssertNoUniquelyLocalizingIons` helper). The
   "Confirmed design decisions" / T3 entries above describing the toggle are historical.
4. **Library Match tooltip (dev request, 2026-11-02).** The peak tooltip
   (`GraphSpectrum.ToolTipImplementation`) now takes the owning `SpectrumGraphItem` and adds a
   "Uniquely localizes:" row (`GraphsResources.GraphSpectrum_ToolTip_Uniquely_localizes`) per
   uniquely localizing matched ion, naming the ion too when the peak has several matched ions.
   `SpectrumGraphItem` builds a `SiteDeterminingIonAnalyzer` lazily from its `PeptideDocNode` +
   `SrmSettings` (gated on `RulersApplicable`, null unless `CanLocalize`) and exposes
   `GetLocalizedModificationName(MatchedFragmentIon)` (ordinal -> cleavage offset via
   `Transition.OrdinalToOffset`). The analyzer gained a `GetResolvedModification(IonType, int)`
   overload. The library's mod info is not a separate condition: the Library Match lookup is by
   modified sequence, so a shown spectrum already carries the document peptide's mods.
   **Deliberately NOT done** (dev: annotations + their context menu are already overloaded): no
   marker in the peak annotation labels. If team feedback is positive it is one line in
   `AbstractSpectrumGraphItem.GetLabel` using the same lookup. Test: `TestLibraryMatchTooltip`
   renders the tip off screen on a synthetic 2-peak spectrum (b3 / b7 m/z of the resolvable
   precursor) ranked with `NewLibraryRankedSpectrumInfo`, no library file needed.
   Not run: `TestTargetedMSMSTutorial` asserts exact tooltip text, but its peptides carry no
   ambiguous mod, so the analyzer is null there and no row is added; the tutorial zip is not
   local and needs an internet-enabled run.

### /code-review medium on the branch (2026-11-02, before push) - 9 findings, 7 fixed, 2 dropped
- **Real bug (fixed)**: `SpectrumRanker.ApplyRanking` called `TransitionSettings.Accept` without
  the localizing flag, so with library pick = `filter` a unique ion outside the range was never
  ranked and (since that mode only picks ranked ions) never auto-selected. Fix: both `Accept`
  overloads take `SiteDeterminingIonAnalyzer localizingAnalyzer = null` instead of a bool and
  check `IsUniqueToPrecursor(type, offset)` themselves after the range test; `SpectrumRanker`
  builds the analyzer once per ranking (`LocalizingAnalyzer`), `TransitionGroup.GetTransitions`
  passes its own; `OtherLabelTypesAllowed` lost the bool. Test: `TestLibraryFilteredRanking`
  (synthetic spectrum, pick = filter, b3 ranks only with the setting on; b7 always).
- Fixed: multi-mod ions name every resolved mod (`GetResolvedModifications`,
  `GetUniquelyLocalizedModificationNames(Transition|IonType,int)` joined with ", ").
- Fixed: pick-list tip (`PickTransitionTip`) gets the localization row and `HasTip` is true for
  localizing ions (before: only for losses).
- Fixed: analyzer ctor `SrmSettings` parameter removed (never read), `GetProducingSetSizeAsInt` and
  the `TryGetSpan(Transition)` overload removed, `CreateIfLocalizable(Peptide, mods | nodePep)`
  factory replaces four copies of "build, keep only if CanLocalize".
- Fixed: `PeptideTreeNode` caches the analyzer by `DocNode` reference, not settings reference.
- Dropped: disposing the badge `Bitmap` after `ImageList.Images.Add` - the list keeps the original
  reference until its handle is created; same lifetime as the 34 `Resources.*` icons there.
- Dropped: hoisting `IsUniqueToPrecursor` out of the adduct loop - moot once `Accept` evaluates it
  lazily after the range test.
- tcinspect.ps1 first run aborted (inspectcode exit 4) because the pre-build of SkylineTester.csproj
  failed on duplicate assembly attributes from a stale `SkylineTester/obj/x64/Release`; deleted it
  and reran (log `ai/.tmp/sessions/20261102-modsite/tcinspect2.log`).

## Scope items from the data investigation (2026-11-02, dev decision: implement now)
Source: `ai/.tmp/sessions/20261102-modsite/data-investigation-PR4391.md` (Panorama Public HRI
phospho PRM dataset, PXD074030; local copy under `D:\Users\RitaCh\Downloads\V0088-02_...(3)`).
Both items are cheap, analytic, and need no results data. More datasets are being collected to
look for further common patterns before the larger analysis tools are scoped.

Test data provenance: Panorama Public experiment "BayBioMS - Zhang_Schuler_HRI" (2026),
ProteomeXchange PXD074030, https://panoramaweb.org/Panorama%20Public/2026/BayBioMS%20-%20Zhang_Schuler_HRI/project-begin.view
HRI = heme-regulated inhibitor / EIF2AK1, UniProt Q9BQI3; PRM phosphosite monitoring, 40
replicates, library built by BiblioSpec from MaxQuant DDA results; raw PRM files on Panorama in
the RawFiles subfolder (40 x ~550 MB); publication not available as of 2026-11-18. The Skyline
document `V0088-02_Q9BQI3_PRM_phos_2026-02-02_16-17-30(3)` is the submitter's shared document
downloaded as-is (local copy on D:, untouched; all analysis ran on a copy).

- [x] **S1 Neutral-loss ions are never "uniquely localizing".** A phospho fragment minus H3PO4 has
      exactly the composition of the unmodified fragment minus H2O (HPO3 - H3PO4 = -H2O), so the
      m/z the analyzer calls unique to S4 (b4-98) is produced by every other isomer as b4-H2O. Seen in
      the data: b4-98 present in 37/38 files at the T15 peak, y5-98 "unique to T15" present in 38/38
      at the S4/S5 peak. The analyzer works on (IonType, cleavageOffset) and never sees losses:
      `GetProducingSetSize` / `IsUniqueToPrecursor(Transition)` ignore them, and
      `TransitionSettings.Accept(..., localizingAnalyzer)` is called per loss combination in
      `TransitionGroup.GetTransitions` with only (type, offset), so the loss form is auto-picked as a
      localizing ion too. Fix: thread the losses through (`TransitionDocNode.Losses` /
      `TransitionLosses` in `GetTransitions`; `MatchedFragmentIon` losses in the Library Match path)
      and return not-unique when any loss comes from an ambiguous modification (general rule: when
      mod mass minus loss mass is 0 or a generic loss such as H2O / NH3). Every consumer must follow:
      `Transition.UniquelyLocalizing` column, tree badge, tree and pick-list tooltips,
      `SpectrumGraphItem.GetLocalizedModificationName`, `SpectrumRanker` filter path. Add a unit test
      with a phospho loss (b4-98 of the S4 form is NOT unique; b4 phospho intact IS) and extend the
      functional test's setting case so a -98 ion is not added as a localizing ion.
- [x] **S2 Group ambiguity by mass shift, not by StaticMod instance.** Skyline ships "Phospho (ST)"
      and "Phospho (Y)" as two mods, so for VGTCLYASPEQLEGSEYDAK the analyzer sees candidates
      {T3, S8, S15} for the S/T forms and {Y6, Y17} for the Y form, and gives them different
      `LocalizationGroupKey`s although all five residues compete at one precursor m/z (data: the
      three nodes sit on one peak and the Y6/T3 "unique" ions are absent). Fix: in the ctor, group
      the explicit static mods by monoisotopic mass delta (rounded, e.g. 1e-3), and take candidate
      sites as the union of `IsApplicableMod` over every structural mod in the document settings
      with that same mass delta (the peptide's own ExplicitMods do not mention the sibling mod, so
      the analyzer needs `SrmSettings.PeptideSettings.Modifications.StaticModifications` back; the
      ctor's settings parameter was removed in the code review as unused). Key entry and tooltip name
      become the sibling names joined, or the mass delta; both peptides must produce the same key.
      Unit test: Phospho (ST) + Phospho (Y) in settings, Y-form and S-form of one sequence share a
      key and an isomer count of 5; a document with only Phospho (ST) keeps the old behavior.

### S1 + S2 implemented (2026-11-02, late evening)
- S1: every analyzer ion query takes `TransitionLosses` (overloads on `TransitionDocNode`,
  `(Transition, losses)` and `(IonType, offset, losses)`; the loss-free `Transition` overloads are
  gone so no caller can forget). `HasAmbiguousLoss`: a loss whose `PrecursorMod` has the mass shift
  of an ambiguous group makes the ion not unique (`GetProducingSetSize` = `IsomerCount`, resolves
  nothing). `TransitionSettings.Accept` / `TransitionFilter.Accept` gained `TransitionLosses losses`
  after the analyzer; `GetTransitions` passes the loop `losses`, `OtherLabelTypesAllowed` the
  matching node losses, `SpectrumRanker` `match.Losses`, `SpectrumGraphItem` `mfi.Losses`; tree,
  pick list and entity use the `TransitionDocNode` overloads. Tests: `TestPhosphoLossNotUnique`
  (b4 unique, b4-98 not, producing set = isomer count); functional fixture PHOSPHO now has an
  always-included H3PO4 loss and the setting case asserts no loss ion below the precursor m/z;
  `IsIon` / `FindIon` / the column check skip loss transitions.
- S2: ctor groups explicit mods by `GetMassShiftKey` (monoisotopic shift via
  `SequenceMassCalc.GetModMass`, rounded to 1e-3 Da as a long); candidate sites = union of
  `IsApplicableMod` over the placed entries plus every structural mod in
  `settings.PeptideSettings.Modifications.StaticModifications` with that shift. `AmbiguousMod`
  carries `Name` (sibling names sorted, joined with "/") and `MassShiftKey`; `LocalizationGroupKey`
  and the tooltips use `Name`, `Mod` stays the placed entry (tests `AreSame`). The `SrmSettings`
  ctor/factory parameter is back with a real use; `PeptideTreeNode` caches by node AND settings
  reference again. Test `TestSiblingModsShareAmbiguity`: Y5-form and S7-form of
  VGTCLYASPEQLEGSEYDAK share key and isomer count 5, b6 (T2+Y5) producing set 2; settings with
  only Phospho (ST) give 3 and a key without the Y entry.
- Gate: build + the 7-test batch green (analyzer, functional en, filter serialization,
  TestNeutralLoss, TestAutoSelect, TestLibraryRankedNeutralLosses, CodeInspection).

### CI follow-up (2026-11-03) - TestReportsHelpDocumentation
- TeamCity builds 22606/22609 failed only on `TestReportsHelpDocumentation`: it compares freshly
  generated Document Grid documentation to the checked-in `Documentation/Help/<lang>/Reports-*.html`,
  which lacked the three new columns. Regenerated with the test's record mode (flip `IsRecordMode`
  to true, run once, restore the file from git), 6 files / +18 lines (proteomic + mixed, en/ja/zh-Hans;
  small-molecule pages unchanged). Commit c771ba25dc, pushed. Lesson: any new Document Grid column
  needs this regeneration; the local 7-test batch does not include it.

## Possible further scope (2026-11-18, candidates for discussion with Brendan; not committed)
Context: Mike's 2026-11-17 feedback took Thesaurus off the table (scoring needs site-determining
fragments; stats did not hold up) and pointed at predicted RT + predicted fragment abundances with
isomer competition, with a peptidoform score as an Osprey research item. Skyline's user base is
MRM/PRM first, so every item below is acquisition-agnostic unless marked. Ranked by cost.

Tier A - extensions of the existing analyzer (no results data needed)
- [ ] **A1 Must-be-absent ions.** For isomer A, the union of the other isomers' unique ions.
      Report as "excluding" transitions (column + tooltip + pick list), subject to the same
      neutral-loss / isobar exclusion as S1. Display/explanation layer, not a score.
- [ ] **A2 Producing-set grade instead of a unique flag.** Expose `GetProducingSetSize` as
      "unique / discriminates N of M / shared" so partially discriminating ions (e.g. y13u =
      S4 or S5 only in NDESSSSSIIFAEPTPEK) are visible and sortable.
- [ ] **A3 Residue-class diagnostic ions.** Fixed table per modification (pY immonium 216.04,
      acetyl-K 126.09/143.12, HexNAc oxonium 204.09/138.06, precursor -98 => S/T not Y). Seed
      via Transition Settings > Special ions, or show in the spectrum annotation. Complements S2.

Tier B - library / input data (DDA-first, benefits every workflow that builds a library)
- [ ] **B1 Site-probability pass-through in BiblioSpec.** Read the search engine's localization
      column (MaxQuant "Phospho (STY) Probabilities", Proteome Discoverer ptmRS, MSFragger /
      PTMProphet localization, DIA-NN PTM.Site.Confidence / PTM.Q.Value, Spectronaut PTM
      probabilities) into a new blib column; show it in the Library Explorer and on isomer nodes;
      optional min-probability filter at library build so low-probability placements stop
      seeding unsupported isomer nodes (data finding 5). Schema change: coordinate with Matt.
- [ ] **B2 Isomer-group reporting.** `LocalizationGroupKey` / isomer count as Document Grid
      columns and a tree filter "show isomer groups", so a user can review groups in one place.

Tier C - chromatogram-based diagnostics (PRM/DIA; need results)
- [ ] **C1 Co-assigned peak warning.** Flag isomers of one group whose chosen peaks overlap in
      RT in a replicate (data finding 6); cheapest form of isomer competition.
- [ ] **C2 Purity / ratio-across-peak diagnostic.** Ratio of a unique (or nested-set) ion to a
      shared ion across the peak, per replicate; drift indicates a co-eluting isomer mixture
      (HRI peak A = S4/S5). Could be a graph overlay plus a per-peak metric.
- [ ] **C3 Predicted RT per isomer.** Show predicted RT delta per isomer vs the observed apex
      (Chronologer / Carafe / AlphaPeptDeep via Koina handle phospho; Prosit does not) and an
      "RT consistent" flag. Feasibility first: predict isomer RTs for the HRI peptides and compare
      with the measured apexes (S4/S8/T15 separated 0.5-1 min; S4/S5 co-elute).
- [ ] **C4 Predicted-spectrum dotp per isomer at the chosen peak.** Library dotp against a
      predicted spectrum for each isomer; delta best-vs-second as the localization margin.

Tier D - out of PR scope (Osprey)
- Isomer competition in search and a DIA-NN-style peptidoform score; Skyline reads the result.

### Unifying model (2026-11-18, Rita's idea: Bayesian posterior over isomers)
Treat each transition's producing set as the likelihood structure: under isomer k the ion is
expected intense if k produces it, at noise otherwise. Observed peak areas update a posterior
over the isomer group; the prior slot takes outside evidence (uniform, B1 site probability,
C3 predicted RT). Mixture form = the deferred deconvolution `area[t] = sum_k x[k] * expected[t,k]`
with non-negative fractions x; producing sets are the zero pattern of `expected`. Then A1
(must-be-absent) is the absent branch of the likelihood, A2 (grade) is the ion's information
content, C2 (ratio across the peak) is the posterior per time bin, C4 is the same model with
predicted intensities. Caveats: binary matrix + uniform prior reduces to Ascore; posterior is
uncalibrated (report as a score, calibrate later against shuffled/relocalized forms as DIA-NN
is believed to do); isobaric collisions (S1) must be modeled as shared in m/z space; "absent"
needs an expected intensity and a per-replicate noise floor.

### Dev observation (2026-11-18): weak unique ions make absence uninformative
In the HRI document every isomer of NDESSSSSIIFAEPTPEK has a weak y14 (long y ions and the
short serine-run b ions are weak in HCD whatever the site), so "y14 unmodified absent" says
nothing against S5. Absence is evidence only in proportion to the expected intensity under
the competing isomer. Consequences: A1 must not ship as a bare flag (needs an expected
intensity per ion; without one show "would distinguish S4/S5, too weak here"); for clustered
candidate sites the evidence lives in intensity shifts of the strong shared ions and in RT,
i.e. C3/C4, not in the unique ions; C2 should report an uncertainty, since it is a ratio of
weak ions.

### Noise-weighted presence score (2026-11-18, Rita's idea; first concrete scoring step)
Evidence per ion = log-likelihood ratio of its intensity against the noise level at the peak,
credited to the ion's producing set (shared ions contribute 0). Presence evidence needs only
S/N, so this works with no library and no predictor (PRM hand-built documents). Absence
evidence still needs an expected intensity (prediction, reference spectrum, or the same ion in
a clean replicate/peak), so it waits for C4. Per replicate, then aggregated across replicates
(HRI: y14u above noise in 33/38 files at peak A is strong in aggregate, marginal per file).
Propagate the same noise into the C2 ratio for error bars. Skyline side: transition peaks
store background; chromatogram outside the boundaries gives sigma per transition per replicate;
check whether an existing peak-scoring feature already exposes S/N before adding one.
Noise estimation (2026-11-18): reuse the per-transition part of `NextGenSignalNoiseCalc`
(`Model/Results/Scoring/NextGenFeatureCalc.cs`: median of points within 500 on each side of the
boundaries, log10(height/median)) but (1) add sigma = 1.4826 * MAD of the same points (level vs
fluctuation), (2) exclude the other isomers' peak regions from the noise window (HRI peaks are
~1.2 min apart), (3) handle zero-floored traces with sigma from successive differences
(median |x[i+1]-x[i]| / sqrt 2). Presence gate without sigma: shape correlation of the weak unique
ion's trace with the summed shared-ion trace across the peak (what Thesaurus/Osprey use; Skyline
has co-elution features already).

### Deconvolution as the peak-picking fix (2026-11-18, Rita's idea: use the fit quality)
The mixture fit `area[t] = sum_k x[k] * expected[t,k]` gives three things:
1. A peak-scoring feature: residual of the best non-negative fit per candidate peak (library
   dotp generalized to "best combination of isomer spectra"); report best-single-isomer residual
   and mixture residual, the gap flags a mixed peak; penalize the number of non-zero fractions.
2. Mixed-peak detection: fit per scan / time bin with a smoothness constraint; constant fractions
   = pure peak, drifting fractions = partially separated isomers (the y14u/y13u ratio generalized
   to all ions with expected intensities and noise weights).
3. Per-isomer chromatograms: fraction profile x_k(t) times the summed fragment trace is a trace
   that belongs to isomer k alone; pick peaks on those, so S4 and S5 get their own apex,
   boundaries and areas at peak A. Fits the existing data model (each isomer node already has its
   own boundaries/areas per replicate); no schema change.
Needs: expected intensities per isomer (binary matrix is under-determined when the unique ions
are weak, so predicted spectra are essential here), per-ion per-scan noise weights inside the
fit, and the residual trace shown as an interference chromatogram. Supersedes the deferred
"#2 isomer deconvolution" line with a concrete purpose: localization-aware peak picking.
Scope note (2026-11-18, Rita): with predicted spectra the fit is a generic mixed-peak resolution
problem (near-isobaric DIA co-elution, light/heavy cross-talk, in-source fragments, isomeric
lipids/metabolites in molecule mode), not an isomer feature. Proposed split: a generic module
(closed candidate set from the document + expected spectra + shared chromatograms -> fractions
over time + residual trace) with mod localization as the first client. Mod-specific layers stay
on top: candidate enumeration by the analyzer, isobar row merging (S1), relocalized decoys,
FLR, site display. Boundary: closed candidate sets only (open sets = library search = Osprey).
Molecule mode would run on library spectra (no predictor) and is a later step.

## Direction from Brendan (2026-11-19, relayed by Rita)
1. **Badge visibility.** The 5x5 "U" in the icon corner (`AddLocalizingBadge`) is not prominent
   enough; needs something clearly visible at a glance in the Targets tree and the pick list.
2. **Ions that limit the isomer set: keep going in that direction.** The producing-set view
   (which isomers an observed ion leaves possible, which ones it excludes) is the part to grow:
   A1 must-be-absent / A2 producing-set grade as UI, an "isomers still consistent with the
   observed ions" view per peptide and replicate.
3. **Scope = UI features for working with positional isomers, not quantitative methods.** The
   scoring model, decoy-trained localization score, deconvolution / per-isomer traces, predicted
   RT and spectrum items (C3, C4, the Bayesian and generic mixed-peak notes above) are parked as
   background for later work, not this PR's scope.
4. **Re-instate the Pick Children toggle** (`tbbSiteDetermining`, removed 2026-11-02 as a dev
   decision, see "Pick Children toggle removed"): the transition-selection dialog gets its
   site-determining filter button back.

Re-prioritized candidate list under this direction (no code on the data thread; for the PR agent):
- [ ] D1 Badge redesign (item 1).
- [ ] D2 Restore the Pick Children toggle (item 4); reuse the 2026-07 implementation and tests.
- [ ] D3 Isomer-set narrowing view (item 2): per peptide and replicate, list isomers consistent
      with the ions present above noise and those excluded by a must-be-absent ion; show the
      ions that did the narrowing. Noise gate from `NextGenSignalNoiseCalc` per transition.
- [ ] D4 B2 isomer-group reporting (group key + isomer count columns, tree filter).
- [ ] D5 C1 co-assigned peak warning (isomers of a group sharing a peak in a replicate).
- [ ] D6 A3 residue-class diagnostic ions (table per mod; UI only).
- [ ] B1 site-probability pass-through stays a candidate (data, not quantitative) but is a
      BiblioSpec change; separate PR if pursued.
