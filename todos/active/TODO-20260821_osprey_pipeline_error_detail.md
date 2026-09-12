# A failed run reports ex.Message, so a 17-hour failure can be unattributable

## Branch Information
- **Branch**: `Skyline/work/20260821_osprey_pipeline_error_detail`
- **Base**: `master`
- **Created**: 2026-08-21
- **Status**: PR opened 2026-09-12 - rebased onto master, review findings applied, gate green
  (593/593, inspection 0). Sat as an unpushed local commit from 2026-08-21 to 2026-09-12
- **Module**: `osprey`
- **PR**: [#4660](https://github.com/ProteoWizard/pwiz/pull/4660) (opened 2026-09-12)
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
      before the pipeline started (directory creation, the input checks, the mdiag
      render) reported one line and no frames; usage errors stay one-line messages
- [x] Osprey pre-commit gate green: build, 592/592 tests, ReSharper zero warnings
- [x] Confirm on a real failure that the new line names a type - done 2026-09-12 with a
      forced one (a scratch copy of the Stellar mzML against a `.blib` that is not SQLite):
      `[ERROR] Pipeline failed: code = NotADb (26), message =
      System.Data.SQLite.SQLiteException (0x87AF0570): file is not a database` followed by
      the full frame chain down to `AnalysisPipeline.Run`. The type, the SQLite error code
      and the cause are all on the first line; the old sink would have printed
      `Pipeline failed: file is not a database` and a stack
- [x] Rebased onto master `7af9eb0ea5` (2026-09-12, clean; the two catch blocks were
      untouched by the 38 intervening commits) and re-ran the gate: both TFMs build,
      593/593 tests, inspection 0 warnings in 92.8 s
- [x] `/code-review max`, push, open the PR - #4660, 2026-09-12

## Deliberately not in scope

- **Making `BlibWriter`'s constructor more robust** (retry, pre-flight the path, clearer
  wrapper). Without knowing what actually threw, any hardening is a guess, and a guess
  here would be indistinguishable from a fix. Diagnose first.
- **The other `ex.Message` call sites.** The ~18 remaining each wrap ONE known call and
  name their own operation and file ("Failed to cache `<file>`: ...", "Failed to read decoy
  pairing manifest `<path>`: ..."), so the message is the useful part - and that holds
  whether the site then continues (most) or sets `ExitCode = 1` (`SpectraCacheTask`, the
  pairing-manifest read, the retained-base_id write, the strict resume rehydrate). The
  earlier wording here called them all "non-fatal", which `/code-review` correctly flagged
  as wrong; the scoping reason was never fatality but that a narrow, self-naming sink is
  not the defect. The defect is the two catch-alls at the end of the process, which can
  receive anything from anywhere and named nothing.
- **A usage-error type.** The review found the first cut turned CLI typos into a type name
  plus parser frames. Fixed by catching the parser's own exception types around
  `ParseArgs` and reporting the message alone, as `ValidateArgs` errors are; a dedicated
  usage-exception class would be cleaner but is a wider change than this fix warrants.

## Notes

- The blib is written last, after every expensive artifact is already computed and
  persisted. That ordering is what makes the 29-minute recovery possible, and is worth
  keeping.

## Progress Log

### 2026-09-12 - Rebased, reviewed, PR opened

Rebased onto master `7af9eb0ea5` (clean; the 38 intervening commits never touched the two
catch blocks). `/code-review max` returned 13 findings after its verification pass; applied:

* **Usage errors regressed to a type + parser frames** - the real one. `ParseArgs` is now
  wrapped in a catch for `ArgumentException` / `IOException` / `InvalidDataException` that
  logs the message alone; verified on the built exe (`Unknown argument: --bogus-flag...`,
  `Invalid value '7' for --fdrbench-pass...`, `--input-list file not found...` are each one
  line again).
* The `Program.Main` comment named "opening the library" as a failure that sink receives; it
  cannot (the pipeline's sink catches it - the forced-failure check proved exactly that).
* Dropped the `@` verbatim marker from the two user-facing format strings so the RESX sweep
  will find them.
* Commit message: developer-action verb ("Fixed ... to report"), `See TODO-...md in
  pwiz-ai/todos` form, 10 lines. Amended locally before any push.
* CHS README's example error line annotated with the new shape.

Dropped after verification: four more `ExitCode = 1` sinks that name their own context (see
the scope note above); Message-only warnings under `--task FirstPassFDR`; a
`PerFileRescoreTask` rethrow without `InnerException`; a test seam for the two sinks; a
comment quibble about which of the three example causes was the real one on 2026-08-21 (the
comment says they were INDISTINGUISHABLE, which is the point); merging the two sinks into
one helper. The reviewer also refuted its own OOM-ordering candidate.

Gate on the amended commit: both TFMs build, 593/593, inspection 0 warnings.
