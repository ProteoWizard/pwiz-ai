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

(i) is what walled; (ii) is next in line. Both must go.

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
