# Osprey: gate the library-fragment release so it cannot silently stop happening

## Branch Information
- **Branch**: `Skyline/work/20260806_osprey_release_gate`
- **Created**: 2026-08-06
- **Status**: Completed
- **Module**: `osprey`
- **PR**: [#4539](https://github.com/ProteoWizard/pwiz/pull/4539) (merged 2026-08-07 as `5d54d0ef0a`)
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
* the HPC SecondPassFDR node realized zero saving

**Every one is in the uncovered column.** Not one was an over-release. So the class of defect
this feature keeps producing is precisely the class with no automated detection, and all three
were found by a human reading logs.

**Deleting the production call site today leaves the entire suite green** - unit tests and
`regression.ps1` alike.

Consequence if it regresses: nobody learns from a red build. They learn from an OOM at 82
files, which is the exact failure #4532 existed to prevent.

## Approach - assert the logs the harness already has

NOT a C# integration test. `regression.ps1` already runs every leg and already keeps each
leg's log; verifying SecondPassFDR on 2026-08-06 was a matter of reading them by hand. Turn
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
| HPC SecondPassFDR node | `phase4.log` | 1 line, 76,442 | present, > 0 |
| warm re-run | `warm.log` | 0 | none |

**CORRECTION to this file's first draft.** I wrote that `phase3_rescore_*` (the Stage 6 worker)
"releases nothing today". It DOES - 152,830 entries, via `FirstPassFdrTask.Rehydrate` reached
through a lazy `Demand`, even though `FirstPassFdrTask.IsIncluded` excludes it from that leg's
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
straight/straight.log FirstPassFDR:   152,830 of 485,628 (166,399 base_ids retained)
straight/straight.log SecondPassFDR node:        0 of 485,628 (166,399 base_ids retained)
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
`--task PerFileRescoring` workers, and SecondPassFDR. `--task FirstPassFDR`'s absence
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
- [x] `regression.ps1 -Dataset All` - **30/30 PASS**, mode 5 green on all four datasets. The
      three non-Stellar ones differ in decoy mode and had never exercised it; no calibration
      was needed, the release behaves identically across them.
      Log: `ai/.tmp/regression-all-mode5.log`
- [x] PR [#4539](https://github.com/ProteoWizard/pwiz/pull/4539)
- [x] Copilot review addressed (`31cf67966d`) + thread resolved
- [x] **Renumbered to mode 6** after #4537 landed its OWN mode 5 on master, and merged master in
      (`5fe225cf6c`). Post-merge `-Dataset All`: **44/44 PASS**, mode 5 and mode 6 green together
      on all four datasets
- [x] `/code-review max` - 15 findings. **12 were against #4537** (the review diffed a STALE
      local `master`); filed as [issue #4542](https://github.com/ProteoWizard/pwiz/issues/4542).
      3 were this PR's, all fixed - see below
- [x] Re-gate `-Dataset All` after the review fixes (`b478aecf88`) - see below
- [x] **Rebased onto [#4540](https://github.com/ProteoWizard/pwiz/pull/4540)** (merged
      `dce8841689`). Post-rename `-Dataset All`: **44/44 PASS**, mode 6 green on all four
      datasets. Pushed as `e597a3c27e`.
      Log: `ai/.tmp/regression-all-mode6-postrename.log`
- [x] TeamCity Perf/Regression **4124701 SUCCESS** on the merged tip `e597a3c27e` (SHA verified
      against the build, not assumed). 4123351 also passed but on `5fe225cf6c`, two merges back
- [x] Squash-merged as `5d54d0ef0a`

## SEQUENCING: #4540 merges first, this rebases onto it

[#4540](https://github.com/ProteoWizard/pwiz/pull/4540) - `osprey: Renamed the join tasks to
match their user-facing task Names` - touches **72 files including BOTH of this PR's**:
`regression.ps1` and `Regression/README.md`. It also renames `FirstJoinTask.cs` ->
`FirstPassFdrTask.cs` and `MergeNodeTask.cs` -> `SecondPassFdrTask.cs`.

Brendan's decision is that #4540 goes first. So after it merges, this branch must:

1. Merge master; expect conflicts in `regression.ps1` and `Regression/README.md`
2. Update **13 now-stale references in this PR's own added lines**: 4x `FirstJoinTask`,
   1x `MergeNodeTask`, 7x "merge node" (-> "SecondPassFDR node"), 1x
   `LoadOwnReconciliationBundle` (verify whether that method name survives the rename)
3. Re-run `-Dataset All` - the THIRD full gate on this branch
4. Only then ask about TeamCity

**Keep the pre-merge gate result as a bisection anchor.** If the post-#4540 gate goes red, the
green run on `b478aecf88` is what separates "my review fixes broke it" from "the merge did".
That is the whole reason it was not cancelled once #4540 was announced.

**Recorded, not re-argued**: merging this PR first would have let #4540's rename sweep pick up
those 13 references mechanically along with its other 72 files, saving a full `-Dataset All`
cycle and the hand-edit. Brendan chose the other order; the cost is ~2.5 h of gating, which is
wall-clock, not risk.

**Third time master moved under this branch** (#4534, #4537, #4540). The mode-5 numbering
collision came from the same overlap. A branch touching `regression.ps1` should assume it will
rebase at least once.

### The rebase, as done (2026-08-07)

Cheaper than feared. `regression.ps1` auto-merged; ONE conflict in `Regression/README.md`, and
it was precisely the line this PR had corrected ("Runs **last**") colliding with #4540's rename
of the same sentence ("SecondPassFDR leg"). Kept both: their wording, this PR's correction.

Then 13 stale references in THIS PR's own added lines: `FirstJoinTask` -> `FirstPassFdrTask`,
`MergeNodeTask` -> `SecondPassFdrTask`, "merge node" -> "SecondPassFDR node" (including the
user-visible `HPC SecondPassFDR node` failure label).

**Two things checked rather than assumed**, both of which could have silently broken mode 6:

* **The release LOG TEXT survived the rename.** Mode 6 keys on log wording, not class names,
  so a reworded message would have killed `$releaseLinePattern` outright. Both format strings
  are intact (`FirstPassFdrTask.cs:2084`, `SecondPassFdrTask.cs:279`). The new run-wide
  liveness assertion would have caught it, but knowing beforehand beats a red gate.
* **The chain log copies are transparent to the directory rename.** #4540 renamed
  `phase4_mergenode` -> `phase4_SecondPassFDR`; the `Copy-Item` calls use the `$ph4` variable,
  so nothing needed changing.

## THE REVIEW FOUND A HOLE IN THE GATE - and a claim of mine that was false

**`/code-review max`, finding A: mode 6's resume check does NOT cover `Rehydrate`.** I asserted
- in the PR body, in this TODO, and in a code comment - that the resume leg exercises
"`FirstJoinTask.Rehydrate`, the path that shipped broken in #4534". It does not. The evidence
was in the file I was editing:

* `Invoke-ResumeInvalidation` deletes `*.FirstPassFDR.osprey.task`
* mode 2 asserts `-ExpectRan @('FirstPassFDR', 'SecondPassFDR')` on that very log

So the resume leg **RUNS** FirstPassFDR. What was actually covered: `Run` (straight-through,
resume) and `Rehydrate` via a **worker-supplied** bundle (phase 3). What was covered ZERO
times: the **own-sidecar** rehydrate arm - `LoadOwnReconciliationBundle` /
`StreamOwnReconciliationBundle` - which is exactly what #4537's new mode 5 exercises via
`rehydrate.log`, a log mode 6 never read.

Demonstrable: delete the release from that call site, run `-SkipHpcChain`, and mode 6 reports
PASS having asserted it zero times. **A hole in a gate whose entire purpose is closing holes.**

Fixed by adding a `rehydrate.log` entry inside the `-not $SkipRehydrate` branch. It PASSES,
so `StreamOwnReconciliationBundle` does populate `GlobalFirstPassBaseIds` and the arm really
does release - no latent defect, but it was unasserted.

**Finding B: `-ExpectNone` was structurally vacuous.** It returns PASS on an empty result, so
it could not distinguish "this leg correctly released nothing" from "the C# wording drifted and
the regex matches nothing anywhere". It only failed closed by accident, because the sibling
`-ExpectScopes` checks break on the same drift - an accident of which legs are enabled, not a
design. Closed with a run-wide liveness assertion: if the pattern matches nothing in ANY leg,
that is itself the failure. **A negative assertion cannot fail closed by itself** - worth
carrying to any future log-scraping gate.

**Finding C**: mode 6 was undocumented in `Regression/README.md`, and mode 5's "Runs last" was
left false by the renumber. Both fixed.

**Process note**: the review diffed `master...HEAD` against the LOCAL `master` ref, which was
stale at `988c73c294` because /pw-complete had synced it before #4537 landed. Three quarters of
its findings were therefore about someone else's merged code. `git fetch` before a review, or
diff against `origin/master`.

## THE COLLISION - two mode 5s (2026-08-06)

PR [#4537](https://github.com/ProteoWizard/pwiz/pull/4537) merged to master while this branch
was open and added its own **mode 5** (Stage-5 rehydrate self-consistency). A real numbering
collision, not a textual conflict. Master's landed first and keeps the number; this became
**mode 6**.

Resolved by taking master's `regression.ps1` as the new baseline and RE-APPLYING these
additions on top, rather than hand-resolving three conflict hunks - the change is purely
additive, so a re-apply cannot silently drop one of master's lines the way a hand merge can.
Verified after: 0 conflict markers, 0 stale `mode5 (library-fragment` references, master's 12
mode-5 references intact, parse clean, and still **230 insertions / 0 deletions** against the
new master.

**The integration risk was real and is now cleared.** #4537 changed `FirstJoinTask`'s rehydrate
path - the same path mode 6 asserts a release on - so the two had never run together. The
resume leg passes on all four datasets post-merge.

Also: the `appveyor` FAILURE on the PR was `"AppVeyor was unable to build non-mergeable pull
request"` - a consequence of the conflict, not of the code. It cleared on pushing the merge.
Worth recognizing rather than investigating next time.

## Progress Log

### 2026-08-07 - Merged

PR #4539 merged as commit `5d54d0ef0a`. Shipped regression **mode 6**: a leg-level assertion,
read from each leg's own log, that the library-fragment release RAN on every leg holding the
library - straight-through, resume, the own-sidecar rehydrate, each `--task PerFileRescoring`
worker, and the `SecondPassFDR` node - and did NOT run on `--task FirstPassFDR`. Plus the chain
phase-log preservation that makes it work in the default (CI) mode, and a run-wide pattern
liveness check so a reworded C# line fails the gate rather than quietly satisfying the
must-not-release leg. Test harness only: `regression.ps1` + `Regression/README.md`, 268
insertions / 0 deletions against master, no product code.

Gates: `-Dataset All` 44/44 twice (pre- and post-rename), 576 unit tests, zero inspection
warnings, TeamCity 4124701 green on the merged tip, and the break test showing modes 1-5 green
with the feature disabled while only mode 6 goes red.

**Nothing was deferred from this PR's own scope.** Two things it deliberately did not take on,
both recorded above: releasing on the `--task PerFileRescoring` Stage 6 worker, and bounding
`FragmentMath._top6MzCache` during Stages 3-4 rather than only clearing it at the release point.

Follow-up filed: [issue #4542](https://github.com/ProteoWizard/pwiz/issues/4542) - 12
code-review findings against #4537's already-merged code, surfaced because the review diffed a
stale local `master`. Three look behavioral. Filed WITHOUT independent verification; they need
checking before anyone acts on them.

Branches were held after merge at Brendan's instruction while a stacked branch was rebased onto
master, then deleted.


### 2026-08-06 - opened

Split out after #4534 merged. Brendan flagged that deferring this may have been hasty; the
review of the coverage picture agreed - and sharpened it. My own earlier claim that
"`regression.ps1` mode1/mode3 covers it" was WRONG, and worth recording as the reason this
TODO exists: mode1 proves the release is HARMLESS (the committed golden predates it, so
matching proves output-neutrality). It does not prove the release HAPPENED. Those are
different properties and I conflated them.
