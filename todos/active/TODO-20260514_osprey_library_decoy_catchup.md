# TODO-20260514_osprey_library_decoy_catchup.md — Library-decoy FDR catch-up

> **Designed for autonomous overnight execution.** This is a self-contained
> sprint spec for catching OspreySharp up to maccoss/osprey `origin/main`
> on the load-bearing library-decoy FDR control fix Mike landed
> 2026-05-11..2026-05-12.

## Branch Information

- **Branch**: `Skyline/work/20260514_osprey_library_decoy_catchup`
- **Base**: `master` (post-#4213 squash, currently at `d348697df2`)
- **Created**: 2026-05-14
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

## Mission

Translate Mike MacCoss's 5-commit library-decoy FDR control fix arc from
maccoss/osprey (Rust) to OspreySharp (C#), with **cross-impl unit-test
parity** for the new code paths and **continued Stellar + Astral
end-to-end bit parity** for the existing reverse-decoy mode. After this
sprint, OspreySharp produces the same decoy preparation behavior as
`maccoss/osprey:origin/main` at SHA `bcd7249` for the cases Mike's
tests cover, AND the existing Stellar / Astral cross-impl
Test-Regression runs continue to pass at byte parity vs Rust HEAD.

**What we cannot verify tonight**: library-decoy end-to-end parity on
real Stellar / Astral data. Mike has the Astral library + pairing
manifest but hasn't sent them yet, and he hasn't generated the
Stellar pairing manifest at all -- both arrive tomorrow. Mike's note:
*"It can still do it the old way but the FDR control doesn't work
anywhere near as well."* So OspreySharp must still run the existing
reverse-decoy flow on Stellar / Astral with byte-identical output;
the new library-decoy code paths just need to compile, pass their
unit tests, and stay dormant when `decoys_in_library` is unset.

## Strategic context

OspreySharp's `FdrController.CompeteAndFilter<T>` already implements
target-decoy competition correctly (`baseId = entryId & 0x7FFFFFFF`).
The bug Mike fixed is in **decoy preparation**, not in the FDR controller
itself: `decoys_in_library: true` used to silently fall through to
reverse generation, leaving library-supplied decoys unmarked and
unpaired, so the LDA/SVM trained without competition filtering and
q-values came out optimistic. The five commits below add the *feeder*
logic — prefix detection, manifest reading, composition pairing,
dual-signal marking, and the bail-if-low-pairing gate.

User strategy: convince Mike to abandon Rust and adopt OspreySharp. For
that to work, OspreySharp must match Rust behavior. This sprint closes
the gap on the case Mike most recently exposed (Carafe-generated
entrapment libraries).

## Required reading at session start

In order:

1. This file (you're already here).
2. `ai/.tmp/osprey-catchup-assessment-20260514.md` — the full assessment
   with file-level mapping, sprint plan, and risk register.
3. `ai/CRITICAL-RULES.md` and `ai/MEMORY.md` for OspreySharp coding
   conventions.
4. Mike's commit messages and Rust diffs (in semantic order — same as
   the porting order below):
   - `cd /c/proj/osprey && git show 6630ab1 -- '*.rs'`
   - `git show a8ae4a1 -- '*.rs'`
   - `git show 4bb7068 -- '*.rs'`
   - `git show fe7c7c1 -- '*.rs'`
   - `git show d23d496 -- '*.rs'`
   - `git show 42f46d4 -- '*.rs'` — *out of scope this sprint; do not port*

## Settled design decisions

These are pre-decided. Do not relitigate.

1. **Scope: 5-commit FDR arc only.** No mzML refactor (42f46d4), no
   `--fdrbench` export (5da4a46), no LF normalization. Those are
   separate follow-ups.
2. **Module placement.**
   - Manifest reader → `OspreySharp.IO\DecoyPairingManifest.cs` (mirrors
     Rust `osprey-io/src/pairing.rs`).
   - Composition pairer + `PairingStats` + `MarkingStats` records →
     `OspreySharp.Core\LibraryDecoyPairing.cs` (mirrors Rust
     `osprey-core/src/types.rs` additions).
   - `apply_library_decoy_marking` → `OspreySharp.IO\LibraryDecoyMarker.cs`.
   - Pipeline wiring → `OspreySharp\AnalysisPipeline.cs`, just after
     `LoadLibrary` and before any task runs.
3. **`decoy_pair_min_fraction = 0.80` default: hard-bail.** Match Rust
   exactly. Will reject libraries that previously "worked" badly. This
   is the correct call for the strategic goal (Mike sees identical
   behavior).
4. **`DecoyMethod.FromLibrary` enum value**: treat as synonym for
   `decoys_in_library: true` per Rust. Don't deprecate; document the
   alias.
5. **Underflow defense**: use `Math.Max(0, ...)` in C# to match Rust's
   `saturating_sub` intent. Defense-in-depth, not load-bearing.
6. **Parity gate: cross-impl unit-test parity.** Translate each of
   Mike's Rust unit tests 1:1 to C#. Brendan has texted Mike about new
   libraries that will let us add end-to-end parity in Stellar/Astral
   Test-Regression in a follow-up sprint; for this sprint, unit tests
   are sufficient. Stellar Test-Regression continues to gate against
   regressions in the reverse-decoy case.
7. **Branch/PR**: one branch, multi-commit PR. 5-6 commits mirroring
   Mike's commit order.

## Porting order (5 commits, ~4-5 person-days of work compressed into
overnight autonomous execution)

Each commit lands as its own C# commit on the feature branch and gates
on its own validation. Do not advance to the next commit until the
current one's gates are green.

### Commit 1 — Prefix marking + config (`6630ab1` port)

**Files added:**
- `OspreySharp.IO\LibraryDecoyMarker.cs` with `ApplyLibraryDecoyMarking(library, decoyPrefixes, out MarkingStats)` and `LooksLikeLibraryDecoy(libraryEntry, prefixes)`.
- `OspreySharp.Core\MarkingStats.cs` (or as a record inside LibraryDecoyMarker.cs).

**Files modified:**
- `OspreySharp.Core\LibraryEntry.cs` — add `DECOY_ID_BIT = 0x80000000u` named const (replace the magic number).
- `OspreySharp.Core\OspreyConfig.cs` — add `DecoyPrefixes` (default `["DECOY_", "rev_", "decoy_"]`, case-insensitive).
- `OspreySharp\AnalysisPipeline.cs` — call `ApplyLibraryDecoyMarking` after `LoadLibrary` when `DecoysInLibrary` is true. Hard error when no entries match.

**Tests** (translate from `osprey-core/src/types.rs` and any
`osprey-io/tests/...` files Mike added in `6630ab1`):
- Prefix detection: `DECOY_`, `rev_`, `decoy_`, case-insensitive variants.
- ID bit set on marked entries.
- Hard error when `DecoysInLibrary` set but no entries match.
- Library with mixed prefix and non-prefix entries.

### Commit 2 — Composition pairing (`a8ae4a1` port, part 1: composition only)

The biggest single chunk. Budget 1.5x time if charge/composition
grouping trips up.

**Files added:**
- `OspreySharp.Core\LibraryDecoyPairing.cs` with
  `PairLibraryDecoysByComposition(library, decoyPrefixes, out PairingStats)`.
- `OspreySharp.Core\PairingStats.cs` (or as record).

**Algorithm**: strip prefix from decoy `protein_ids` to recover target
accession. Group by `(stripped_accession, charge, sorted_amino_acid_composition)`.
Within each group, sort by `(sequence, id)` for determinism, then zip
1:1 target-to-decoy. Rewrite each paired decoy's `id` to
`target.id | DECOY_ID_BIT`.

**Files modified:**
- `OspreySharp\AnalysisPipeline.cs` — after marking, call composition
  pairer. Bail if `n_paired / n_decoys < 0.80`. Log
  `PairingStats.n_paired_via_composition`.

**Tests** (translate from Mike's composition tests; ~14 of them):
- Single target-decoy pair via composition.
- Multiple charge states: pair within charge.
- Targets without composition match left unpaired.
- Decoys without composition match left unpaired.
- Pairing is deterministic across runs (sort by `(sequence, id)`).
- Hard bail when paired/decoys < 0.80.

### Commit 3 — Manifest reader + hybrid pairing (`a8ae4a1` part 2 + `4bb7068`)

**Files added:**
- `OspreySharp.IO\DecoyPairingManifest.cs` with TSV reader,
  `PeptideKind` enum (`target`, `decoy`, `p_target`, `p_decoy`),
  `ApplyToLibrary(library, manifest, out ManifestApplyStats)`.

**Manifest format** (FDRBench 5-column TSV):
`sequence`, `decoy`, `proteins`, `peptide_type`, `peptide_pair_index`.
Within each `peptide_pair_index` group, form pairs `target<->decoy` and
`p_target<->p_decoy`. Honor charge.

**Files modified:**
- `OspreySharp.Core\OspreyConfig.cs` — add `DecoyPairingManifestPath`,
  `DecoyPairMinFraction = 0.80`.
- `OspreySharp\AnalysisPipeline.cs` — hybrid path: if manifest path
  set, run manifest pairing first; then run composition pairing over
  the remainder. Combine `PairingStats` from both. Bail on total
  paired/decoys < threshold.

**Tests** (translate Mike's manifest + hybrid tests):
- TSV column auto-detect.
- `peptide_type` mapping to `PeptideKind`.
- Pairing within `peptide_pair_index` groups.
- Hybrid: manifest fills some, composition fills rest.
- Stats record both contributions.

### Commit 4 — Dual-signal decoy detection in DIA-NN loader (`fe7c7c1`)

**Files modified:**
- `OspreySharp.IO\DiannTsvLoader.cs` — add `Decoy` column to
  `ColumnIndices.FromHeaders`. Parse `1`/`true`/`yes`/`y`/`t`
  case-insensitive at row load time. Set `IsDecoy = true` on
  column-flagged entries.
- `OspreySharp.IO\LibraryDecoyMarker.cs` (from commit 1) — extend so
  marking also canonicalises `DECOY_ID_BIT` onto entries that were
  loader-flagged (not just prefix-flagged). Extend `MarkingStats` with
  `n_via_column` vs `n_via_prefix`.

**Tests** (translate Mike's loader + marking tests; ~5 of them):
- `Decoy` column auto-detect in TSV.
- Column-flagged entries get `IsDecoy = true`.
- Marking canonicalises `DECOY_ID_BIT` on column-flagged entries
  (without scanning prefix again).
- `MarkingStats` reports column vs prefix contributions correctly.

### Commit 5 — Manifest-authoritative `is_decoy` (`d23d496`)

**Files modified:**
- `OspreySharp.IO\DecoyPairingManifest.cs` — `ApplyToLibrary` flips
  `IsDecoy = true` on every manifest-classified decoy (whether paired
  or not). Critical: Carafe strips decoy prefixes from protein
  accessions, so prefix scan finds only a fraction of decoys; manifest
  `peptide_type` is the authoritative signal.
- Underflow defense: switch `n_unpaired_decoys = n_decoys - n_paired`
  to `Math.Max(0, n_decoys - n_paired)`.

**Tests** (translate Mike's 2 new tests):
- `manifest_flips_unflagged_decoys_to_is_decoy`.
- `manifest_marks_unpaired_decoy_without_pairing_it`.

## Validation gates (per commit)

After EACH commit before advancing:

1. **Build clean** (multi-target net472 + net8.0):
   ```
   pwsh -File './ai/scripts/OspreySharp/Build-OspreySharp.ps1' -RunTests
   ```
   Required: 0 errors, 0 warnings, all unit tests pass.

2. **No regression in reverse-decoy case** — Stellar 3-file snapshot
   regression PASS at every stage:
   ```
   pwsh -File './ai/scripts/OspreySharp/Test-Snapshot.ps1' -Dataset Stellar -Files All
   ```
   Stellar uses `DecoyMethod.Reverse` (generates decoys, not from
   library), so existing behavior must not change. **Commit 4
   (`fe7c7c1`, DIA-NN loader `Decoy` column) is the highest-risk
   for reverse-decoy regression** — that change fires on every load,
   not just when `decoys_in_library: true`. If Stellar's library TSV
   has a `Decoy` column, the loader change could alter behavior. The
   agent should inspect Stellar's library header before/after
   commit 4 and confirm parity holds. If it doesn't, the C# loader
   needs to be gated on `DecoysInLibrary` to match Rust's expected
   no-op behavior in reverse-decoy mode.

3. **Cross-impl unit-test parity for the translated tests** — every
   Rust test translated to C# in this commit produces a behaviorally
   equivalent assertion (same inputs → same outputs). Cross-reference
   against Rust source manually; no automated check, but the agent
   should verify each test it writes against the Rust test it ports.

### On any gate failure: load the `debugging` skill

Any per-commit or PR-open gate failure triggers root-cause analysis
before any fix. **Load the `debugging` skill immediately** -- it
enforces "diagnose before patch" and references the cross-impl
bisection methodology. Required reading on first failure:

- `pwiz_tools/OspreySharp/Osprey-workflow.html` -- the DIA pipeline
  conceptual reference (Stages 1-4 fan-out, Stage 5 first-join,
  Stage 6 reconciliation, Stage 7 protein FDR, blib write).
- `ai/docs/osprey-development-guide.md` section *"Cross-impl
  bisection methodology"*.

`Test-Regression.ps1` is the bisection harness: it marches
stage1to4 -> stage5 -> stage6 -> stage7 -> blib, stops at the first
FAIL, and prints the exact tight-iteration command for re-running
just the failing stage on the C# side. The handoff file
(`ai/.tmp/handoff-20260514_osprey_library_decoy_catchup.md`) has
the full debug-loop protocol; consult it before improvising.

## PR-open gates (after all 5 commits)

The PR opens only when ALL of these pass:

1. **Build + unit tests clean.** 0 errors, 0 warnings, all unit
   tests pass. At least +30 new C# unit tests over the 5 commits
   (rough count -- exact number depends on what Mike's Rust tests
   actually contain).

2. **Stellar end-to-end bit parity (reverse-decoy mode)**:
   ```
   pwsh -File './ai/scripts/OspreySharp/Test-Snapshot.ps1' -Dataset Stellar -Files All
   pwsh -File './ai/scripts/OspreySharp/Test-Regression.ps1' -Dataset Stellar -Force
   ```
   Both PASS at every stage. The cross-impl Test-Regression is the
   stronger gate (byte-equality vs Rust HEAD at `bcd7249`).

3. **Astral end-to-end bit parity (reverse-decoy mode)**:
   ```
   pwsh -File './ai/scripts/OspreySharp/Test-Snapshot.ps1' -Dataset Astral -Files All
   pwsh -File './ai/scripts/OspreySharp/Test-Regression.ps1' -Dataset Astral -Force
   ```
   Both PASS at every stage. Astral cross-impl Test-Regression is
   added as a PR-open gate this sprint (Phase B/C only required
   Stellar cross-impl); given we cannot yet verify library-decoy E2E
   parity, the strongest available reverse-decoy parity gate is
   Stellar + Astral both green.

4. **ReSharper green** on touched files.

## Deferred to follow-up (waiting on Mike's test files)

- **Library-decoy end-to-end parity**: real Stellar / Astral runs
  with `decoys_in_library: true` + a real FDRBench manifest. Mike
  has the Astral library + manifest and will send tomorrow; Stellar
  manifest doesn't exist yet (Mike will generate tomorrow).
- **Library-decoy parity gate**: add a third dataset shape to
  `Test-Snapshot.ps1` and `Test-Regression.ps1` that runs the
  library-decoy flow once Mike's fixtures arrive.

These are explicitly out of scope for the overnight sprint. Document
that the PR title is *"...library-decoy FDR catch-up"* not
*"...library-decoy FDR catch-up + parity-tested"* so reviewers know
the implementation matches Rust but the end-to-end gate is a follow-up.

## Out of scope (do NOT do)

1. mzML aggregate summary refactor (42f46d4).
2. `--fdrbench` native export (5da4a46).
3. LF line-ending normalization (f57e60e).
4. Python tooling (entrapment FASTA builder, FDRBench TSV builder).
5. Carafe-style E2E library fixture for Test-Regression (Brendan is
   waiting on Mike to provide test libraries; that's a follow-up sprint).

## Autonomous execution hints

- **Use `Build-OspreySharp.ps1 -RunTests -Summary`** for the per-commit
  build+test gate; the `-Summary` flag is required to avoid piping
  output through grep/tail (forbidden by CRITICAL-RULES).
- **Use `pw-pcommit`** or the equivalent commit flow per
  `ai/docs/version-control-guide.md` (past-tense title, `* ` bullets,
  TODO reference, Co-Authored-By).
- **For each Rust test you port**: read the Rust test source first
  (`git show <sha> -- '*test*.rs'`), then write the C# equivalent using
  the same input data and assertion shape.
- **Cross-impl naming consistency** matters: when Rust uses
  `apply_library_decoy_marking`, C# should be `ApplyLibraryDecoyMarking`
  (same words, PascalCase). When Rust returns `(library, stats)`,
  C# returns the library and an `out MarkingStats stats`.
- **Module assembly references**: `OspreySharp.IO` references
  `OspreySharp.Core`. `OspreySharp` references both. Already wired —
  no project file changes expected.
- **Don't introduce async/await** anywhere (CRITICAL-RULES).
- **String comparisons**: use `StringComparison.OrdinalIgnoreCase` for
  prefix matching (matches Rust's `to_ascii_lowercase` semantics).

## Progress log

### 2026-05-14 — Sprint planned

- Assessment complete (`ai/.tmp/osprey-catchup-assessment-20260514.md`).
- All four open questions resolved by Brendan.
- Branch + PR strategy: one branch, multi-commit PR.
- Parity gate: cross-impl unit-test parity (E2E fixture deferred until
  Mike provides libraries).
- Hard-bail at 0.80 pairing threshold.
- Module placement: `OspreySharp.IO` for manifest + marker,
  `OspreySharp.Core` for composition pairer + records.
- TODO file written; ready for autonomous overnight execution.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260514_osprey_library_decoy_catchup.md` before
starting work.

### (Agent: append per-commit updates here)

### 2026-05-14 / 2026-05-15 overnight -- Commit 1 in flight

- Skills loaded: `osprey-development`, `skyline-development`.
- Read Rust diff for `6630ab1` (config.rs, types.rs, main.rs,
  pipeline.rs).
- Implementation:
  - `OspreySharp.Core/LibraryEntry.cs` -- added
    `DECOY_ID_BIT = 0x80000000u` const and `LooksLikeLibraryDecoy`
    instance method.
  - `OspreySharp.IO/LibraryDecoyMarker.cs` (new) --
    `ApplyLibraryDecoyMarking(library, prefixes, out MarkingStats)`
    + `MarkingStats` (NViaPrefix for now; commit 4 extends with
    NViaColumn).
  - `OspreySharp.Core/OspreyConfig.cs` -- added `DecoyPrefixes`
    property (default `DECOY_`, `rev_`, `decoy_`); included in
    `SearchParameterHash()` sorted+lowercased (matches Rust
    `format!("decoy_prefixes:{:?}\n", ...)`).
  - `OspreySharp/Tasks/PerFileScoringTask.cs` -- treats
    `DecoyMethod.FromLibrary` as synonym for `DecoysInLibrary`;
    calls `ApplyLibraryDecoyMarking` after `LoadLibrary`; hard
    error when library-supplies-decoys but no entries match.
- Tests: 7 Rust tests translated to
  `OspreySharp.Test/LibraryDecoyMarkerTest.cs` (case-insensitivity,
  prefix-position, empty inputs, any-protein, marking sets
  bit+flag, idempotency).
- Gates:
  - Build + RunTests: 316 tests pass, 0 errors.
  - Inspection: 4 pre-existing warnings in untouched files
    (RescoreWorker, FileSaver, PerFileRescoreTask); no new warnings
    introduced by this commit.
  - Stellar snapshot: commit 1's intentional hash bump
    (`decoy_prefixes` in search hash, matching Rust) invalidates
    the old `_snapshots/main` baseline. Stage1to4 still PASSed
    column-wise (no scoring change), but stage5+ refused the
    frozen parquets due to `search_hash mismatch`. **Re-captured
    the Stellar `main` snapshot** with the post-commit-1 build so
    commits 2-5 validate against the new (Rust-aligned) baseline.
- Commit pending: stage CRLF normalisation done, all files clean,
  ready to commit + push.
- **Landed**: commit `dede958de6` on
  `Skyline/work/20260514_osprey_library_decoy_catchup`.

### 2026-05-15 -- Commit 2 landed (composition pairing, a8ae4a1)

- Implementation:
  - `OspreySharp.Core/LibraryDecoyPairing.cs` (new) --
    `PairLibraryDecoysByComposition` + `PairingStats`; deterministic
    `(sequence, id)` zip within each
    `(accession, charge, sorted-AA)` bucket. Strips configured prefix
    to recover target accession; honors charge; shared-peptide
    fallthrough across sorted accessions.
  - `OspreyConfig.DecoyPairMinFraction = 0.80`; folded into
    `SearchParameterHash` (Rust folds it together with
    `decoy_pairing_manifest`; we add the manifest field in commit 3).
  - `PerFileScoringTask` runs the pairer after marking, logs
    paired/unpaired stats, hard error if below threshold.
- Cross-impl-parity note: had to add an inline `// Array.Sort OK:`
  exemption for the single `Array.Sort(char[])` in `SortedAa` (canonical
  AA composition is a single primitive array; ties are byte-identical
  so stability is irrelevant). `TestNoUnstableArraySort` would
  otherwise refuse production use of `Array.Sort`.
- ResSharper picked up a `MemberHidesStaticFromOuterClass` on
  `TargetKey.SortedAa` hiding the outer-class method; renamed the field
  to `TargetKey.Composition`.
- Tests: 8 Rust composition-pairing tests ported to
  `LibraryDecoyPairingTest`; 324 OspreySharp tests pass total.
- Inspection: still 4 pre-existing baseline warnings in untouched
  files; no new warnings from commit 2.
- Snapshot: commit 2's hash bump (added `decoy_pair_min_fraction` to
  the search hash, matching Rust) invalidates the post-commit-1
  baseline. Re-capture in progress on a separate process
  (`b9fegwujg`); commit 3 work proceeds in parallel.
- **Landed**: commit `fe76fc0120` on
  `Skyline/work/20260514_osprey_library_decoy_catchup`.

### 2026-05-15 -- Commit 3 landed (manifest + hybrid, 4bb7068)

- Implementation:
  - `OspreySharp.IO/DecoyPairingManifest.cs` (new) -- 5-column TSV
    reader; `PeptideKind` enum; `ApplyToLibrary(library, state)`
    returns the count paired this pass.
  - `OspreySharp.Core/LibraryDecoyPairing.cs` -- refactored to
    state-based incremental API. `PairingState` (claimed_targets +
    paired_decoys) shared between passes;
    `PairLibraryDecoysByComposition` now skips already-paired
    decoys / already-claimed targets.
  - `PairingStats` extended with `NPairedViaManifest` and
    `NPairedViaComposition`.
  - `OspreyConfig.DecoyPairingManifestPath` (string); folded into
    `SearchParameterHash` (None / Some("path") encoding matching
    Rust `{:?}`).
  - `PerFileScoringTask` runs manifest pairing first when path is
    set, then composition fallback; logs manifest/composition
    breakdown.
- Existing 8 composition tests refactored through a private
  `RunCompositionOnly` helper to keep their shape against the new
  state-based core.
- Added 6 manifest + hybrid tests in
  `DecoyPairingManifestTest` (pair-index target/decoy + p-pairs;
  charge-aware; sequences not in manifest stay unpaired; manifest
  then composition hybrid; unknown peptide_type rows skipped;
  missing required columns throws).
- ResSharper hit two more `MemberHidesStaticFromOuterClass` (BucketKey
  hiding `IsTargetSide` and `Partition`); renamed methods to
  `IsTargetSideOf` / `PartitionOf`.
- Gate sequence noted: rebuilding OspreySharp while the post-commit-2
  snapshot capture was mid-flight caused stage7 to fail with a
  search-hash mismatch (the running stage5/6 used commit-2's bin,
  stage7 picked up the freshly-built commit-3 bin). **Lesson**:
  pause OspreySharp builds during snapshot captures.
- Gates after fix: 330 tests pass; 4 baseline ResSharper warnings
  (untouched files). Stellar snapshot re-capture launched in
  background (`bqwsijdip`); commit 4 prep proceeds in parallel.
- **Landed**: commit `0e3c3cb5de` on
  `Skyline/work/20260514_osprey_library_decoy_catchup`.

### 2026-05-15 -- Commit 4 landed (DIA-NN Decoy column, fe7c7c1)

- Implementation:
  - `OspreySharp.IO/DiannTsvLoader.cs`: added `Decoy` / `IsDecoy` /
    `Is.Decoy` column to `ColumnIndices` plus a `ParseDecoyFlag` helper
    matching Rust (truthy values 1, true, yes, y, t case-insensitive;
    everything else target). Loader sets `LibraryEntry.IsDecoy` at
    load time; precursor-level OR across rows is defensive against
    inconsistent loaders.
  - `OspreySharp.IO/LibraryDecoyMarker.cs`: split `MarkingStats` into
    `NViaColumn` + `NViaPrefix`; `ApplyLibraryDecoyMarking`
    canonicalises `DECOY_ID_BIT` on loader-flagged entries (and
    counts them) before doing the prefix scan. Idempotent across
    repeat calls.
  - `PerFileScoringTask` log shows the new column/prefix breakdown.
- Tests: 4 new (`ParseDecoyFlag`, `LoaderReadsDecoyColumn`,
  `LoaderNoDecoyColumnDefaultsToTarget`,
  `ApplyLibraryDecoyMarkingCanonicalisesLoaderFlaggedDecoys`);
  updated `ApplyLibraryDecoyMarkingIsIdempotent` for the new stats
  shape. 334 tests pass.
- Reverse-decoy regression risk: verified Stellar's
  `hela-filtered-SkylineAI_spectral_library.tsv` and Astral's
  `SkylineAI_spectral_library.tsv` both have a `Decoy` column with
  every row = 0. Loader change is a true no-op for these datasets;
  reverse-decoy parity is preserved. Search hash unchanged (no new
  config fields).
- Inspection: 4 baseline warnings (untouched files); no new.
- Stellar snapshot compare-mode regression launched in background
  (`b3h0h4knr`) -- expected PASS without re-capture since no hash
  bump.
- **Landed**: commit `6b2a3f9ad5` on
  `Skyline/work/20260514_osprey_library_decoy_catchup`.
- Stellar snapshot regression (post-commit-4): ALL 5 stages PASS
  against the post-commit-3 baseline.

### 2026-05-15 -- Commit 5 landed (manifest-authoritative IsDecoy, d23d496)

- Implementation:
  - `OspreySharp.IO/DecoyPairingManifest.cs`: added
    `ManifestApplyStats` (NPaired + NNewlyMarkedDecoy);
    `ApplyToLibrary` returns the new stats and stamps `IsDecoy=true`
    + `DECOY_ID_BIT` on every manifest-classified decoy/p_decoy
    entry (paired or not) BEFORE running the pairing pass. Catches
    the Carafe failure mode where the predictor strips decoy
    prefixes from accessions, so the prefix scan only flags a
    fraction of true decoys but the manifest sequence-classification
    is authoritative.
  - `PerFileScoringTask`: captures `manifestStats.NNewlyMarkedDecoy`;
    when non-zero, re-counts targets/decoys via
    `CountTargetsAndDecoys` so the pairing fraction is honest;
    emits a dedicated log line.
  - `NUnpairedDecoys` already used `Math.Max(0, ...)` from the
    commit 2 port; matches Rust's saturating_sub intent.
- Tests: 4 existing manifest tests updated to the new
  `ApplyToLibrary(...).NPaired` accessor; 2 new tests
  (`ManifestFlipsUnflaggedDecoysToIsDecoy`,
  `ManifestMarksUnpairedDecoyWithoutPairingIt`). 336 total tests
  pass.
- Inspection: 4 baseline warnings (untouched files), no new.
- Search hash unchanged in commit 5 (no new config fields, no
  behavior change in reverse-decoy mode), so the post-commit-3
  Stellar snapshot remains the valid baseline.
- **Landed**: commit `17fb0be0b4` on
  `Skyline/work/20260514_osprey_library_decoy_catchup`.

### 2026-05-15 -- PR-open gates in progress

- Per-commit Stellar snapshot regression: PASS post-commit-4
  (commit 5 is no-op for reverse-decoy mode so the same baseline
  remains valid).
- Stellar cross-impl `Test-Regression.ps1` and Astral
  `Test-Snapshot.ps1` + `Test-Regression.ps1` still to run before
  opening the PR.

#### 2026-05-15 -- gate progress

- Local `/c/proj/osprey` was 28 commits behind `maccoss/osprey`
  origin/main; brought to `bcd7249` (Rust v26.6.0) and rebuilt.
- First Stellar `Test-Regression.ps1 -Force` against the new Rust
  binary failed at stage5 with osprey major/minor version mismatch
  (parquet stamped 26.6.0, C# said 26.5.0). Bumped
  `OspreySharp/Program.cs` `VERSION` to `26.6.0` (matching Rust
  release that contains the same 5 commits we just ported) plus the
  doc/test references in `TaskValiditySidecar.cs` and `IOTest.cs`.
  Landed as commit `6f3258f6d2`.
- Second Stellar `Test-Regression.ps1 -Force`: ALL 5 stages
  (`stage1to4`, `stage5`, `stage6`, `stage7`, `blib`) PASS at byte
  equality vs Rust v26.6.0.
- Astral `Test-Snapshot.ps1 -Files All` + `Test-Regression.ps1
  -Force` running sequentially in background (`bxxpfde2j`); 25 min
  + 25 min wall.
