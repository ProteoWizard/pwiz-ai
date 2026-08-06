# Osprey: gate the library-fragment release so it cannot silently stop happening

## Branch Information
- **Branch**: `Skyline/work/20260806_osprey_release_gate`
- **Created**: 2026-08-06
- **Status**: In Progress
- **Module**: `osprey`
- **Follows**: [TODO-20260805_osprey_library_fragment_release.md](../completed/TODO-20260805_osprey_library_fragment_release.md)
  (#4532, merged as `988c73c294`)

## Why this exists

The library-fragment release is **output-neutral by design**. That is its safety argument -
and it is also why no gate can currently tell whether it ran.

Split the failure modes:

| If the release... | What happens | Caught by |
|---|---|---|
| releases TOO MUCH | tripwire throws when Stage 6 or the blib reads a released entry | regression, loudly |
| **does not run at all** | output byte-identical, saving silently gone | **nothing** |
| **runs but frees nothing** | output identical, log claims millions released | **nothing** |

Now compare against the defects `/code-review max` actually found on #4534:

* the Rehydrate (RESUME) path never released
* `--task FirstPassFDR` fabricated a saving - printed millions released having freed ZERO,
  directly above a [MEM] probe an HPC sizing A/B would read as measured
* the HPC merge node realized zero saving

**Every one is in the uncovered column.** Not one was an over-release. So the class of defect
this feature keeps producing is precisely the class with no automated detection, and all three
were found by a human reading logs.

**Deleting the production call site today leaves the entire suite green** - unit tests and
`regression.ps1` alike.

Consequence if it regresses: nobody learns from a red build. They learn from an OOM at 82
files, which is the exact failure #4532 existed to prevent.

## Approach - assert the logs the harness already has

NOT a C# integration test. `regression.ps1` already runs every leg and already keeps each
leg's log; verifying the merge node on 2026-08-06 was a matter of reading them by hand. Turn
that manual read into an assertion.

Per-leg expectations, **calibrated against an observation run** (`-Dataset Stellar -KeepOutput`,
run dir `regression-20260806_061531`) rather than written from reasoning - which is how the
original defects got in, and which caught two of my own assumptions wrong:

| leg | log | observed | assert |
|---|---|---|---|
| straight-through | `straight.log` | 2 lines: 152,830 then 0 | both scopes present, rescore line > 0 |
| resume (Rehydrate) | `resume.log` | 2 lines: 152,830 then 0 | both scopes present, rescore line > 0 |
| HPC `--task PerFileScoring` | `phase1.log` | 0 | none |
| HPC `--task FirstPassFDR` | `phase2.log` | **0** | **none** - locks in the fabricated-saving fix |
| HPC `--task PerFileRescoring` | `phase3.log` x3 | 1 line, 152,830 | present, > 0 |
| HPC merge node | `phase4.log` | 1 line, 76,442 | present, > 0 |
| warm re-run | `warm.log` | 0 | none |

**CORRECTION to this file's first draft.** I wrote that `phase3_rescore_*` (the Stage 6 worker)
"releases nothing today". It DOES - 152,830 entries, via `FirstJoinTask.Rehydrate` reached
through a lazy `Demand`, even though `FirstJoinTask.IsIncluded` excludes it from that leg's
pipeline. So the Stage 6 worker is already covered and IS assertable. I also nearly asserted a
release on the warm re-run leg, which legitimately does no work at all and logs nothing - that
would have been a false red on every run.

Assert PRESENCE/ABSENCE and `released > 0`, NOT exact counts: counts move with any scoring
change and a gate that cries wolf gets ignored. The three real defect classes are all caught by
presence plus non-zero.

Follow the established harness pattern: `$summaryLines.Add("$name modeN (...): PASS")`, and on
failure set `$overallFail = $true` plus `Write-Problem-Tc`.

## Reference numbers (2026-08-06, Stellar, from the #4534 verification)

```
chain/phase4_mergenode/phase4.log:  76,442 of 242,841 (166,399 base_ids retained)
straight/straight.log FirstJoin:   152,830 of 485,628 (166,399 base_ids retained)
straight/straight.log merge node:        0 of 485,628 (166,399 base_ids retained)
```

242,841 vs 485,628 because `ExpectReconciledInput` skips the decoy rebuild. Retained base_ids
match across all three, which is the cross-check that the reported-pool set and the
survivors+gap-fill set agree.

## THE BREAK TEST - the gate is a gate (2026-08-06)

`regression.ps1 -Dataset Stellar` with `OSPREY_RELEASE_LIBRARY_FRAGMENTS=0`, i.e. the feature
switched off entirely:

| mode | result |
|---|---|
| mode1 (vs golden) | **PASS** |
| mode2 (resume cache hits) | **PASS** |
| mode2 (resume==straight) | **PASS** |
| mode3 (HPC chain==straight) | **PASS** |
| mode4 (warm re-run all cached) | **PASS** |
| **mode5 (release engaged)** | **FAIL - 8 issues** |

Five independent correctness assertions stay green with the feature OFF. Only mode 5 sees it,
and it names every leg: straight-through (both scopes), resume (both scopes), all three
`--task PerFileRescoring` workers, and the merge node. `--task FirstPassFDR`'s absence
assertion correctly stayed quiet.

**That is the argument for this PR, measured rather than reasoned.** It is also exactly the
blind spot that let three wiring defects through the #4534 review.

## Mode 5 caught a defect in ITSELF first

Its first run went red because the HPC chain frees phases 1, 2 and every phase-3 worker
mid-run to bound peak disk - so those logs exist only under `-KeepOutput`, and my observation
run had `-KeepOutput` set, which masked it. Same shape as the bug class this gate targets:
something that looks verified because the verification ran under conditions the real path does
not have.

Fix: copy each phase log into `<chain>\logs\` as the phase finishes. A few KB survives; the
multi-GB inputs still do not, so the disk-bounding behaviour is unchanged.

## Tasks

- [x] Observation run (`-Dataset Stellar -KeepOutput`) to read what every leg actually logs,
      resume included - corrected TWO wrong assumptions before they became assertions
- [x] Assertion helper in `regression.ps1`, calibrated to the observation
- [x] Preserve chain phase logs so the assertion works in the DEFAULT (CI) mode, not just
      under `-KeepOutput`
- [x] Verify it FAILS when the release is disabled - a gate never seen red is not a gate
- [x] `regression.ps1 -Dataset Stellar` green with the assertion in place
- [ ] `regression.ps1 -Dataset All` - mode 5 now runs on all four datasets and only Stellar
      has been exercised; the others differ in decoy mode and could plausibly log different
      scopes
- [ ] PR

## Progress Log

### 2026-08-06 - opened

Split out after #4534 merged. Brendan flagged that deferring this may have been hasty; the
review of the coverage picture agreed - and sharpened it. My own earlier claim that
"`regression.ps1` mode1/mode3 covers it" was WRONG, and worth recording as the reason this
TODO exists: mode1 proves the release is HARMLESS (the committed golden predates it, so
matching proves output-neutrality). It does not prove the release HAPPENED. Those are
different properties and I conflated them.
