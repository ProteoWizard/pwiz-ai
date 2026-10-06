# TODO: Check a file's charges once per process under library identity

## Branch Information
- **Branch**: `Skyline/work/20261005_osprey_charge_check_once` (`C:\proj\pwiz-work1` on the i9)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), branched at `1ee7a12bd1`
- **Created**: 2026-10-05
- **Status**: Committed locally (not pushed). Gates: inspection 0/0, unit 651/651. Next: push, /code-review, PR.
- **Module**: `osprey`
- **PR**: (pending)

## Problem

Uncontested CHS 446 FirstPassFDR on the merged #4765 (`effd991447`) took 9,450 s, 6.7% slower than
the pre-review build (8,856.5 s) while reading fewer bytes (933 vs 1,119 GB) over more reads
(465,227 vs 382,901): ~30 extra reads per file in every stub walk (pass 0, 1, 2, protein resolve,
both planning passes), none in the training feature load. See the completed
`TODO-20260926_osprey_firstpassfdr_parallel.md`.

## Isolation (HDD D:, CHS 128 files, 3 lanes, gate on, cold)

| arm | FirstPassFDR | reads | GB read | disk read s |
|---|---|---|---|---|
| merged (A) | 2,054.0 | 136,071 | 274.1 | 1,572 |
| pre-review BlockReadStream (cf8294ae18) | 2,061.6 | 135,175 | 329.0 | 1,554 |
| merged, PlanSpan does not stop at delivered chunks | 2,006.7 | 136,071 | 322.6 | 1,532 |
| merged, no exact head/footer reads | 2,058.8 | 135,175 | 280.5 | 1,541 |
| merged (A again) | 2,043.3 | 136,071 | 274.1 | 1,525 |
| **merged, RequireFileCharges off** | **1,992.0** | **112,830** | 273.1 | 1,471 |
| pre-review build v6 (2026-10-03) | 1,997.3 | 111,934 | 327.8 | 1,497 |
| **fix: charges checked once per file** | **1,995.2** | **116,731** | 273.3 | 1,482 |

BlockReadStream's review changes are time-neutral and save ~16% of bytes. Root cause: #4765 review
fix #2 (`RequireFileCharges`) decodes the charge column in every library-identity walk; the column
is outside the span the identity walk otherwise reads, so it is a seek per row group per walk.
Fix: `_chargesChecked` (process-wide, by path) - first walk checks, later walks skip; a walk that
throws does not mark the file. Outputs: 514/514 identical to the merged arm and to `hash128-l1`.
Logs: `D:\test\osprey-runs\chs-seer\runs\chs-128files-...-hdd-ab-*`; builds `D:\test\osprey-runs\_bin\{blockab-*,chargeonce}`.

## Remaining
- [ ] Push, `/code-review` (diff is ~30 lines), open PR against the port branch with label `osprey`
- [ ] regression-parallel All on the branch; TeamCity Perf/Regression before merge (ask first)
- [ ] Optional: CHS 446 uncontested on the fix (expect ~8,850 s)

## Notes
- 2026-10-05: the port branch was force-pushed after #4765 merged (`effd991447` -> `f7021e609c`, same
  patch-id, identical Osprey tree). The local `Skyline/work/20260612_net8_port` in `pwiz-work1` still
  points at the pre-rewrite history; reset it to origin rather than pulling.
