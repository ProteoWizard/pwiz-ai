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
