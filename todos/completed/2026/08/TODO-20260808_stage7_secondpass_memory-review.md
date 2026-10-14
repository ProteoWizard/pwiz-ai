# /code-review max findings - #4486 branch (2026-08-09)

Run against `Skyline/work/20260808_stage7_secondpass_memory` @ `e2bdf7e41a` (5 commits).
15 findings. **Only #1 was verified before the session ran out of context - the other 14 are
UNVERIFIED and must be reproduced or refuted individually.** The version-control skill is
explicit that this reviewer can be confidently wrong; do not auto-apply.

## STATUS after the 2026-08-09 fix passes

FIXED and gate-green (0 errors, 0 warnings, 576 tests) across pwiz 3544d7533e, 9b8e51c807,
72f6ed9c93, 31af2e17f1 and ai 7bdedbc: **#1** (guarded), **#2**, **#3**, **#5**, **#6**,
**#7**, **#10**, **#11** (partly), **#13**, **#15**, and the worst of **#14**.

STILL OPEN: **#4** (duplicate stems), **#8** (the vacuous ratchet assertion), the REST of
**#9**, the rest of **#14** (five more stale comments), and the below-cap items.

**#9 is only partly closed.** `TestFirstPassMembershipAcrossTasks` pins the membership truth
table across all five task shapes, which is what the replaced `!NoJoin` proxy got wrong - but
it is NOT red on master, because `IsIncludedFor` was extracted rather than changed.
`ShouldStreamCompaction` and `PreCompactionPoolReason` remain untested: both are private and
take a `PipelineContext`, so covering them means making them testable first (the same
env-statics-passed-in shape `ResidentPoolGuardError` already uses).

**`regression.ps1 -Dataset Stellar` PASSED on the fix pass (2026-08-09)** - all 8 checks,
including mode 3 (HPC chain) and mode 5 (rehydrate==straight, which the fat/lean branch
change touches). Necessary but NOT sufficient for #1: mode 3 copies the pass-2 sidecars
into phase 4, so the overlay overwrites exactly the protein q the guard affects. Green
means nothing observable broke; it does NOT confirm the guard fixed the FDR skew.

**`-Dataset All` PASSED on the fix pass, 44/44** (2026-08-09,
`regression-all-fixpass.log`) - identical to the pre-fix run, so none of the 12 fixes
regressed anything the gate can see. The summary also now prints the #4486 gap
(`#4486  token: NONE`, required tokens still 0), confirming finding #12's fix.

STILL NOT VALIDATED by that green: the #1 guard. Mode 3 copies the pass-2 sidecars into
phase 4, so the overlay overwrites exactly the protein q the guard changes. The FDRBench
oracle is owed. Original launch note ->
`D:	est\Pilot-MTG-Tissue-May2026\Astral-DIAunsegression-all-fixpass.log`.
READ IT FIRST next session. Note the run was started BEFORE the regression.ps1 gaps-table
commit, so its summary will still print "none" there; that entry is output-only.

**Still owed for #1: the FDRBench oracle.** Delete the pass-2 sidecars from a mode-3 phase-4
dir (or use the 82-file rig, ~26 min) so the recomputed protein q actually reaches disk,
then compare against straight-through.

**Lesson from fixing #13:** the resume rehydrate branched on `needsResidentPool` while its
builder now came from `CanUseLeanProjection`, so the "latent" case became a live
NullReferenceException that inspection caught. Both now key off the builder. If another
finding looks latent, check whether this branch made it reachable.

## 1. BLOCKER - VERIFIED - GUARDED 2026-08-09 (oracle still owed) - join node runs first-pass protein FDR on a COMPACTED pool

`PerFileRescoreTask.cs:495`, `RescoreHydration.cs:535`

Confirmed by direct read. `HydrateCompactedStreaming` does, in order: load full stubs;
`OverlayFirstPassSidecar`; `onStubsHydrated` (commented as "the caller's one look at this
file's full pre-compaction pool"); then
`stubs.RemoveAll(e => !retainBaseIds.Contains(...))`; then
`perFileEntries.Add(fileName, stubs)`. So `RescoreInputs.PerFileEntries` is ALREADY
COMPACTED when published.

`PerFileRescoreTask` then calls `ProteinFdrEngine.RunFirstPass(bundle.PerFileEntries, ...)`
under a comment stating it runs BEFORE compaction, and a standing warning "Do not remove
without re-checking the 2nd-pass protein-FDR path." The batch twin
(`HydrateReconciliationOverlay`) does not compact there - `RescoreCompaction.Apply` did it
afterwards. **This branch flips the input population to first-pass protein FDR on the
`--task SecondPassFDR` node.**

Claimed consequence, NOT yet verified: `ProteinFdr.cs:684` gates the TARGET side at
`BestQvalue <= qvalueGate` while `:671` documents "Decoy side: NOT gated (forms the null
distribution)". Compaction retains only passing base_ids, so the decoy null loses most of
its members, `cumDecoys` collapses, and every propagated protein q is anti-conservatively
low. It reaches disk via `Pass2FdrSidecar.cs:245` ONLY for files with no
`.2nd-pass.fdr_scores.bin`; `regression.ps1:1155-1156` copies every pass-2 bin into phase 4,
so the golden chain always takes the overwrite path and **44/44 green cannot witness this.**

NEXT STEP: this is an FDR question, so settle it with the FDRBench entrapment oracle
(`StellarGenDecoyEntrap`, or the 82-file rig's `fdrbench.tsv`), NOT byte-parity. Compare
`RunProteinQvalue` from a mode-3 phase-4 run with the pass-2 bins DELETED against
straight-through.

## 2. mdiag accumulator pinned with no reader on the join node

`PerFileScoringTask.cs:1293`. `--task SecondPassFDR --model-diagnostics` is legal
(`Program.cs:474-481` never mentions it). The streaming branch, newly reachable here, builds
and feeds a whole-run accumulator whose only reader/nuller (`FirstPassFdrTask.cs:605/611`)
sits in a task excluded on this node - pinning ~1-2 GB through Stage 7, on the very node
this change exists to shrink. Also the build call at `:1269-1272` has no try/catch while the
identical call at `FirstPassFdrTask.cs:950` deliberately does.

## 3. FIXED 2026-08-09 - The resident-pool warning went silent on the case my new term covers

`PerFileScoringTask.cs:1251`. Gate is
`needsResidentPool || (hasReconSidecars && !streamCompaction)`. Partially-copied chain
(reconciled parquets present, one `.reconciliation.json` missing): all terms false, builder
null via `CanUseLeanProjection`, and the loop at `:1299` materializes every file's
pre-compaction list with NOTHING logged. Pre-change the operator got the warning. Suggested
gate: `!streamCompaction && builder == null`.

## 4. Duplicate-stem invariant newly armed

`RescoreCompaction.cs:224`. The throw (`entriesAfter != entriesBefore`) is now armed on the
merge. `Apply` re-derives retain sets through a name-keyed map (`:186-189`) where a duplicate
stem keeps only the last file's list, while the hydrate unions positionally.
`RescoreHydration.cs:139-143` says same-stem paths in different directories are a real case.

## 5. FIXED 2026-08-09 - Compaction ratio log is now always N -> N

`PerFileRescoreTask.cs:501`. `RescoreCompaction.cs:76-80` says `EntriesBefore` equals
`EntriesAfter` on this path and that a caller wanting the real figure must read
`TotalPreCompactionStubs`; `FirstPassFdrTask.cs:1388-1390` does, this call site does not.

## 6. FIXED 2026-08-09 - Dead `Features = null` loop over the whole survivor pool

`PerFileScoringTask.cs:1689`. The shared tail runs on the streaming arm where features were
never loaded. `FirstPassFdrTask.cs:876-881` guards the identical loop with `if (!leanStubs)`
citing "~88.9 M reference writes at 163 files, each tripping the GC write barrier".

## 7. `PassingTargets` computed and never read on this node

`PerFileScoringTask.cs:1284`. `ScoringTaskShared.cs:286-292` evaluates
`EffectiveRunQvalue <= RunFdr` for ~344 M stubs at 82 files to fill a field whose only
reader is in an excluded task.

## 8. PUSHED BACK 2026-08-09 - New ratchet assertion is vacuous

`ResidentPoolGuardTest.cs:104`. `GuardResidentPool` has no reachable call site on any
`--input-scores` run (`:385` is the compute path; `:647` requires InputScores EMPTY), so the
test hand-passes a `needsResidentPool: true` that no production caller can produce.

**Reachability premise CONFIRMED, conclusion REJECTED.** Verified by reading: `:385` is
inside `PerFileScoringTask.Run`, whose own opening comment says the `--input-scores`
counterpart "lives in Rehydrate", and `:647` is inside `RehydrateFromOwnOutputs`. So the
reviewer is right that no `--input-scores` run reaches either site with `true` for THIS
config.

That is what the line ABOVE the flagged one asserts: `AssertNeedsResidentPool(false, hpc)`
(`:103`) is the production-reachable claim. `:104-108` then deliberately tests the
counterfactual - if `NeedsResidentPool` ever regressed to true for the merge, no token,
including the retired `hpc-merge`, may admit it. That is a regression RATCHET, not a
reachability claim, and the comment at `:96-101` already says so. It exercises real logic
in `ResidentPoolGuardError` (a retired token must not be honored), and deleting it would
delete exactly the guard against the regression the ratchet exists to catch.

Note `GuardResidentPool` IS reachable with `true` in production generally - just via the
compute path at `:385` (FDRBench pass 1, non-Percolator FdrMethod, OSPREY_FDR_PROJECTION=0),
not via a reconciled-input merge. "No production caller can produce it" is therefore too
broad as written.

No code change. The genuine remaining gap here is finding 9's tail (the pinned trigger set
has no task-flag-driven case left), which is tracked there.

## 9. PARTLY FIXED 2026-08-09 - Core behavioral change has zero unit coverage

`ResidentPoolGuardTest.cs:96`. No test references `ShouldStreamCompaction`,
`PreCompactionPoolReason` or `IsIncludedFor`. Removing `AssertNeedsResidentPool(true, hpc)`
also left the pinned trigger set with no task-flag-driven case.

## 10. FIXED 2026-08-09 - `RunProteinFdr` probe has no pre-GC companion

`SecondPassFdrTask.cs:204`. The forced collection destroys the parsimony/TDC transient the
probe exists to measure; every other new probe got a pre-GC line.

## 11. Probes perturb the measurement they take

`SecondPassFdrTask.cs:151`. Five probes = ten blocking gen2 collections; gen2 moved
1111->1115 across the protein-FDR/blib window on the branch's own run, i.e. 100% of gen2
there was probe-forced (~16 s stop-the-world in a 1588 s stage). Three of five returned no
new information. `ai/scripts/Osprey/Get-MemoryReport.ps1:98-111` has no regex for any
`stage7-*` label, so none of the five reaches the report.

## 12. FIXED 2026-08-09 - `$knownResidentGaps` prints "none" while the preamble names an open gap

`regression.ps1:239`. The one gap the rewritten preamble names by issue number is absent
from the table it says exists to keep gaps legible.

## 13. FIXED 2026-08-09 (and it was NOT latent) - `CanUseLeanProjection` applied at only one of two sibling call sites

`PerFileScoringTask.cs:656`. `RehydrateFromOwnOutputs` still gates on bare
`NeedsResidentPool`. Latent (`:483` routes InputScores away) but it is exactly the drift
this PR claims to remove.

## 14. MOSTLY FIXED 2026-08-09 (ShouldStreamCompaction XML doc, the stubs-only
## rationale, the warn-not-throw list) - remaining: PerFileScoringTask:1898,
## ScoringTaskShared:278-281, regression.ps1:1310-1313 - Six stale comments, including the XML doc of the inverted predicate

`PerFileScoringTask.cs:1420` still explains term 2 as the deleted NoJoin proxy and says
"--task SecondPassFDR is NOT among them". Also `:1898`, `:1244-1247`, `:1367`,
`ScoringTaskShared.cs:278-281`, `regression.ps1:1310-1313`.

## 15. Retired token degrades to silence

`OspreyEnvironment.cs:534`. `AllowUnfixedResidentUnrecognized` is declared and never read
(its sibling `Pass2QValueUnrecognized` IS consumed at `Program.cs:269`). `hpc-merge` is the
first previously-valid token to become invalid and committed automation still passes it
(`Measure-Stage6Rescore.ps1:278,485`). I found this dead field independently during the
session and left it alone as out of scope; retiring the token makes it live scope.

## Below the reviewer's cap, noted

`SecondPassFdrTask.cs:432` warns-and-proceeds on an empty pool rather than distinguishing
"zero loaded" from "zero passed" - the deeper fix that would make #13 and the new
`!ExpectReconciledInput` term unnecessary. `LibraryFragmentRelease.cs:123` hand-copies the
`NeedsResidentPool` trigger set. `IsIncludedFor(OspreyConfig c)` uses `c` where the three
predicates it unifies all spell it `config`.

## Verified clean by the reviewer - do not re-litigate

`NeedsResidentPool`/`ResidentPoolTrigger` stay in lockstep; `CanUseLeanProjection` is
bit-equivalent to the old expression for every non-SecondPassFDR run; the
`!NoJoin` -> `IsIncludedFor` swap changes disposition only for `--task SecondPassFDR`;
`PipelineMembershipTest` unaffected; streaming and batch `RescoreInputs` fill the same
fields.
