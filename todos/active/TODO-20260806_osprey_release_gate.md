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

Per-leg expectations (**to be calibrated against an observation run before being asserted** -
do not write these from reasoning alone, that is how the original defects got in):

| leg | log | expectation |
|---|---|---|
| straight-through | `straight.log` | FirstJoin release line, released > 0 |
| straight-through | `straight.log` | merge-node release line present (count may legitimately be 0 - FirstJoin already released in-process) |
| resume | `resume.log` | release line, released > 0 - this is the Rehydrate path that shipped broken |
| HPC `--task FirstPassFDR` | `phase2.log` | **NO release line at all** - locks in the fabricated-saving fix |
| HPC merge node | `phase4.log` | release line, released > 0 |

Deliberately NOT asserted: `phase3_rescore_*` (the Stage 6 worker). It releases nothing today,
and that is a known gap rather than intended behavior - asserting its absence would lock in
something we may want to change.

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

## Tasks

- [ ] Observation run (`-Dataset Stellar -KeepOutput`) to read what every leg actually logs,
      resume included
- [ ] Assertion helper in `regression.ps1`, calibrated to the observation
- [ ] Verify it FAILS when the release is disabled (`OSPREY_RELEASE_LIBRARY_FRAGMENTS=0`) -
      a gate never seen red is not a gate
- [ ] `regression.ps1 -Dataset Stellar` green with the assertion in place
- [ ] PR

## Progress Log

### 2026-08-06 - opened

Split out after #4534 merged. Brendan flagged that deferring this may have been hasty; the
review of the coverage picture agreed - and sharpened it. My own earlier claim that
"`regression.ps1` mode1/mode3 covers it" was WRONG, and worth recording as the reason this
TODO exists: mode1 proves the release is HARMLESS (the committed golden predates it, so
matching proves output-neutrality). It does not prove the release HAPPENED. Those are
different properties and I conflated them.
