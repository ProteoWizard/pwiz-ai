# TODO-20260809_mz5_continueonerror.md

## Branch Information
- **Branch**: `Skyline/work/20261012_continueonerror_all_writers` (created 2026-10-12, C# port)
- **Checkout**: `C:\Dev\mz5` (moved from `C:\Dev\master_clean` 2026-10-12)
- **Module**: `pwiz`
- **Base**: `origin/master`
- **Status**: In progress. C# port committed locally, not pushed; MsData.Tests (89) and
  MsConvert.Tests (18) green. Next: `/code-review`, push, PR.
- **GitHub Issue**: (none yet)
- **PR**: (none)
- **Cherry-pick to release**: undecided
- **Obsolete C++ branch**: `Skyline/work/20260809_mz5_continueonerror` in `C:\Dev\BugFix`, two
  unpushed commits (`30e25b3e57`, `6fb292297c`). Every file it touches was deleted when #4658
  retired the C++ tree, so it cannot be merged; it stays only as the reference for the port.
  Delete the branch once the C# PR merges.

## Objective

`MSDataFile::write` never forwards `config.continueOnError` to `Serializer_mz5`, so the flag is
permanently off for mz5. `msconvert --mz5 --continueOnError` aborts on the first unreadable
spectrum, even though msconvert's own error handler tells the user to re-run with exactly that
flag. Forward it.

## Root cause (verified 2026-08-09)

`pwiz/data/msdata/MSDataFile.cpp:239`:

```cpp
serializer.write(filename, msd, iterationListenerRegistry, config.useWorkerThreads);
```

The 5th parameter is omitted and `Serializer_mz5.hpp:64` defaults `continueOnError = false`. Every
other format forwards it - mzML 170, mzXML 179, MGF 185, MS1 191, CMS1 197, MS2 203, CMS2 209.
mz5 is the lone outlier, which reads as an oversight when the flag was threaded through rather
than a deliberate choice.

Everything below that call site is already correct: `Serializer_mz5::write` (`.cpp:157`) ->
`Impl::write` (`:97`) -> `ReferenceWrite_mz5::writeTo` (`:508`) -> `readAndWriteSpectra` (`:354`,
skip branch at `:385`) and `readAndWriteChromatograms` (`:432`, skip branch at `:463`), and
`SpectrumWorkerThreads` is constructed with it at `:368`. So this is plumbing that stops one
level short, not missing capability.

### Second instance of the same gap, in the test

`Serializer_mz5_Test.cpp:101-103` sets `writeConfig.continueOnError = true` under the comment
"test with error skipping", but `testWriteRead` calls `mz5Serializer.write(filename, msd, &ilr)`
with three arguments, so the default `false` wins there too. That case has never exercised error
skipping. Worth fixing in the same PR so the intent in that comment becomes true.

### Impact

- `msconvert --mz5 --continueOnError` aborts the whole conversion on one bad spectrum, while
  `msconvert.cpp:1018` advises that flag as the remedy
- MSConvertGUI sets `config.WriteConfig.continueOnError = true` (`ProgressForm.cs:205`) to no
  effect
- `continueOnError = false` also reaches `SpectrumWorkerThreads`, disabling worker-thread error
  tolerance

### Nothing depends on the current behaviour

The only other `Serializer_mz5::write` callers pass neither flag and are unaffected:
`VendorReaderTestHarness.cpp:461,722` and `ChromatogramList_mz5_Test.cpp:50`. No test asserts
that an mz5 write aborts. The behaviour change is limited to callers who already asked for
`continueOnError` and were silently ignored.

## Plan

1. Failing test first, in `MSDataFileTest.cpp` (where `MSDataFile::write` is tested), not a new
   file: an MSData whose spectrum list throws for one index, written with
   `format = Format_MZ5, continueOnError = true`; assert the write does not throw and the file
   comes back with the surviving spectra.
2. Fix `MSDataFile.cpp:239` by forwarding `config.continueOnError`.
3. Fix `Serializer_mz5_Test.cpp:101-103` so its "error skipping" case actually passes the flag.

Prefer a helper that can be pointed at other formats later - the same test shape would catch this
class of bug for any serializer - but do not expand this PR to add coverage for formats that are
already correct.

## Verification

- [x] New test red before the fix, green after. Red was specific: mzML skipped and continued,
      mz5 let the exception escape
- [x] `pwiz/data/msdata` suite green (70 targets on the final run, all `.passed`)
- [x] `msconvert --mz5 --continueOnError` on a good file still converts normally. Producing a
      genuinely unreadable spectrum through the CLI is impractical; the unit test covers that at
      the `MSDataFile::write` level, which is the same code path msconvert uses
- [ ] `/code-review max` findings settled
- [ ] CodeInspectionTest + full ReSharper inspection green

## Progress Log

### 2026-08-09 - implemented

**Changes**

- `pwiz/data/msdata/MSDataFile.cpp:239` - forward `config.continueOnError`. The one-line fix.
- `pwiz/data/msdata/Serializer_mz5_Test.cpp:55` - pass `config.useWorkerThreads` and
  `config.continueOnError` through, so the existing "test with error skipping" case at 101-103
  actually skips errors instead of silently testing the default.
- `pwiz/data/msdata/mz5/ReferenceWrite_mz5.cpp` - `sp.reset()` / `cp.reset()` before each read.
  See below; this one was not in the original plan.
- `pwiz/data/msdata/MSDataFileTest.cpp` - extended (not a new file) with `UnreadableSpectrumList`
  and `testContinueOnError(format)`, run for mzML and mz5.

**The wrong-spectrum-id bug, found by fixing this one**

With `continueOnError` finally reaching mz5, the skip diagnostic named the wrong spectrum:

```
Skipping spectrum 1 "scan=20": ...   <- mzML, correct
Skipping spectrum 1 "scan=19": ...   <- mz5, names spectrum 0
```

`sp` is declared outside the loop (`ReferenceWrite_mz5.cpp:365`) and only assigned inside the
`try`, so on failure it still holds the previously read spectrum and the `(sp ? sp->id : ...)`
ternary takes the wrong branch. Latent until now precisely because the catch was unreachable.
`cp` in `readAndWriteChromatograms` has the identical shape. Fixed both by resetting before the
read. The test asserts the reported id, so this cannot regress - and that assertion is real: the
pre-fix run printed `scan=19` against an expected `scan=20`.

**Test fixture gotcha worth knowing**

The first version of `UnreadableSpectrumList` overrode only `spectrum()`, which broke *every*
format: `SpectrumListSimple::spectrumIdentity` is implemented as `return *spectrum(index, false)`
(`MSData.cpp:1247-1250`), so the throw also escaped from inside the serializers' own error
diagnostic when it called `spectrumIdentity(i)` to name the failed spectrum. The fixture now
overrides `spectrumIdentity` to read `spectra[index]` directly, which also models reality better -
a real reader enumerates an index it cannot read data from.

### 2026-08-09 - scope widened after `/code-review max`

The review found the one-line fix was not sufficient on its own. Verified each claim against
source before acting; four mattered.

**1. mz5 did not renumber surviving spectra, so the fix produced unusable files.** The mzML
writer does `spectrum->index -= skipped` (`IO.cpp:3028`); mz5 stored the original index verbatim
(`Datastructures_mz5.cpp:2372`). A skipped spectrum therefore left a gap, and feeding that mz5 to
`msconvert --mzML` hits `IO.cpp:3027` `throw runtime_error("[IO::write(SpectrumList)] Bad
index.")` - which is *outside* the try, so a second `--continueOnError` run cannot recover it
either. Enabling the flag without renumbering just moved the failure downstream. Now renumbered
around the `SpectrumMZ5` construction, which is also what registers the id the file resolves
precursor references through (`Datastructures_mz5.cpp:2352`), so both see the adjusted value.
Same for chromatograms. When nothing is skipped the arithmetic is a no-op, so the ordinary path
is bit-identical to before.

**2. msconvert still never told mz5 users the flag exists.** The advice is gated on
`catch (pwiz::util::enumeration_error&)` (`msconvert.cpp:1014`, `:1117`), and that type was
thrown only from the mzML path (`IO.cpp:3017`, `:3149`). mz5 did a bare `throw;` and landed in
the generic handler. Now throws `enumeration_error`, so the hint fires.

**3. The identical bug was still live for MS1/CMS1/MS2/CMS2.** `Serializer_MSn.cpp:555` accepted
`useWorkerThreads` and `continueOnError` and then dropped both when forwarding to `Impl::write`,
compiling only because that Impl is the one of five that defaults them. Fixed.

**4. `sp.reset()` was the wrong shape.** Every other serializer declares the pointer inside the
loop (`IO.cpp:3000`, `Serializer_mzXML.cpp:770`, `Serializer_MSn.cpp:463`, `Serializer_MGF.cpp:82`);
mz5 was the lone hoist. Declared in-loop instead, which makes the stale value unrepresentable and
removes the two added `reset()` lines.

**Test rework**

- `UnreadableSpectrumList` now *decorates* a healthy list instead of deriving `SpectrumListSimple`.
  That drops the hand-copy of `spectra`/`dp` and, more importantly, the `spectrumIdentity`
  override that was papering over `SpectrumListSimple::spectrumIdentity` delegating to
  `spectrum()`. Same shape as the existing `SpectrumListError` in `Serializer_mzML_Test.cpp:64`.
- Runs over six formats now, not two: mzML and mz5 with the full check, mzXML/MGF/MS2/CMS2 with
  the skip check only (those write a subset, so a spectrum count would not be meaningful).
- Asserts renumbering directly: every surviving spectrum has `index == i` and none carries the
  skipped id.
- **Proved the MSn coverage bites**: temporarily reverted `Serializer_MSn.cpp:555` and the test
  went red, then restored it.

**Considered and not done**

Promoting `SpectrumListError` to a shared test header, as the review suggested. It lives in a
different test binary, so sharing it means a new header for one double; the decorator rewrite
above already removes the substantive objection (the bad shape), leaving only duplication across
two test files.

### 2026-08-09 - second `/code-review max` round

Three findings were genuinely against this diff and are fixed; the rest are pre-existing issues in
a code path this change makes live for the first time.

1. **Unsigned underflow in the new renumbering.** `IO.cpp:3027` guards its `-= skipped` with
   `if (spectrum->index != i) throw`; the copy here had no precondition. `SpectrumIdentity::index`
   is `size_t` defaulting to `(size_t)-1` and narrows into `SpectrumMZ5::index` (unsigned int), so
   a list whose index does not match its position would wrap to `0xFFFFFFFF` - which is mz5's
   `ULONG_MAX` "unresolved reference" sentinel, and would also be handed to
   `addSpectrumIndexPair`. Guarded now, but only under `skipped > 0`: when nothing is skipped the
   subtraction is a no-op, so the ordinary write path gains no new throw and stays byte-identical.
2. **`enumeration_error` had been applied to mz5 only.** `Serializer_MSn`, `Serializer_MGF` and
   `Serializer_mzXML` still bare-`throw;`, so msconvert's hint fired for mz5 and no other format -
   an inconsistency this branch introduced by adding tests for those formats. All three converted.
3. **The `enumeration_error` conversion had no coverage** - every test path set
   `continueOnError = true`. Added a negative assertion (`unit_assert_throws(..., enumeration_error)`)
   which runs for all six formats. **Proved it bites**: reverted mz5's throw, watched it go red,
   restored.

**Line-ending trap, hit twice.** `Serializer_MSn.cpp` and `Serializer_MGF.cpp` have *mixed*
endings (MSn: 562 CR vs 567 LF). The Edit tool normalizes them, so a one-line change churned 60
lines in MGF and 4 in MSn. Caught both with `git diff --ignore-all-space --stat`, restored, and
reapplied via `[System.IO.File]::ReadAllText`/`WriteAllText` with an explicit `\r\n` search. Check
that diff-stat comparison on every C++ edit in this tree. See
[[reference_line_ending_churn_diagnosis]].

### Known limitations - newly reachable, not fixed here

Enabling `continueOnError` for mz5 makes a previously dead path live, and that path has gaps that
predate this work. None is a regression; all need their own issue:

- If *every* spectrum is skipped, no `SpectrumMetaData` dataset is written and reading that file
  back leaves `run.spectrumListPtr` null (`Serializer_mz5.cpp:118`), which downstream serializers
  dereference unguarded. mzML writes a valid empty list.
- A skipped spectrum is never registered via `addSpectrumIndexPair`, so a surviving MS2 naming it
  as precursor silently loses `Precursor::spectrumID` on read. mzML keeps the dangling id string,
  so the two formats disagree about what a skip preserves.
- `SpectrumWorkerThreads`' constructor eagerly reads spectrum 0 *before* the loop's try, so a bad
  first spectrum bypasses `continueOnError` entirely. Same shape pre-exists for mzML
  (`IO.cpp:2983`).
- `Serializer_MSn.cpp:159` re-reads the precursor spectrum outside the loop's try, so an
  unreadable precursor still aborts an MS2 conversion.
- The test pins `useWorkerThreads = false` (the cerr capture requires it), so the threaded
  marshaling in `SpectrumWorkerThreads` is uncovered.

**Not touched**

`Serializer_mzXML` and `Serializer_MGF` handle `continueOnError` correctly and needed no change.
Findings about `<spectrumList count>` overstating on skip (`IO.cpp:2975`), the mzMLb index not
filtering `-1` sentinels (`Serializer_mzML.cpp:210`), `Format_Text` having no error handling at
all (`MSDataFile.cpp:160`), and the defaulted-trailing-argument pattern that allows this whole bug
class are all real and all pre-existing. They belong in their own issues, not here.

### 2026-10-12 - C++ tree retired; ported to C#

#4658 (merged by 2026-10-08) deleted every C++ file the branch above changes, so that work is a
reference only. The C# port had its own version of the bug, and a worse one for mzXML:

- **MGF and MSn** (`MgfSerializer.cs`, `SerializerMSn.cs`, both loops): no `ContinueOnError` at all.
  A failed `GetSpectrum` escaped raw, so msconvert's `EnumerationException` hint never fired.
- **mzXML** (`MzxmlWriter.cs`): `catch { continue; }` skipped every unreadable spectrum *silently*,
  with or without the flag and with no log line - spectra could vanish from a conversion unreported.
- **`MSDataFile.Write`** forwarded the flag only to mzML / mzMLb. `WriteConfig.ContinueOnError`'s
  own doc admitted it ("other format writers stop on the first failure regardless").
- **mzML** skipped correctly but wrote `spec.Index` verbatim, leaving a gap after a skip - the same
  defect the C++ review found in mz5. Reading it back gave the survivor index 2, not 1.
- **mz5**: no C# writer exists yet (`NotImplementedException`), so the original mz5 bug is moot
  until one is written.

**Changes** (branch `Skyline/work/20261012_continueonerror_all_writers`)

- New `pwiz/data/msdata/ContinueOnErrorPolicy.cs`: one `GetSpectrumOrSkip` used by every writer's
  spectrum loop - logs `Skipping spectrum i "id": msg` and returns null under the flag, otherwise
  wraps in `EnumerationException`. Replaces the copy inline in `MzmlWriter`.
- `ContinueOnError` + `SkipLog` added to `MzxmlWriter`, `MgfSerializer`, `SerializerMSn`;
  `MSDataFile.Write` forwards the flag to all of them (MSn cases folded into a local `WriteMSn`).
- `MzmlWriter` writes `spec.Index - skipped` (cpp `IO.cpp:3028`), passed as a parameter rather than
  assigned, because the list may hand back the caller's own `Spectrum`. No-skip output unchanged.
- `WriteConfig.ContinueOnError` doc corrected.

**Tests** - extended `WriterIterationListenerTests.cs` (already the cross-writer file), no new file:
`UnreadableSpectrumList` decorator (throws on index 1, identity still resolves), run over mzML,
mzXML, MGF, MS2 and CMS2 through `MSDataFile.Write` - the msconvert path, so forwarding is covered.

- `..._SkipTheUnreadableSpectrumAndKeepTheRest` - read back, survivors identified by first peak
  m/z (works for formats that drop the nativeID); mzML indices contiguous.
- `..._LogTheSkippedSpectrumById` - exact diagnostic per writer, so a wrong-id regression shows.
- `..._WithoutContinueOnError_ThrowEnumerationException` - inner exception preserved.
- Red before the fix (mzML index 2 vs 1; mzXML threw nothing). Proved MGF and MSn forwarding are
  covered by removing each from `MSDataFile.Write` in turn: red both times, restored.
- Full MsData.Tests green (89); MsConvert.Tests green (18).

**Follow-ups, not in this change**

- mzML chromatogram loop has the same index gap (`MzmlWriter.cs` WriteChromatogramInner writes
  `chrom.Index` verbatim after a skip). Same fix shape; needs an unreadable-chromatogram fixture.
- The eager mzXML reader never sets `Spectrum.Index` (always -1, `MzxmlReader.cs` ReadOneScan).
  Unrelated to skipping; found because the index assertion first ran over mzXML.
- `<spectrumList count>` still states the input count after a skip (same as cpp `IO.cpp:2975`).

## Notes

- Found while investigating `TODO-20260809_mz5_combineims_error` (closed won't fix). That work is
  unrelated to this bug beyond having touched the same call path.
- Vendor DLLs are absent on this machine, so vendor reader paths cannot be exercised locally.
  Not needed here - the test constructs its own throwing spectrum list.
