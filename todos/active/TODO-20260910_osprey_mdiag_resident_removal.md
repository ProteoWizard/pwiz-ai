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
