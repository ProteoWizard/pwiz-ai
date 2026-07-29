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
