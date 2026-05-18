# TODO-20260516_osprey_libdecoy_e2e_and_fdrbench.md -- Library-decoy E2E + `--fdrbench` port

> Follow-up sprint to PR #4215. Two tracks: (1) close the library-
> decoy gap by running the cross-impl byte-parity gate on Mike's
> Carafe-built Astral library + FDRBench manifest; (2) port the
> `--fdrbench` native-export Rust pieces that were intentionally
> deferred from #4215 to keep that PR a "quick" merge.

## Branch Information

- **Branch**: `Skyline/work/20260516_osprey_libdecoy_e2e_and_fdrbench`
  (to be created)
- **Base**: `master` (post-#4215 squash at `bb1992e248`)
- **Created**: 2026-05-16
- **Status**: Not Started
- **GitHub Issue**: (none)
- **PR**: (planned -- one PR if scope holds; split if Track 2 grows)
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

OspreySharp going primary next week needs the library-decoy code
path verified at byte-parity against Rust on real Carafe-built data
(Track 1), and Mike's most recent functional work in osprey-io's
FDRBench TSV writer ported so the C# port doesn't fall behind on
the artifact downstream FDRBench GUI consumes (Track 2). After this
sprint, OspreySharp produces the same library-decoy and FDRBench-
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
   `ai/scripts/OspreySharp/Dataset-Config.ps1`:
   - `Library`: currently
     `SkylineAI_entrapment_carafe_spectral_library.tsv`. Replace
     with Mike's actual filename.
   - `Manifest`: currently
     `SkylineAI_entrapment_carafe_pairing_manifest_pep.txt`.
     Same -- replace with Mike's actual filename. (FDRBench
     calls these `*_pep.txt` by convention; check.)
3. **Capture the same-impl baseline** at v26.6.0:
   ```
   pwsh -File ai/scripts/OspreySharp/Test-Snapshot.ps1 \
     -Dataset AstralLibraryDecoy -Files All -CreateSnapshot
   ```
   Watch for the new "Library-decoy mode" log lines that PR
   #4215 added; confirm `NProteinsReplaced > 0` if the Carafe
   library has the per-peptide-suffix `ProteinID` pattern. If
   the baseline doesn't capture cleanly, fix forward before
   running the cross-impl gate.
4. **Run cross-impl Test-Regression** vs Rust v26.6.0:
   ```
   pwsh -File ai/scripts/OspreySharp/Test-Regression.ps1 \
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

## Track 2 -- `--fdrbench` native export port

The deferred Track 2 from PR #4215. Two upstream Rust commits to
port, in dependency order. Mike's email is expected to include the
canonical CLI invocation example, which clarifies the exact output
shape we need to match.

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
- `OspreySharp.Core/OspreyConfig.cs`: add `FdrbenchOutputPath`
  and `FdrbenchPerRun` properties. Fold into
  `SearchParameterHash` matching Rust formatting (path through
  `EscapeForRustDebug`, bool as `b()`).
- `OspreySharp.IO/FdrbenchWriter.cs` (NEW): the TSV writer.
  Mirror Rust's column set exactly; use the patched
  `ParquetNet.dll` overlay convention if Parquet I/O is
  involved (it isn't here -- TSV-only).
- `OspreySharp.FDR/ProteinFdr.cs`: the picked-protein
  helper.
- `OspreySharp/Program.cs`: `--fdrbench <PATH>` and
  `--fdrbench-per-run` CLI flags (same `internal static
  ParseArgs` exposure as #4215 used for the library-decoy
  flags, with strict path validation).
- `OspreySharp/Tasks/PerFileScoringTask.cs` or `MergeNodeTask.cs`:
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

## Track 3 -- Upstream sync follow-ups

Hold for the maccoss/osprey upstream PRs to merge:

1. **`maccoss/osprey#35`** (defer "no library decoys" until
   after manifest pass). Once merged:
   - Update local osprey to the new HEAD (`git pull`).
   - Port the deferral back to OspreySharp at
     `PerFileScoringTask.cs:308`: move the `NDecoys == 0`
     bail to AFTER the manifest pass; recount decoys via the
     `CountTargetsAndDecoys` helper.
   - Remove the `TODO(brendanmaclean,maccoss):` comment at
     the bail site.
   - Add a regression test: a Carafe-shaped library with zero
     prefix-flagged decoys + a manifest that classifies some
     entries as `decoy` should now succeed instead of erroring.

## Validation gates (per commit)

1. **Build + tests**: `pwsh -File
   ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests
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

- The OspreySharp NextFlow / Linux packaging work tracked at
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
