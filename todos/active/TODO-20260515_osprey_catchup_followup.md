# TODO-20260515_osprey_catchup_followup.md — Catch-up follow-up

> Follow-up arc after the merged OspreySharp library-decoy catch-up
> (PR ProteoWizard/pwiz#4214, squash 230a08a3ba) and the upstream
> Rust fix (PR maccoss/osprey#35). Scoped for one pwiz PR with two
> tracks: end-to-end gate harness preparation + porting the Rust
> commits Mike landed between the catch-up arc and v26.6.0.

## Branch Information

- **Branch**: `Skyline/work/20260515_osprey_catchup_followup`
- **Base**: `master` (post-#4214 squash, currently at `230a08a3ba`)
- **Created**: 2026-05-15
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending — one PR planned)
- **Sibling Rust PR**: [maccoss/osprey#35](https://github.com/maccoss/osprey/pull/35)

## Mission

Two tracks, both setting up for OspreySharp going primary next week:

1. **End-to-end gate harness for library-decoy mode** (item #1 from
   the post-merge plan). Mike committed to sending the Astral
   library + FDRBench pairing manifest and generating the Stellar
   manifest. The harness work prepares OspreySharp + the test
   scripts so the cross-impl Test-Regression byte-parity gate can
   run on the library-decoy flow as soon as the files arrive.
   Without this work, library-decoy mode is only reachable through
   a hand-edited YAML config.

2. **Port the Rust functional changes between the catch-up arc and
   `bcd7249`** (item #3 from the post-merge plan). The mid-May Rust
   commits Mike is most proud of -- the manifest's `proteins`
   column as the authoritative protein-ID source on Carafe
   libraries with stripped accessions, the `--fdrbench` native
   export, and the 4000-byte protein-column cap. None of these
   need to be left "Rust-only" if OspreySharp is going primary.

## Track 1 -- library-decoy harness

### Delivered

- **OspreySharp CLI flags**: `--decoys-in-library` and
  `--decoy-pairing-manifest <PATH>`. Wired into
  `OspreyConfig.DecoysInLibrary` / `DecoyPairingManifestPath`. Both
  flags match Rust osprey's semantics (`--decoys-in-library` is a
  flat boolean; `--decoy-pairing-manifest` sets a path string).
  Three new ParseArgs tests pin the contract.
- **Dataset-Config.ps1 extension**: `DecoysInLibrary` (bool) and
  `Manifest` (string|null) fields are now part of the dataset
  hashtable contract. Default values keep existing Stellar /
  Astral runs in reverse-decoy mode unchanged.
- **New dataset**: `AstralLibraryDecoy`. Uses the existing Astral
  mzML files; library / manifest paths are placeholders until Mike
  sends the final files. Running it before staging produces a
  clear "file not found" error in Run-Osprey.ps1.
- **Run-Osprey.ps1**: passes `--decoys-in-library` (and
  `--decoy-pairing-manifest <path>` when set) from the dataset
  config. Verifies the manifest path exists before invoking the
  binary.
- **Test-Snapshot.ps1 / Test-Regression.ps1 / Test-Features.ps1 /
  Run-Osprey.ps1**: `ValidateSet` parameter attributes now accept
  `AstralLibraryDecoy` in addition to `Stellar` / `Astral`.
  Diagnostic / Compare-* scripts are unchanged; they'll be updated
  when needed (not gating).

### Pending (blocked on Mike)

- Stage the actual Carafe-built library + FDRBench manifest at
  `D:\test\osprey-runs\astral-libdecoy\` (paths in
  `Dataset-Config.ps1`).
- Run `pwsh Test-Snapshot.ps1 -Dataset AstralLibraryDecoy -Files
  All -CreateSnapshot` to capture the v26.6.0 same-impl baseline.
- Run `pwsh Test-Regression.ps1 -Dataset AstralLibraryDecoy
  -Files All -Force` to verify cross-impl byte parity vs Rust
  v26.6.0 on the library-decoy code path.

## Track 2 -- Rust catch-up (Mike's mid-May functional changes)

### Delivered this session

1. **`0c3a73e` (Rust-side piece): manifest-proteins-override.**
   `DecoyPairingManifest` now reads the optional `proteins` column
   and substitutes the clean source accessions for every covered
   library entry whose stored `ProteinIds` disagree. Catches the
   Carafe failure mode where the library generator stripped decoy
   prefixes from accessions and Carafe's deduplication then
   collapsed protein-peptide linkage. `ManifestApplyStats` gains
   `NProteinsReplaced`; `PerFileScoringTask` logs the count when
   non-zero. Two cross-impl tests
   (`ManifestReplacesProteinIdsWithCleanAccessions`,
   `ManifestSkipsReplacementWhenProteinsColumnEmpty`) pin the
   contract against the Rust unit tests of the same names.
   **Landed**: commit `b1c3a81e1e`.

### Deferred to a follow-up sprint

The next two pieces fit the same "Mike's recent functional work"
bucket but each adds substantial new surface area, and the user
asked to stop at "commits done" without a second PR. Recorded
here so the next session can pick them up. Both stay in scope
for the broader OspreySharp-going-primary transition.

2. **`5da4a46`: `--fdrbench` native export.** Adds a new
   `osprey-io/src/output/fdrbench.rs` module (~404 lines) +
   `--fdrbench` / `--fdrbench-per-run` CLI flags + a protein-side
   helper in `osprey-fdr/src/protein.rs` (~47 lines) + pipeline
   wiring (~34 lines). Writes a FDRBench-compatible TSV from the
   pre-compaction first-pass FDR pool so every scored target is
   included, not just FDR-passing entries as in the blib. Carries
   the SVM discriminant as the `score` column so FDRBench can
   re-rank and count entrapment hits. Level auto-selects from
   `--fdr-level` (Both -> precursor, Protein -> picked-protein
   TSV). Decoys are excluded per FDRBench convention; entrapment
   `_p_target` sequences pass through. ~527 lines total port.

3. **`1fd7552`: cap protein column at 4000 bytes.** Small
   defensive fix in `fdrbench.rs` (~125 lines) to truncate
   oversized protein-ID lists with a marker so a Carafe library
   stamping a multi-thousand-character `ProteinID` doesn't crash
   downstream parsers. Depends on #2 being landed.

### Scope decision

User instruction was "stop when commits are done for that work,
and don't create a second pwiz PR." The two deferred pieces above
will land in a follow-up PR; the next session can resume from
this TODO without re-deriving the catch-up frame.

## Validation gates (per commit)

After each commit:

1. `pwsh -File ai/scripts/OspreySharp/Build-OspreySharp.ps1
   -RunTests -RunInspection`: 0 errors, all tests pass,
   inspection at the existing 4-baseline-warning state.
2. **Stellar reverse-decoy snapshot**: existing Stellar Test-
   Snapshot baseline (post-#4214) MUST still pass. This catches
   accidental regressions in the reverse-decoy code path.
3. **Stellar cross-impl Test-Regression**: optional but
   recommended on Track 2 commits that touch shared pipeline
   code.

## PR-open gates (after the last commit)

- Stellar `Test-Snapshot` PASS
- Stellar cross-impl `Test-Regression` PASS at every stage
- Astral cross-impl `Test-Regression` PASS at every stage
- Copilot review addressed
- `/pw-self-review` fresh-context agent review addressed
- Astral same-impl snapshot still valid (was recaptured at
  `b5c48f6309` during #4214; should not need recapture unless
  Track 2 bumps SearchParameterHash)

## Out of scope

- Library-decoy E2E run (gated on Mike's files; harness ready,
  data not staged).
- Python-side `scripts/build_entrapment_peptide_fasta.py`
  changes from `0c3a73e` / `15e3a96`. That's a Mike-side
  library-building workflow; OspreySharp consumes the output
  but doesn't replicate the FASTA writer.
- NextFlow / Linux packaging. Tracked separately at
  `ai/todos/backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md`.

## Progress log

### 2026-05-15 -- Track 1 in flight

- OspreySharp `--decoys-in-library` + `--decoy-pairing-manifest`
  flags landed. Three ParseArgs tests pin the contract. Total
  test count: 343 passing.
- Dataset-Config.ps1 extended with `DecoysInLibrary` / `Manifest`
  fields and a new `AstralLibraryDecoy` placeholder entry.
- Run-Osprey.ps1 forwards the new flags from the dataset config;
  verifies the manifest path before invoking the binary.
- Test-Snapshot.ps1 / Test-Regression.ps1 / Test-Features.ps1
  ValidateSets updated to accept `AstralLibraryDecoy`.
- Inspection clean (4 pre-existing baseline warnings, no new).
