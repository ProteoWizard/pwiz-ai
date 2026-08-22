# A failed run reports ex.Message, so a 17-hour failure can be unattributable

## Branch Information
- **Branch**: `Skyline/work/20260821_osprey_pipeline_error_detail`
- **Base**: `master`
- **Created**: 2026-08-21
- **Status**: Active
- **Module**: `osprey`
- **Worktree**: `C:\proj\pwiz`
- **Requester/Reporter**: none - found while auditing the TDP-43 163-file baseline run

## Objective

Osprey's two terminal exception sinks log `ex.Message` and discard the exception type and
the `InnerException` chain. `Message` can be empty and a wrapper carries its real cause
only in its inner exception, so the pair can name the throwing frame while saying nothing
about why it threw.

This is not hypothetical. The TDP-43 163-file baseline run
(`tdp43-163files-libdecoy-r1.0-protein-compact-20260816_203716`) completed pass-2 FDR,
protein FDR and sidecar patching, then died on the final step - writing the blib - after
**17 hours 11 minutes**:

```
[2026/08/17 13:48:41] [ERROR] Pipeline failed:
[2026/08/17 13:48:41] [ERROR]    at pwiz.Osprey.IO.BlibWriter..ctor(String path)
   at pwiz.Osprey.Tasks.BlibOutputWriter.Write(...)
   ...
DONE dataset=tdp43 ... exit=1 elapsed=1031min
```

The message after the colon is empty. `BlibWriter`'s constructor does `File.Delete` then
opens a SQLite connection, so a file lock, a full disk, a permissions denial and a failure
to load the native SQLite interop are all consistent with that log - and cannot be told
apart from it. The cause of that specific failure is now unrecoverable; the point of this
change is that the next one is not.

Recovery, for the record: re-running `--task SecondPassFDR --input-scores <run dir>`
reloaded the persisted protein-compact stratum and 2nd-pass scores and finished the output
steps in **29 minutes**, reproducing the straight-through numbers exactly (390,627 base-id
stratum, 35,292 peptides, 3,951 protein groups). A terminal failure at the blib step is
therefore cheap to recover from *once diagnosed* - the diagnosis is the expensive part.

## Tasks

- [x] `AnalysisPipeline.Run` catch logs the whole exception (type, message, inner chain,
      stack) instead of `ex.Message` plus a separate `ex.StackTrace`
- [x] `Program.Main` catch does the same - it had **no stack trace at all**, so any failure
      before the pipeline started (argument parsing, config resolution, opening the
      library) reported one line and no frames
- [x] Osprey pre-commit gate green: build, 592/592 tests, ReSharper zero warnings
- [ ] Confirm on a real failure that the new line names a type

## Deliberately not in scope

- **Making `BlibWriter`'s constructor more robust** (retry, pre-flight the path, clearer
  wrapper). Without knowing what actually threw, any hardening is a guess, and a guess
  here would be indistinguishable from a fix. Diagnose first.
- **The other `ex.Message` call sites.** The ~18 remaining are warnings on non-fatal paths
  that name their own context ("Failed to load calibration for `<file>`: ..."), where the
  message is the useful part and the run continues. The defect is specific to the two
  sinks that end the process.

## Notes

- The blib is written last, after every expensive artifact is already computed and
  persisted. That ordering is what makes the 29-minute recovery possible, and is worth
  keeping.
