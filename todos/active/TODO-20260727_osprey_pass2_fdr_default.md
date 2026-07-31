# Osprey: retire OSPREY_PASS2_QVALUE=percolator as the default; choose the pass-2 FDR default

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_pass2_fdr_default` (pwiz-work1)
- **Base**: `master`
- **Created**: 2026-07-27
- **Status**: In Progress
- **GitHub Issue**: [#4484](https://github.com/ProteoWizard/pwiz/issues/4484)
- **PR**: (pending)
- **Requester/Reporter**: Mike + Brendan (both Osprey developers) — NO credit line
  (developer planning on their own project, per version-control crediting rules)

## Objective

Mike and Brendan have decided the current default 2nd-pass FDR mode --
`OSPREY_PASS2_QVALUE=percolator` (retrain the Percolator SVM + recompute a
target/decoy null on the reconciled **+ compacted** pool) -- is **not a valid
approach**. The compacted pool is decoy-depleted, so the retrained null is
thin/biased and the reported q is anti-conservative (Stellar libdecoy
entrapment: 1.57% true FDP @ nominal 1% vs 0.92% for the 1st-pass q -- see
#4363).

This issue is the **decision + default-flip**: pick the replacement default
among the frozen-model modes and resolve the open question of whether
`transfer-compete` is actually valid and/or better than plain `transfer`.
All frozen modes already shipped **off by default** in #4446 (C#), with the
Rust port in maccoss/osprey#57. This is the umbrella "flip the default"
decision that consumes #4363 (calibration root cause) and #4436 (sensitivity
recovery) as inputs.

## The four modes (`OspreyEnvironment.cs`, `docs/12-second-pass-fdr.md`)

| Mode | Retrain? | Null population | Level |
|---|---|---|---|
| `percolator` (default today) | yes | reconciled + **compacted** (decoy-depleted -> anti-conservative) | precursor + peptide |
| `transfer` | no | pass-1 q carried; only reconciliation-**moved** peaks re-mapped via each file's full-pool score->q table | precursor + peptide |
| `transfer-compete` | no (frozen) | fresh full-population target-decoy competition on frozen 1st-pass scores | precursor |
| `protein-compact` | no (frozen) | competition constrained to the protein stratum; off-stratum survivors keep pass-1 q | precursor |

Diagnostic A/B lever: `OSPREY_PROTEIN_COMPACT_RETRAIN` (retrain instead of
frozen within `protein-compact`, to isolate frozen-vs-retrain calibration).

## Open question: is `transfer-compete` valid / better than `transfer`?

- `transfer` reads each peak's q from a fixed co-monotone 1st-pass full-null
  score->q table (Rost 2016 TRIC). #4363 cell E validated it calibrated
  (0.86% true FDP @ nominal 1% on Stellar). Recovers only reconciliation
  peak-move ranking gain.
- `transfer-compete` re-runs a fresh target-decoy competition over the full
  reconciled population using frozen scores -- a peak can change rank vs
  decoys it did not face in pass 1. Potential source of both extra
  sensitivity AND any new mis-calibration.

Questions to answer:
1. Is `transfer-compete`'s fresh competition a statistically valid q, or does
   re-competing frozen scores re-introduce optimism vs `transfer`'s
   co-monotone inheritance?
2. On the FDRBench entrapment oracle, is `transfer-compete` more sensitive at
   matched TRUE FDP than `transfer`, or is the gain just looser calibration?
3. How do the three modes compose? Is a `transfer`-style (co-monotone)
   stratum worth comparing? Is the right default `protein-compact`
   (best measured: +24% precursors @ 0.466% true FDP on Stellar -- #4436)
   or a more conservative `transfer`?

## Prior measured evidence (re-confirm under current binary before deciding)

From #4363 (Stellar 3-file libdecoy, precursor, `--fragment-tolerance 0.4`,
ground truth = FDRBench entrapment):

| variant | reported FDP @1% q | disc @ TRUE 1% FDP | note |
|---|---|---|---|
| A -- 1st-pass q (no pass-2) | 0.92% | 27,292 | no 2nd-pass Percolator |
| B -- retrain (`percolator`, ships today) | 1.57% | 27,682 | anti-conservative; best ranking |
| E -- `transfer` + FULL 1st-pass null | 0.86% | 27,496 | transfer + full null -> calibrated |

From #4436: `protein-compact` measured +24% precursors @ 0.466% true FDP vs
the `transfer-compete` baseline (Stellar); matched true FDP +19.7% @0.5%,
+20.2% @0.75%.

## Tasks

- [ ] FDRBench entrapment-oracle A/B: `transfer` vs `transfer-compete` vs
      `protein-compact` at matched TRUE FDP -- Stellar AND Astral
      (`-Dataset All`; Astral has the selenocysteine gotcha + largest DIA-NN gap)
- [ ] Statistical-validity write-up: `transfer-compete` fresh-competition vs
      `transfer` co-monotone inheritance (is re-competing frozen scores valid?)
- [ ] Pick the default; decide `percolator`'s fate (keep for parity / remove)
- [ ] Coordinated C#+Rust golden-rebaseline PR to flip the default
      (parity with maccoss/osprey#57)
- [ ] Optional: promote `OSPREY_PASS2_QVALUE` to a `--pass2-fdr` CLI flag
- [ ] Docs: update `docs/12-second-pass-fdr.md` default + command-line docs

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey regression (golden rebaseline) + any unit coverage
- **Fails on master**: (TBD)
- **Passes on fix**: (TBD)

This is a golden-output-changing default flip. The primary verifier is the
committed C# golden regression rebaseline (regression.ps1) coordinated with
the Rust golden. Entrapment-oracle A/B measurements are decision evidence, not
regression tests; capture their on-disk paths in the Progress Log.

## Related

- #4363 -- root cause (decoy-depleted null) + validated `transfer` + full-null
- #4436 -- honest FDR + sensitivity recovery (`transfer-compete`, `protein-compact`, GBDT)
- #4446 (merged) -- shipped all frozen modes off by default (C#)
- maccoss/osprey#57 -- Rust port of the frozen modes
- `pwiz_tools/Osprey/docs/12-second-pass-fdr.md`, `Osprey.Core/OspreyEnvironment.cs`

## Build work (prerequisite for the flip): HPC-ready frozen 2nd-pass

Decision deferred (Mike + Brendan not rushing; may re-run the oracle on a larger
dataset). Confident percolator must go; exact winner (protein-compact vs a
co-monotone stratum, and future run-count features) may take >1 PR. Tonight's
build makes the frozen modes usable at scale so the experiment can iterate.

### Piece 1 — persist + reload the 1st-pass model (frozen modes in the merge node)

Root cause: the frozen 2nd-pass modes need the in-process 1st-pass Percolator
model (`ctx.Publish` in FirstJoinTask); a distributed `--task SecondPassFDR` merge
node never trained pass 1, so `Pass2FdrSidecar` fail-fasts. This blocks
`--task SecondPassFDR` for frozen modes AND blocks the pass-2-only experiment.

Implemented (branch build):
- `FeatureStandardizer.FromMeansStds` factory (Osprey.ML) to reconstruct from persisted means/stds.
- `Osprey.Tasks/FirstPassModelIO.cs`: per-file `<stem>.1st-pass.model.json` sidecar
  (standardizer + fold weights/biases) via Newtonsoft + RoundtripDoubleConverter
  (byte-exact). Per-file (not join-wide) so the merge node finds it by the same
  input-stem derivation as every other reconciled sidecar. SVM only; GBDT declines
  (merge-node GBDT stays fail-fast, unchanged).
- Persist in FirstJoinTask (stage 5, beside reconciliation.json).
- Reload in Pass2FdrSidecar.ComputeAndPersist: when a frozen mode is requested and
  the model isn't in ctx, LoadFromAny(perFileParquetPaths) + Publish.
- regression.ps1 phase-4 copy loop ships the model sidecar to the merge node.

Verified:
- Unit test `FirstPassModelIoTest` (3 tests green): round-trip is score-bit-identical;
  Save declines GBDT/degenerate; Load of a missing path returns null.
- Straight-through protein-compact byte-unchanged with the change (30,130 @ 0.90%
  reproduced exactly) -> persist/reload is byte-neutral for the in-process path.
- Persist writes a valid 21-feature model sidecar (JSON inspected).
- Standing gate: regression.ps1 -Dataset Stellar (byte-identity + HPC chain) — running.
- Live frozen-mode merge-node reload: to prove via `OSPREY_PASS2_QVALUE=protein-compact
  regression.ps1 -Dataset Stellar -KeepOutput` (self-consistent config; check phase4.log)
  — the manual `--task`/resume staging hit pre-existing search_hash / rehydrate
  requirements unrelated to this change.

### Piece 2 — 2nd-pass `--model-diagnostics` HTML (mostly existing)

`MergeNodeTask.cs:230` already calls `ModelDiagnosticsReport.WritePass2AndFinalize`
building a Pass2Data bundle (FDR calibration incl. entrapment true-FDP, id-yield,
cross-run, per-file) rendered with a Pass 1/Pass 2 switch. Q-driven cards need no
first-pass data. Remaining: confirm it renders for frozen modes in a merge-node-only
run (structural retrain-only cards correctly show "n/a"); optional: split the
reported-pool score histogram from the model build so it shows under transfer.

## EVIDENCE SUMMARY (2026-07-28) — write-up seed for the transfer decision

### TRANSFER AT 82 FILES IS MEASURED, NOT INFERRED (found 2026-07-30)
`D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-transfer-5dayTransferPerRunMdiag\` (run
2026-07-20, 07:40->11:19, peak ~42 GB, threads 8, LinkFrom resume + `--model-diagnostics` +
`--fdrbench-pass 2`). Log confirms the per-run-only path: "pass-2 carries the pass-1 q through and
re-maps ONLY the per-run q of reconciliation-moved peaks". Pass-2 calibration across the ladder
(`CohortAnalysis/plateau_check.py`):

| nominal | 0.1% | 0.25% | 0.5% | 1% | 2% | 5% |
|---|---|---|---|---|---|---|
| true FDP | 0.11% | 0.18% | 0.42% | **0.92%** | 1.80% | **4.83%** |

Segment slopes 0.48 / 0.96 / 1.00 / 0.88 / **1.01** - tracks the diagonal the whole way, INCLUDING
past 2% where pass 1's pool is exhausted. No plateau, conservative at the operating point. Against
transfer-compete (1.96%, pool 12.8% contaminated) and protein-compact (1.51%, pool 38.5%) this is
not close.

**STALE GUARD IN SHIPPED MASTER (verified 2026-07-30 at master `520d559fd`)**: #4438 (per-run-only q)
IS merged, but `FirstJoinTask.cs:288-290` still reads

```csharp
bool needsResidentFirstPassPool =
    (!string.IsNullOrEmpty(config.OutputFdrBench) && config.FdrBenchPass == 1) ||
    OspreyEnvironment.Pass2TransferQ;
```

The comment immediately above it already documents that the full pre-compaction score->q table -
the only reason transfer needed the resident pool - was dropped, and the NOTE below reasons that
transfer-compete does not need it. The 2026-07-20 transfer run peaked at **~42 GB**, not the ~104 GB
a resident pool implies, so that build was not taking this path. **On master today an 82-file
transfer arm still fails in ~25 s on `GuardResidentPool` despite the fix being in.** Deleting
`|| OspreyEnvironment.Pass2TransferQ` is a one-line defect fix in shipped code and is the
prerequisite for the default flip - then re-confirm the 82-file transfer arm on master.

**IT IS A REGRESSION, proven by `git log -S Pass2TransferQ -- pwiz_tools/Osprey/Osprey.Tasks/FirstJoinTask.cs`**
(three commits, newest first): `dd9e84581` #4446, `8a32095c5` #4438, `2985b4d06` #4410.
- **#4438 REMOVED it**: `-                OspreyEnvironment.Pass2TransferQ;` from
  `needsResidentFirstPassPool` - which is why the 2026-07-20 run peaked at ~42 GB.
- **#4446 RE-ADDED it**: `+                OspreyEnvironment.Pass2TransferQ;` while introducing
  transfer-compete / protein-compact. Almost certainly a merge artifact, not intent - the same hunk
  adds the NOTE reasoning that transfer-compete does NOT need the resident pool.
So the memory-bounding shipped in #4438 was silently undone six days later, and the 4-way (07-28)
ran on the re-broken build - which is exactly why its transfer arm never completed while the 07-20
run had. PR = revert that one line, then re-run
`ai/.tmp/run-pass2-82-4way.ps1 -Mode transfer` (expect ~42 GB, ~3.5 h) and compare to the ladder
above.

### 82-file SEA-AD entrapment 4-way (current binary, experiment scope, FDRBench-validated)
| mode | disc @ 1% q | true FDP @ 1% q | disc @ TRUE 1% FDP | verdict |
|---|---|---|---|---|
| **transfer ≈ Pass-1** | **37,676** | **0.92%** | (calibrated) | WINS both axes |
| protein-compact | 37,232 | 1.51% | 33,722 | anti-conservative, ~flat sensitivity |
| transfer-compete | 33,984 | 1.96% | 28,185 | worst: anti-conservative AND least sensitive |
| percolator | — | ~9% (prior 82f) | — | catastrophic (depleted null) |

**VERDICT: every re-derivation mode is anti-conservative at scale; only `transfer` (freezes
Pass-1 experiment q, never re-derives) holds calibration AND is the most sensitive. Pass 2 is a
net LOSS at 82 files** (protein-compact 37,232 < Pass-1 37,676 @ 0.92%). 3-file was misleading
(protein-compact 0.90% looked best); the inflation grows with run count as predicted.

### Why (diagnostic evidence, from the model-diagnostics HTML — FDRBench is blind to this)
- **Per-run q can't gate the experiment**: per-run q<=1% -> 65,116 disc @ **13.05% true FDP**;
  worsens with N (per-run falses are distinct singletons, trues overlap: union FDP ~ N*alpha).
- **Run-count histogram k=1 slice** (the tell): per-run 12,852 (20%) @ **47.2% FDP**; even
  experiment-wide q (best-of-runs) leaves 639 (2%) @ **20.6% FDP** — bounds the left end but
  doesn't remove the 1-run accumulation, and it WORSENS with N (more lucky-single-run falses clear
  a reproducibility-blind max-score gate as max-of-N-null grows).
- **Reproducibility frontier**: peak ~44,900 @ 1% true FDP (per-run peak >=2 runs Q*0.5%; exp-wide
  peak >=4 Q*10%) = **+19% over exp-wide-q standard 37,763** at same true FDP, 92% same peptides.
  "Reproducibility, not the q statistic, selects them." At >=4 runs even a 10% q holds 1% FDP.

### Validity argument (core of the write-up — why transfer-compete/protein-compact are invalid)
TDC needs a decoy score to be an HONEST NULL DRAW (conditional exchangeability). **Pairing gives
matched COUNTS, not exchangeability.** A decoy transform is valid iff it is a function of the
decoy's OWN data alone; it is invalid the moment it reads the target's q / RT / protein-detection.
- **transfer-compete**: reconciliation (consensus RT + gap-fill) is gated on the TARGET's run-q
  <=0.01 (`ConsensusRts.Qualifies` excludes decoys :99-133; `GapFillTargetIdentifier` targets-only
  :103-197); the paired decoy is rescored at the TARGET's chosen RT -> a reproducible-interference
  false target gets boosted, its decoy at the same RT measures unrelated (different-m/z) noise and
  is NOT boosted -> decoy undercounts false targets -> anti-conservative (1.96% @ 82f).
- **protein-compact**: the >=2-peptide stratum gate is TARGET-only (`BuildProteinCompactStratum`
  `FirstJoinTask.cs:1566`: peptide->protein map from `!e.IsDecoy`; `present2` from target
  `DetectedPeptides`); decoys enter ONLY by base_id pairing. Selection is target-driven + q-gated
  -> stratum decoy null is not symmetric -> anti-conservative (1.51% @ 82f). NOT pair-symmetric in
  the way the code comment claims (membership is symmetric; SELECTION is target-only).
- **percolator**: compaction depletes decoys -> retrain on a thin null -> anti-conservative.
- This is Mike's recurring "pairing == equal treatment" error: two failure modes (depleted-null
  COUNT asymmetry + conditioned-selection DISTRIBUTION asymmetry), one belief, surviving because he
  re-derives FDR in Pass 2. Neither the pairing nor the Pass-2 venue makes an estimator honest.

### HOW protein-compact actually depletes the null (code read + Brendan, 2026-07-30)
`BuildProteinCompactStratum` (`FirstJoinTask.cs:1540`) builds `pepProteins` from TARGET entries
only (`!e.IsDecoy`), counts DETECTED target peptides per protein, keeps proteins with >=2, then
adds `e.Id & ~LibraryEntry.DECOY_ID_BIT` - a BASE_ID. Target and decoy share that base_id, so the
stratum removes and retains COMPLETE PAIRS. There is no decoy-side tally anywhere: a decoy peptide
can never contribute to any protein's count.

So the failure is NOT pass-through retention of decoys whose targets passed (our isolation
experiment's fatal arm); pair-complete removal by itself is harmless (CONTROL 2). It is
**CORRELATION**:
- a high-scoring TARGET is probably a real peptide of a really-present protein, so its protein
  probably has >=2 other detected peptides -> retained;
- a high-scoring DECOY sits on a qualifying protein only by luck, since qualification is decided by
  its PAIRED TARGET's protein, which knows nothing about the decoy's score -> retained at the base rate.
Retention above the cut is therefore higher for targets than decoys, D(s)/T(s) falls, q is
optimistic. **Pair-symmetric membership with a target-correlated criterion is the trap** - which is
exactly what the code comment ("target and paired decoy share a base_id, so this is pair-symmetric")
asserts as its defence.

Second channel, same cause, seen from the ADDED peptides: the sub-1% targets admitted via the
protein rule were not selected for beating their decoys, but they are scored against a null that
has lost every high decoy whose pair sat on a non-qualifying protein.

**Rule of thumb that falls out (Brendan)**: re-admit every target AND decoy down to the lowest
score just added and nothing changes - counts above every threshold in play are whole again. So
**any pass-2 scheme whose q differs from full-population TDC differs only because of what it
deleted. The gain IS the deletion.**

Candidate fix (unmeasured): convert the target q cutoff to a composite score s*, then require the
selection trait per class on its OWN peptides - a target protein qualifies on >=2 target peptides
above s*, a decoy protein on >=2 DECOY peptides above s* - and retain all decoys down to s*
regardless. Implementable: the pairing manifest gives decoys source-protein accessions. CAUTION:
decoy proteins clear >=2 essentially only by fluke, and conditioning on a fluke selects unusually
high-scoring decoy groups, so this could overshoot into CONSERVATIVE rather than land calibrated.
Measure both strata at the same s* (qualifying target vs decoy protein counts) plus the entrapment
oracle before believing either direction. Note it does NOT fix auditability - entrapment proteins
still cannot reach >=2 peptides, so the oracle stays blind either way.

### MEASURED 2026-07-30: the entrapment oracle is STRUCTURALLY BLIND to the protein stratum
Brendan's point — keeping a paired decoy does not preserve symmetry when the decoy is kept ONLY
because its target was kept — has a measurable consequence for the ORACLE, not just the decoy null.
`CohortAnalysis/gate_audit.py` on the recorded 82-file runs (reproduces the recorded FDPs:
protein-compact 37,624 @ **1.53%**, transfer-compete 34,325 @ **1.96%**):

| accepted-set proteins | real | entrapment |
|---|---|---|
| clear the >=2-peptide gate | **73.7%** (4,256) | **6.4%** (18) |
| accepted peptides inside those proteins | **37,389** | **37** |

The library is ~1:0.97 target:entrapment; **inside the protein stratum it is ~1000:1**. A real
protein is 11.5x more likely to clear the gate (48x in the transfer-compete run). So the FDRBench
entrapment set barely exists in the population protein-compact expands over, and **the measured
1.51-1.53% is a LOWER BOUND** on the inflation: the (1 + 1/r) estimator assumes entrapment samples
the false population at library ratio, but in the stratum it samples at ~1/1000th of that. Of the
283 entrapment acceptances at most ~37 can be in the stratum at all.

The expansion itself: protein-compact reports **647,139 rows transfer-compete does not, 20.7% of
them entrapment** (vs 0.75% in the accepted set), none clearing 1% q today. So at the current
operating point the gain is re-competition with off-stratum decoys removed, not admission of the
expansion - and that expansion sits just outside the gate as a one-fifth-entrapment reservoir. Any
loosening of the cutoff, or any drift of stratum q with run count, starts drawing on it.

**Consequence for method assessment generally**: an entrapment oracle can only audit a selection
rule if the entrapment set is exchangeable with the false-target population UNDER THAT RULE. Priors
built on protein grouping are unauditable by a per-peptide entrapment set. The repair is
protein-level entrapment (a foreign proteome retains real multi-peptide proteins - see the natural
Arabidopsis entrapment work) with a peptide-count distribution matched to the targets. Reproducibility
priors do NOT have this problem: 48-73% of accepted entrapment hits rest on >=2 runs, so the oracle
can see them (measured 2026-07-30, see TODO-20260728_osprey_mean_best2).

### REDUCTIO (2026-07-30): the inflation needs no biology at all
Brendan's construction: accept at q<=5%, then re-compete using ONLY the paired decoys of the
accepted targets. `CohortAnalysis/paired_recal_demo.py` simulates it on this dataset's measured
pass-1 score histograms with the measured false fraction (plateauRatio 0.922), equal-chance holding
BY CONSTRUCTION (every decoy and false target drawn from the same null):

| step | accepted @1% | true FDP |
|---|---|---|
| baseline full competition | 9,519 | **0.96%** (calibrated) |
| gate at q<=5% | 13,385 | 5.05% |
| re-compete inside the gate, paired decoys only | **13,385** | **5.05%** |

**+40.6% acceptances on identical evidence, still reporting 1%, true error 5.3x the baseline.**
Null support at the baseline 1% score cut: **95 decoys against 9,519 targets in the full
competition, 1 inside the gate.** The decoys were never selected; the targets were.

The manipulation is a pure RELABELING - sweeping the gate gives 2% -> true 2.02%, 5% -> 5.05%,
10% -> 9.72%, and in every case the ENTIRE gated set clears "1%". Whatever you admit at the gate
becomes your 1% set; the +40.6% is just the consequence of choosing 5%.

**Which failure this models (Brendan, 2026-07-30): the EncyclopeDIA / Spectronaut / original-Osprey
pass-2 case, NOT protein-compact.** A q-based gate sweeps entrapment in at the false-target rate -
measured here: 332 entrapment at a 1% gate, 647 at 2%, **1,294 at 5%**, 2,225 at 10% - so the
relabelled pool still contains them and the oracle REPORTS the inflation (this is why those tools
show the Fig-4a plateau). The >=2-peptide protein stratum contains **37** entrapment peptides:
~35x less oracle visibility, no plateau, metrics look clean. Same estimator error, opposite
detectability. The organising rule and the detector split are in
[[TODO-osprey_selected_null_diagnostics]].

### CURVE SHAPE (2026-07-30): protein-compact does NOT show the Fig-4a plateau
`CohortAnalysis/plateau_check.py`, estimated FDP vs nominal threshold, 82-file runs:
- pass 1: segment slopes 0.60 / 0.89 / 1.00 / 0.92 then frozen -> tracks; overconfidence 0.92x.
- protein-compact pass 2: 1.85 / 1.48 / 1.37 / 1.03 / 0.63 -> **tracks**; overconfidence **1.51x**.
- transfer-compete pass 2: same shape; overconfidence **1.96x**.
So the plateau test that exposes EncyclopeDIA/Spectronaut (Wen Fig 4a: flat ~1.3% across a 0-5%
sweep) **passes protein-compact** - its q still discriminates, it is merely inflated. Catching it
needs the auditability check (D5) and the null-provenance panel, not the curve shape. Full
diagnostic programme: [[TODO-osprey_selected_null_diagnostics]].
**GOTCHA for anyone re-running this**: a q-filtered report goes flat when it runs out of pool, and
that is not a plateau - pass 1 gains 5,864 discoveries from 1%->2% then exactly ONE more out to 5%.
Judge flatness per segment, only where the accepted set is still growing.

### The lever (valid sensitivity, the honest route to Mike's gains) — NEXT IMPLEMENTATION
`mean(best-2 runs)` = experiment-wide peptide score; `mean(best-2 peptides)` = protein score;
replace best-peak(max) aggregation IN THE 1ST PASS (null intact). Symmetric by construction (decoy
uses its OWN two best runs/peptides — no target conditioning), self-calibrating in N (decoys ride
the same order-statistic, so valid at ANY N; power gently fades at huge N, never validity),
generalizes to `mean(best-ceil(f*N))` for the very-large-N fraction. Also aligns detection with the
MIN quant requirement (2 measurements: no CV/ratio from 1 point) — reproducibility governs FDR AND
quant usability, so requiring it is not a sensitivity tax; the lost 1-few-run detections were
unquantifiable and high-FDP anyway.

### FUTURE WORK (from Brendan, 2026-07-28)
1. **Write-up** justifying `transfer` default over transfer-compete/protein-compact (evidence above).
2. **FDRBench PR** (pressing, not started): add the best diagnostic plots to FDRBench — run-count
   histogram + per-k FDP (incl. the decoy-based entrapment-free version #4489), reproducibility
   frontier, per-run-vs-experiment calibration. Needed for side-by-side DIA-NN comparison; harder to
   game than the x=y metric (Fig 4 of the FDRBench paper s41592-025-02719-x: Spectronaut/EncyclopeDIA
   flat-q plateaus, all tools anti-conservative, DIA-NN tuned by Vadim to pass x=y).
3. **DIA-NN side-by-side** (not started). EncyclopeDIA finding: two-stage Percolator (per-file
   mProphet LDA + global `getGlobalVersion` run); likely depleted global null (matches its Fig-4
   plateau) — confirm the global MProphetDataset target/decoy population to make it airtight.
4. **Scaling proof** on a 2nd test machine (Mike's larger datasets): 200 (today) / 300 / 500 runs.
   Expect re-derivation modes to worsen and `transfer` to hold; validate `mean(best-2)` at scale.

### Artifacts
- Analysis: `ai/.tmp/pass2-fdr-default-validity.md`, `ai/.tmp/pass2-82-4way-results.md`.
- Runs: `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2-82-4way-{protein-compact,transfer-compete}\`
  (mdiag HTMLs). Extract: python parse of `out.model-diagnostics.html` pass2.fdpViews[0]
  (experiment): q[], combined[], nTargetAccepted[]. Driver: `ai/.tmp/run-pass2-82-4way.ps1`.

**Next session handoff**: read `ai/.tmp/handoff-20260728.md` for the startup protocol before starting work.

## DIRECTION (2026-07-28 morning, Brendan awake) — DECISION LEANING

- **Default = `transfer`** (strong lean). The only statistically defensible option: it inherits
  Pass-1's honest experiment q, never re-derives FDR on a conditioned/depleted null. percolator
  (depleted null) + transfer-compete/protein-compact (target-conditioned selection: stratum ≥2 gate
  is target-only, decoys ride by base_id — `FirstJoinTask.cs:1566` BuildProteinCompactStratum) are
  NOT symmetric-treatment-valid. 82-file confirmed protein-compact 1.51% (anti-conservative) AND
  slightly LESS sensitive than Pass 1 (37,232 vs Pass-1 37,676 @ 0.92%) — Pass 2 is a net loss at scale.
- **Sensitivity lever (the honest route to Mike's gains) = reproducibility in the 1st-pass
  experiment/protein score**: experiment-wide peptide = `mean(best-2 runs)`, protein = `mean(best-2
  peptides)`. Replaces best-peak(max) aggregation. Symmetric by construction (decoy computes its OWN
  mean-best-2, no target conditioning), self-calibrating in N (decoys ride the same order-statistic),
  and encodes the reproducibility that the run-count/frontier plots prove is decisive (frontier: ≥2
  runs + floated q = 44,966 = +19% over exp-wide-q std 37,763 at same true FDP; k=1 slice = 20.6% FDP
  even with exp-wide q). Generalizes to `mean(best-⌈f·N⌉)` for very large N. NEXT IMPLEMENTATION.
- **#4489 (opened, assigned brendanx67)**: decoy-based per-k FDP — entrapment-free run-count
  diagnostic (N_D(k)/N_T(k)); to be proposed to FDRBench authors as a harder-to-game truth metric
  (the x=y metric is gameable — Fig 4 of the FDRBench paper shows Spectronaut/EncyclopeDIA flat-q
  plateaus + all tools anti-conservative, DIA-NN tuned by Vadim to pass x=y).
- Diagnostics HTML (mdiag) is the load-bearing tool here (FDRBench is blind to per-k / reproducibility).

## mean(best-2) design — PINNED (2026-07-28, with Brendan)

Full spec: `ai/.tmp/mean-best2-spec.md`. The honest sensitivity lever; flag-gated A/B vs the
current max; C#-only for now (Rust match if it becomes a PR); golden-changing but gated.

- **Reproducibility primitive = a single PRECURSOR across runs.** mean(best-2) applies ONLY at
  the precursor level; peptide + protein are MAX roll-ups (refines the earlier loose "mean at
  peptide/protein" wording).
  1. Precursor (ModSeq+Charge) score = mean of best-2 per-run scores (best peak per run, 2
     highest distinct runs). **1 valid run → mean(score, decoy-median floor)** (the typical null
     score, negative; NOT 0 which is the decision boundary; multi-run experiments only; symmetric
     decoys). A/B variants: decoy mean, low decoy percentile.
  2. Peptide score = MAX over its precursors' scores.
  3. Protein score = MAX over its peptides' scores.
  4. TDC + q on the rolled-up scores; symmetric for decoys (each decoy computes its OWN
     precursor mean-best-2). Valid because the transform reads only each unit's own per-run data.
- **Key structural task**: `FdrEntry` has NO file/run id; the experiment competition flat-pools
  entries and drops file identity. mean(best-2 RUNS) needs per-run grouping threaded in (reuse
  the `nRunsDetected` machinery). Sites: `CompeteFromIndices` :2703, `BestPrecursorPerPeptide`
  :4216 (flat max → rebuild as roll-up), `ComputeProteinFdr` :664, streaming mirrors
  `StreamingFirstPassQ.Add` :4071 + `FirstPassProteinFdrAccumulator.Add` :200.
- Scoring is SPARSE (entry only where a peak passes apex-acceptance + the ≥2-fragment signal
  pre-filter; no score cutoff) → 1-run units are real (k=1 ~20% per-run in the run-count
  histogram) and are exactly what the zero-fill demotion targets.
- Executes on a FRESH branch off master after #4487 merges (not on this branch).

## PR #4487 Copilot review follow-up (/pw-respond, pending machine free + build gate)

Two Copilot inline comments, both to FIX (real + trivial). Turnkey:
- **#1 (real bug)** `FirstPassModelIO.Load` (`:170`): documented "null when absent OR unreadable"
  but THROWS on invalid JSON / IO -> can crash the merge node. FIX: wrap ReadAllText +
  DeserializeObject + construction in `try { ... } catch (Exception) { return null; }` (matches the
  FirstJoinTask persist pattern), and tighten the check to `dto == null || dto.SchemaVersion != 1 ||
  Means/Stds null || Means.Length != Stds.Length || FoldWeights null/empty || FoldBiases.Length !=
  FoldWeights.Length -> null`. Thread id 3663404408.
- **#2 (trivial)** `FirstPassModelIoTest.cs:93`: NumFeatures is int, asserted via AssertBitEqual
  (coerces to double). FIX: `Assert.AreEqual(model.Standardizer.NumFeatures, reloaded.Standardizer.NumFeatures)`.
  Thread id 3663404459.
- Gate: `Build-Osprey.ps1 -RunInspection -RunTests` (needs the Release dir free -> after the 82-file
  transfer-compete run finishes). Commit "Addressed Copilot review feedback on PR #4487" (NEW commit,
  never amend). Reply `Fixed in <SHA>` + resolve both threads (see /pw-respond step 3).

## Night 2026-07-27/28 outcome + morning playbook

- **PR #4487 opened**: HPC 1st-pass model persistence (commits fb36ef7f12, acc8112ece).
  Byte-identity regression PASSED; unit tests green; persist verified firing in the HPC
  chain (phase-2 writes `<stem>.1st-pass.model.json`). Enables `transfer`/`transfer-compete`
  in the merge node.
- **KNOWN GAP (follow-up, ~15 min)**: `protein-compact` merge-node also needs the **protein
  stratum** persisted like the model. SPEC: `ProteinCompactStratum { HashSet<uint> BaseIds }`
  (`PipelineByproducts.cs:194`), published at `FirstJoinTask.cs:1611`. Implement:
  (1) a per-file `<stem>.1st-pass.stratum.json` (uint[] base_ids) via Newtonsoft — or fold
  base_ids into FirstPassModelIO's DTO; (2) persist beside the model in FirstJoinTask (the
  stratum is available where it's published, ~1611); (3) in `Pass2FdrSidecar.ComputeAndPersist`,
  alongside the model reload, when `Pass2ProteinCompact && !ctx.TryGet<ProteinCompactStratum>`,
  load the base_ids + `ctx.Publish(new ProteinCompactStratum(set))`. Then the frozen dispatch at
  `Pass2FdrSidecar.cs:665` finds it. Straight-through is unaffected (both in-process). Gate:
  regression byte-identity + a protein-compact chain run (`OSPREY_PASS2_QVALUE=protein-compact
  regression.ps1 -Dataset Stellar -KeepOutput`, add the stratum sidecar to phase-4 copy).
- **Live merge-node reload**: frozen chain proof revealed the harness sourced the model from
  the wrong phase (fixed, acc8112ece); a `transfer-compete` chain rerun to watch the reload
  fire is queued (machine was busy on the 82-file run).
- **82-file protein-compact run LAUNCHED** (detached, `run-pass2-82-4way.ps1 -Mode protein-compact`,
  stage1-4 resume CONFIRMED "skipping (outputs valid)"). Out:
  `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2-82-4way-protein-compact\`.
  **DONE 03:37: 37,232 disc @1%q, true FDP 1.51%, 33,722 disc @ TRUE 1% FDP.**
  **KEY: 3-file protein-compact was 0.90% (calibrated); 82-file is 1.51% (ANTI-CONSERVATIVE)
  — inflation grows with run count as predicted.** Still far better than percolator ~9%, but
  NOT calibrated at scale -> the 3-file "protein-compact default" lean is unsafe for hundreds
  of runs; `transfer` (freezes experiment q, prior 82f ~0.94%) is the calibration-holding
  candidate. Full 4-way table + interpretation: `ai/.tmp/pass2-82-4way-results.md`.
  transfer-compete RUNNING (Monitor bzlvxtvh6); then rerun transfer (current binary).
  Persist VERIFIED at 82-file ("Persisted 1st-pass model ... 82 file sidecar(s)").
- **Full 4-way**: launch the other 3 modes with `run-pass2-82-4way.ps1 -Mode {percolator|transfer|
  transfer-compete}` (sequential, one Osprey at a time). Each ~3h40m straight-through; OR fast via
  --task SecondPassFDR once stratum persistence lands (protein-compact) / for transfer-compete now.
- Cosmetic: new .cs files are LF; run fix-crlf before merge. `/code-review max` + inspection
  re-verify (one pre-existing cref fixed) pending. Handoff: `ai/.tmp/handoff-20260728-pass2-hpc.md`.

## Progress Log

### 2026-07-31 (night session) - PICK_LDA measurement started: a small NEGATIVE on both 3-file entrapment sets

Measurement only; no default flipped, no golden rebaselined. Full session record:
`ai/.tmp/handoff-20260731_meanN_picklda.md`.

**What PICK_LDA is, verified against source** (`Osprey.Scoring/PeakDataExtractor.cs:319-339`,
`Osprey.Scoring/PickLdaModel.cs:76-84`) rather than taken from a prior summary. Both paths compute
the same four raw terms per CWT candidate and the argmax + tie-break are unchanged; only the rank
function differs:
* default: `coelution * rt_penalty * ln(1 + apex_intensity)` - median_polish absent entirely
* PICK_LDA: `w0*z(coelution) + w1*z(ln_intensity) + w2*z(rt_penalty) + w3*z(median_polish)`

Frozen resolution-keyed weights. **Astral/HRAM**: coelution 0.535, ln_intensity **0.0041**,
rt_penalty 0.335, median_polish **0.776**. **Stellar/unit**: coelution **0.993**, ln_intensity
0.047, rt_penalty 0.027, median_polish 0.102. So "PICK_LDA" is not one behaviour - on Astral it is
cosine-led, on Stellar it is essentially the coelution term alone.

**RESULT (3 files each, `Run-FdrBench.ps1 -DecoySource Library -ProteinFdr ''`, pass-2 reported
set, FDRBench oracle).** `-ProteinFdr ''` deliberately: the 0.01 default enables the pass-2
Percolator recalibration that independently inflates FDR, which would swamp the pick effect.

| | default | PICK_LDA | delta |
|---|---|---|---|
| Stellar disc @ matched 1% TRUE | 27,541 | 27,452 | **-89 (-0.3%)** |
| Stellar true FDP @ 1% q | 1.47% | 1.51% | +0.04 pts |
| Astral disc @ matched 1% TRUE | 86,304 | 85,670 | **-634 (-0.7%)** |
| Astral true FDP @ 1% q (paired) | 1.36% (1.27%) | 1.37% (1.27%) | +0.01 pts (unchanged) |

**A small negative on both, calibration essentially unchanged.** Quote the matched-TRUE row: both
baselines are already anti-conservative (1.47% / 1.36% true at nominal 1%), so a reported-q
comparison rewards whichever arm is more miscalibrated.

**A PRE-REGISTERED PREDICTION FAILED, and that is the durable lesson.** From the weights I
predicted Stellar would barely move (it did not, -0.3%) and **Astral would move a lot. It did not
(-0.7%).** The error was equating weight magnitude with decision change. The pick is an ARGMAX over
candidates inside ONE precursor's RT window, and those candidates' four features are strongly
correlated - the best-coelution candidate usually also has the best library cosine, since both
measure "this looks like the real peptide". A rank function can be radically re-weighted and still
select the same candidate almost every time; the achievable gain is bounded by the DISAGREEMENT
RATE, about which the weights say nothing. **Do not repeat the inference "the Astral weights differ
hugely, so the discovery set must move hugely".** To get the disagreement rate directly, use
`OSPREY_PICK_DUMP_CANDIDATES` and compute argmax(product) vs argmax(LDA) offline - no second search
needed.

The flag is live: all four numbers differ between arms, so peaks did move. There are just few of
them and they do not help.

**20-file SEA-AD arm, pass-1 (the cohort we understand):**

| | default | PICK_LDA | delta |
|---|---|---|---|
| RUN scope true FDP @ 1% q | 3.918% | 3.896% | better |
| RUN disc @ matched 1% TRUE | 46,223 | 45,249 | **-974 (-2.1%)** |
| EXP scope true FDP @ 1% q | 0.876% | 0.778% | better |
| EXP disc @ matched 1% TRUE | 46,496 | 44,860 | **-1,636 (-3.5%)** |
| `modelComposite` (target-decoy delta-mu) | 0.1565 | 0.1315 | **-16.0%** |
| exp-accepted / run-accepted | 77.1% | 73.2% | -3.9 pts |
| per-file targets | 608,520 | 605,407 | -0.5% (8 up, 12 down) |
| entrapment / target | 0.371% | 0.361% | -0.010 pts |

Note `-LinkFrom` is UNAVAILABLE for any PICK_LDA arm: the pick moves at PerFileScoring, so Stage-4
parquets cannot be reused and every arm is a full pipeline from mzML (~2 h per 20-file arm here).

### FINAL HEADLINE (after a disjoint replication): PICK_LDA is a SMALL change of INCONSISTENT SIGN

**Read this before the two superseded headlines below it.** A disjoint 6-file cohort (files 21-26,
no overlap with the 20-file cohort) was run specifically to test the "sign flips between pass 1 and
pass 2" reading. **It failed to replicate, and so did the model-degradation story:**

| | 20 files (1-20) | 6 files (21-26) |
|---|---|---|
| pass-1 exp, delta disc @ matched TRUE | -3.5% | -0.4% |
| pass-2, delta disc @ matched TRUE | **+1.8%** | **-1.1%** |
| `modelComposite` | **-16%** | **+20.5%** |

All seven comparisons made this session:

| arm | delta disc @ matched 1% TRUE |
|---|---|
| Stellar libdecoy 3f, pass 2 | -0.3% |
| Astral libdecoy 3f, pass 2 | -0.7% |
| Stellar gendecoy 3f, pass 2 | -1.3% |
| SEA-AD 6f (21-26), pass 1 exp | -0.4% |
| SEA-AD 6f (21-26), pass 2 | -1.1% |
| SEA-AD 20f (1-20), pass 1 exp | -3.5% |
| SEA-AD 20f (1-20), pass 2 | **+1.8%** |

**Six of seven negative, spanning -0.3% to -3.5%; one positive at +1.8%; none large.** That is the
whole result. Do not build a mechanism on it.

This is exactly what the disagreement-rate measurement predicts (the one finding that HAS held):
relocating ~44% of picked peaks moves discoveries ~1% in either direction. When the effect is that
small, per-cohort variation dominates - and TODO-20260728 measured within-size spreads up to 9.9
points on this dataset, several times the entire PICK_LDA effect. Two mechanism narratives were
read out of that noise tonight before the replication killed them.

**Consequence for the default decision.** PICK_LDA is not a sensitivity lever in either direction.
Keep it OUT of the coordinated golden re-baseline - not because it costs sensitivity, but because
it buys nothing measurable while forcing a re-baseline, and its per-cohort sign is unstable enough
that any single validation run will mislead whoever reads it.

**`modelComposite` is not trustworthy as a single-cohort statistic.** -16% one cohort, +20.5% the
next. TODO-20260728 already recorded it swinging 3x non-monotonically with file count. Do not
quote one cohort's value as evidence of anything.

---

### SUPERSEDED (kept so the reasoning trail is auditable): "the sign flips between pass 1 and 2"

| arm | delta disc @ matched 1% TRUE |
|---|---|
| Stellar, library decoys (3f), pass 2 | -0.3% |
| Astral, library decoys (3f), pass 2 | -0.7% |
| Stellar, generated decoys (3f), pass 2 | -1.3% |
| SEA-AD 20-file, pass 1 run scope | -2.1% |
| SEA-AD 20-file, pass 1 experiment scope | -3.5% |
| **SEA-AD 20-file, pass 2 (reported set)** | **+1.8%** |

| 20-file pass 2 | default | PICK_LDA |
|---|---|---|
| disc @ 1% reported q | 61,715 | 61,212 (-0.8%) |
| true FDP @ 1% q | 3.289% | 2.983% (better) |
| paired FDP @ 1% q | 3.059% | 2.782% |
| **disc @ matched 1% TRUE** | **41,364** | **42,122 (+1.8%)** |

**AN EARLIER LINE IN THIS SESSION SAID "PICK_LDA NEVER WINS". THAT WAS WRONG** - correct for the
cells then in hand (all pass-2 at 3 files, plus 20-file pass 1), falsified by the 20-file pass-2
cell run afterwards. Do not quote it.

**The pattern that fits: PICK_LDA damages the FIRST-PASS model, and at 20 files the pass-2 stage
more than reverses it.** Both pass-2 arms are badly anti-conservative (2.98-3.29% true at a nominal
1%) - the known pass-2 recalibration inflation, equally present in both, so it does not explain the
DELTA. But it does mean the +1.8% is delivered by a stage this TODO is separately considering
changing.

**Consequence for the default decision - STRENGTHENED, not weakened.** The planned coordinated
re-baseline was to flip protein-compact + **LDA-pick** + frozen-model together. LDA-pick's SIGN
depends on which pass-2 mode is in force, so bundling it with a pass-2 change means neither can be
attributed. Split LDA-pick out and decide it on its own evidence, against a fixed pass-2 mode.

**Convention warning for anyone extending this table.** `disc @ 1% TRUE` is
`max(n_t)` over rows with `combined_fdp <= 0.01`, exactly as `Run-FdrBench.ps1`'s `Get-FdpMetrics`
computes it - that is what makes these cells comparable. That script's `disc @ 1% q` is a ROW COUNT
(`($atQ | Measure-Object).Count`), not `max(n_t)`, and its FDP-at-1%-q is read off the LAST row
sorted by q, not the max-n_t row. An ad-hoc reimplementation that uses `max(n_t)` for the q column
gives 60,700 where the script gives 61,715 on the same file. Copy the script's semantics.

### A SECOND PRE-REGISTERED HYPOTHESIS, FALSIFIED (wrong sign)

To explain the -16% `modelComposite`, I proposed: Carafe LIBRARY decoys carry their own library
spectra, so a cosine-led pick lifts decoy candidates as much as targets and compresses separation;
therefore PICK_LDA should do BETTER under GENERATED decoys, which have no real spectrum to score a
cosine against. Ran it (same dataset, same entrapment, only the decoy source changes):
**library -0.3% vs generated -1.3% - four times WORSE, the opposite sign.** Hypothesis dead.

Both of tonight's failed predictions came from the same bad habit: reasoning about what a scoring
change OUGHT to do (from weight magnitudes, then from the decoy channel) instead of measuring what
it DID. Treat any mechanism story about the pick model as a lead until a cell confirms it.

### MEASURED: the pick relocates ~44% of peaks and it barely matters

One Astral file with `OSPREY_PICK_DUMP_CANDIDATES=1`, then both argmaxes recomputed OFFLINE from the
same candidate set (`ai/.tmp/pick_disagreement.py`). One run, no second search, so there is no
confound from two arms having scored different populations:

```
target  precursors 2,152,584   with >1 candidate 1,679,273 (78.0%)
        product vs LDA pick DIFFERS on 733,267 = 43.7% of contested
decoy   precursors 2,096,478   with >1 candidate 1,622,739 (77.4%)
        product vs LDA pick DIFFERS on 746,200 = 46.0% of contested
decoy - target disagreement: +2.3 pts
```

**This kills my OTHER explanation.** I had said the effect was small because the argmax rarely
changes despite different weights. It changes on ~44% of contested precursors. So:

**PICK_LDA relocates roughly half the picked peaks and moves the Astral discovery set by under 1%.**
The choice of peak among CWT candidates is far LESS consequential than the weights or intuition
suggest - downstream scoring and FDR absorb nearly all of it. Likely reading (inference, not
measured): most relocations are between near-identical candidates (adjacent apexes, shoulders)
whose downstream features barely differ, so large index-level churn yields a small feature-level
change.

**This is the most reusable result of the night: it sets a CEILING on what any pick-model work can
buy.** Tuning the rank function is not where the sensitivity is. Weigh that before funding more
pick-model training.

The surviving asymmetry: decoys are relocated **2.3 pts more often** than targets, the right
direction to compress target-decoy separation and at least consistent with the -16%
`modelComposite`. NOT claimed as the explanation - this dump is library-decoy Astral, and the
library-decoy story already failed once tonight. A gendecoy dump would test whether the asymmetry
survives.

**SCORE FOR THE NIGHT: three mechanism stories proposed, three corrected by measurement** (weights
=> big effect; argmax rarely changes; cosine lifts library decoys). Every measurement held. Treat
pick-model reasoning as a lead until a cell confirms it.

**The -16% model degradation is therefore OPEN, not explained.** Next candidate worth testing:
the pick model was trained to select the CORRECT peak, but the downstream SVM needs SEPARABLE
peaks - and intensity, while a weak per-candidate correctness cue, may proxy measurement quality
(brighter peaks give cleaner coelution and cosine estimates), so dropping its weight to ~0.004 may
hand the SVM noisier features across the board. Testable offline from an
`OSPREY_PICK_DUMP_CANDIDATES` dump; no new search required.

**Tooling**: `ai/.tmp/picklda_compare.py` A/Bs two runs on the mdiag at BOTH pass-1 scopes (run and
experiment), calibration before sensitivity, plus per-file targets and entrapment. Validated
against the known mean-N A/B before use - which caught two bugs in it, including a first-crossing
scan for matched-true FDP that returned 1 (the curve is noise at tiny counts; the correct
convention, copied from `extract_pass1_fdp.disc_at_fdp`, is the MAX qualifying grid point).

### 2026-07-28 - PR #4487 MERGED (checkpoint)

Squash-merged #4487 (merge commit ebe24eeb68) after all gates green: local build/tests/inspection,
Stellar byte-identity regression, /code-review max (3 findings folded), Copilot resolved, and the
full **TeamCity Perf/Regression finished-SUCCESS** (Stellar + Astral mode1/2/3 + perf, build 4111956).
Branch `Skyline/work/20260727_osprey_pass2_fdr_default` deleted (local + remote).

**#4484 umbrella STAYS OPEN** — #4487 was Piece 1 (HPC 1st-pass model persistence enabling frozen
2nd-pass modes in the merge node), not the umbrella decision. Remaining under #4484: the default flip
off `percolator` (lead = `transfer`), pending the 164-file confirmation; and the `mean(best-2)`
sensitivity lever (separate branch `Skyline/work/20260728_osprey_mean_best2`, TODO-20260728_osprey_mean_best2).
Future #4484 default-flip work needs a NEW branch off master (this one is consumed).

**Known follow-up now on master**: protein-compact merge-node still needs its ProteinCompactStratum
persisted (spec in the "Night" section below) — deferred; `transfer`/`transfer-compete` merge-node
reload works and is proven.

### 2026-07-28 - PR #4487 /code-review max + hardening (checkpoint-merge prep)

Ran `/code-review max` on the branch (6 findings). Verified each against source before acting.
Brendan's call: fold the 3 small golden-neutral fixes, defer the 2 refactors. Commit `f4aa3a3e13`:
- **#1 (CONFIRMED bug)** `regression.ps1:686` read the model sidecar from the already-deleted
  `$ph2` (line 668), so the frozen-mode merge-node reload was NEVER exercised — the exact reason
  the handoff called it "unverified". Fixed: relay the model `$ph2->$ph3->$ph4` like the sibling
  Stage-5 sidecars. **PROVEN**: `transfer`-mode chain **mode3 (HPC chain==straight): PASS** (byte
  26,787,840) + merge-node `phase4.log` logs "Reloaded persisted 1st-pass model sidecar" — reload
  fires and is bit-identical to the in-process path. (mode1 vs the percolator golden FAILs by
  design — different mode.)
- **#3** `Pass2FdrSidecar.cs:104` dropped protein-compact from `wantsFrozenModel`: it reloaded +
  logged a false "reloaded" success then fail-fasted on the still-missing stratum. Now excluded
  until the stratum is persisted.
- **#2+#6** `FirstPassModelIO.Load` now validates fold widths + consumes the previously-dead
  `NumFeatures` as a consistency check (corrupt sidecar -> null, not a merge-node crash). New unit
  test `TestFirstPassModelLoadRejectsCorruptOrInconsistent`.

**Deferred to the frozen-mode-completion piece** (pair with stratum persistence): #4 (ride
`reconciliation.json` instead of N per-file model copies), #5 (extract the shared canonical-JSON
writer from `ReconciliationFile.Save`), and #2's deeper "model width vs current PIN feature count"
hard-fail at the consumer.

Gates on `f4aa3a3e13`: build Release/net8.0 clean, inspection 0/0, **550/550** unit tests,
**Stellar byte-identity regression PASS** (mode1/2/3, blib 30,597,120 — fixes are golden-neutral).
TeamCity Perf/Regression re-triggered on `pull/4487` (build 4111956, ~1h) after cancelling the
stale 4111950. Merge is checkpoint-only — does NOT close #4484.

**Surfaced (default-flip prerequisite, NOT this checkpoint)**: `transfer` trips `GuardResidentPool`
(`PerFileScoringTask.cs:1557`) and needs `OSPREY_ALLOW_UNBOUNDED_MEMORY=1` — the #4438-removed /
#4446-re-added guard. Making `transfer` the DEFAULT requires restoring its streaming path first
(per-file score->run-q table) or every default run demands unbounded memory (won't scale to 164f).

### 2026-07-28 - PR #4487 Copilot review addressed

Applied both Copilot inline fixes in a NEW commit `5de9896d81` (never amend post-review):
- `FirstPassModelIO.Load`: wrapped read/parse/construct in try/catch → null (honors the
  documented "unreadable → null" contract instead of throwing and crashing the merge node);
  added shape validation (`SchemaVersion == 1`, `Means.Length == Stds.Length`, `FoldWeights`
  non-empty, `FoldBiases.Length == FoldWeights.Length`). `NumFeatures` intentionally NOT a
  load-blocking invariant — reconstruction derives it from `Means` via `FromMeansStds`.
- `FirstPassModelIoTest.cs`: `NumFeatures` now asserted with `Assert.AreEqual` (int equality)
  not the double bit-parity helper.

Gate (pwiz-work1, Debug): build clean, **549/549 tests passed**, inspection **0 warnings/0
errors** (re-confirmed the earlier dangling-cref fix holds). Build's fix-crlf step converted
both files LF→CRLF, so the handoff's CRLF gotcha is now resolved for these two files.
Replied `Fixed in 5de9896d81` + resolved both threads (3663404408, 3663404459). Added the
missing `osprey` module label and `osprey:` title prefix to the PR.

**Still pending before human review**: `/code-review max` on the branch (deferred overnight);
protein-compact stratum persistence follow-up (~15 min, spec above).

### 2026-07-27 - Session Start

Starting work on this issue. Created branch
`Skyline/work/20260727_osprey_pass2_fdr_default` in pwiz-work1. This is the
umbrella default-flip decision anticipated in prior pass-2 work; #4446 (C#) and
osprey#57 (Rust) already shipped the frozen modes off by default.

### 2026-07-27 - Statistical-validity analysis + oracle run launched

Discussion-first (Mike/Brendan want the methodology settled before the flip).

- Mechanical flip is trivial: `OspreyEnvironment.NormalizePass2QValue` returns
  `PASS2_QVALUE_PERCOLATOR` on empty input (`OspreyEnvironment.cs:361`); all four
  modes + `OSPREY_PROTEIN_COMPACT_RETRAIN` already present. Substance = the decision.
- **Verified transfer-compete competes over the full PRE-compaction population**
  (`PercolatorFdr.cs:2928-2929`) — not decoy-depleted, not retrained. Both
  `percolator` sins gone; if reconciliation moved nothing it reproduces pass-1 q.
- **Verified reconciliation is structurally target/decoy asymmetric.** Every gate
  that selects what gets reconciled / where it re-integrates is a target-only q
  quantity: consensus qualification excludes decoys (`ConsensusRts.cs:99-133`),
  planner gated on target min-q (`ReconciliationPlanner.cs:131-144`), gap-fill
  targets-only at the target's ExpectedRt (`GapFillTargetIdentifier.cs:103-197`).
  Direction: harmless for true targets, anti-conservative for reproducible false
  targets → `transfer` (experiment-q frozen) is immune by construction;
  `transfer-compete` is exposed. Confirms Brendan's "only targets can carry a q".
- Orthogonal-axes analysis (protein corroboration = mean-top-2/posterior-product;
  reproducibility = binomial-tail not raw count, scale-correct; overlap → joint
  CV-trained feature model, not more q-cutoff modes; decoy-fairness constraint).
- **Write-up captured**: `ai/.tmp/pass2-fdr-default-validity.md` (Task 2, the
  statistical-validity deliverable; pre-measurement draft — distill to
  `docs/12-second-pass-fdr.md` after testing).
- **Harness**: added `-Pass2QValue` to `ai/scripts/Osprey/Run-FdrBench.ps1`
  (sets/restores OSPREY_PASS2_QVALUE, folds into OutName + metrics.csv). Built a
  fresh Release net8.0 Osprey in pwiz-work1 (master-equivalent; HEAD == origin/master).
- **Oracle 3-way results** (branch build; matched precursor / pass 2 /
  --protein-fdr 0.01; Stellar +tol0.4, Astral calibrated). disc @ TRUE 1% FDP:

  | mode | Stellar (true FDP) | Astral (true FDP) |
  |---|---|---|
  | transfer | 27348 (0.94%) | 84659 (0.85%) |
  | transfer-compete | 27738 (0.69%) | 85042 (0.87%) |
  | protein-compact | **30433 (0.90%)** | **105883 (0.77%)** |

  Findings: (1) transfer-compete is NOT anti-conservative (conservative both) —
  the reconciliation asymmetry doesn't bite; full pre-compaction null is
  decoy-rich. (2) protein-compact dominates: +9.7% (Stellar) / +24.5% (Astral)
  disc @ matched TRUE FDP, calibrated both, reproduces #4436. (3) transfer ≈
  transfer-compete (fresh competition adds ~nothing); gain is the protein stratum.
  (4) **transfer resident-pool trip is a regression**: #4438 removed
  `|| Pass2TransferQ` from NeedsResidentPool (transfer streams via per-file
  score→run-q table); #4446 re-added it (`PerFileScoringTask.cs:1513`, merge
  artifact) contradicting its own docstring. transfer numbers ran resident under
  the memory override; lean==fat by #4438's invariant so they stand.
- **Recommendation**: default → `protein-compact` (both datasets agree); retire
  `percolator`; keep transfer/transfer-compete opt-in; fix the #4446 regression
  first. Full analysis + tables: `ai/.tmp/pass2-fdr-default-validity.md`.
- Driver: `ai/.tmp/run-pass2-oracle-3way.ps1` (-Dataset param); logs
  `ai/.tmp/pass2-oracle-3way.{stellar,astral}.driver.log`.
