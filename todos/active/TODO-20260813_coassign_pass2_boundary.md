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

1. **`CarafeProteinIdNormalizer`** (new, `Osprey.IO`) - detect Carafe's per-peptide `_pepNNNNN`
   pseudo-protein accessions at library load, WARN, and strip. Wired into `LibraryLoader` on the
   fresh-parse path (before dedup) and the cache-load path.
2. **Per-q-system pass-2 acceptance boundary** (`ModelDiagnosticsData.CoAssignment.cs`) - the
   actual #4573 fix, see below.
3. A repurposed regression test locking in the cutoff-vs-crossing divergence as a DETECTOR.

## The real #4573 fix: a decoy is admitted against ITS OWN q system's boundary

Everything above the "was wrong" section below was about the STRATUM being broken. That was a
prerequisite, not the fix. The defect Brendan kept pointing at survived it:

`SealCutoffs` took ONE `min(ExperimentAggregateScore)` over the q-accepted set and applied it to
every decoy. Under protein-compact that set spans two q systems - in-stratum entries had q AND
aggregate recomputed by the pass-2 stratified competition, off-stratum entries carry both forward
from pass 1 untouched. Decoys have no q and are admitted on SCORE, so the pooled minimum is a
pass-1 quantity for in-stratum decoys or a pass-2 quantity for off-stratum ones, depending only
on which side happened to produce the lower score.

`CoAssignmentPassBuilder` now takes the stratum (threaded `SecondPassFdrTask` -> report ->
`BuildPass2` -> `BuildCoAssignment`), computes `ExperimentCutoffInStratum` and
`ExperimentCutoffOffStratum`, and admits each decoy against the boundary matching its own base_id
membership. A null stratum (pass 1, every non-protein-compact mode) reproduces the single-boundary
behaviour exactly.

**Measured on stellar-gendecoy-entrap** (all four values now pinned in the golden):

| | value |
|---|---|
| accepted in-stratum | **29,387 (97.3%)** |
| accepted off-stratum | 806 (2.7%) |
| `cutoffInStratum` | **0.000179** |
| `cutoffOffStratum` | **0.21067** (pass 1's own bar is 0.21062) |
| pooled `cutoff` | 0.000179 |

Brendan predicted the in-stratum bar is what most peptides use; it is 97.3%. The pooled minimum
equalled the IN-stratum bar here, because the depleted null gives in-stratum the lower score - so
in-stratum decoys were already judged correctly by accident and the error was confined to
**off-stratum decoys judged on a bar ~1,000x lower than their own**. No off-stratum decoy falls in
that band on this dataset, so the decoy row is unchanged at 292: the correction is right but
INERT here. Consistency check: 29,387 + 806 = 30,193 = target 30,020 + entrapment 173.

**So the gate cannot validate this fix.** It bites where off-stratum decoys populate the band
between the two bars, and the off-stratum population grows with run count - SEA-AD is where it
would show, which is why the diagnostics-only regeneration matters.


**The FIRST attempt at the boundary - adopting the pool's own FDR crossing - was built and
reverted.** See below for why. What ships is different.

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

## Why the FIRST boundary attempt (adopt the crossing) was reverted

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

## `--task ModelDiagnostics` - regenerate the report for a COMPLETED run

Built here rather than as a follow-on branch, on Brendan's call: it is the ONLY way to validate
the pass-2 boundary rework, which is inert on every gate dataset (see above). A separate branch
would have had to fork from this one and become a second PR to test this one.

Design: runs the CANONICAL pipeline (not a one-task pipeline like SpectraCache), so Stages 1-5
rehydrate from their valid stamps; `OspreyConfig.DiagnosticsOnly` then suppresses the `.blib`,
the protein/summary reports and the 2nd-pass sidecar writes. **`Outputs` declares NOTHING** under
that flag - `PipelineContext.CanRehydrate` returns false on an empty output list, which is what
makes "regenerate on demand" actually re-run. Declaring the report instead made the task skip
itself the moment the report existed, which is exactly the case being asked to redo (observed:
first acceptance run changed 0 of 45 files). The selector implies `--model-diagnostics`.

**Acceptance test** (`ai/.tmp/mdtask-acceptance.ps1`, stellar-libdecoy, 3 files):

* `CHANGED  output.model-diagnostics.html` / **`unchanged: 44 of 45`** - blib, protein report,
  every FDR sidecar, reconciled parquet and spectra caches byte-identical.
* The regenerated page is byte-ACCURATE against the golden: target 28,664 / entrap 84 /
  decoy 279, cutoff -0.05957189983520067, cutoffInStratum identical, cutoffOffStratum
  0.23524740586743198.

Also updates `Documentation/Help/en/CommandLine.html` - `TestCommandLineHelpDocumentation`
REGENERATES that file, so the first run after adding a task fails and the second passes. That is
self-healing, not flaky, and the regenerated file must be committed.

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

## The strip moves manifest-using datasets too - by design

StellarGenDecoyEntrap was the terminal case, but it exposed a GENERAL vulnerability. Normalizing
at load also changed StellarLibDecoy (78 result + 50 diagnostic differences, pass 1 included),
which had a pairing manifest and therefore looked healthy.

Why a manifest run was never actually immune: `ApplyToLibrary` overrides only the entries the
manifest COVERS, so everything else kept its suffix and the library was a mix of clean and
pseudo accessions. Uniform stripping removes that inconsistency; the manifest still wins where
it genuinely disagrees, dropping from "nearly every entry" to **1,198 entries replaced**.

The mechanism behind the pass-1 movement is a SECOND dedup pass, easy to miss: the per-file
`Double-counting deduplication` (9,655 entries removed here). Collapsing the pseudo-proteins
makes entries that were artificially distinct merge there, which changes the searched pool and
therefore pass-1 q. Protein grouping alone would not explain a pass-1 change.

Effect is small and benign, and both passes stay under nominal:

| StellarLibDecoy | before | after |
|---|---|---|
| pass 1 accepted / combined FDP | 26,781 / 0.961% | 27,260 / 0.974% |
| pass 2 accepted / combined FDP | 29,415 / 0.609% | 28,662 / 0.590% |

**Rejected alternative**: skip the strip when a manifest is supplied, which would keep
StellarLibDecoy byte-identical. That preserves exactly the inconsistency being removed and keeps
Osprey dependent on a manifest for correct protein identity - the opposite of the hardening
Brendan asked for. Confirmed by Brendan 2026-08-14: worth the extra golden retraining.

`Stellar` and `Astral` use clean `SkylineAI_spectral_library.tsv` files, so the normalizer is a
no-op there and their goldens do not move.

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

* **Do not wait on `Get-Process -Name Osprey` to detect that the gate finished.** The gate has
  gaps between phases with no Osprey child alive; a build started in one dies on MSB3027 and -
  worse - a snapshot step then silently copies the STALE exe. Wait on the gate's own pwsh PID.
* The `.osprey.task` stamp key is `version`, not `osprey_version`; the file is JSON, so
  `(Get-Content $p -Raw | ConvertFrom-Json).version` beats a regex.

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


## OPEN AND HANDED BACK: pass-1 decoy row is 15x its definition at 82-file scale

Measured on the SEA-AD 82-file cohort by regenerating the page with `--task ModelDiagnostics`
(20m41s), current code:

```
pass1 experimentCutoff        = -0.5622904637   <- composite of the worst q-accepted entry
pass1 experimentFdrCrossing   = +0.6976485125   <- where this pool reaches 1% by its own count
pass1 fdrCrossingDecoys       = 376
pass1 fdrCrossingNonDecoys    = 37,679
pass1 experiment rows         : target 37,510  entrapment 164  decoy 5,677
pass1 run rows                : target 67,563  entrapment 4,343  decoy 8,919
```

Brendan's definitional test: the pass-1 decoy count must be `(targets + entrapment) * 0.01` =
`(37,510 + 164) * 0.01` = **377**. The panel's own CROSSING gives **376** (376/37,679 = 0.998%),
i.e. correct to one decoy. The CLASS TABLE gives **5,677**, 15x too many.

### What it is NOT

* **Not losing decoys.** Both the crossing walk and `AddRow` apply `WonItsPair`, so pair-losers
  are already excluded on both paths - the earlier fix is still in place. If losers were leaking,
  the crossing would be inflated too, and it is not.
* **Not `max(experiment-wide, per-run)`.** Per Brendan, that question was already worked through
  in the #4558 session and shown to only ever REMOVE targets from the accepted list, never add a
  worse-scoring precursor. Flooring q upward shrinks the accepted set, which would RAISE the
  minimum, not lower it.

### What it is

`experimentCutoff` IS "the composite score of the worst q-accepted entry" - the `min()` in
`SealCutoffs` is just how that worst one is found, not a second concept. It and the crossing MUST
be the same number **iff q is monotone in the composite score**: if `{q <= 0.01}` equals
`{composite >= s*}`, then the worst accepted composite IS `s*` and the walk stops there too.

They differ by **1.26 score units**, so on this pool **q is not monotone in the composite score
the panel ranks on** - at PASS 1, where there is supposed to be only one q system. Something is
accepted at q <= 1% while carrying a composite of -0.562, far below the score where the
target-decoy count puts 1%. The `min()` then faithfully reports that entry and every decoy above
it floods the row. A minimum is not a robust estimator; the crossing is rank-based and immune.

This is invisible on the 3-file gate datasets, where pass-1 cutoff and crossing agree closely
(0.2106 vs 0.2079). That is why the gate reported "perfect pass-1 calibration" honestly and this
only appears at 82-file scale.

### The measurement that would settle it

Take the pass-1 accepted set, select entries whose experiment aggregate is BELOW the crossing
(+0.698), and report their count plus where their q came from. A handful => an outlier or a
score-vintage mismatch between the value the competition ranked on and the
`ExperimentAggregateScore` the panel reads. Thousands => the accepted set genuinely is not
score-ordered and "worst accepted precursor" is unsound as a boundary at scale.

**Question for the #4558 session**: it worked through the two-q-space question and settled the
max(experiment, per-run) branch. What else did it establish about which entries can be accepted
with a composite below the pool's own 1% point at PASS 1 - and did it ever compare
`ExperimentAggregateScore` against the score the pass-1 competition actually ranked each entry
on? That pairing is the remaining suspect.

### Caveat on this page

`FirstPassFDR` was SKIPPED as valid during the regeneration, so the pass-1 half is built from the
run's existing 1st-pass artifacts. The pass-1 fields ARE current-code (the new
`cutoffInStratum`/`acceptedInStratum` keys are present, correctly NaN/0 since pass 1 has no
stratum), but the decoy row moved 5,911 -> 5,677 versus the 8/11 page and that shift is not yet
explained. Treat pass-1 numbers as current-code reading stale inputs until that is understood.
