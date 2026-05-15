# TODO-20260514_osprey_library_decoy_catchup.md — Library-decoy FDR catch-up

> **Designed for autonomous overnight execution.** This is a self-contained
> sprint spec for catching OspreySharp up to maccoss/osprey `origin/main`
> on the load-bearing library-decoy FDR control fix Mike landed
> 2026-05-11..2026-05-12.

## Branch Information

- **Branch**: `Skyline/work/20260514_osprey_library_decoy_catchup`
- **Base**: `master` (post-Phase-C; will rebase if PR #4213 merges first)
- **Created**: 2026-05-14
- **Status**: Ready to start (autonomous overnight session)
- **GitHub Issue**: (none — Brendan will create if needed)
- **PR**: (pending)

## Mission

Translate Mike MacCoss's 5-commit library-decoy FDR control fix arc from
maccoss/osprey (Rust) to OspreySharp (C#), with **cross-impl unit-test
parity** as the per-step gate. After this sprint, OspreySharp produces
the same decoy preparation behavior as `maccoss/osprey:origin/main` at
SHA `bcd7249` for the cases Mike's tests cover.

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
   library), so existing behavior must not change.

3. **Cross-impl unit-test parity for the translated tests** — every
   Rust test translated to C# in this commit produces a behaviorally
   equivalent assertion (same inputs → same outputs). Cross-reference
   against Rust source manually; no automated check, but the agent
   should verify each test it writes against the Rust test it ports.

## PR-open gates (after all 5 commits)

- All five per-commit gates pass.
- Astral 3-file snapshot regression PASS at every stage:
  ```
  pwsh -File './ai/scripts/OspreySharp/Test-Snapshot.ps1' -Dataset Astral -Files All
  ```
- Stellar cross-impl Test-Regression PASS at every stage (no regression
  in the reverse-decoy case):
  ```
  pwsh -File './ai/scripts/OspreySharp/Test-Regression.ps1' -Dataset Stellar -Force
  ```
- Unit-test count: at least +30 new unit tests across the 5 commits.
- ReSharper green on touched files.

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
