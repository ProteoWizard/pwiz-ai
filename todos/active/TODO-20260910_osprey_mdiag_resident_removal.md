# Remove the O(files x entries) resident paths reachable from `--task ModelDiagnostics`

**Branch**: `Skyline/work/20260910_osprey_mdiag_resident_removal` (in `C:\proj\pwiz-work1`)
**Module**: `osprey`
**Found**: 446-file night run, 2026-09-09 -> 10. Evidence:
`ai/.tmp/sessions/20260910-night/FINDINGS.md`, handoff
`ai/.tmp/handoff-20260910_osprey_446_diagnostics_results.md`.

## The defect

`--task ModelDiagnostics` cannot complete on the 446-run CHS cohort. It writes the pass-1
report correctly, then hydrates the all-runs Stage 6 bundle and grows on the private **floor**
at ~0.10 GB/file (31.2 -> 41.8 GB over files 1-102), projected past this box's 63.7 GB around
file ~310 of 446. Killed deliberately at 00:07 rather than page until morning.

**Two resident paths in this route, not one:**

| # | site | cost | reached because |
|---|---|---|---|
| i | `FirstPassFdrTask.Rehydrate` -> `RescoreHydration.HydrateCompactedStreaming` | 0.10-0.22 GB/file | `CanHydratePerRun` declines on `SelectedTask` |
| ii | `SecondPassFdrTask.FoldPass2DiagnosticsOnly` -> resident survivor pool | 0.197 GB/file, 91.1 GB @ 446 | no per-run source published by (i) |

(i) is what walled; (ii) is next in line. (i) is fixed; (ii) is blocked - see the scope
correction below, which is why this TODO does not close with the branch.

### Mechanism

`ScoringTaskShared.CanHydratePerRun` fails closed on any selected task but `PerFileRescore`:

```csharp
if (config.SelectedTask.HasValue && config.SelectedTask != HpcTask.PerFileRescore)
    return false;
```

so `FirstPassFdrTask.cs:816` takes the all-runs arm, whose loop streams the *reading* but
accumulates the *result* (`RescoreHydration.cs:652`):

```csharp
perFileEntries.Add(new KeyValuePair<string, List<FdrEntry>>(fileName, stubs));
```

The admit-list shape is deliberate and correct - it was written that way because
`--task ModelDiagnostics` had previously been admitted by omission and skipped its own
regeneration (Astral mode 7). The exclusion's original justification is gone: the report is now
FirstPassFDR's declared output, produced by `FoldDiagnosticsOnly` **before** `Rehydrate`.

The intended design is already stated at `FirstPassFdrTask.cs:812-815`: *"What downstream still
needs from this task is the per-run SURVIVOR LOADER, and it needs the retained base_id set to
build it. That set comes from the analysis-wide summary rather than from a bundle assembled by
reading every run."* The `retained_base_ids` sidecar is present, so the fat bundle has no
consumer in this route.

### Why no guard fired (the second bug)

`Stage7ResidentGuardError` only fires when the operator set `OSPREY_STAGE7_STREAM=0`. It asks
"did you CHOOSE residency?", not "is this run about to be resident?". Here nobody chose it - an
upstream predicate declined the per-run arm - so the guard has no subject.

### Why the gate missed it

`regression.ps1` **mode 7 is `--task ModelDiagnostics` regeneration acceptance** and it
traverses this exact dispatch ("it rehydrates Stages 1-5 and re-runs Stage 7 only"). Its two
assertions are FILE-level (exactly one artifact changed) and VALUE-level (report matches the
golden). Neither can see *which arm ran*, and at 3 files an O(files) bundle is free. The gate
covering this task is structurally blind to this defect class.

## Status (2026-09-10 10:35)

Two commits on the branch: `a197f68cf7` (steps 2 and 5) and `5c69a1b641` (step 4).
Step 1 is banked. Step 3 is blocked and may stay blocked for a while - see the scope
correction below.

| step | state |
|---|---|
| 1 bank the Stage-7 A/B | **DONE** - both halves, see below |
| 2 route ModelDiagnostics to the per-run arm | **DONE** (`a197f68cf7`) |
| 3 delete the fold's resident arm | **BLOCKED** - see the scope correction; it keeps live subjects |
| 4 retire `OSPREY_STAGE7_STREAM` / shrink `KNOWN_UNFIXED` | **DONE** (`5c69a1b641`), 5 -> 4 |
| 5 route assertions in modes 7 and 11 | **DONE** (`a197f68cf7`) |

### What `5c69a1b641` removed

`OSPREY_STAGE7_STREAM` / `OspreyEnvironment.Stage7Stream`; `Stage7StreamValidityKeySuffix()`
(empty on the default, so no existing output directory is invalidated by its removal);
`ResidentPaths.STAGE7_STREAM_OFF`; `ScoringTaskShared.Stage7ResidentGuardError`; the two-argument
`CanStreamStage7Join` overload and `Stage7StreamAdmittedBeforeRescore`'s `stage7Stream`
parameter; `AssertStage7JoinGuard`; and regression.ps1's `$abSwitchSet` term.

**`WarnResidentStage7Join` was deliberately KEPT.** It keys on the MILESTONE
(`rescored.Streams`), not on the switch, and cites #4486 - so `NeedsResidentPool` still gives it
a subject. It is now the disclosure for a resident join reachable only by declaration, which
makes it more useful after this change rather than less.

Also tidied, because the removal exposed them: an orphaned doc comment that documented
`AssertStage6HandoffGuard` while sitting above a different method, and regression.ps1's note at
~:2054 which had PREDICTED this removal ("a leg built on that switch would be built to be
deleted") - updated to record that the call held.

Green after removal: build 0 errors / 0 warnings, code inspection zero warnings, 593/593 tests.

**Verified so far**: 593/593 unit tests + zero-warning inspection; full
`regression.ps1 -Dataset StellarLibDecoy` **PASSED** (`GATE EXIT 0`), every mode green
including mode 3 (HPC chain blib byte-identical), mode 5 (the rehydrate arm changed here) and
mode 11 (pass-2 byte-exact). `Tokens REQUIRED by this gate: 0 (target: 0)` - unchanged, and the
new guard fired on no leg, so nothing in the gate depends on the all-runs bundle.

**One correction worth keeping**: the route assertion was first put in mode 7 and failed there
(`regeneration wall 0.2s`, no per-run marker). Mode 7 re-enters a run whose products are still
on disk, so `OnlyDiagnosticsProductOutstanding` sees the file, declines the fold arm, and the
task only RE-RENDERS - it hydrates nothing, correctly. Mode 7 therefore gets the negative half
only; the positive half belongs to mode 11, which deletes the products and forces the fold.

**Still owed before this is a merge candidate**: the confirming `-Dataset StellarLibDecoy`
gate after the removal, then `regression-parallel.ps1 -Dataset All`; `/code-review max` on the
branch BEFORE opening the PR; and the real oracle - a 446-file `--task ModelDiagnostics`
re-run, which walls within ~1 h if the fix did not take. The oracle needs the box free, so it
queues behind the in-flight 446-file phase-5 run.

## Step 1 result - the Stage-7 A/B, banked 2026-09-10

Run with `OSPREY_STAGE7_STREAM=0` + `OSPREY_ALLOW_UNFIXED_RESIDENT=stage7-stream-off` on
StellarLibDecoy: **`Osprey regression PASSED`, `A/B EXIT 0`**, every mode green including
`mode1 (vs golden)` at 1e-9.

The resident arm really ran - the streamed-join assertions **skipped**, which is the direct
evidence:

```
mode1/2/3/5 (streamed join): SKIP (this configuration cannot stream the join)
```

(`Tokens REQUIRED by this gate: 0` on that run is accounting, not a contradiction: it counts
tokens the GATE requires, and no leg sets the switch - the operator did, externally.)

**HTML half - RESULT.** Byte-identical apart from the clock. Parsing the embedded
`<script id="osprey-data">` payload from both pages:

```
keys only in resident: none
keys only in streamed: none
differing keys: ['generatedUtc']
  resident = "2026-09-10 16:44:10 UTC"
  streamed = "2026-09-10 17:21:10 UTC"    (37 min apart - the gap between the two runs)
```

Both files 431,757 bytes (the timestamp is fixed-width). All 30 top-level views - `cal`,
`model`, `featureHistEdges`, `featureCount`, `modelComposite`, `coAssignment`, `fdpViews` and
the rest - are identical between the resident and streamed Stage-7 joins. That is the permanent
record; the mechanism to reproduce it is gone with the switch.

**Why a second, HTML-only comparison was needed.** `Compare-DiagnosticsGolden` is value-level;
regression.ps1 does not store the whole page as a golden master, so a green gate under the
resident arm proves the VALUES match, not the HTML. `ab-html-compare.ps1` supplies the missing
half: the straight-through `output.model-diagnostics.html` from both arms, SHA-256 compared.
Captured before mode 7 rewrites the report, from each run's own timestamped `TestResults` root.

Resident page banked at `ai/.tmp/sessions/20260910-night/ab-html/resident-straight.html`
(431,757 bytes, md5 `ad4d537cdfbd00d2b32a3d737abf5cb4`).

## Scope correction - "remove the fat path entirely" is only PARTLY reachable today

`RescoredEntries.Streams` is false whenever `BuildStage7PerRunSource` returns null, i.e. when
`!CanStreamStage7Join`. Deleting `OSPREY_STAGE7_STREAM` makes `stage7Stream` constantly true,
but `Stage7StreamAdmittedBeforeRescore` still declines on `NeedsResidentPool`, which is true
for three paths that are still live and still tokened:

```csharp
return !useFdrProjection ||                                   // PROJECTION_OFF
       !config.FdrMethod.UsesPercolatorFramework() ||         // NON_PERCOLATOR_FDR
       (!string.IsNullOrEmpty(config.OutputFdrBench) && config.FdrBenchPass == 1);  // FDRBENCH_PASS1
```

So the fold's resident arm keeps a live subject after the switch goes.

| removable now | must stay until PROJECTION_OFF / NON_PERCOLATOR_FDR / FDRBENCH_PASS1 go |
|---|---|
| `OSPREY_STAGE7_STREAM` switch | `FoldPass2DiagnosticsOnly`'s resident `else` arm |
| `ResidentPaths.STAGE7_STREAM_OFF` (KNOWN_UNFIXED **5 -> 4**) | `Pass2FdrSidecar.OverlayPass2OntoResidentPool` |
| `ScoringTaskShared.Stage7ResidentGuardError` | resident `ModelDiagnosticsReport.WritePass2AndFinalize` overload |
| `SecondPassFdrTask.WarnResidentStage7Join` | |
| the `stage7Stream` parameter threading | |
| `regression.ps1`'s `$abSwitchSet` STAGE7_STREAM terms | |

`PROJECTION_OFF` is documented as leaving the list last (it needs #4507, FDRBench pass 1,
first), so that is the gating dependency for finishing the removal.

## Plan

1. **Bank the A/B oracle before deleting it.** `OSPREY_STAGE7_STREAM=0` vs default on Stellar +
   Astral; record byte-identity here and in the commit message. Deleting the resident arm is a
   one-way door - afterwards "did streaming change results?" can only be answered against the
   committed golden, never against the twin.
2. **Route `--task ModelDiagnostics` to `RehydrateForPerRunRescore`** so path (i) has no
   consumer. Keep the admit-list shape (name what is admitted; fail closed).
3. **Delete path (ii)**: the `else` arm of `FoldPass2DiagnosticsOnly`,
   `Pass2FdrSidecar.OverlayPass2OntoResidentPool` (1 def + 1 call),
   `SecondPassFdrTask.WarnResidentStage7Join` (1 def + 2 calls), and the resident
   `ModelDiagnosticsReport.WritePass2AndFinalize` overload. The streamed twin
   `WritePass2AndFinalizeFromAccumulator` already exists.
4. **Retire `OSPREY_STAGE7_STREAM`** and shrink `ResidentPaths.KNOWN_UNFIXED` from 5 to 4
   (`STAGE7_STREAM_OFF` goes). Update `ResidentPoolGuardTest` to pin the smaller list - the
   ratchet running the right way, which the class remarks require.
5. **Add a route assertion to mode 7**: have the per-run arm emit a marker and require it. This
   is the item that would actually have caught the defect, and it fails at 3 files where a
   memory-shape check cannot. Optionally also assert at the allocation point - reaching the
   all-runs builder with `SelectedTask.HasValue` is a hard error naming the O(files x entries)
   cost.

**Do NOT** add `HpcTask.ModelDiagnostics` to `Program.cs:136`'s `StopAfterStage5`. That is the
tempting one-liner and it is strictly worse: FirstPassFDR returns before publishing the survivor
loader, so pass-2's fold falls to the resident buffer - trading 0.10 GB/file for 91.1 GB.

## Gates

* `regression.ps1 -Dataset Stellar`, then `regression-parallel.ps1 -Dataset All`.
* Mode 3's per-run-hydrate leg, which `CanHydratePerRun`'s own comment names as the check
  ("SKIPPED on all three --model-diagnostics datasets for exactly this reason and must now run
  and pass").
* Mode 7 with the new route assertion, and mode 11 for the report.
* **The real oracle**: a 446-file `--task ModelDiagnostics` re-run on the CHS cohort. It walls
  within ~1 h if the fix did not take, so it fails fast.

## Evidence that the report itself is correct (so this is a memory fix only)

From the night run, all at 446 files - the report is route- and build-invariant:

* phase 5 (straight-through) vs `chs446-mdiag-coldfpfdr`: **IDENTICAL**, only `generatedUtc`;
  252,021 bytes both sides including the trained model's 21 coefficients.
* phase 2 (pay-later) vs `p16proof`: **IDENTICAL**, only `ospreyVersion`.
* phase 5 vs phase 2, same exe: **IDENTICAL** except the four model-derived views a resumed run
  cannot retrain.
* `--model-diagnostics` is output-neutral: phase 5 and the source run both report
  `4376266 targets, 43124 decoys pass 1.0% FDR`.

## Out of scope, but adjacent

`FdrProjectionSet.Builder` is confirmed dead production code (zero call sites; only
`FdrTest.cs:3257` instantiates it). Its parity test certifies a live implementation against an
unreachable one. Delete both - separate commit.

## Phase-5 run: stopped deliberately, resume is now part of the test plan (2026-09-10 11:40)

The 446-file straight-through-with-diagnostics run was killed at **11:40:27** after 11h32m, at
file **344/446** of the Stage 6 rescore. Not a failure - a decision: finishing it would have
spent ~4 more hours testing a STALE exe (the master snapshot, v26.1.1.252) while the branch sat
unreviewed. Front-loading the PR work and resuming later on the FIXED exe tests more, not less.

**Anchor at the kill**, so the resume can be verified rather than trusted: 344 reconciled
parquets, 344 `.2nd-pass.fdr_scores.bin`, 1032 `PerFileRescoring` stamps (3 per file).

**Part 1 banked**: `phase5-part1-00h08-11h40.log` (1,422,659 bytes) and
`phase5-part1-perfviz.png`.

```
duration : 11:31:40, 0 gaps >= 30s
managed  : peak 36.6 GB  floor 9.2 -> 9.7 GB  +1 MB/file  LEVEL
total    : peak 41.7 GB
  FirstPassFDR      p10 7.3 / p50 14.5 / peak 36.6 GB   priv 41.7 GB   311 min
  PerFileRescoring  p10 10.2 / p50 12.4 / peak 24.8 GB  priv 40.4 GB   380 min
```

Private already peaked at **41.7 GB** in FirstPassFDR, and Stage 7 - where the source run peaked
at 41.5 GB *without* diagnostics - has not run yet. Stage-7 headroom against the 63.7 GB box is
the open question the resumed leg answers.

**The resume is itself a test.** `phase5-resume.ps1` re-enters the same directory on the fixed
exe, which exercises stop/crash tolerance on a real 446-run cohort **across builds** - the state
a user is in who loses a long run and upgrades before resuming. Regression modes 8 and 9 cover
this on 3 files. The script asserts the claim rather than assuming it: it counts `Re-scoring
file` lines and expects ~102, not ~446.

`-LinkFrom` is kept, and it does the version pinning itself (26.1.1.243 off the source run's
markers). The fixed exe stamps 26.1.1.253, so without that pin all 344 completed files would
read as a version mismatch and Stages 1-4 would re-run for hours - Finding 0 again.

## Log preservation - one real gap, in this session's own scripts

`OspreyDatasetRun.psm1:921-941` already rotates `run.log` correctly (`Move-Item` to
`run-<stamp>.log`, stamped with the OLD log's last-write time, same-second collisions
disambiguated). Its comment records why: *"one -Resume into the wrong directory silently
destroyed an 18-hour run's 1.8 MB log this way."*

The gap was in **this session's launcher**, not the runner: `phase5-launch.ps1` opened its
capture log with a plain `Out-File`, a truncating write, so a resume would have destroyed part
1's 11.5 hours of `[MEM]` probes. Rolled before anything relaunched, and both
`phase5-launch.ps1` and `phase5-resume.ps1` now rotate the same way the runner does.

## Code review triage (`/code-review max`, 2026-09-10 ~12:10)

15 findings, 10 finder angles, 275k subagent tokens. **Verdict: NOT mergeable as-is.** Three
findings are real defects introduced by this branch, verified against source, and two of them
are regressions against master. Recorded here rather than fixed immediately so the decision is
reviewable.

### BLOCKING - defects this branch introduced

**F1 - `AllRunsBundleGuardError` is an unconditional refusal keyed on the wrong predicate.**
VERIFIED. The method ends in an unconditional `return string.Format(...)`, so `if (bundleError
!= null)` at `FirstPassFdrTask.cs:824` is always true. It fires on `!CanHydratePerRun`, whose
false branch ends:

```csharp
string path = RetainedBaseIdSidecar.PathFor(config.OutputBlib, ArtifactSiblingPath(config));
return !string.IsNullOrEmpty(path) && RetainedBaseIdSidecar.IsCurrentFormat(path);
```

- those are **disk-state** conditions - missing or stale-format `retained_base_ids.bin`, or no
  `-o` blib - not "an operator chose a resident route";
- master completed those runs via `LoadOwnReconciliationBundle`, so this is a **regression**;
- the message directs the operator to the per-run survivor loader, which is built **from the
  very file whose absence triggered the refusal** - a remedy that cannot exist where the
  refusal fires;
- it contradicts `WarnPreCompactionPool`'s stated policy that failing these configurations
  "would be a regression, not a guard".

I deleted `Stage7ResidentGuardError` precisely because it only refused the CHOSEN case - and
then wrote a guard that refuses every case. **Fix**: restore that distinction. Fire only where
the bounded alternative genuinely exists (retained sidecar present and current, and the run
declined the per-run arm for a reason other than disk state).

**F2 - admitting ModelDiagnostics to `CanHydratePerRun` disarms an unrelated hard-fail.**
VERIFIED. `PerFileRescoreTask.cs:450`:

```csharp
bool noRescorePossible = rescoreBundle == null && !perRunPlanAvailable;
```

`perRunPlanAvailable` is now true for `--task ModelDiagnostics`, so the abort at 451 can no
longer fire for it. That abort's own comment names the incident it exists for: *"measured
2026-09-03 on Astral, where --model-diagnostics makes perRunPlanAvailable false and the bundle
is null, so this arm fired for a cohort with 1 of 3 runs still to re-score."* Consequence: on a
cohort with an interrupted Stage 6, a command documented at `OspreyConfig.cs:435-441` as
suppressing every artifact write except the report can now fall through into a real rescore and
write parquets and sidecars. **Fix**: the abort must key on whether this task will actually
rescore, not on whether a per-run plan is available.

**F6 + F13 - the route assertion cannot detect what it claims.** VERIFIED.
`ProgressReporter.LOG_WAIT_SECONDS = 0.5` / `MIN_PERCENT_SECONDS = 1.0` defer the heading, so a
3-file hydrate never prints `Hydrating reconciliation bundle`; and that heading is emitted
**identically** by the bounded `HydrateCompactedStreaming` (RescoreHydration.cs:578) and the
resident `HydrateReconciliationOverlay` (:348). The secondary marker is guard prose that my own
test comment says appears on zero legs. So `Test-NoAllRunsBundle` finds neither marker whether
or not the bundle was built, and its only liveness check is `Test-Path` - it passes on an empty
or unflushed log. **Fix**: give the resident overlay a distinct marker (`nameof(
HydrateReconciliationOverlay)` is already threaded through it) and add a liveness assertion.

This is the sharpest lesson of the review: I added an assertion to close a gate blind spot, and
the assertion has the same blind spot. It went green for the same reason the original defect
did - 3 files is too small for the shape to appear.

### CHEAP AND CLEARLY RIGHT - fold into the same change

* **F11** stacked `<summary>` blocks in `ScoringTaskShared.cs` (my insertion orphaned
  `ReadRetainedBaseIdsOrFail`'s doc) - the identical defect this diff *fixes* in
  `ResidentPoolGuardTest.cs`. Embarrassing, trivial.
* **F12** the deleted `Stage7Stream`'s 24-line doc block left attached to nothing, written with
  `///` where every sibling tombstone in this changeset uses `//`. Also strands the measurement
  that justifies the streamed-join architecture - move it to `CanStreamStage7Join`.
* **F7** my new `ResidentPaths` / `SecondPassFdrTask` comments assert the resident arm is
  reachable "never by choice". False: `Stage7StreamAdmittedBeforeRescore` still declines for
  `!Pass2ProteinCompact`, i.e. `OSPREY_PASS2_QVALUE=transfer` - operator-chosen, no token.
  Deleting `Stage7ResidentGuardError` also erased the only code-level record of that exemption.
* **F8** no startup refusal for the removed `OSPREY_STAGE7_STREAM`.
  `ai/docs/osprey-development-guide.md:929` requires it: *"Fail loudly on the removed spelling."*
  Precedent both ways in `Program.cs:335-373`.
* **F10** `docs/00-pipeline-architecture.md` still documents three deleted symbols as live
  (:1123, :1131, :1148). Same guide, `:934`: *"Fix the docs in the same change."*
* **F15** stale references to the deleted switch in four touched files - notably
  `PerFileRescoreTask.cs:2651`, where it is the entire stated justification for
  `PublishedSurvivorLoader` existing separately.

### FOLLOW-UP - real, but not this PR

* **F3** the guard sits at the consumer, not the producer, and misses two other doors into the
  bundle (`PerFileScoringTask.cs:1967`, `:1486`). The right home is beside the
  `perRunRescore`/`perRunJoin` branch at `:1440`. Bigger change; file an issue.
* **F4** `retained_base_ids.bin` appears in neither `Outputs` nor `ValidityKey`, so a future
  `FormatVersion` bump hard-fails every field resume with no regeneration path. Pre-existing,
  but F1's guard makes it essential. Own issue.
* **F14** `HpcTask` routing is a hand-maintained enum list across four predicates in three
  styles; this is the second task added by hand, each at the cost of an OOM. Wants an
  `HpcTaskProfile` table with an exhaustive switch. Architectural; own issue.

**F5** (guard predicate wider than the builder's) and **F9** (~400 lines unreachable behind the
guard, including `LoadOwnReconciliationBundle`, and mode 5 permanently unable to reach its
documented purpose) are **consequences of F1** and dissolve when F1 is fixed. Not separate work.

### Nothing dropped as invalid

Unusually for a max review, every finding checked out. The ones I am deferring are deferred on
scope, not on correctness.

## Latent bug found and fixed while gating: the prune deletes live run dirs (`b7bf3867ed`)

Not related to this branch's subject - found because it killed the `-Dataset All` run - but
fixed here rather than inherited, because it is **active on this machine right now**.

**Symptom.** The Astral lane aborted mid-mode-3: `Invoke-HpcChain` (regression.ps1:1497) could
not write `...\Astral\chain\logs\phase1_<stem>.log`. `$chainLogDir` is created with `-Force` at
:1455, at the top of that same function, so it existed and then vanished.

**Cause.** The Stellar lane runs `regression.ps1` once per dataset, and each invocation runs the
startup prune. Its log shows the prune targeting the LIVE Astral run:

```
Osprey regression PASSED                       <- Stellar dataset 1 done
==> Pruning 1 stale TestResults run dir(s), keeping the most recent 0
  WARN: failed to prune ...\regression-20260910_114226_21248: The process cannot access ...
==> Dataset StellarLibDecoy                    <- dataset 2
```

`Test-RunDirLive` returned false for pid 21248 while it was running. Not the regex - `-notmatch`
does populate `$Matches` (verified: group 1 = 21248). The check was
`$p.ProcessName -eq 'pwsh'`, and **`Get-Process().ProcessName` reports the running image's
on-disk name**. Something replaced `pwsh.exe` (a PowerShell update; `.rbf` is a Windows
Installer rollback file), so live processes report the rollback name:

```
  Pid  Win32Name  GetProcessName
37796  pwsh.exe   5cc84f5d.rbf
32240  pwsh.exe   5cc84f5d.rbf
15580  pwsh.exe   5cc84f5d.rbf
 3104  pwsh.exe   5cc84f5d.rbf
26128  pwsh.exe   pwsh
24620  pwsh.exe   pwsh
```

Four of six live pwsh processes read as dead. **Any regression run started on this box today was
one sibling invocation away from being destroyed.**

**Why it was destructive despite "failing".** `Remove-Item -Recurse` deletes depth-first, so it
had already destroyed `chain\logs` before it reached a locked file. The prune then reported a
WARN and continued; the run was already wrecked.

**Fix.** Identify the image via `Win32_Process.Name` (which correctly reports `pwsh.exe`), and
**fail toward "live"** on any uncertainty - an unprunable orphan costs disk until the next run,
a wrongly-pruned live gate costs the run. Verified against the real failure mode:

```
live pwsh with rbf ProcessName: 37796
OLD check would say live: False      <- would prune a running gate
NEW check says live      : True
dead pid 21248 -> False              <- genuine orphan, still prunable
legacy name    -> False              <- pre-PID name, still prunable
```

**Worth considering as follow-up** (not done): the prune's destructive-then-warn shape. Even
with a correct liveness check, a half-completed recursive delete of someone else's scratch is a
bad failure mode. Deleting to a staging name first, or checking writability before recursing,
would make a mistaken prune recoverable instead of fatal.

## Gate status at handoff

`-Dataset All` via `regression-parallel.ps1`: **TOTAL 76 PASS / 0 FAIL / 0 SKIP**, 01:14:26.

* Stellar + StellarLibDecoy + StellarGenDecoyEntrap lane: **exit 0, 72 PASS / 0 FAIL / 0 SKIP** -
  every mode including 3, 5, 6, 7, 11, 8, 9.
* Astral lane: **exit 1, 4 PASS / 0 FAIL / 0 SKIP** - ABORTED by the prune above after modes 1,
  1c, 1b. **No assertion failed anywhere in either lane.**

**Astral re-run SERIALLY and alone: `Osprey regression PASSED`, `ASTRAL GATE EXIT 0`**
(13:00 -> 14:00), `Tokens REQUIRED by this gate: 0 (target: 0)`. Every mode green, including the
one that aborted:

```
Astral mode3 (per-file FDR sidecars==straight): PASS (14,413,584 records)
Astral mode3 (shipped fold):    PASS (worker answer folded for every file)
Astral mode3 (streamed join):   PASS (per-run fold, no all-runs pool)
Astral mode3 (verifier split):  PASS (straight verified, chain shipped-path)
Astral mode3 (per-run hydrate): PASS (3 worker(s))
Astral mode3 (HPC chain==straight):     PASS
Astral mode3 (chain report is two-pass): PASS
Astral mode7  (diagnostics regeneration: report only, vs golden): PASS
Astral mode11 (pay-later diagnostics: folded, no analysis, same report): PASS (pass-2 byte-exact)
Astral mode4/5/6/8/9: PASS
Astral mode2 (streamed join): SKIP (leg not run - mode 2 is not run for Astral by suite design)
```

Run alone, so this result does not depend on the prune fix being correct.

**Coverage is therefore complete across all four datasets**, in two runs rather than one:
72 PASS / 0 FAIL for the three Stellar variants, plus a full green Astral. No assertion failed
anywhere at any point.

## Follow-up: stop cleaning up after a run (`-KeepRunDirs` default 0 -> 1)

Brendan, 2026-09-10: *"Many sessions have wasted time rerunning tests because the existing test
cleans up so aggressively by default. Leaving files by default is probably the right decision as
long as there is only one set at any time."*

**Rule**: clean **BEFORE** a run; do not clean after, on either outcome. Bound disk by keeping
only the most recent set.

This retires the earlier "clean before, clean after SUCCESS, never after failure" formulation.
The success half did not survive contact - measured twice:

* 2026-09-03: two ~30-minute re-runs to recover a `partial-resume.log` a FAILING run had already
  written (which "keep on failure" would have covered).
* 2026-09-10, **this session**: the Stage-7 A/B needed the STREAMED diagnostics HTML. It had
  existed and been self-cleaned, so a second full ~40-minute gate ran solely to regenerate an
  input that had already been produced; the comparison itself took minutes.

The second case is what rules out verdict-gated cleanup: **that run PASSED.** Nothing about its
verdict predicted its output would be wanted an hour later for a comparison that did not exist
when it ran.

**Change**: `regression.ps1`'s `-KeepRunDirs` default `0` -> `1`. The startup prune already runs
unconditionally, so this keeps exactly one set and bounds disk by construction - no dev/CI
distinction needed, which was the weakness of the older "make `-KeepOutput` the default on dev
machines" idea.

**Sequence it AFTER `b7bf3867ed`** (this branch's prune fix). "Keep the last set" is only safe if
the prune can be trusted not to delete a LIVE set, which it could not until that commit.

Deliberately NOT folded into this branch: unrelated to its subject, and the branch is green at a
clean handoff point. Its own small change, or fold into the next session's work if convenient.

## Code review fixes - all three blocking findings closed (2026-09-10 14:30)

Two commits, both green (build 0 errors, inspection zero warnings, 593/593):

| commit | |
|---|---|
| `b689ee8c45` | Fixed the all-runs bundle guard refusing runs it had no remedy for (F1, F2, F6+F13) |
| `1fe93f8996` | Refused the removed `OSPREY_STAGE7_STREAM` spelling at startup (F7, F8, F10, F11, F12, F15) |

**F1.** `CanHydratePerRun` split into the ROUTE half and the DISK half
(`PerRunSurvivorLoaderAvailable`, which also DRYs `CanStreamStage7Join`'s copy of the same
probe). `AllRunsBundleGuardError` now takes the config and returns null when the loader
cannot exist - no `-o` blib, or a summary this build cannot read - so those runs warn and
take the bundle exactly as master does. What survives is the case the review asked for: the
loader is on disk and this route declined it, which is unreachable once F1 itself is fixed
and is precisely the `--task ModelDiagnostics` shape. `ResidentPoolGuardTest` now pins BOTH
halves; the null half is the one that would otherwise regress in silence.

**F2.** The rescore-resume abort is re-keyed from "a plan is available" to
`willRescoreHere = !DiagnosticsOnly && (didPlan || !noRescorePossible)`. Admitting
ModelDiagnostics to `CanHydratePerRun` had made `perRunPlanAvailable` true for the one task
that never rescores, so an interrupted cohort would have fallen through into a real Stage 6
rescore - hours of work and reconciled-parquet writes on an analysis the command is
documented not to disturb. Modes 7 and 11 are unaffected: both leave every analysis artifact
current and only delete the diagnostics products, so `pass2Present == pass2Expected`.

**F6+F13.** The marker moved to the PRODUCER: `HydrateReconciliationOverlay` logs
`Hydrating the ALL-RUNS reconciliation bundle: N run(s) held at once` unconditionally,
through a new optional `logInfo` (the shape `FoldPreCompactionPerRun` already uses), so every
door into the bundle is visible rather than one caller. `Test-NoAllRunsBundle` drops the
`Hydrating reconciliation bundle` heading - deferred past `LOG_WAIT_SECONDS` at 3 files and
emitted identically by the BOUNDED route when slow, so it could not fire at gate scale and
would have fired wrongly at cohort scale - and gains a liveness check: no `[TASK]` banner
means the log proves nothing and the leg fails.

### Deferred findings: dropped, not filed

Per the standing rule that a review's leftovers are fixed or dropped, never relocated:

* **F3** (guard at the consumer, not the producer) - the DETECTION half is now at the
  producer and covers every door, which is what the finding was really about. Its second
  citation, `PerFileScoringTask.cs:1486`, is the STREAMED twin `HydrateCompactedStreaming`,
  not a door into the bundle; the real second door (`:1967`) already discloses through
  `WarnPreCompactionPool` and now emits the marker too. The refusal stays where the bounded
  alternative is decided.
* **F4** (`retained_base_ids.bin` in neither `Outputs` nor `ValidityKey`) - tried and backed
  out. Stamping is per-writer, not generic, so declaring an output that has never been
  stamped makes `OnlyDiagnosticsProductOutstanding` read every completed analysis on disk as
  owing a first pass: `--task ModelDiagnostics` on the 446-run bed would re-run Stage 1-5 for
  hours instead of folding in seconds, which would also destroy this branch's own oracle.
  Left as a located instruction on `RetainedBaseIdSidecar.FormatVersion` naming all three
  edits a bump owes, to be paid WITH the bump that makes those directories stale anyway.
  The F1 warning was reworded in the same pass - it had named "re-run the FirstPassFDR phase"
  as the remedy, which does nothing on a complete analysis for exactly this reason.
* **F14** (`HpcTask` routing as a hand-maintained list across four predicates) - a scope
  decision rather than a defect; see the question raised with Brendan.

### Gates after the fixes

* Local pre-commit: build 0 errors / 0 warnings, inspection zero warnings, 593/593.
* `regression.ps1 -Dataset StellarLibDecoy` 14:34 -> 15:03: **mode 7 FAIL, every other leg
  PASS** - see below. Log kept at
  `ai/.tmp/sessions/20260910-01Qwgkv/gate-stellarlibdecoy-20260910_150300.log`.
* Re-run launched 16:53 after the fix (`5959964200`), with
  `regression-parallel.ps1 -Dataset All` chained behind it as a waiter that only fires on
  exit 0. Then `/code-review max` again, then the 446-file oracle.

### The liveness anchor failed mode 7 for being itself (`5959964200`)

The gate's only red was **my own new assertion**, and it is the same lesson as F6+F13 in a
new costume: I added a check to close a blind spot and gave the check a blind spot.

`Test-NoAllRunsBundle`'s liveness anchor was "the log contains a `[TASK]` banner". Mode 7
re-renders a report whose products are all present, and `Program.cs` settles that case in
`RunModelDiagnosticsTask` and returns **before** `new AnalysisPipeline()` is reached - so it
emits no task banner at all. Mode 11, which deletes the products, falls through to the
pipeline and emits several. An anchor only one of the two routes reaches fails the other for
being itself. I had verified `[TASK]` appears in *a* run log, not in *this leg's* log.

Now anchored on the startup banner (`Threads:`), which every invocation emits after argument
parsing and before any route is chosen. Also fixed a PowerShell `-f` precedence bug in the
same message - `("a" + "b" -f $x)` binds `-f` to the last string only, so it printed `{0}`
and `{1}` literally; the sibling assertion three lines down had the parentheses right.

Worth keeping: **the check worked.** It refused to certify a log that could not prove
anything, which is exactly what it was added to do - it just refused the wrong leg.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260910_osprey_mdiag_resident_removal.md` before starting work.
