# TODO-20260704_osprey_filesaver_atomic_writes.md -- Route durable Osprey writes through FileSaver (atomic same-directory rename)

## Status
**Completed.** PR [#4366](https://github.com/ProteoWizard/pwiz/pull/4366) merged
2026-07-05 as `4e777a7f25`. Issue **#4356** auto-closed via `Fixes #4356`.

### 2026-07-05 - Merged
PR #4366 merged (squash `4e777a7f25`). Shipped exactly the branch contents: FileSaver
moved to `Osprey.Core`, 7 durable writers routed through it, the parquet cross-volume
`File.Move` truncation risk fixed, and a new `FileSaverTest` (added during self-review,
alongside a comment documenting the BlibWriter WAL-checkpoint reliance). All gates green:
`regression.ps1 -Dataset Stellar` byte-identical (mode1/2/3), 448 unit tests, 0 new
inspection warnings, and the full TeamCity Stellar+Astral Perf/Regression SUCCESS. A
comment on #4356 recommends closing it (the copy_and_verify port is unnecessary: FileSaver's
same-directory rename is atomic and cannot truncate). Self-review was clean after the WAL
comment + FileSaverTest were added.

## What is on the branch (build + 447 unit tests GREEN)
- Moved `FileSaver` from `Osprey.IO` to `Osprey.Core` so every project can use it.
- Routed 7 durable-artifact writers through FileSaver (write to a same-directory sibling
  temp; atomic rename on `Commit`): `calibration.json`, `.osprey.task`, `.spectra.bin`,
  `.libcache`, `.scores.parquet` (both `WriteScoresParquet` overloads), `.blib`,
  `--fdrbench` input.
- Fixed the parquet cross-volume `File.Move` (temp in `Path.GetTempPath()` -> output dir)
  that could truncate on NAS -- the actual #4356 risk, present in our own code.
- Updated `TestStampSwallowsWriteFailure` for FileSaver's directory-create behavior.

## To finish (also in ai/.tmp/handoff-20260704-osprey-multipr.md, "PR 0")
1. `regression.ps1 -Dataset Stellar` -- golden MUST stay byte-identical (FileSaver only
   changes WHERE the temp sits, not final bytes; any diff = a real bug to chase).
2. `/pw-self-review` -- a sub-agent wrote the 9 converted files; re-scan for style nits
   (single-line `if`, etc.).
3. `gh pr create` -- `Fixes #4356`; credit `Reported by Michael.` (Mike raised #4356).
4. Comment on #4356 and recommend CLOSE: FileSaver already provides the temp->atomic-rename
   pattern; the real find was our parquet cross-volume `File.Move` (now fixed);
   `copy_and_verify` is unnecessary because a same-directory rename is atomic and cannot
   truncate.
5. Guide doc already committed (pwiz-ai `870ab3b`): the "Atomic file writes: FileSaver"
   section + the "Conventions -- read this first" callout.

## References
- Issue #4356. Canonical FileSaver usage: `Osprey.IO/FdrScoresSidecar.cs`.
- Guide: `ai/docs/osprey-development-guide.md` ("Atomic file writes: FileSaver").
