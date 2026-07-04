# TODO-20260516_osprey_libdecoy_e2e_and_fdrbench.md -- Library-decoy E2E + `--fdrbench` port

> **RETIRED / SUPERSEDED 2026-07-04.** Track 2 (`--fdrbench` native export) shipped in
> PR #4337. Track 1 (the AstralLibraryDecoy cross-impl byte-parity gate) never ran as
> specced: the Carafe Astral entrapment/decoy library + manifest we were blocked on
> became the files later used directly in the reconciliation base_id work, and Track 1's
> intent (proving library-decoy FDR is controlled) was met by PR #4347 + FDRBench
> validation on Stellar entrapment rather than the never-staged AstralLibraryDecoy
> Test-Regression gate. No residual work retained. Moved to completed as done+superseded.

> Follow-up sprint to PR #4215. Two tracks: (1) close the library-
> decoy gap by running the cross-impl byte-parity gate on Mike's
> Carafe-built Astral library + FDRBench manifest; (2) port the
> `--fdrbench` native-export Rust pieces that were intentionally
> deferred from #4215 to keep that PR a "quick" merge.

## Branch Information

- **Branch**: `Skyline/work/20260630_osprey_libdecoy_reconciliation_baseid`
  (created 2026-06-30; the 20260516 name was never used -- see re-scope note)
- **Base**: `master` (post-#4215 squash at `bb1992e248`)
- **Created**: 2026-05-16
- **Re-scoped**: 2026-06-30
- **Status**: **RE-SCOPED 2026-06-30 -- mostly OBE.** The world moved on in the
  6 weeks this TODO sat dormant:
  - **Track 2 (`--fdrbench` port) is DONE** via **PR #4337** (merged
    2026-06-30) -- the full writer plus the 4000-byte protein-column cap,
    tested, validated end-to-end via Carafe on Stellar HeLa entrapment data.
    Both upstream commits (`5da4a46`, `1fd7552`) are now ported. Track 2 needs
    no further work here.
  - **Rust osprey was archived 2026-06-03** ("Relicensed to LGPL-3.0 and
    archived in favor of OspreySharp"), so the original validation premise --
    a cross-impl byte-parity gate against *maintained* Rust at v26.6.0
    (`bcd7249`) -- no longer points at a moving target. Parity vs `bcd7249`
    stays valid as a frozen oracle, but is no longer the forward gate.
  - **Track 1's E2E dataset is still missing.** Mike's Carafe-built Astral
    library + manifest never arrived (`D:\test\osprey-runs\astral-libdecoy\`
    does not exist). BUT PR #4337 shows a **Stellar HeLa entrapment dataset now
    exists and works end-to-end**, which likely makes the Astral-specific
    dataset non-essential for proving FDR control.
  - **Track 3's upstream blocker cleared**: `maccoss/osprey#35` merged
    2026-05-16; the C# deferral port is the one genuinely-actionable code item
    left (small).
  Two open decisions remain (see re-scoped Next steps below): how to frame
  Track 1's E2E gate now that Stellar entrapment data exists and Rust is
  frozen, and whether to port the Track 3 deferral (it breaks byte-parity vs
  the now-frozen `bcd7249`).
- **GitHub Issue**: (none)
- **PR**: Track 2 landed as **#4337** (outside this TODO's branch). Track 3
  deferral would be a small separate PR if pursued.
- **Predecessor TODO**:
  [`TODO-20260515_osprey_catchup_followup.md`](../completed/TODO-20260515_osprey_catchup_followup.md)
- **Upstream Rust references**:
  - `maccoss/osprey` at `bcd7249` (v26.6.0). Commits to port:
    - [`5da4a46`](https://github.com/maccoss/osprey/commit/5da4a46) --
      `--fdrbench` native export (~527 lines)
    - [`1fd7552`](https://github.com/maccoss/osprey/commit/1fd7552) --
      4000-byte protein column cap on `--fdrbench` output (~125 lines)
  - [`maccoss/osprey#35`](https://github.com/maccoss/osprey/pull/35)
    -- the "defer no-decoys check until after manifest" fix; once
    merged upstream, port the deferral back here and remove the
    `TODO(brendanmaclean,maccoss):` comment at
    `PerFileScoringTask.cs:308`.

## Mission

Osprey going primary next week needs the library-decoy code
path verified at byte-parity against Rust on real Carafe-built data
(Track 1), and Mike's most recent functional work in osprey-io's
FDRBench TSV writer ported so the C# port doesn't fall behind on
the artifact downstream FDRBench GUI consumes (Track 2). After this
sprint, Osprey produces the same library-decoy and FDRBench-
input outputs as `maccoss/osprey:bcd7249` and the AstralLibraryDecoy
dataset shape is a real gate, not a placeholder.

## Track 1 -- AstralLibraryDecoy E2E gate (the unblocked piece)

PR #4215 added the harness plumbing
(`AstralLibraryDecoy` dataset in `Dataset-Config.ps1`, the
`--decoys-in-library` + `--decoy-pairing-manifest` CLI flags,
ValidateSet updates on `Test-Snapshot.ps1` / `Test-Regression.ps1` /
`Test-Features.ps1` / `Run-Osprey.ps1`). The placeholder filenames
at `D:\test\osprey-runs\astral-libdecoy\` need to become real
files, and the gate needs to run.

### Mike's message (forwarded 2026-05-15 evening)

> Tonight I will send you libraries that contain data for both
> entrapment and decoys. Most of the time we won't want entrapment
> sequences as it reduces the sensitivity because of multiple
> testing. However, for testing it is fine and it will let you
> check that the FDR is controlled.
>
> I will send the latest commands to use the library with the
> decoys and the pairing manifest and generate the input to the
> FDRBench. That is now part of the Rust code too.

So the inputs to expect:
- A Carafe-built Astral spectral library TSV with both target +
  entrapment + decoys baked in.
- An FDRBench-style pairing manifest TXT (peptide-pair file)
  with `peptide_type` rows for `target`, `decoy`, `p_target`,
  `p_decoy`.
- A sample command (likely a CLI invocation example) showing
  the canonical `--decoys-in-library --decoy-pairing-manifest
  <path>` flow plus `--fdrbench <out.tsv>` for the
  FDRBench-input export (gated on Track 2 being landed).

### Steps

1. **Stage the files** Mike sends at
   `D:\test\osprey-runs\astral-libdecoy\` (or wherever the
   `$env:OSPREY_TEST_BASE_DIR` override resolves to).
2. **Update placeholders** in
   `ai/scripts/Osprey/Dataset-Config.ps1`:
   - `Library`: currently
     `SkylineAI_entrapment_carafe_spectral_library.tsv`. Replace
     with Mike's actual filename.
   - `Manifest`: currently
     `SkylineAI_entrapment_carafe_pairing_manifest_pep.txt`.
     Same -- replace with Mike's actual filename. (FDRBench
     calls these `*_pep.txt` by convention; check.)
3. **Capture the same-impl baseline** at v26.6.0:
   ```
   pwsh -File ai/scripts/Osprey/Test-Snapshot.ps1 \
     -Dataset AstralLibraryDecoy -Files All -CreateSnapshot
   ```
   Watch for the new "Library-decoy mode" log lines that PR
   #4215 added; confirm `NProteinsReplaced > 0` if the Carafe
   library has the per-peptide-suffix `ProteinID` pattern. If
   the baseline doesn't capture cleanly, fix forward before
   running the cross-impl gate.
4. **Run cross-impl Test-Regression** vs Rust v26.6.0:
   ```
   pwsh -File ai/scripts/Osprey/Test-Regression.ps1 \
     -Dataset AstralLibraryDecoy -Files All -Force
   ```
   Goal: PASS at every stage (`stage1to4 -> stage5 -> stage6
   -> stage7 -> blib`), same as we get on Stellar / Astral
   reverse-decoy. If it FAILs at any stage, the bisection
   harness drops into the per-stage diagnostic and we debug
   from there. Likely failure modes:
   - Stage 1-4: library-load divergence; check
     `NProteinsReplaced` and `NNewlyMarkedDecoy` on both
     sides via `Run-Osprey.ps1 -Tool Rust` vs `-Tool CSharp`.
   - Stage 5 (Percolator): pairing-fraction divergence; the
     composition pairer's deterministic sort is the usual
     suspect.
5. **Wire as a PR-open gate** (alongside Stellar / Astral
   reverse-decoy) in the post-PR checklist for any future
   library-decoy-touching change.

## Track 2 -- `--fdrbench` native export port -- ✅ DONE (PR #4337, 2026-06-30)

**COMPLETED outside this TODO's branch.** PR #4337 ("Osprey: add
`--fdrbench` / `--fdrbench-per-run` FDRBench input output", merged
2026-06-30) ported both upstream commits:
- `5da4a46` (writer) -> `Osprey.Tasks/FdrBenchInputWriter.cs` (+ test),
  `OspreyConfig` (`OutputFdrBench`, `FdrBenchPerRun`), `OspreyCommandArgs`,
  pipeline wiring in `MergeNodeTask` (output/merge stage, reflecting the
  peptides actually written to the library), `--fdr-level` auto-selection,
  regenerated `CommandLine.html`.
- `1fd7552` (4000-byte protein-column cap) -> the protein-truncation logic
  in `FdrBenchInputWriter` (exercised by `FdrBenchInputWriterTest`).

Validated end-to-end via Carafe on Stellar HeLa entrapment data: at q=0.01,
combined FDP 0.98% / paired FDP 0.88% (on/below the unity line). Note the
final C# placement put the writer in `Osprey.Tasks`, not the originally
planned `Osprey.IO`, and wired it through `MergeNodeTask` -- both fine.

The original porting plan is kept below for reference only.

### (reference -- original Track 2 plan, now satisfied by #4337)

### Step 1 -- Port `5da4a46` (`--fdrbench` native export)

Rust source layout:
- `crates/osprey-core/src/config.rs` (+21 lines) -- two new
  config fields: `fdrbench` output path + `fdrbench_per_run`
  bool.
- `crates/osprey-fdr/src/protein.rs` (+47 lines) -- protein-
  side helper to emit picked-protein FDRBench input.
- `crates/osprey-io/src/output/fdrbench.rs` (+404 lines, NEW)
  -- the FDRBench TSV writer module.
- `crates/osprey-io/src/output/mod.rs` (+3 lines).
- `crates/osprey/src/main.rs` (+17 lines) -- CLI flags.
- `crates/osprey/src/pipeline.rs` (+34 lines) -- pipeline
  wiring + `--fdr-level` auto-selection.

C# placement plan:
- `Osprey.Core/OspreyConfig.cs`: add `FdrbenchOutputPath`
  and `FdrbenchPerRun` properties. Fold into
  `SearchParameterHash` matching Rust formatting (path through
  `EscapeForRustDebug`, bool as `b()`).
- `Osprey.IO/FdrbenchWriter.cs` (NEW): the TSV writer.
  Mirror Rust's column set exactly; use the patched
  `ParquetNet.dll` overlay convention if Parquet I/O is
  involved (it isn't here -- TSV-only).
- `Osprey.FDR/ProteinFdr.cs`: the picked-protein
  helper.
- `Osprey/Program.cs`: `--fdrbench <PATH>` and
  `--fdrbench-per-run` CLI flags (same `internal static
  ParseArgs` exposure as #4215 used for the library-decoy
  flags, with strict path validation).
- `Osprey/Tasks/PerFileScoringTask.cs` or `MergeNodeTask.cs`:
  the pipeline wiring -- emit after first-pass FDR but
  before compaction (mirror Rust's "pre-compaction first-pass
  FDR pool" sequencing). `--fdr-level` auto-selection.

Tests:
- Translate every Rust unit test in `osprey-io/src/output/fdrbench.rs`
  to MSTest. Use the same input shapes the Rust tests use
  (header parsing, level auto-select, picked-protein TSV
  output, `_p_target` pass-through, decoy exclusion).
- Add a smoke test that runs the writer on a synthetic
  `FdrEntry`-shaped fixture and SHA-256-compares the output
  against the Rust writer's output on the same input. This is
  the cross-impl byte-parity gate -- the strongest signal
  the port is right.

CLI validation surface (don't repeat #4215's mistakes):
- Reject bare `--fdrbench` or `--`-prefixed value (port the
  same `i >= args.Length || args[i].StartsWith("--")` check
  pattern from `--decoy-pairing-manifest`).
- `--fdrbench-per-run` is a flat boolean; same shape as
  `--decoys-in-library`.
- Add both to `PrintUsage`.

### Step 2 -- Port `1fd7552` (4000-byte protein column cap)

Small defensive fix in `crates/osprey-io/src/output/fdrbench.rs`
(~125 lines, mostly tests). Truncates oversized protein-ID
lists with a marker so a Carafe-built library stamping a
multi-thousand-character `ProteinID` doesn't crash the
FDRBench GUI parser.

Depends on Step 1 being landed (the cap lives in the writer
Step 1 introduces).

C# placement: add `TruncateProteinColumn` (or similar) to
`FdrbenchWriter.cs`; mirror Rust's truncation marker exactly
for cross-impl byte parity on the test fixture above.

## Track 3 -- Upstream sync follow-ups -- UNBLOCKED, port pending (decision needed)

1. **`maccoss/osprey#35`** (defer "no library decoys" until
   after manifest pass) -- **MERGED upstream 2026-05-16.** The C# port is
   NOT yet done. Current state (verified 2026-06-30): the `nLibraryDecoys
   == 0` bail still runs BEFORE the manifest pass in
   `PerFileScoringTask.cs:733` (`TryPairSuppliedDecoys`), with the live
   `TODO(brendanmaclean,maccoss)` comment at `:727` explaining it matches
   Rust v26.6.0 (`bcd7249`) for the cross-impl byte-parity gate.

   To port:
   - Move the `nLibraryDecoys == 0` bail to AFTER manifest application
     (the manifest can flip predictor-stripped entries to `IsDecoy=true`);
     recount via `LibraryDecoyPairing.CountTargetsAndDecoys`.
   - Remove the `TODO(brendanmaclean,maccoss)` comment at `:727`.
   - Add a regression test: a Carafe-shaped library with zero
     prefix-flagged decoys + a manifest that classifies some entries as
     `decoy` should now succeed instead of erroring.

   **Decision needed before porting:** this deliberately breaks byte-parity
   against the pinned `bcd7249` (the comment at `:727` says so). Since Rust
   is archived as of 2026-06-03 and #35 is *post*-`bcd7249`, "parity vs
   `bcd7249`" is no longer the forward gate -- but confirm with Brendan that
   we're moving the C# oracle forward past `bcd7249` rather than holding it
   pinned. If yes, this is a small standalone PR.

## Validation gates (per commit)

1. **Build + tests**: `pwsh -File
   ai/scripts/Osprey/Build-Osprey.ps1 -RunTests
   -RunInspection`. 0 errors, all tests pass, inspection at
   baseline 4 warnings.
2. **Stellar reverse-decoy snapshot**: still PASS post-commit.
   Catches accidental regressions in code paths unrelated to
   the library-decoy work.
3. **AstralLibraryDecoy snapshot**: PASS once Track 1's
   baseline is captured.

## PR-open gates

- Build + tests clean
- ResSharper at baseline
- Stellar same-impl `Test-Snapshot.ps1 -Files All` PASS
- Stellar cross-impl `Test-Regression.ps1 -Force` PASS
- Astral cross-impl `Test-Regression.ps1 -Force` PASS
- **AstralLibraryDecoy cross-impl `Test-Regression.ps1 -Force`
  PASS** (new gate; first PR that has the data for it)
- Copilot review chain complete (`/pw-respond`)
- `/pw-self-review` fresh-context pass complete

## Out of scope

- The Osprey NextFlow / Linux packaging work tracked at
  [`ai/todos/backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md`](../backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md).
  That's a new-feature track for the lab member starting
  NextFlow testing; separate sprint.
- Any new functional work upstream lands in osprey AFTER
  `bcd7249`. If Mike pushes additional commits while this
  sprint is in flight, those land in a follow-up to this TODO,
  not in scope here.

## Progress log

### 2026-05-16 -- Sprint planned

- PR [#4215](https://github.com/ProteoWizard/pwiz/pull/4215) merged
  as `bb1992e248`; the previous TODO closed at
  [`TODO-20260515_osprey_catchup_followup.md`](../completed/TODO-20260515_osprey_catchup_followup.md).
- Mike's message (forwarded the evening of 2026-05-15)
  unblocks Track 1: library + manifest arriving overnight.
- Track 2 dependency order confirmed: `5da4a46` (writer) ->
  `1fd7552` (4000-byte cap).
- Track 3 hold confirmed: waits on
  [maccoss/osprey#35](https://github.com/maccoss/osprey/pull/35)
  to merge before the C# deferral can ship.

### 2026-06-30 -- Re-scoped after 6 weeks dormant; mostly OBE

Resumed via `/pw-continue`. Branch was never created (pwiz on `master`).
Surveyed current state against the original plan -- the landscape shifted
substantially:

- **Track 2 DONE via PR #4337** (merged 2026-06-30, `f51c1d8`): full
  `--fdrbench`/`--fdrbench-per-run` writer + 4000-byte protein cap, tested,
  Carafe-validated on Stellar entrapment data. Both upstream commits
  (`5da4a46`, `1fd7552`) ported. Landed outside this TODO's (uncreated)
  branch. Track 2 section marked done.
- **Rust osprey archived 2026-06-03** ("Relicensed to LGPL-3.0 and archived
  in favor of OspreySharp", `07d17a4`). Original cross-impl-vs-maintained-Rust
  validation premise is OBE; `bcd7249` remains valid only as a frozen oracle.
- **Track 1 dataset still absent**: `D:\test\osprey-runs\astral-libdecoy\`
  does not exist; Mike's Astral library/manifest (promised "overnight"
  2026-05-15) never arrived. The library-decoy *code* is done + unit-tested.
  PR #4337's Stellar HeLa entrapment validation suggests the Astral-specific
  E2E gate may be non-essential.
- **Track 3 unblocked**: `maccoss/osprey#35` merged 2026-05-16. C# deferral
  port still pending at `PerFileScoringTask.cs:727/733`; flagged as the one
  actionable code item, pending a parity-oracle decision with Brendan.

**Open decisions for Brendan (next session):**
1. **Track 1 E2E gate** -- drop the Astral-dataset dependency and treat the
   Stellar HeLa entrapment run (#4337) as the FDR-control gate? Or still want
   Mike's Astral library? (If still want it, the action is a single ping to
   Mike, 6+ weeks overdue.)
2. **Track 3 deferral port** -- move the C# oracle forward past `bcd7249`
   (archived Rust HEAD includes #35) and port the deferral as a small PR? Or
   hold the pin and leave the bail-before-manifest ordering as-is?
3. **This TODO** -- with Track 2 done and Track 1 effectively unblocked-by-
   substitution, consider closing this TODO and spinning Track 3 into its own
   small TODO if pursued.

### 2026-06-30 (session 2) -- Dataset arrived; E2E gate run; found + fixed a real bug

Mike delivered the testable target-decoy libraries (Panorama:
`StellarTest-TargetDecoyLibraries/` + `AstralTest-TargetDecoyLibraries/`,
each with `target+decoy/` and `target+decoy+entrapment/` variants:
`carafe_spectral_library.tsv` + `osprey_library_db_pairing.tsv` FDRBench
manifest + fasta). Staged the entrapment variants at
`D:\test\osprey-runs\{stellar,astral}-libdecoy\` (mzML hardlinked from
`osprey-testfiles-mzML`). Entrapment ratio is 1:1 (218871 each of
target/decoy/p_target/p_decoy).

**Two silent harness bugs fixed first (both from the 2026-06-27 rename):**
1. `Dataset-Config.ps1` had two functions named `Get-OspreyExe` (C# +
   Rust); the second silently shadowed the first, so `-Framework` calls
   returned the **Rust** exe. The cross-impl gate was running **Rust vs
   Rust** -- a green that validated nothing. Renamed the Rust accessor to
   `Get-OspreyRustExe`; repointed callers.
2. `Compare-EndToEnd-Crossimpl.ps1` precursor-count regex didn't match the
   reworded C# log line ("Wrote N library spectra"), forcing a false
   `OVERALL: FAIL`. Broadened the regex.
   Extended the gate + `Dataset-Config` for the library-decoy path (new
   `StellarLibraryDecoy`/`AstralLibraryDecoy` datasets; forwards
   `--decoys-in-library` + `--decoy-pairing-manifest`; stages the manifest).

**Parity matrix (C# @ branch vs Rust @ HEAD 696c938, 1e-9 gate):**
| Run | Result |
|-----|--------|
| plain Stellar 1-file / 3-file | PASS / PASS |
| libdecoy Stellar 1-file | PASS |
| libdecoy Stellar 3-file (pre-fix) | **FAIL** rust=30674 cs=28542 |
| libdecoy Stellar 3-file (post-fix) | **PASS** 30674=30674 |

**Root cause + fix (committed `a5fd65ba3e`):** the multi-file library-
decoy divergence was a partial port of Rust `0abe0ff` ("pair library-
supplied decoys by base_id"). `ConsensusRts.cs` had the base_id fix but
`ReconciliationPlanner.cs` still keyed `passingPrecursors` on the
`DECOY_`-prefix-stripped sequence -- library-supplied (Carafe) decoys have
no prefix, so they were skipped from reconciliation, froze at first-pass
boundaries, and biased second-pass FDR. Fixed to key on
`(EntryId & 0x7FFFFFFF, charge)`; removed the dead `DECOY_PREFIX`; added
`TestPlanLibrarySuppliedDecoyReconciledViaBaseId` (proven fail pre-fix,
pass post-fix). `#45` (exclude-decoys-from-gap-fill) was already ported.

**Gates green:** build (Debug+Release), 440 tests + new regression test,
inspection clean, `regression.ps1 -Dataset Stellar` PASS (mode1 golden
confirms plain output byte-identical -- the fix is inert for generated
decoys), libdecoy Stellar 3-file cross-impl PASS.

**Still open:**
- **Astral libdecoy cross-impl** (3-file, hram, 12.5GB lib) -- not yet run;
  confirms the fix generalizes. ~45 min.
- **FDRBench graph reproduction** -- pipeline works end-to-end (Osprey
  `--fdrbench` -> FDRBench v1.1.1 jar at `D:\test\fdrbench\` -> FDP CSV).
  Stellar precursor-level gives 30641 disc / combined 1.46% / paired 1.33%
  (FDR controlled, curves near/below unity) but does NOT match Mike's
  screenshot 1 (27479 / 0.98% / 0.88%). Peptide-level FDRBench errored
  ("entrapment hits > k=1"). Need Mike's exact FDRBench invocation
  (`-level`, `-fold`/`-r`) -- the graph is parameter-sensitive.
- Push branch + open PR. Astral FDRBench (screenshot 2: 84214 / 0.83% /
  0.76%) after params are confirmed.

### 2026-06-30 (session 2, cont.) -- Parity fix HELD BACK: it degrades FDR

**Critical reversal.** A controlled FDRBench A/B (identical params, same
Stellar libdecoy 3-file input, only the base_id fix differs) shows the fix
makes entrapment FDP **anti-conservative**, i.e. it degrades real FDR
control:

| | disc@1% | combined FDP@1% | paired FDP@1% | mean dist. from unity line |
|-|---------|-----------------|---------------|----------------------------|
| pre-fix (buggy) | 28517 | 0.82% | 0.77% | 0.10 / 0.12 pp (below line, controlled) |
| post-fix (base_id) | 30641 | **1.46%** | **1.33%** | 0.78 / 0.70 pp (ABOVE line, under-controlled) |

- Pre-fix reproduces Mike's screenshot (0.82/0.77 ~ his 0.98/0.88); confirms
  his plots were pre-fix C#.
- Post-fix == Rust HEAD (bit-parity proven: 30674=30674, stage7+blib @1e-9),
  so **Rust HEAD is anti-conservative here too** -- not a C# port bug. The
  `0abe0ff` reconciliation admits +2124 discoveries but a disproportionate
  share are entrapment (false) -> FDP crosses above the FDR line.

**Decision (Brendan):** do NOT commit a change that degrades FDR just because
it matches Rust. The fix commit `a5fd65ba3e` is **held** on branch
`Skyline/held/20260630_libdecoy_baseid_fix`; the work branch is reset to the
pre-fix (matches-Mike) state. Plan: (1) commit the FDR-neutral reproduction
tooling; (2) confirm C# and Rust `--fdrbench` output are byte-identical; (3)
investigate why reconciling library decoys over-includes false discoveries
before proposing any FDR-affecting change. Loop Mike in -- his current Rust
would now show ~1.46%, not his 0.98% screenshot.

### 2026-06-30 (session 2, end) -- Night-session handoff: FDRBench pass-1/pass-2 assessment

**Reframe (Brendan):** matching this *late-breaking, possibly-incorrect* Rust is
NOT a correctness proof. FDRBench entrapment FDP is the **independent
correctness oracle** and wins when it disagrees with cross-impl parity. Today's
data already shows the base_id fix reaches Rust parity but *degrades* entrapment
FDR -- so it stays HELD (`Skyline/held/20260630_libdecoy_baseid_fix`); the work
branch/tree is the pre-fix "matches-Mike" state; only FDR-neutral tooling was
committed (ai `9f51eed`).

**Next session = `/night-session` autonomous work.** Full protocol +
implementation detail + run matrix + plotting spec + gotchas are in the handoff:

**Next session handoff**: read
`ai/.tmp/handoff-20260630-fdrbench-assessment.md` and follow its Session Start
Protocol before doing anything.

Mission summary (see handoff for detail):
1. **New CLI capability**: emit `--fdrbench` at **pass-1** (pre-compaction
   first-pass pool + pass-1 q, mirroring Rust `write_fdrbench_peptide_input`)
   OR **pass-2** (current post-compaction survivors + final q). Suggested
   `--fdrbench-pass <1|2>`.
2. **Decoy-free libraries**: strip `decoy_`-prefixed ProteinID rows from the
   entrapment library → target+entrapment, for Osprey-generated-decoy runs.
3. **Run 4 conditions x 2 datasets = 8**: {library-supplied vs Osprey-generated
   decoys} x {pass-1 vs pass-2}, on Stellar + Astral (3-file).
4. **FDRBench + calibration (q-q) plots** zoomed to q in [0, 0.02] (deviations
   below 1% are the point; 0->1.0 hides them). combined + paired FDP vs Osprey
   q, y=x = perfect.
5. **Test the hypothesis**: library-supplied decoys should out-calibrate
   Osprey-generated decoys per FDRBench (Mike's May motivation). Report all 8
   cells honestly; judge any code change on the entrapment oracle, not parity.

### 2026-06-30 (session 3, night) -- pass-1 `--fdrbench` CLI landed; 8-cell matrix running

Autonomous `/night-session`. Executed the handoff mission.

**Implementation task 1 DONE + committed (`dc05539eb7`):** new `--fdrbench-pass
<1|2>` CLI. Pass 2 (default) = the existing post-compaction second-pass reported
set (MergeNodeTask). Pass 1 = the full pre-compaction first-pass pool emitted from
`FirstJoinTask` right after first-pass protein FDR / before compaction, mirroring
Rust `write_fdrbench_peptide_input`. The C# pipeline point was located by reading
the Rust call site (pipeline.rs ~4629, after `persist_fdr_scores`, before the
`first_pass_base_ids` compaction) and matching the C# analogue; the existing
`FdrBenchInputWriter` is reused unchanged (its `EffectiveExperimentQvalue` fields
hold first-pass values at that point -- confirmed `PercolatorEngine`/`PercolatorFdr`
populate experiment q at first pass). Files: `OspreyConfig` (`FdrBenchPass=2`),
`OspreyCommandArgs` (+ arg, `ParseFdrBenchPass`, help, validation, arg test),
`FirstJoinTask` (`WriteFdrBenchPass1IfRequested`), `MergeNodeTask` (pass-2 guard),
regenerated `CommandLine.html`. Gates: Debug build + 442 tests + zero-warning
inspection GREEN. `FdrBenchPass` is deliberately NOT in `SearchIdentity` (fdrbench
is a terminal output, not a scoring parameter -- parquet reuse unaffected).

**Pass-1 wiring VERIFIED byte-equal to Rust HEAD** (the strongest cross-check):
C# pass-1 on Stellar 3-file library-decoy = 493,101 rows, identical key set to
`_fdrbench_rust/rust_fdrbench.tsv` (0 keys unique either side), max|dq|=0.0,
max|dscore|=1e-10 (cosmetic float-format slip, below 1e-9). This holds even though
the Rust ref is post-`0abe0ff` and the C# branch is pre-fix: pass-1 is
pre-compaction / pre-reconciliation, so the base_id reconciliation fix cannot
affect it. Same run's blib wrote 28,542 spectra (the pre-fix "matches-Mike"
state), confirming the branch is unchanged.

**Implementation task 2 DONE:** decoy-free libraries built by stripping
`decoy_`/`rev_` ProteinID-prefixed rows (streaming awk; `ai/.tmp/strip-decoys.sh`).
Stellar 9,215,671 kept rows (= exact non-decoy count), Astral 47,927,450. Staged at
`D:\test\osprey-runs\{stellar,astral}-gendecoy\` with hardlinked mzML.

**8-cell matrix RUNNING** (`ai/.tmp/drive-all.sh`, background): {libdecoy,gendecoy}
x {pass1,pass2} x {Stellar,Astral}, each a full Osprey run + FDRBench (precursor
level, `-score score:1`, `_p_target` entrapment). Stellar cells ~4.5min each,
Astral ~40min each. Cell 1 (stellar libdecoy pass1) already done + verified.
Plotting/metrics: `ai/.tmp/plot-calibration.py` -> 2 figures (zoom q,FDP in [0,2%])
+ `fdrbench_metrics.csv`. Deliverable table + hypothesis assessment pending matrix
completion.

Helper scripts (all in `ai/.tmp/`, gitignored): `run-cell.sh`, `run-fdrbench.sh`,
`drive-all.sh`, `plot-calibration.py`, `strip-decoys.sh`.

**RESULTS -- all 8 cells done (02:23 PDT), no failures. Combined FDP @ Osprey q=1%:**

| dataset | decoy source | pass | disc@1%q | comb FDP@1%q | disc@1% true FDP |
|---------|-------------|------|----------|--------------|-------------------|
| Stellar | library-supplied | 2 | 28517 | **0.82%** | 30503 |
| Stellar | library-supplied | 1 | 27154 | 2.03% | 24633 |
| Stellar | Osprey-generated | 2 | 51975 | **16.05%** | 16126 |
| Stellar | Osprey-generated | 1 | 37872 | 11.73% | 24167 |
| Astral  | library-supplied | 2 | 99714 | **1.32%** | 84618 |
| Astral  | library-supplied | 1 | 82979 | 1.89% | 71529 |
| Astral  | Osprey-generated | 2 | 149150 | **12.19%** | 63860 |
| Astral  | Osprey-generated | 1 | 111361 | 8.15% | 75260 |

**HYPOTHESIS CONFIRMED on both datasets.** Library-supplied (Carafe) decoys are
near-calibrated at the reported pass-2 level (Stellar 0.82% below the line, Astral
1.32% just above); Osprey-generated reverse decoys are severely anti-conservative
(16.05% / 12.19% true FDP at a claimed 1%). At equal 1% TRUE FDP, library decoys
yield more real IDs (Stellar 30503 vs 16126 ~1.9x; Astral 84618 vs 63860 ~1.3x).
Pass diagnostic: library decoys tighten p1->p2, generated decoys degrade p1->p2.
Stellar libdecoy pass2 = 0.82% reproduces the pre-fix anchor exactly (pipeline
validated). Full write-up + figures: `ai/.tmp/fdrbench-assessment-report.md`,
`calibration_{stellar,astral}.png`, `fdrbench_metrics.csv`.

**Decisions this settles:** (1) base_id reconciliation fix stays HELD -- pre-fix is
well-calibrated (0.82%), matching Rust HEAD degrades it to 1.46%; do not ship to
match Rust. (2) Product guidance for Mike: on entrapment libraries, prefer
library-supplied decoys; generated reverse decoys badly under-estimate FDR. No new
code change warranted by the oracle. Caveats: precursor level only; entrapment-oracle
assumptions (truly-absent entrapment, 1:1 ratio, FDRBench estimator); the separate
Astral cross-impl divergence is out of scope.

### 2026-07-03 (deep FDR-calibration investigation, Brendan pairing) -- ROOT CAUSE: reversed decoys are anti-conservative
Long interactive session dissecting WHY FDRBench `combined` FDP sits ~2x above Osprey's
q on Stellar libdecoy pass-1. **Conclusion (Brendan, well-supported): Osprey's decoy FDR
is genuinely ANTI-CONSERVATIVE on library-supplied (Carafe reversed/shuffled) decoys --
NOT a plotting/estimator artifact.** Earlier "combined is just the estimator doubling,
Osprey ~right" framing was WRONG.

KEY FACTS (all on Stellar libdecoy, pass-1 pre-compaction pool; DB is balanced 1:1:1:1
target:decoy:p_target:p_decoy, 218871 each):
- `combined_fdp = 2 x lower_bound_fdp` EXACTLY (formula). At Osprey q=0.01: lower_bound
  1.01%, combined 2.03%, paired 1.79%. FDRBench's own `lower_bound_fdp` column = the raw
  entrapment fraction n_P/(n_T+n_P); it was never plotted in the earlier post-PR4347 q-q
  graphs (only combined+paired), which is why the 2x looked like inflation.
- ROOT CAUSE via per-pair decoy-win fraction (`ai/.tmp/OspreyFDR/winfrac.py`, from the
  Stage-5 percolator dump): **entrapment-vs-its-p_decoy = fair ~50/50 at every score band;
  real-target-vs-its-decoy = decoy wins far less (0.7% at winner>=0).** Much of that is
  true positives, but the entrapment 50/50 is the tell: real peptides beat their
  reversed/shuffled decoys (reversal destroys peptide-likeness), so FALSE reals also beat
  their decoys > 50/50 -> Osprey's decoys UNDER-count the false reals -> anti-conservative.
  A PAIRED effect, invisible in the marginal density (which shows decoy==entrapment==target
  null-bulk overlapping). This is Mike's decoy-GENERATION quality issue, not an FDR-code bug.
- `lower_bound` is an ASSUMPTION-FREE hard floor (entrapment are known-false). In the boost
  experiment (below) Osprey-q drops BELOW lower_bound -> provable anti-conservatism, no
  exchangeability argument needed ("+1 entrapment < +1 FP").
- NO Osprey code fix brings combined->y=x; fix is better decoys OR decoy-independent
  calibration (pi0/mixture, PeptideProphet-style -- Nesvizhskii's approach would catch this
  and is immune to reversed-decoy bias). Product read: on entrapment libraries trust the
  entrapment/combined (or lower_bound floor), not the decoy q, on this data.

DIAGNOSTICS BUILT (on branch, Release+Debug green, zero-warning inspection):
- **`OSPREY_BOOST_TARGET_DISCRIMINANT=c`** (NEW, committed-worthy): adds c to the first-pass
  SVM discriminant of REAL targets only (non-decoy, non-entrapment via `_p_target` protein),
  before FDR q-comp; entrapment+decoys untouched. 6 edits: OspreyEnvironment (env+
  ParseDoubleOrZero), FdrEntry.IsEntrapment, PercolatorEntry.IsEntrapment,
  PercolatorEntryBuilder copy, FirstJoinTask.TagEntrapmentForBoost (library lookup),
  PercolatorFdr boost in ScorePopulationAndComputeFdr. Default-off. VALIDATED: c=0
  reproduces the real baseline (27154 disc, 2.03%) exactly -> faithful. c=1/2/3: disc@q=0.01
  27154->63137 while combined stays ~2%, lower_bound rises 1.01%->1.13% (crosses above y=x).
- `Run-FdrBench.ps1` (committed, ai/scripts/Osprey) + ai/.tmp/OspreyFDR/ python plotters:
  density-plot.py (4-class), plot-boost.py, winfrac.py, qq-with-lowerbound.py, whatif-*.py.
- Faithful Osprey q + FDRBench FDP requires running THROUGH Osprey (the boost hook); every
  from-scratch competition reconstruction from the dump MISSED (base_id vs precursor dedup).

ARTIFACTS: /d/test/osprey-runs/_boost/boost_{0..3}/ (fdp.csv), _density/stellar_{lib,gen}decoy/
(cs_stage5_percolator.tsv dumps), _gendecoy_repro/. Density PNGs + boost PNG in
ai/.tmp/OspreyFDR/density/. Diagnostic-development notes NOT yet written up (TODO).

NEXT EXPERIMENT (Brendan, queued): all-null control -- remove real targets+decoys, split the
entrapment 1/2 "target" 1/2 "entrapment" (all false, generated, symmetric with decoys), run
FDRBench. Prediction (agreed): combined ON y=x, lower_bound at y=x/2, Osprey-q == combined
-> confirms combined is correct when the null is fair and the real-case 2x is the
reversed-decoy asymmetry. Heads-up: no true positives -> q collapses ~1.0 (a point at
(1,1)/(1,0.5), not a spanning line unless some real true targets are salted in).

REMAINING TODOs from this session: (1) write up the reversed-decoy-bias finding +
lower_bound-as-hard-floor argument as a durable note; (2) commit the boost diagnostic +
winfrac + Run-FdrBench (currently on libdecoy branch, uncommitted); (3) run the all-null
control; (4) regenerate post-PR4347 q-q plots with lower_bound + Osprey-q reference lines.
Session ran below 10% context; continuing past auto-compact.

PASS-1 vs PASS-2 RESOLUTION (Mike's pass-2 plot, same Stellar libdecoy no-protein-fdr):
Mike's pass-2 = combined 0.90% (ON y=x), lower_bound 0.45% (~y=x/2), 26898 disc -> CALIBRATED.
Ours pass-1 = combined 2.03%, lower_bound 1.01%. combined=2xlower_bound in BOTH; the ONLY
difference is the entrapment fraction halving (1.01%->0.45%), which slides combined from
2x-above to on y=x. WHY pass-2 has half the entrapment: COMPACTION + RECONCILIATION. The
reversed-decoy bias admits false targets (entrapment + false-real) on lucky SINGLE-RUN peak
matches in pass 1; pass-2 reconciliation demands CROSS-RUN consensus, which demotes those
lucky peaks (false peptides have no consistent cross-run signal) -> ~275 entrapment drop to
~121. So reconciliation is a false-positive filter that removes exactly the reversed-decoy
errors -> pass-2 calibrated. CONSEQUENCE: Osprey's SHIPPING output (pass 2) is well-calibrated
(Mike right); the anti-conservatism is a PASS-1 property. But pass-1 q drives COMPACTION, so it
admits extra false-reals into the compacted pool (reconciliation cleans them) -- and this is
exactly why --protein-fdr, which RECALIBRATES on the compacted/decoy-depleted pool, goes
anti-conservative. VERIFY NEXT: confirm 275->121 is reconciliation demoting lucky single-run
peaks; re-run winfrac on the pass-2 pool (real-target decoy-win should climb back toward the
entrapment's fair 50/50 once lucky matches are gone).
