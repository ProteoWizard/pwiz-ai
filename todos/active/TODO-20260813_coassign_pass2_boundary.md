# Carafe per-peptide pseudo-protein accessions broke protein-compact (from #4573)

## Branch Information
- **Branch**: `Skyline/work/20260813_coassign_pass2_boundary`
- **Base**: `master` (at `8d0a2aa6cf`, the #4558 merge)
- **Created**: 2026-08-13
- **Status**: In Progress - gate verify running
- **GitHub Issue**: [#4573](https://github.com/ProteoWizard/pwiz/issues/4573) - to be closed as
  NOT a product defect; the panel was right and the input was wrong
- **Module**: `osprey`
- **PR**: (pending)

Reporter is Brendan (project developer) - no credit line per version-control-guide "Crediting
Reporters and Requesters".

## What this branch actually does

**It does NOT change the pass-2 acceptance boundary.** That was the plan; the investigation
killed it. What it ships instead:

1. `CarafeProteinIdNormalizer` (new, `Osprey.IO`) - detects Carafe's per-peptide `_pepNNNNN`
   pseudo-protein accessions in a loaded spectral library, **warns**, and strips them. Wired into
   `LibraryLoader` on BOTH the fresh-parse path (before dedup) and the cache-load path.
2. A repurposed regression test that locks in the cutoff-vs-crossing **divergence as a detector**
   rather than asserting it away.

## The original theory, and why it was wrong

#4573 said the pass-2 co-assignment panel inherits its acceptance boundary from pass 1: the
cutoff was bit-identical to pass 1's `0.2106` while the panel's own FDR crossing said `-1.9960`,
so the decoy row read 10 where the crossing said 325 against 32,549 non-decoys (= 1.0%).

That was all real, and all downstream of a **test-harness bug**. The gate builds
StellarGenDecoyEntrap by stripping decoys out of the StellarLibDecoy library, and that library's
`ProteinID` column carries a per-peptide pseudo-accession
(`sp|O95139_pep00019|NDUB6_HUMAN`). Every peptide therefore became its own protein, so
`protein-compact`'s stratum - proteins with >=2 DETECTED peptides - could not populate:

| | broken | fixed |
|---|---|---|
| proteins with >=2 detected peptides | **7** | **4,022** |
| stratum | **23 base_ids** | **167,660 base_ids** |
| reported protein groups | 26,710 | 4,728 |
| pass2 coAssign cutoff | 0.2106236326 (= pass 1) | 0.0001790772 |
| pass2 coAssign crossing | -1.9959828989 | -0.0378617924 |
| **cutoff-crossing gap** | **2.21** | **0.038** |
| pass2 decoy row vs crossing | 10 vs 325 | 292 vs 309 |
| pass2 experiment accepted | 23,115 | 29,956 |
| pass2 combined FDP @1% q | 1.334% | 1.110% |

With a 23-base_id stratum essentially nothing recompeted, so `protein-compact` silently degraded
into `transfer` at experiment scope - every reported q-value was the carried-over pass-1 value.
The "pass-1 bar on a pass-2 pool" the issue described was the panel **correctly reporting that**.
Fixing the library both increased discoveries (23,115 -> 29,956) and improved calibration
(1.334% -> 1.110% FDP at nominal 1%).

## Why the boundary change was reverted

It is a no-op when the run is sound and harmful when it is not. The `cutoff` vs `fdrCrossing`
divergence is a **working misconfiguration detector**: the two are the same quantity whenever a
pool's q-values are its own, so a gap means the q-values came from a different population.
Adopting the crossing would have replaced that evidence with a bar drawn from a pool that never
recompeted. #4558's diagnostic did its job; we nearly fixed the messenger.

**The residual 0.038 gap is real and is Brendan's two-q-systems artifact** (pass 1, with one q
system, sits at 0.0027). Under `protein-compact` in-stratum entries carry recomputed q while
off-stratum entries keep pass-1 q, so the accepted set is assembled from two different score
orderings and its minimum aggregate cannot be exactly the pool's own crossing. Brendan's framing:
entrapment is structurally off-stratum, so it is excluded from the depleted-null q boost that
in-stratum peptides receive, which breaks the monotonic ordering of q with composite score - and
the entrapment used to MEASURE FDP is sitting in the disadvantaged system.

**Deliberately not addressed here** (needs Mike MacCoss): forcing off-stratum peptides to
participate in pass-2 q estimation would give one q system for all peptides, but would likely
admit more entrapment at 1% and make `protein-compact` even more anti-conservative. Mike's likely
position is that advantaging peptides of multi-detection proteins is the entire point, exactly as
`mean-best-N` advantages peptides detected in multiple runs; both are known to raise confidence,
and the open question is how that should be expressed statistically without resorting to hard
cutoffs (no single-hit proteins; must appear in N runs). Improve diagnostics, do not change the
algorithm.

## Library survey - which libraries carry the suffix

Every `carafe_spectral_library.tsv`; both `SkylineAI_spectral_library.tsv` are clean.

| library | ProteinID | status |
|---|---|---|
| gate `stellar` (plain) | `sp\|Q9NP61\|ARFG3_HUMAN` | clean |
| gate `astral` | `sp\|Q04726\|TLE3_HUMAN` | clean |
| gate `stellar-libdecoy` | `sp\|Q8IV48_pep00016\|ERI1_HUMAN` | **suffixed** |
| all 15 SEA-AD `lib/*` variants | `sp\|O95139_pep00019\|NDUB6_HUMAN` | **suffixed** |

`sea-ad/target+decoy` has no entrapment at all and is still suffixed, so this comes from the
**Carafe library build**, not from entrapment or decoy generation. On the full stellar-libdecoy
file, 359,656 distinct target accessions collapse to 23,874 real ones.

**Corrupted on disk is not the same as broken in use.** A pairing manifest carries clean
accessions in its `proteins` column and `DecoyPairingManifest.ApplyToLibrary` overwrites the
library with them - but its **sole caller is `TryPairSuppliedDecoys`**, reached only when the
library SUPPLIES its decoys, and that method also hard-fails when the library holds no decoys. So
before this branch a Carafe library searched with GENERATED decoys had no route to clean
accessions at all. Observed:

| run | decoys | manifest applied | groups with `_pep` |
|---|---|---|---|
| SEA-AD 82-file | in library | yes | 73 / 6,218 |
| StellarLibDecoy | in library | yes | 22 / 4,495 |
| StellarGenDecoyEntrap | generated | **no** | **26,710 / 26,711** |

`PerFileScoringTask.cs:951-961` already documented this exact failure for the HPC-chain path.
Brendan's call: since Osprey and Carafe are expected to be tightly integrated, Osprey should be
fault-tolerant here rather than depending on a manifest - hence the load-time normalizer.

## Verification

- **Acceptance criterion met**: with the harness left untouched, the product-side normalizer
  reproduces the goldens captured by pre-stripping the source TSV. Gate diagnostics **PASS** and
  every content table matched; the only diff was the recorded library FILENAME
  (`nodecoy-cleanprot.tsv` vs `nodecoy.tsv`) from a temporary harness rename, since recaptured.
- Ordering matters and is asserted in the code comment: the strip must run **before**
  `LibraryDeduplicator`, which unions each (modified sequence, charge) group's accessions through
  a `SortedSet`. Stripping after dedup would leave duplicate identical accessions in that union
  and would NOT reproduce the goldens.
- 580 C# tests pass (578 + 2 new normalizer tests), ReSharper 0 warnings both TFMs.
- Cross-impl **PASS at 1e-9** (Stellar 3-file): precursors 29,300 both sides, Stage 7 + blib +
  FDR sidecars clean. Run before the golden capture, per the #4558 handoff.

## Regression Test

- **Test names**: `TestCarafeProteinIdNormalizer` and
  `TestCarafeProteinIdNormalizerLeavesCleanLibraries` (`Osprey.Test/IOTest.cs`);
  `TestCoAssignmentReportsInheritedQDivergence` (`ModelDiagnosticsDataTest.cs`)
- **Test project**: Osprey.Test
- **Fails on master**: the normalizer tests cannot exist on master (new type). The detector test
  was **proven discriminating by mutation**: re-applying the reverted adopt-the-crossing behaviour
  fails it with `Expected ... <5> and actual value <0.5>. the acceptance cutoff stopped being the
  minimum aggregate over the q-accepted set`; removing the mutation returns 578/578.
- **Passes on fix**: yes, 580/580.

The detector test has two arms: inherited q MUST diverge and the class table must stay on the
cutoff; q computed over the pool being counted MUST put cutoff and crossing at the same score.

## Traps hit this session - read before repeating any of this

* **`regression.ps1` has NO `-Exe` parameter.** `pwsh -File` silently discards unbound arguments,
  so every `-Exe <snapshot>` run used the BUILD-TREE exe instead. This invalidated an A/B whose
  two arms turned out to be the same binary, and produced a wrong "cutoff and crossing are
  identical" claim that had to be retracted. The `-Exe` idiom in the #4558 handoff belongs to a
  different script. To A/B, snapshot and run the exe directly, or verify the DLL hash.
* **`-CreateGolden` rewrites `protein_fdr.tsv` with LF against the repo's CRLF**, so `git status`
  reports all four as modified with ZERO content change. Check `git diff --numstat`, not
  `git status`, before believing a golden moved.
* **Rust osprey needs `C:\vcpkg\installed\x64-windows\bin` on PATH to RUN**; without it
  cross-impl dies with a bare `-1073741515` naming no DLL. Also pass
  `-TestBaseDir 'D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML-v2'`.
* **Sampling a 12 GB library at a few offsets cannot prove a negative.** A "zero pseudo-proteins
  group 2+ peptides" result was an artifact of narrow sampling windows; the run's own
  `protein_groups.tsv` settled it in one grep.
* `cd /c/proj && pwsh -File './pwiz_tools/...'` breaks the relative path - CLAUDE.md forbids the
  `cd &&` form for exactly this reason. Invoke `ai/` scripts by absolute path.

## Follow-ups NOT done here (ask before filing)

* **Stratum-size guard**: warn when protein-compact's stratum is implausibly small relative to
  detected peptides. Would have caught this in seconds and catches a badly-annotated user library.
* **Two-q-systems diagnostic**: surface the in-stratum/off-stratum split and the q-vs-score
  monotonicity break. Brendan is still mulling the framing - do not pre-empt it.
* **Carafe generator**: stop emitting `_pepNNNNN` at the source. The normalizer makes Osprey
  tolerant, but the libraries remain wrong on disk.
* Review findings from `/code-review max` that survived and are NOT in scope here: `--fdr-level`
  is ignored at pass-2 experiment scope by the score-gated decoy rule; `EntrapmentClass.Unknown`
  non-decoys are counted by the crossing walk but tallied into no class row (12,548 unclassified
  on stellar-libdecoy, 3 above the boundary); the crossing walk skips losing decoys but counts
  losing targets.

## Progress Log

### 2026-08-13 - the boundary change, built then reverted

Implemented `AdoptPass2Boundary`, measured it on all three gate datasets, rebaselined, cross-impl
PASS, `-Dataset All` PASS. Then `/code-review max` raised the entrapment oracle against it: the
FDR Calibration tab at the depth the new bar admitted reported 3.41% FDP (marginal band 8.46%),
against the decoy-derived 1% the bar claims by construction. Brendan pointed at the tab as the
authority, which is what exposed that the whole measurement sat on a degenerate stratum.

### 2026-08-14 - root cause, revert, and the product fix

Traced the stratum collapse to the library's per-peptide accessions and the manifest-only repair
path. Reverted the boundary change, repurposed the test as a detector, and moved the repair into
`CarafeProteinIdNormalizer` at library load per Brendan's direction, with the harness left
untouched so the gate exercises the product path. Goldens recaptured; `-Dataset All` verifying.
