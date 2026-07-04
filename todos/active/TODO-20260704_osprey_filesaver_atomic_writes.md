# TODO-20260704_osprey_filesaver_atomic_writes.md -- Route durable Osprey writes through FileSaver (atomic same-directory rename)

## Status
Active (brendanx67). Branch `Skyline/work/20260704_osprey_filesaver_atomic_writes`
(commit `1ebf4bc0e0`, pushed). Issue: **#4356**. Started 2026-07-04.

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
