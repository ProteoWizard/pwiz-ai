# Straight-through drops Score and RunProteinQvalue that the task-by-task route keeps

## Branch Information
- **Branch**: `Skyline/work/20260809_fdr_sidecar_parity`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-08-09
- **Status**: In Progress - both fixes written and green on Stellar (regression mode 3 +
  cross-impl all legs); awaiting `-Dataset All`, then the approved golden rebaseline
- **GitHub Issue**: [#4553](https://github.com/ProteoWizard/pwiz/issues/4553)
- **Module**: `osprey`
- **Other labels**: none yet (candidate: `bug`)
- **PR**: [#4557](https://github.com/ProteoWizard/pwiz/pull/4557) (pwiz, label `osprey`) +
  [maccoss/osprey#61](https://github.com/maccoss/osprey/pull/61) (Rust, branch
  `fix/pass2-restore-pass1-scalars`) - both opened 2026-08-10, reviews to follow
- **Requester/Reporter**: none - found by Brendan and Claude while building the FDRBench
  oracle for #4486. No credit line (Osprey developers on Osprey code).

## Objective

The straight-through pipeline and the four-task (`--task`) route write DIFFERENT values
into every `<stem>.2nd-pass.fdr_scores.bin`, and no gate compares that file. Add the
comparison (it goes red immediately), then fix the divergence.

## Root cause - ALREADY DIAGNOSED, do not re-derive

`OverlayRescoredEntries` (`PerFileRescoreTask.cs:1437`) calls `FdrEntry.ResetScores()` on
every entry Stage 6 touches - both the successfully rescored ones (`:1459`) and the
"no peak at the override boundary" ones (`:1468`). `ResetScores()` (`FdrEntry.cs:169`)
clears EIGHT fields:

```
Score = 0.0;  RunPrecursorQvalue = 1.0;  RunPeptideQvalue = 1.0;  RunProteinQvalue = 1.0;
ExperimentPrecursorQvalue = 1.0;  ExperimentPeptideQvalue = 1.0;
ExperimentProteinQvalue = 1.0;  Pep = 1.0;
```

The DEFAULT pass-2 mode (`protein-compact`, via `ComputePass2TransferCompeteFull`) writes
back only five of them - `RunPrecursorQvalue`, `RunPeptideQvalue`,
`ExperimentPrecursorQvalue`, `ExperimentPeptideQvalue`, `Pep`. It never writes `Score` or
`RunProteinQvalue`, so those two are persisted at their reset defaults.

**Why the task-by-task route is unaffected**: `--task SecondPassFDR` cannot use live
in-memory state, so it rehydrates from `.1st-pass.fdr_scores.bin` and
`OverlayFirstPassSidecar` writes all seven scalar fields back - including the two nothing
else restores. The distributed route accidentally REPAIRS what the in-process route drops.
So the more-correct output comes from the path we would have assumed was riskier.

The sibling mode does it right: `AssignPerRunQ` (`OSPREY_PASS2_QVALUE=transfer`) sets
`entry.Score` on all three of its branches. Only the frozen-competition modes
(`transfer-compete`, `protein-compact`) omit it.

## Measured (StellarGenDecoyEntrap, 3 files, 260,419 records)

Each route's OWN 1st-pass sidecar vs its 2nd-pass sidecar:

| | straight-through | task-by-task |
|---|---|---|
| `score`: real in 1st -> **0** in 2nd | **99,992** | 0 |
| `run_protein_qvalue`: real in 1st -> **1.0** in 2nd | **32,450** | 0 |
| `protq`: 1.0 in both (legitimately) | 129,627 | 129,627 |
| `score`: eid absent from 1st-pass (gap-fill) | 741 | 741 |

Zero-score totals in the straight-through 2nd-pass sidecar: **100,733 of 260,419 (39%)** -
targets 33,207 and decoys 67,526. Decoys are hit at 52% vs targets at 25%, so the persisted
null is disproportionately zeroed. At 82 files the protein-q divergence is 1,355,103 of
86,581,597 (1.57%).

Protein-level consistency (Brendan's invariant - all peptides of a protein should share a
protein q): straight-through leaves **14,325 of 28,806 proteins mixed** (some peptides real,
some 1.0); the task route leaves **622**. No protein on either route has two DIFFERENT real
values, so the q itself is consistent - only its propagation is not.

## Why no gate sees it

* `regression.ps1`'s four-task-chain leg asserts `Compare-BlibFull` and nothing else about
  per-file outputs. Protein q and per-entry SVM score are not in the blib, and they move no
  count the gate reads: peptides at 1% experiment FDR (26,714), protein groups passing 1%
  (21,861) and the blib (23,292 spectra from 69,876 passing entries) are IDENTICAL between
  the two routes.
* The cross-impl C#/Rust comparison does not cover it either. Both
  `Compare-EndToEnd-Crossimpl.ps1` and the committed golden compare the Stage 7 protein FDR
  dump, whose columns are per-protein-GROUP (`accessions, n_unique, n_shared,
  best_peptide_score, group_qvalue, is_target_winner`); its emitter notes it "reads only the
  parsimony / FDR result (not the stubs)". These fields live on the stubs.

## INCOMING from the #4522 branch (peak co-assignment) - 2026-08-10

From the session on `Skyline/work/20260808_peak_coassignment_diagnostics`, after pulling this
TODO. Full context in `TODO-20260808_peak_coassignment_diagnostics.md`, section
"FOR THE #4553 SESSION". Two asks, both small if done with your fix and unpleasant at merge.

**Your diagnosis explains that branch's pass-2 numbers.** Its co-assignment panel reports 36,228
decoys at pass 2 against ~23-25k targets. Its decoy acceptance boundary is the minimum score over
accepted target/entrapment precursors, so your 67,526 zeroed decoy records collapse it to ~0 and
admit nearly everything. That row is a symptom of #4553, not a second bug; that branch is not
touching pass 2 until this lands. Its pass-1 numbers are unaffected.

**Ask 1 - a FOURTH field for your seeding fix.** #4522 adds
`FdrEntry.ExperimentAggregateScore` and clears it in `ResetScores()` alongside `Score`. It added
a carry in `AssignPerRunQ` (the mode you correctly identify as already right) but NOT in
`ComputePass2TransferCompeteFull`, so on the DEFAULT mode it is dropped by exactly your
five-of-eight defect. It needs seeding from the 1st-pass sidecar with `Score` / `Pep` /
`RunProteinQvalue`, on both C# and Rust. Since your list already grew from two to three, driving
the seeding off the record layout rather than an enumerated list would close this class of bug.

**Ask 2 - your sidecar decoder needs the v4 layout.** #4522 bumps the record from **60 bytes /
seven scalars to 68 bytes / eight** (`experiment_aggregate_score` at `[60..68]`, version byte
3 -> 4), in C# and Rust. `Regression/FdrSidecars.ps1` and therefore
`Compare-FdrSidecars-Crossimpl.ps1` need the bump plus a comparison arm for the new field. Your
script SKIPs cleanly on a missing helper (exit 3) but has no guard for a format mismatch - a v4
file against a v3 decoder is a silent misparse.

**Ordering agreed with Brendan**: #4553 lands first, #4522 rebases onto it, then ONE joint golden
rebaseline. #4522's pass-1 numbers do not move under your fix but its pass-2 numbers will, so it
must not bless goldens first.

## REPLY to the #4522 branch - 2026-08-10

Both asks read and agreed. Your pass-2 decoy row being a symptom rather than a second bug
matches from this side too: the 67,526 zeroed decoy records are 52% of decoys against 25%
of targets, so any statistic whose boundary is a min-over-accepted-scores collapses.

**Ask 2, the silent-misparse half: DONE on this branch, you inherit it.**
`FdrSidecars.ps1` now validates magic bytes AND the version byte, and names the reason:

```
... unreadable on the expected side: sidecar format version 4, but this comparison
decodes version 3 (60-byte records). Update FdrSidecars.ps1 for the newer layout.
```

Verified against a synthetic v4 file. Note the old size-only check WOULD have rejected a v4
file, but only because 68 and 60 happen not to divide alike - luck, not a guard. **The v4
decoding itself is yours to add after you rebase**, since implementing an unmerged format
from this side is how the ai/-vs-pwiz breakage below happened.

**Ask 1: your field is a one-line addition to each side of my fix, after you rebase.**
Do NOT wait on me - `ExperimentAggregateScore` does not exist on this branch, so I cannot
gate a seeding change for it. The two places:

* C# `Pass2FdrSidecar.RestorePass1Scalars` - the `rec => { ... }` callback, alongside
  `entry.Score` / `entry.Pep` / `entry.RunProteinQvalue`.
* Rust `restore_pass1_scalars` - the `if let Some(&(score, pep, run_protein_q))` destructure,
  plus widening `read_fdr_scores_pass1_scalars`'s tuple.

**On driving it off the layout - agreed in spirit, and I would go further: invert the
default.** Seed everything the record carries EXCEPT an explicit exclusion list of the
fields pass 2 provably rewrites. A newly added field is then seeded automatically instead of
silently dropped, which is exactly the failure mode that took this from two fields to three
mid-session.

**Caveat before anyone implements that: it is NOT behavior-neutral.** Seeding the run and
experiment q-values changes entries that are absent from `run_q` and currently `continue`
past the map-back keeping the reset 1.0. That needs its own `-Dataset All`, not a blind
flip. Suggest it lands on your branch, where it can be gated together with the v4 format
that makes it matter.

**BRANCH IS PUSHED - rebase away.** `Skyline/work/20260809_fdr_sidecar_parity` at
`a23e246fd0` (force-pushed; it was rebased onto master this morning, so re-fetch rather
than merging your old copy). Three commits:

* `9b4b292275` the failing sidecar comparison
* `c056a7f88c` the fix - **this is the one you extend** with `ExperimentAggregateScore`
* `a23e246fd0` the golden rebaseline, deliberately SEPARATE so it can be dropped without
  touching the fix

Rust side is `maccoss/osprey` branch `fix/pass2-restore-pass1-scalars` (commit `6548ea9`),
PR to be opened alongside the pwiz one.

**Golden rebaseline - one or two? OPEN, with Brendan.** Reading "then ONE golden
rebaseline" as *mine is the one* (this branch lands first, you inherit a correct baseline,
master is never red). The alternative - neither branch blesses until both are in - means
this branch merges with `mode1` red on all four datasets. Proceeding on the first reading,
but the golden is committed SEPARATELY from the code so dropping it is one commit, not a
rebase. If you need the other ordering, say so and it comes back out.

## Review round 1 - Copilot (2) + `/code-review max` (15) - 2026-08-10

Every finding verified against the code before acting; two were pushed back on rather than
applied. Testing the FIRST round of fixes caught a bug in my own fix (`-f` binds tighter
than `+` in PowerShell, so the new message emitted raw `{0}` braces), which is why the
comparer now has a 10-case suite: `ai/.tmp/test_sidecar_comparer.ps1`.

**Applied.** The comparer was rewritten rather than patched finding-by-finding:

| finding | what was wrong | fix |
|---|---|---|
| Copilot 1 / cr 4 | Only intersecting entry_ids compared; count arithmetic missed set differences and went NEGATIVE on duplicates | TRUE set difference over distinct ids, duplicates counted and reported |
| Copilot 2 | Short-header / size-mismatch returned null with no reason | Named problem on every path |
| cr 2 | Header pass byte at [9] never validated - a mis-stamped sidecar every canonical reader REJECTS would compare PASS | `-Pass` now validated against the header |
| cr 3 | `Offsets[]` / `FieldNames[]` parallel arrays separately bounded the compare and report loops - extending one silently green | ONE `Fields[]` table; it cannot drift against itself |
| cr 5 | `Compared` computed and never read - zero-record sidecars reported PASS | Liveness assert in the comparer AND in regression.ps1; PASS line now prints the record count |
| cr 9 | Unchecked `ulong` size arithmetic wraps, then walks off the buffer and kills every remaining dataset | `checked`, matching the canonical reader |
| cr 10 | `File.ReadAllBytes` unguarded, throwing out of an `Add-Type` static under `$ErrorActionPreference='Stop'` | try/catch to an issue line |
| cr 11 | Last-wins duplicate map: byte-identical files could report a diff, and drift in a non-last duplicate was invisible | duplicates reported explicitly |
| cr 14 | `Math.Abs(NaN-NaN)` is NaN, so byte-identical NaN records "differed" | bit-equality fast path first |
| cr 6 / 13 | Comments factually wrong: `transfer` IS a frozen mode and DOES write Score; "recomputes five" did not reconcile; and Score IS an input to Stage-8 protein FDR | corrected; the warning now states the real consequence |
| cr 12 | `ReadRecords` may return false AFTER partial callbacks; mutating in the callback left a half-seeded pool | stage into a buffer, apply only on a clean read |
| cr 15 | The restore's whole-run sidecar read was billed to `[STAGE-WALL] second-pass-fdr` | own stopwatch, own line |
| secondary | `blib_summary.tsv` 3-ULP rebaseline was unnecessary (that gate is RELATIVE 1e-6) | reverted; golden diff is now protein_fdr only |
| secondary | mode 3 wired only `-Pass 2` though pass 1 is now an INPUT to pass 2 | both passes compared, prefixed so the stage is unambiguous |

### cr 7 TESTED, not argued - and it points the other way

Ran `regression.ps1 -Dataset Stellar` with `OSPREY_FDR_PROJECTION=0` to exercise the
batch-hydrate arm directly (log: `ai/.tmp/regression-projoff4.log`). Three assertions fail
there, none caused by this branch, and `mode1 (vs golden)` PASSES so the output is correct:

* **mode 3** - `run_protein_qvalue` differs on 133/116/141 records. **All 390 are ABSENT from
  the 1st-pass sidecar** - gap-fill entries created in Stage 6 - so the seed provably cannot
  touch them (it only reads sidecar records). Every other field agrees on those same records
  (0 mismatches) and the two 1st-pass sidecars agree exactly (0 of 482,891). What actually
  differs: the chain's SecondPassFDR node recomputes protein q via
  `ProteinFdrEngine.RunFirstPass` and assigns **0.0** to gap-fill entries, while
  straight-through leaves them at **1.0** because nothing assigns one. So the finding's
  direction is inverted - the chain ASSIGNS a value the seed cannot reach, rather than the
  seed clobbering a good one. Pre-existing on both sides; the sidecars were never compared
  before. **Worth a follow-up issue**: should a gap-fill entry carry a run protein q at all?
* **mode 5** - asserts a log line for the STREAMING rehydrate, which this switch disables.
* **mode 6** - `Scopes present: (none)`; the library-fragment release does not engage on this
  arm at all.

5 and 6 are default-arm assertions firing against a switch that turns those paths off. This
branch adds no streaming, release or logging behavior that could affect either.

Two false starts on this test were mine, not the code's: `OSPREY_ALLOW_UNFIXED_RESIDENT=1`
(it takes NAMED tokens - `projection-off`), then shell quoting delivering the token with
literal quotes. Both times the guard named exactly what was wrong. Wrapper that gets it
right: `ai/.tmp/run-projoff.ps1`.

**Pushed back, left for human review:**

* **cr 7 (batch-hydrate clobber)** - reads the cited evidence backwards, I believe. The
  comment at `PerFileRescoreTask.cs:514-519` says the pre-existing sidecar divergence "is
  tracked separately in **#4553**, which also covers the regression.ps1 gap that lets it
  pass green (mode 3 compares the blib, never these sidecars)" - i.e. THIS issue and the
  very leg added here. Mode 3 is now green on all four datasets, so the seed makes the two
  routes agree, which is the stated goal. Tested directly with `OSPREY_FDR_PROJECTION=0`
  to exercise the batch-hydrate arm rather than argue it.
* **cr 8 (off-stratum mixed provenance)** - real observation, genuine design question: an
  off-stratum survivor ends with pass-2 Score and pass-1 experiment q / Pep. Which
  provenance that row SHOULD carry is a decision about the protein-compact contract, not a
  defect in this fix, and it is not a change to make unreviewed. Worth deciding alongside
  #4522's `ExperimentAggregateScore` work, which touches the same map-back.

**Golden disclosure corrected.** Commit `a23e246fd0`'s message overclaims and the PR body
has been fixed to match measurement. Actual per-dataset movement:

| dataset | best_peptide_score | passing at 1% |
|---|---|---|
| stellar | 126 up, 0 down | 4342 -> 4337 (**-5**) |
| stellar-libdecoy | 98 up, 0 down | 4253 -> 4253 (0) |
| stellar-gendecoy-entrap | 665 up, 0 down | 21861 -> **21821 (-40)** |
| astral | 104 up, **3 down** | 8909 -> **8912 (+3)** |

So "upward everywhere" was wrong (astral has 3 down), the shift is NOT uniformly
conservative (astral GAINS 3 proteins), and the largest ID delta (-40) went unmentioned.
The `NaN` in flipped rows is pre-existing convention for a non-winner group (237 such rows
before the change, 242 after, matching the 5 flips), not a new artifact.

## Tasks

- [ ] **(from #4522)** Seed `ExperimentAggregateScore` too, once that branch is merged/rebased -
      it is the fourth field the five-of-eight write-back drops
- [ ] **(from #4522)** Bump `Regression/FdrSidecars.ps1` to the v4 68-byte / eight-scalar record
      and add a comparison arm for `experiment_aggregate_score`
- [x] Add `Regression/FdrSidecars.ps1` (`Compare-Pass2Sidecars`) comparing all seven scalar
      fields per entry_id, byte-equality fast path, per-field failure tallies
- [x] Wire it into the four-task-chain leg as its own summary line
- [x] Verify it FAILS on the current divergence (Pass=False, Compared=260419, Issues=9)
- [x] Decide whether Rust has the same defect (see below) before choosing the fix -
      **ANSWERED: yes, identically. Shared design defect, not a port error.**
- [x] Add the cross-impl sidecar comparison FIRST, so a one-sided fix cannot pass:
      `ai/scripts/Osprey/Compare/Compare-FdrSidecars-Crossimpl.ps1`, wired into
      `Compare-EndToEnd-Crossimpl.ps1`, sharing the decoder with the regression leg.
      Verified GREEN on unfixed code (both sides equally wrong), then RED after the
      C#-only fix - which is the property it exists to have.
- [x] Fix the C# side (option 1, chosen 2026-08-10): seed `Score` + `Pep` +
      `RunProteinQvalue` from the 1st-pass sidecar ahead of the mode dispatch, then let
      the frozen-model score overwrite `Score`. THREE fields, not the two first diagnosed
      (see below - `pep` was found by fixing two and re-running the gate)
- [x] Fix the Rust side identically (`fmt` / `clippy` / `cargo test` all green)
- [x] `regression.ps1 -Dataset Stellar` with both fixes: **mode 3 sidecars PASS**, every
      other leg PASS; only `mode1 (vs golden)` red, which is the rebaseline below
- [x] Re-run the cross-impl gate with BOTH sides fixed - **OVERALL: PASS** on Stellar
      3-file (precursors 29364==29364, Stage 7 PASS, blib PASS, sidecars PASS over
      1,448,698 1st-pass + 994,899 2nd-pass records). Stage 7 returning to green is the
      independent evidence that the Rust fix reproduces the C# one: both sides moved the
      protein-FDR result the same way, from separately written code.
- [x] `regression.ps1 -Dataset All` pre-rebaseline evidence run - **all three gates pass**
      (table below). Only red is `mode1 (vs golden)` on all four datasets.
- [ ] Rebaseline the golden - **APPROVED by Brendan 2026-08-10**, conditional on the
      direction and changes looking correct; all three gates met, so
      `-Dataset All -CreateGolden` is RUNNING (started ~09:50).
- [x] Verification `-Dataset All` after the rebaseline - **48/48 PASS**, every leg on every
      dataset including `mode1 (vs golden)`. The captured golden reproduces on a fresh run,
      so it encodes behavior rather than a one-off.
- [x] Commit both repos, push, open both PRs (#4557 and maccoss/osprey#61)
- [x] Reviews: Copilot (2 findings, both fixed, threads replied to and RESOLVED) and
      `/code-review max` (15 findings; 13 applied, 2 pushed back with evidence)
- [x] Merged master into the branch (`d6d6a6d69b`) - only #4556 and #4551, neither touching
      Osprey, so the gate results above still stand
- [x] TeamCity Osprey Perf/Regression triggered on `pull/4557` (build 4128246) with
      Brendan's explicit go-ahead - RUNNING
- [ ] Confirm TeamCity green, then the PR is merge-ready pending #4522's readiness
- [ ] Follow-up issue: gap-fill entries get `run_protein_qvalue` 0.0 on the batch-hydrate
      arm and 1.0 on straight-through (see below) - pre-existing, newly visible

## Is the bug in Rust too? - ANSWERED 2026-08-10: YES, IDENTICALLY

**This is a shared design defect, not a port error. Both implementations need the same
fix, and the C#/Rust parity gate has been agreeing on the wrong value.**

### Source-level proof (Rust)

Rust reproduces every step of the C# defect:

1. **The reset.** Stage 6 replaces the stub wholesale via `CoelutionScoredEntry::to_fdr_entry()`
   (`osprey-core/src/types.rs:987`), copying the freshly-searched entry's fields. `run_search`
   constructs those with `score: 0.0`, all six q-values `1.0`, `pep: 1.0`
   (`pipeline.rs:8403-8410`). Same eight-field clear as C#'s `ResetScores()`, done by
   replacement instead of mutation. Rust's own comments confirm the intent - `pipeline.rs:1881`
   and `:6390` both say the post-rescore overlay "already zeroed" the in-memory copy.
2. **The five-field map-back.** `compute_pass2_transfer_compete` (`pipeline.rs:6277`) writes
   back exactly `run_precursor_qvalue`, `run_peptide_qvalue`, `experiment_precursor_qvalue`,
   `experiment_peptide_qvalue`, `pep` (`:6425-6446`). It never writes `score`, never writes
   `run_protein_qvalue` - the same five of eight as C# `ComputePass2TransferCompeteFull`.
   `pass2_qvalue::compute_full_population_fdr_streaming` returns only `(run_q, exp_q, pep)`,
   so the two missing fields are absent from the contract, not dropped at the call site.
3. **The sidecar is written from those stubs.** `write_fdr_scores_sidecar`
   (`pipeline.rs:1828`, called at `:2128`) serializes `per_file_entries` directly, immediately
   after the pass-2 block (`:5783`). Its comment at `:5776` claims `per_file_entries` "already
   carry the authoritative final-pass scores" - demonstrably false for the frozen modes.
4. **The same accidental repair on the distributed route.** `load_fdr_scores_sidecar`
   (`pipeline.rs:2064-2073`) restores all seven scalars including `score` and
   `run_protein_qvalue`, and `hydrate_for_rescore` (`rescore.rs:193`) calls it. Identical to
   C#'s `OverlayFirstPassSidecar`.

### Measured, both implementations, same run (Astral 3-file, 3,458,574 records)

From a preserved cross-impl run at
`D:\test\osprey-runs\astral\_endtoend_crossimpl\{cs,rust}` (analysis scripts:
`ai/.tmp/sidecar_defect_check.py`, `ai/.tmp/sidecar_score_magnitude.py`):

| | C# | Rust |
|---|---|---|
| `score`: real in 1st -> **0** in 2nd | **227,327** (6.57%) | **227,327** (6.57%) |
| `run_protein_qvalue`: real -> **1.0** | **60,923** (1.76%) | **60,923** (1.76%) |
| zero `score` in 2nd (total) | 236,127 (6.83%) | 236,127 (6.83%) |
| `entry_id` absent from 1st (gap-fill) | 8,800 | 8,800 |

Per-file counts match exactly, not just the totals.

**The zeroed populations are the same records, not merely the same size**: comparing the two
2nd-pass sidecars entry_id by entry_id gives `zero in C# only = 0`, `zero in Rust only = 0`,
and `run_protein_qvalue differs = 0` on all three files. Every other field agrees to float
noise (`score` max abs diff 1.8e-13 on two files; `pep` 4.0e-14). One single entry of
3.46M exceeds 1e-9 absolute (file `_49`, entry_id 1531881, cs `-8.911570303079918` vs rust
`-8.911570202905288`, 1.0e-7 abs / 1.1e-8 rel) - noted, unrelated to this defect, not
investigated.

This also resolves the sub-question the C# `:1466` comment raised: C# resets the "no peak at
the override boundary" stubs in place, and the measured zeroed sets match Rust's exactly, so
whatever Rust does there produces the same end state. No divergence hides in that branch.

### Why it matters that BOTH sides are wrong

The corrupted 2nd-pass sidecar has a real consumer: Stage 7 `--join-at-pass=2` reads it
unconditionally (stated at `pipeline.rs:5779`). A merge node fed a straight-through-written
sidecar sees `score = 0` for 6.6% of entries and `run_protein_qvalue = 1.0` for 1.8%.

Fixing only C# would introduce a genuine cross-impl divergence that **no gate would catch** -
`Compare-EndToEnd-Crossimpl.ps1` and the committed golden compare the Stage 7 protein FDR
dump (per-protein-GROUP columns), never the sidecar. So the fix has to land on both sides, or
the cross-impl comparison has to gain a sidecar leg first.

**Superseded**: the 2026-08-09 `-TestBaseDir D:\test\osprey-runs\crossimpl-4553` attempt that
failed to launch. No fresh cross-impl run was needed - a preserved one already had both
sides' straight-through sidecars.

## Regression Test

TWO gates, because the defect was symmetric across implementations and needed one guard per
axis. Neither existed before; each is red on master and green on the fix.

1. **`regression.ps1` four-task-chain leg** - `mode3 (per-file FDR sidecars==straight)`,
   C#-only, distributed route vs straight-through.
   - Test project: `pwiz_tools/Osprey/regression.ps1` (+ `Regression/FdrSidecars.ps1`)
   - Fails on master: **yes** - `Pass=False Compared=260419 Issues=9`, naming `score`,
     `pep` and `run_protein_qvalue` per file.
2. **`Compare-FdrSidecars-Crossimpl.ps1`** - C# vs Rust, both passes, wired into
   `Compare-EndToEnd-Crossimpl.ps1`.
   - This one is green on master BY DESIGN: both implementations were wrong in the same
     way, so it can only catch a ONE-SIDED fix. Verified it does: green on unfixed code,
     red the moment C# alone was fixed, green again once Rust matched. Without it, fixing
     one side would have shipped a silent cross-impl divergence, since neither the Stage 7
     comparator nor the golden reads these fields.

- **Passes on fix**: yes, both. Verification sequence actually run, each step measured
  rather than assumed:

| step | mode 3 sidecars (C#) | cross-impl sidecars | cross-impl Stage 7 |
|---|---|---|---|
| neither side fixed | FAIL (9 issues: score, pep, protq x3 files) | PASS (both wrong alike) | PASS |
| C# `Score` + `RunProteinQvalue` only | FAIL (3 issues: **pep** x3 files) | FAIL | FAIL |
| C# all three fields | **PASS** | FAIL (Rust unfixed) | FAIL |
| both sides, all three | **PASS** | **PASS** | **PASS** |

The middle row is why the cross-impl leg had to be built first: with only C# fixed, the
sidecar leg is the gate that says so.

This is the guard the issue exists to add: the divergence was invisible because the only
per-file assertion was the blib, which carries neither field.

## Gotchas

* `-o out.blib` is RELATIVE to the process working directory, not to `--output-dir`. A
  wrapper launched from `C:\proj\pwiz` wrote a 211 MB blib into the repo root. Pass an
  absolute `-o`, or set the working directory.
* The `--task PerFileRescoring` workers write NO `.2nd-pass.fdr_scores.bin`, so
  `regression.ps1`'s `if (Test-Path $pass2)` copy into the SecondPassFDR phase is a no-op
  and that node always recomputes. Any reasoning that assumes the workers' values are
  relayed is wrong.

## Progress Log

### 2026-08-09 - Session Start

Split out of the #4486 Stage 7 memory work, where this was found while building the
FDRBench oracle for that branch's review finding 1. Root cause is diagnosed (above) and the
failing check is written; the fix and the Rust question remain. Kept off the #4486 branch
deliberately: the check turns `-Dataset All` red, which would block a PR that has nothing
to do with this defect.

### 2026-08-10 - Parent PR merged; this branch is where the work resumes

#4554 (the Stage 7 memory/reporting work this was split out of) **merged** as `843f7e553a`,
so master now carries everything this branch was deliberately kept clear of. Nothing here
changed as a result - the divergence this issue tracks is in `ResetScores()` +
`protein-compact`, which #4554 did not touch, so the measured figures below still stand.

**Rebase is CLEAN, verified** (`git merge-tree --write-tree master HEAD`) even though both
#4554 and this branch edit `pwiz_tools/Osprey/regression.ps1` - the hunks do not overlap
(#4554 rewrote the mode-3 preamble comment and the `$knownResidentGaps` Legs line; this
branch adds the `FdrSidecars.ps1` dot-source and a new assertion block just above
`$m3 = Compare-BlibFull`). Rebase onto the new master before doing anything else, so the
failing check runs against current code.

**Related issue filed since**: #4555 - same-base-name inputs from different directories
collide in artifact NAMES (`ArtifactPaths.ResolveOutputDir` flattens everything into
`--output-dir` while names are stem-based) and in the per-file maps. Different defect from
this one, but the same "identity is the bare stem" root, and worth reading before designing
the fix here so the two do not solve it twice in different ways.

**State of this branch**: 1 commit (`6dc9b136fe`), clean tree, pushed. The check is written
and RED against the real divergence; the FIX is not written. The root cause is fully
diagnosed in the section above - do not re-derive it.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260809_fdr_sidecar_parity.md` before starting work. NOTE: that file
predates the 2026-08-10 work and its "next steps" are all done - read this TODO instead;
the handoff is only still useful for its gotchas list.

### 2026-08-10 (later) - Golden rebaseline approved; what gates it

Brendan approved the rebaseline conditionally: "If the direction and the changes look
correct, then you can go ahead next with re-baseline." Gated on three checks against the
in-flight `-Dataset All`, so a rebaseline is not taken on Stellar evidence alone:

1. **mode 3 passes on all four datasets** - the fix itself, independent of any golden.
2. **Tier-2 entrapment ceilings pass on StellarGenDecoyEntrap** - true FDP under the
   committed bound.
3. **mode 1 failures are confined to the three protein-FDR columns** on every dataset.

**The rebaseline cannot launder a calibration regression, by design.** `regression.ps1`
(the `$datasets` comment block, ~line 327) documents that `MaxPass1Fdp` (Tier-2 ceiling on
Pass-1 true FDP at a reported 1% q), `MaxAbsTilt` and `CoinTolerance` are committed bounds
**deliberately NOT regenerated by `-CreateGolden`** - "a rebaseline is exactly how a
calibration regression gets blessed into the baseline, so this bound must not come from the
run." So the entrapment oracle survives the refresh and keeps judging this change. That
retires the earlier open question about needing a separate FDRBench run: the oracle is
already wired into the gate.

### Pre-rebaseline `-Dataset All` - all three gates met (2026-08-10)

Every leg green on all four datasets EXCEPT `mode1 (vs golden)`, which is the rebaseline
itself. Specifically:

| gate | result |
|---|---|
| 1. `mode3 (per-file FDR sidecars==straight)` | **PASS on all four datasets** - the defect is fixed everywhere, not just on Stellar |
| 2. `mode1b (FDR sanity bounds)` | **PASS** on StellarLibDecoy, StellarGenDecoyEntrap, Astral - AND on their `mode5 (rehydrate FDR sanity bounds)` variants |
| 3. `mode1 (vs golden)` failures | confined to the SAME three protein-FDR columns on all four; no other column, no new failure mode |

Gate 2 is the important one. Those are `MaxPass1Fdp` / `MaxAbsTilt` / `CoinTolerance`, the
Tier-2 entrapment ceilings `-CreateGolden` deliberately does NOT regenerate. **Entrapment-
measured true FDP is still inside a bound that predates this change**, which is independent
confirmation of the direction rather than an argument from first principles. It also means
the fix cannot have degraded calibration and then had the rebaseline hide it.

`mode1b (diagnostics vs golden): PASS` everywhere too - the diagnostics golden did not move.
Only the Stage 7 protein FDR dump did.

### Per-dataset golden movement - the mechanism corroborated

| dataset | decoys | groups | `best_peptide_score` | `group_qvalue` | winner flips |
|---|---|---|---|---|---|
| Stellar | generated | 4,579 | 126 | 914 (20%) | 5 |
| StellarLibDecoy | **library** | 4,495 | 98 | **0** | **0** |
| StellarGenDecoyEntrap | generated | 26,714 | 665 | 13,657 (51%) | 40 |
| Astral | generated | 9,470 | 107 | 1,287 (14%) | 2 |

`best_peptide_score` moves UPWARD on every dataset (e.g. Astral 8.056 -> 12.134,
StellarGenDecoyEntrap 1.200 -> 10.103), and the q movement tracks the DECOY SOURCE:

That difference is a prediction of the decoy-skew mechanism, not a wrinkle in it. A target's
picked-protein q depends on how many DECOY winners outrank it. On StellarLibDecoy the scores
rose (1.277 -> 8.407, same upward direction) yet every q held, which requires that no decoy
winner moved. On Stellar 914 q's moved, which requires that decoy winners DID move - and
Stellar is the generated-decoy leg where the zeroed population was measured decoy-skewed
(52% of decoys vs 25% of targets). Library decoys never run `DecoyGenerator`, and Stage 6
evidently does not touch them the same way.

So: score restoration is uniform and upward on both datasets; protein-q movement appears
only where the decoy side was actually being suppressed. That is the signature of a null
being repaired.

### 2026-08-10 - Rebased; Rust question CLOSED (both implementations, same defect)

Rebased onto master (`9b4b292275` on `843f7e553a`), clean, hunks did not overlap as
predicted. Branch needs a force-push.

**The open Rust question is answered: Rust has the identical defect** - see the rewritten
"Is the bug in Rust too?" section above for the source citations and the measured table.
Confirmed two independent ways: reading the Rust pass-2 map-back (writes the same five of
eight fields), and measuring a preserved cross-impl run that happened to hold BOTH sides'
straight-through sidecars. The two implementations zero the same 227,327 scores and the same
60,923 protein q-values, record for record.

No fresh cross-impl run was needed. The preserved run is
`D:\test\osprey-runs\astral\_endtoend_crossimpl\{cs,rust}` - if it is still on disk it
answers sidecar questions in seconds. `D:\test\osprey-runs\crossimpl-4553` remains an empty
shell from the failed 08-09 launch; nothing was ever staged there.

**Consequence for the fix**: it must land on BOTH sides. Fixing only C# creates a real
cross-impl divergence that no existing gate would catch, because neither the cross-impl
comparator nor the golden reads the sidecar. Whether to also add a sidecar leg to
`Compare-EndToEnd-Crossimpl.ps1` is an open call.

### 2026-08-10 - Comparator added first, then both sides fixed

Deliberate order, at Brendan's direction: add the gate that would catch a one-sided fix,
prove it green BEFORE the fix, fix C# and watch it go red, then fix Rust and watch it go
green. Each step verified on Stellar 3-file rather than assumed.

| cross-impl leg | baseline (neither fixed) | C# fixed only |
|---|---|---|
| precursors | 29364 == 29364 | 29364 == 29364 |
| Stage 7 protein FDR | PASS | **FAIL** |
| blib content | PASS | PASS |
| **FDR sidecars (new)** | **PASS** | **FAIL** |

The new leg compares BOTH passes. Its 1st-pass half is what distinguishes "pass 2 dropped
it" from "the runs already diverged upstream", and it earned that keep immediately: on a
preserved Astral run it flagged ONE record (entry_id 1531881, `score` differing 1.0e-7) in
the **1st-pass** sidecar, i.e. upstream of anything #4553 touches. The fresh Stellar run is
clean on both passes, so that record is dataset-specific or an artifact of those older
binaries. **Open, unchased, unrelated to this fix.**

Implementation note: the comparison had to move into compiled C# (`Add-Type` inside
`Regression/FdrSidecars.ps1`). The PowerShell per-record loop took over 10 minutes on one
Astral 3-file pass (6.2M records) and would have been unusable at 82 files; it is 1.9s for
9.7M records now.

### What the fix moves (Stellar 3-file, C# before vs after)

Peptide level does not move at all - 29364 precursors before and after, blib content still
bit-parity with Rust. ALL movement is protein-level:

All figures at the 1e-9 the gates use (an exact-equality count also sees 242 sub-1e-9
`best_peptide_score` wobbles, which are noise and are NOT impact):

| | before | after |
|---|---|---|
| protein groups | 4579 | 4579 |
| `best_peptide_score` changed | - | 126, **all upward** (0 downward) |
| `group_qvalue` changed | - | 914 (28 better, 886 worse) |
| `is_target_winner` flipped | - | 5 |
| **passing at 1% FDR** | **4342** | **4337** (-5, 0.12%) |

Independently confirmed by the golden leg, which flags the same three columns at the same
counts: `best_peptide_score` 126/4579, `group_qvalue` 914/4579, `is_target_winner` 5/4579.

**Why scores rise but q gets worse - this is the mechanism, and it is the argument that the
fix is a correction rather than a regression.** Restoring a real discriminant moves a
suppressed peptide UP (its real score is above the 0 it was parked at; e.g.
`sp|P17152|TMM11_HUMAN` 1.799 -> 7.454). Both labels rise - but **not equally**: Stage 6
touches decoys about twice as often as targets (52% vs 25% on Stellar, measured above), so
the zeroing was suppressing the DECOY null harder than the target signal. Protein FDR was
therefore reading an artificially weak null and reporting q too low. Restoring the scores
rebuilds the null, 886 target groups get an honest (worse) q, and 5 lose their pairwise pick
outright. **The pre-fix protein FDR was anti-conservative; -5 proteins is the cost of
removing that bias, not lost discovery.**

Brendan's framing is what makes this predictable rather than surprising: the discriminant
scale is normalized so **zero IS the accept/reject boundary**, so an unknown score parked at
0 sits exactly at the decision line - which is why mean-best-N deliberately uses the decoy
mean (a negative value) as its missing-score placeholder instead. An entry whose real score
is above 0 gets suppressed by the placeholder and one below it gets inflated; because the
touched population is decoy-skewed, the net was systematically anti-conservative.

Since the discovery set is byte-identical, peptide-level entrapment FDP cannot have moved -
an FDRBench re-run would be measuring an unchanged quantity. The open question is
protein-level only.

### THREE fields, not two - found by fixing two and re-running the gate

The root-cause section above named `Score` and `RunProteinQvalue`. Fixing exactly those took
mode 3 from **9 issues (3 files x 3 fields) to 3 (3 files x 1 field)**, and the survivor was
`pep` - which the original `Issues=9` had named all along:

```
Ste-...-900_20: pep differs on 114 record(s); first entry_id=3656  1 -> 0.6118043102892672
```

Same root cause, third instance: `ResetScores()` clears `Pep`, and the map-back writes it
**only on the on-stratum path**. The off-stratum branch returns early after carrying
experiment q, so straight-through keeps 1.0 while the chain keeps its rehydrated pass-1 PEP.
The chain is the correct side - off-stratum survivors are defined to keep their pass-1
statistics, which is the rule the code already applies to experiment q two lines above.

So the field-by-field framing was the wrong shape. Exactly three of `ResetScores()`'s eight
fields are not reliably recomputed by pass 2:

| field | why it is lost |
|---|---|
| `Score` | no frozen mode wrote one back at all |
| `Pep` | written only for on-stratum survivors |
| `RunProteinQvalue` | written by NO mode; 1st-pass protein FDR is its only producer |

### Where the fix lives

* C# `Pass2FdrSidecar.cs`: `RestorePass1Scalars` (new) seeds all three from the 1st-pass
  sidecar ahead of the mode dispatch; `ReadFile` then overwrites `Score` with the
  frozen-model score where the reconciled features resolve.
* Rust `pipeline.rs`: `restore_pass1_scalars` + `read_fdr_scores_pass1_scalars` (new) at the
  same point; the `compute_pass2_transfer_compete` map-back overwrites `score` the same way.
* **Seed, do not override.** Whatever pass 2 genuinely recomputes is written afterwards and
  wins. What remains is the pass-1 value - which is precisely what the distributed route
  holds at the same point, because it must rehydrate from that same sidecar. The two routes
  then agree BY CONSTRUCTION rather than by coincidence, which is the property worth having:
  a future field added to `ResetScores()` and forgotten by one mode fails the same way, and
  the seed catches it.
* Write ordering verified: `SecondPassFdrTask.cs:175` (`ComputeAndPersist`, writes the
  sidecars) runs BEFORE `:197` (`RunProteinFdr`), so the restored values land in the sidecar
  AND feed `CollectBestPeptideScores`. The second-pass protein FDR does overwrite
  `RunProteinQvalue` in memory afterwards (`ProteinFdrEngine.cs:199`), which is harmless -
  the sidecar is already written.
* `mode 3` converges rather than shifting: the fix lives in the method BOTH routes execute,
  so the chain route's overlay-supplied 1st-pass score is overwritten by the same
  seed-then-override logic. Both routes land on the frozen pass-2 score.
