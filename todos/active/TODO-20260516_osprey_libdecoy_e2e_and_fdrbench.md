# TODO-20260516_osprey_libdecoy_e2e_and_fdrbench.md -- Library-decoy E2E + `--fdrbench` port

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
