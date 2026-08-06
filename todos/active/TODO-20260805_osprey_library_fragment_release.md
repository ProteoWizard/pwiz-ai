# Osprey: release library fragments nothing can score after Stage 5

## Branch Information
- **Branch**: `Skyline/work/20260805_osprey_library_fragment_release`
- **Created**: 2026-08-05
- **Status**: Complete - merged
- **Module**: `osprey`
- **GitHub Issue**: [#4532](https://github.com/ProteoWizard/pwiz/issues/4532)
- **PR**: [#4534](https://github.com/ProteoWizard/pwiz/pull/4534)
- **Split from**: [TODO-20260804_osprey_pass2_ab_and_library_production.md](TODO-20260804_osprey_pass2_ab_and_library_production.md),
  which stays ACTIVE for the pass-2 A/B and library-production work this grew out of

## What it does

Releases `LibraryEntry.Fragments` for every entry nothing downstream can score or write -
everything outside the compaction survivors and the gap-fill candidates. Identity fields
(`ModifiedSequence` / `ProteinIds` / m/z / RT) are KEPT on every entry, because
`ProteinFdr.BuildProteinParsimony` and `FirstJoinTask.BuildProteinCompactStratum` both walk the
ENTIRE library after Stage 5 and read exactly those - so dropping whole entries would silently
move protein FDR, while dropping fragments cannot.

Default ON (`IsNotZero` treats unset as on); `OSPREY_RELEASE_LIBRARY_FRAGMENTS=0` is the A/B
byte-identity arm, the same role `OSPREY_STAGE6_STREAM_SURVIVORS=0` plays for the Stage 6 handoff.

**The released state THROWS on any access to `Fragments`.** That is the point of releasing
through a method rather than assigning null or an empty list: every scorer guards with
`if (entry.Fragments == null || entry.Fragments.Count == 0)`, so both of those are silently
absorbed as "this entry has no spectrum" and an entry released in error would score a degenerate
zero. The sentinel turns that same guard expression into a tripwire.

## MEASURED (2026-08-05)

A/B on 4 SEA-AD files against the full 12.7 GB gated-no-il library, same pinned binary,
sequential. Released 5,459,501 of 6,275,151 entries (87.0%), 409,235 base_ids retained.

| stage | ON | OFF | delta peak |
|---|---|---|---|
| PerFileScoring (pre-release) | 13.9 / 30.5 GB | 15.2 / 30.9 GB | -0.4 (noise) |
| FirstPassFDR | 27.7 / 35.7 GB | 27.3 / 40.3 GB | -4.6 GB |
| PerFileRescoring | 14.5 / 34.0 GB | 20.5 / 41.8 GB | -7.8 GB |
| SecondPassFDR | 15.9 / **17.7** GB | 22.2 / **28.5** GB | **-10.8 GB** |

Stage 7 peak -38%. Slightly faster, not slower. Stage 1-4 unchanged, as it must be.

**FEW FILES IS THE MAXIMUM-SAVING CASE, not a scaled-down one** - the library is fixed while the
retained set grows with file count. At 82 files expect ~70-75% released rather than 87%, so a
smaller (still large) saving. Do not quote the 4-file numbers as production.

## Code review: 15 findings, all addressed

`/code-review max` on the branch returned 15 findings.

### 4 real defects, all WIRING - fixed in `c601d63cd6`

* **The Rehydrate path never released.** That is the RESUME path - what an operator runs after
  the very OOM this change targets - so the one run that most needs a lean library kept the
  whole thing resident. Worse, the doc comment justified it with a claim that was FALSE:
  `RescoreHydration` does surface the surviving set (`GlobalFirstPassBaseIds`).
* **StopAfterStage5 stripped gap-fill AND fabricated a saving.** `PlanStage6` returns early
  before assigning the gap-fill plan while `_firstPassBaseIds` IS set, so the retained set was
  survivors-only; and that path already loads with `OmitFragments`, so `ReleaseSpectrum` (which
  detects by reference identity, not "has a spectrum") swapped one shared singleton for another
  and printed millions released having freed ZERO bytes, directly above a [MEM] probe.
* **Six UTF-8 BOMs** broke the repo BOM gate and turned two 3-line diffs into whole-file
  rewrites. Cause: `io.open(...,'w',encoding='utf-8-sig')` WRITES a BOM. Read utf-8-sig, write
  utf-8.

**The lesson worth carrying**: all four were WIRING, and the only test covered the pure helper's
set arithmetic. Deleting the production call site still leaves the suite green.

### The other 11 - fixed in `a5cb0183a2`

Posted on issue #4532 (comments 5202755992 and 5204026289). The three that mattered:

* **The HPC merge node realized ZERO saving.** `MergeNodeTask` now performs its own release,
  retaining every base_id in the final reported pool. It had to be its own: `FirstJoinTask` -
  where the Stage 5 -> 6 release lives - is excluded from a `--task SecondPassFDR` pipeline
  entirely, and that leg loads fragment-laden (`OmitFragments` is gated on `StopAfterStage5`).
  The retained set is a superset of what is read, because `BlibOutputWriter.PrecompressSpectra`
  reads fragments only for `bestByPrecursor.Values`, derived from that pool by filtering, and
  nothing else after Stage 6 reads a spectrum: pass-2 Percolator reloads FEATURES from the
  reconciled parquet (`Pass2FdrSidecar` never touches the library) and parsimony reads identity.
  Placed AFTER `ctx.Get<RescoredEntries>()`, so the merge-mode compaction it materializes is
  already done.

  **VERIFIED by reading each leg's own log** (`regression.ps1 -Dataset Stellar -KeepOutput`),
  not inferred from a green gate:

  | leg | released |
  |---|---|
  | `chain/phase4_mergenode/phase4.log` | **76,442 of 242,841 (31.5%)** - was zero |
  | `straight/straight.log` FirstJoin | 152,830 of 485,628 |
  | `straight/straight.log` merge node | **0** of 485,628 - idempotent, costs nothing |

  Retained base_ids = **166,399 in all three**, an independent cross-check that the
  reported-pool set and the survivors+gap-fill set agree. 242,841 vs 485,628 entries because
  `ExpectReconciledInput` skips the decoy rebuild - so that leg was carrying the whole TARGET
  fragment set through the blib write and freeing none of it.
* **The validity-key hole is closed at its root.** The suffix moved to
  `LibraryFragmentRelease.ValidityKeySuffix` and is keyed on whether the release RAN
  (`RunsOnThisLeg`), not on the flag - the same predicate the call sites gate on, so key and
  code cannot disagree. It is EMPTY on a leg where a release was impossible
  (`--task FirstPassFDR`, or the resident pool `--fdrbench-pass 1` forces) as well as where it
  ran: there the two arms are literally the same run, and a term would force hours of Stage 5
  re-scoring on an HPC resume to record a difference that cannot exist. **Under default
  settings every leg's key is byte-identical to master's** - nothing is invalidated.
* **`FragmentMath._top6MzCache` is cleared** by the release (`ClearTop6MzCache`). Pure memo, so
  neutral in both directions - and dropping it also stops a released entry's stale cached top-6
  from satisfying the prefilter that should have tripped the tripwire.

The rest: guards that could not fire removed (the silent `fullLibrary == null -> return 0`
degraded quietly in a fail-loud design); the misleading `~7.1 GB` replaced with the measured
28.5 -> 17.7 GB A/B plus the ~3.2 GB fragment-share caveat, since only fragments are freed;
`IsSpectrumReleased`'s doc now says what it answers ("was it RELEASED", not "does it have a
spectrum" - `Array.Empty` reports false); the `-DumpProteinFdr` citation corrected to
`OSPREY_DUMP_STAGE7_PROTEIN_FDR`; `_firstPassBaseIds` documented as deliberately separate from
`_survivorLoader` (the loader is null on the Rehydrate leg, which is where the release matters
most); and the tripwire's inability to name the offending entry recorded as the deliberate cost
of one shared singleton.

## Gates

* 576 tests, zero inspection warnings (`Build-Osprey.ps1 -RunTests -RunInspection`)
* `regression.ps1 -Dataset All` **PASSED all 26 checks across all four datasets**, every
  `mode3 (HPC chain==straight)` included - the leg the merge-node release runs on.
  Log: `ai/.tmp/regression-all-libfrag-review.log`
* **The committed golden predates this change, so mode1 IS the release-on vs release-off
  correctness proof.** Verified it actually engages in the golden-compared leg after an earlier
  revision gated it on `ctx.Diagnostics`, which would have made that gate vacuous.
* TeamCity Perf/Regression **4123277 SUCCESS** on the real tip `a5cb0183a2`. (4123106 also
  passed but covered only `8317479fc4`, before the review fixes - re-triggering on the actual
  tip is what made the gate mean anything.)

## KNOWN GAP - carry this forward

**The test gap is NARROWED, not closed.** New coverage pins the leg truth table (the merge node
MUST release, `--task FirstPassFDR` must NOT), the merge-node retained-set arithmetic, the suffix
contract, and the release arm's participation in `TaskValidityKeyTest`'s canonical-pipeline walk -
asserted against a NON-EMPTY arm, since the default emits nothing and a default-arm assertion
asserts nothing.

But **deleting the production call site still leaves the unit suite green.** Only
`regression.ps1` mode1/mode3 covers that, and only because the committed golden predates the
change - which means the coverage EXPIRES the next time the golden is rebaselined. An
integration test over the release wiring is the standing follow-up.

Two further release opportunities were identified and deliberately NOT taken here, to keep the
change scoped:

* The `--task PerFileRescoring` worker (Stage 6) also holds the library and releases nothing.
  Its retained set would be exactly what it is about to rescore.
* `FragmentMath._top6MzCache` is now cleared, but only at the release point; it still grows to
  whole-library size during Stages 3-4.

## Tasks

- [x] Release at the Stage 5 -> 6 boundary, survivors + gap-fill retained
- [x] Fail-loud sentinel rather than null / empty list
- [x] A/B measured on 4 SEA-AD files (Stage 7 peak -38%)
- [x] `/code-review max` - 15 findings, all addressed
- [x] Merge-node release, verified by log rather than inferred
- [x] `regression.ps1 -Dataset All` green; TeamCity 4123277 green on the tip
- [ ] **Integration test over the release wiring** - the standing gap above

## Progress Log

### 2026-08-06 - review findings closed, gates green on the tip

All 15 findings addressed across `c601d63cd6` (4 wiring defects) and `a5cb0183a2` (the other 11).

Three process notes worth carrying:

**A green correctness gate is not evidence a feature engaged.** `-Dataset All` passing proves
nothing broke; it does not prove the merge node released anything. Reading
`phase4_mergenode/phase4.log` is what proved it, and the straight-through leg's `0 of 485,628`
is what proved the new call is idempotent rather than double-counting.

**TeamCity was running on a stale commit and looked like coverage.** Build 4123106 was triggered
on `8317479fc4` while the branch tip had moved to `c601d63cd6` - so a green Perf/Regression badge
covered none of the review fixes. Check the commit in the build, not just the PR number.

**Validity-key terms are not free.** The first cut emitted `;libfrag=0` whenever the release did
not run, which would have invalidated `--task FirstPassFDR` output directories master produced -
hours of Stage 5 re-scoring to record a difference that cannot exist on that leg. Keying on
"could this leg have released" as well as "did it" keeps every default-settings key
byte-identical to master's.
