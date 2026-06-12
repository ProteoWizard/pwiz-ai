# TODO-20260521_dia_spillfile_chromindex.md -- DIA import crash: shared grouped times/scans read from the wrong spill file

## Status

Active. Root cause is confirmed. Current strategy: **back out the stopgap and instead
make the code throw a clear exception the moment it detects it is about to read a
shared list from the wrong spill file**, so the bug fails loudly and reproducibly.
Then find a **non-confidential** dataset that triggers the exception, implement the
real fix, and verify.

> The dataset that originally surfaced this crash is a customer's **confidential**
> DIA dataset and cannot be committed, shared, or named here. Do not add it (or its
> file names/paths) to the repository, tests, or any committed file.

## The bug

DIA results import crashes with:

```
ArgumentOutOfRangeException ... Parameter name: startIndex
  at BlockedList.ToArray
  at ChromCollector.ReleaseChromatogram   (spill-file back-link read)
```

The crash is **order/size-dependent** -- only some files in a run fail -- which is
why it first looked like a >2GB spill-file overflow. It is not.

## Root cause (confirmed)

In grouped-time DIA extraction, all of a precursor's product ions **share one**
`GroupedTimesCollector` / `ScansCollector`
(`SpectraChromDataProvider.ProcessExtractedSpectrum`). That shared list was spilled
to disk under the **first** product ion's chromatogram index.

But `GetMatchingGroups` (`ChromCacheBuilder`) can match/clone one extracted
precursor's product ions into **multiple peptide groupings** -> different
`RequestOrder` groups -> **different spill files**. At release
(`ChromGroups.ReleaseChromatogram` -> `ChromCollector.ReleaseChromatogram`) the
shared list was read back against the **wrong spill file's bytes**. Only the first
reader of a shared list actually touches disk, and it only throws when that wrong
file happens to be shorter than the back-link offset -- hence the order/size
dependence.

The deeper smell: the spill code juggles too many easily-confused integers
(`RequestOrder` index, group id, provider id, product-filter id, chromatogram
index). The mismatch is a symptom of passing the wrong integer where a spill file
is *chosen* vs. *read*.

## Plan

1. **Back out the stopgap + add a fail-fast guard (in progress).** Restore the
   original spill behavior, and add a guard in `ChromGroups.ReleaseChromatogram`
   that **throws** when a shared times/scans list is about to be read from a spill
   file other than the one it was actually written to (i.e. the exact condition
   that produces wrong/corrupt data). This converts a rare, data-dependent silent
   corruption / out-of-range crash into a deterministic, clearly-described failure.
2. **Find a non-confidential repro (next, owner: Nick).** Locate or construct a
   shareable DIA dataset that makes one extracted precursor's product ions match
   into more than one peptide grouping, so the guard fires. This becomes the
   committable regression test.
3. **Implement the real fix.** Disambiguate the confusable integer ids (distinct
   types/wrappers) so it is impossible to pass the wrong integer where a spill file
   is chosen vs. read. Candidate alternatives already considered: read each list
   from the spill file it was actually written to (more release-path code), or
   compute per-(precursor, group) times at extraction time.
4. **Verify.** The guard no longer fires; the non-confidential repro imports
   correctly; and (locally, off-repo) the original confidential dataset imports
   correctly.

## Work done so far

### Investigation + confirmation (stashed, see below)

A prior pass produced, on top of the original code:
- An **in-memory stopgap**: in `ProcessExtractedSpectrum`, keep the shared grouped
  times/scans in memory (`AddShared`) instead of spilling them, so they are never
  read from disk and the wrong-file read cannot happen. Tradeoff: a few % of
  extracted data stays resident on huge files. (This is the "fix" now being backed
  out in favor of the fail-fast guard.)
- A full **instrumentation/detection layer** in `ChromCollector.cs` (per-list spill
  index tracking, a consistency check, counters, console prints) that proved and
  quantified the mismatch.
- A WIP **candidate real fix** (read each component list from the spill file it was
  written to, via a per-index byte-buffer callback). Did not yet compile (a stray
  method rename).

That entire working-tree state has been preserved with `git stash` in the
`sky_spillfileerror` checkout (message: "WIP spillfile stopgap + instrumentation +
candidate fix"), restricted to `ChromCollector.cs` and `SpectraChromDataProvider.cs`,
so the candidate-fix code and instrumentation are retrievable
(`git stash list` / `git stash show -p`). Retrieve before re-deriving the real fix.

## Key files

- `pwiz_tools/Skyline/Model/Results/SpectraChromDataProvider.cs` --
  `ProcessExtractedSpectrum` grouped-time path (where the shared list is spilled
  under the first product-ion index).
- `pwiz_tools/Skyline/Model/Results/ChromCollector.cs` -- `BlockedList`,
  `ChromGroups.ReleaseChromatogram`, `ChromCollector.ReleaseChromatogram`. The
  fail-fast guard lives here.
- `pwiz_tools/Skyline/Model/Results/ChromCacheBuilder.cs` -- `GetMatchingGroups`
  (where one precursor's product ions get matched into multiple groupings).

## Tests

- A committable regression test is **blocked on step 2** (a non-confidential
  repro). It should import a dataset that triggers the multi-grouping condition and
  assert a successful import once the real fix is in.
- Local-only investigation tests exist in the working tree of the
  `sky_spillfileerror` checkout (a harness that opens the confidential file
  directly, and a sequence-permutation experiment). These reference confidential
  data / hard-coded local paths and **must not be committed**.

## GitHub issue

- [#4287](https://github.com/ProteoWizard/pwiz/issues/4287) -- "DIA import: shared
  grouped times/scans read from the wrong spill file" (skyline, bug; assigned
  nickshulman).

## Checkouts

- `I:\git_i\sky_spillfileerror` -- primary working checkout.
- `I:\git_i\sky_spillfiletest` -- clean.
- `I:\git_i\sky_26_1_spillfile` -- release branch `Skyline/skyline_26_1`; had the
  in-memory stopgap backported (plus unrelated local build-file edits). Decide
  separately whether the 26.1 release ships the stopgap or waits for the real fix.
