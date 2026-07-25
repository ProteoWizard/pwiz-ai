# Osprey: decide the fate of generated (reverse) decoys -- calibrate or hard-gate

## Branch Information
- **Branch**: `Skyline/work/20260725_osprey_gendecoy_decision`
- **Base**: `master`
- **Created**: 2026-07-25
- **Status**: In Progress
- **GitHub Issue**: [#4465](https://github.com/ProteoWizard/pwiz/issues/4465)
- **PR**: (pending)
- **Requester/Reporter**: none (raised internally by the Osprey developers; no credit line)

## Objective

Osprey can build its own decoys ("gendecoy", mechanical sequence reversal) when the
library has none, or use library-supplied decoys from a predictive model ("libdecoy":
Carafe / Prosit / AlphaPeptDeep). The FDRBench entrapment oracle shows gendecoy is
badly miscalibrated -- ~12-16% true FDP at a claimed 1% q on Stellar/Astral -- while
libdecoy is near-calibrated at ~0.8-1.3%.

Decide whether the generated decoys can be fixed so they match the target false
distribution, or whether in-tool decoy generation is a dead end -- in which case Osprey
should always require decoys from a predictive model, and the gendecoy option is removed
or hard-gated.

Do NOT turn the option off before this decision is made.

Compounding finding: `pwiz_tools/Osprey/regression.ps1` never passes
`--decoys-in-library` (verified on master 2026-07-25), so BOTH regression datasets
(Stellar + Astral) exercise only the miscalibrated generated-decoy path. The libdecoy
path we actually recommend has no regression coverage at all, and FDR-change impact
numbers measured on the regression are exaggerated.

Osprey is not yet public -- removing or hard-gating a miscalibrated decoy mode is cheap
now and expensive once external users depend on it.

## Tasks

- [ ] Measure whether a re-predicted (rather than reversed) decoy closes the calibration
      gap on the FDRBench entrapment oracle
- [ ] If it closes: ship the better generator and keep the gendecoy option
- [ ] If it does not: hard-gate or remove in-tool decoy generation and require
      library-supplied decoys -- emit a clear error rather than silently producing
      anti-conservative q-values
- [ ] Either way: move the Osprey regression off the gendecoy `stellar` dataset onto the
      libdecoy path (`--decoys-in-library`)

### Candidate salvage angles (from prior notes)

- [ ] Honest MS1 power for foreign/predicted decoys (existing night-session run-book)
- [ ] Decoy-quality alarms / null-alignment diagnostics -- a decoy-independent `f_false`
      null plus a paired-coin alarm would make this failure visible rather than silent
- [ ] Re-predicting decoy spectra and RT from the same predictive model instead of
      mechanical sequence reversal (most promising structural fix)

## Gate

The FDRBench entrapment oracle is the arbiter, not cross-implementation parity. See the
"FDRBench entrapment validation" section of `ai/docs/osprey-development-guide.md` and
`ai/scripts/Osprey/Run-FdrBench.ps1` (`-DecoySource Library|Generated` is exactly this
comparison).

Standing Osprey gates still apply to any code change:
- correctness: `pwiz_tools/Osprey/regression.ps1`
- perf: `ai/scripts/Osprey/Test-PerfGate.ps1`
- pre-commit: `Build-Osprey.ps1 -RunInspection -RunTests`

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Test | TestData | Osprey regression harness (regression.ps1)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Note: the decision itself is measurement-driven (FDRBench entrapment oracle), not
unit-testable. The concrete testable deliverables are (a) whichever code change the
decision produces -- a better generator, or a hard-gate error path -- and (b) the
regression harness gaining libdecoy coverage. Record red->green evidence here for
whichever lands.

## Progress Log

### 2026-07-25 - Session Start

Starting work on this issue. Branch created off master at 099ec2d5d. Confirmed
`regression.ps1` on master contains no `--decoys-in-library` / `DecoySource` reference,
so the gendecoy-only regression coverage claim in the issue holds.

### 2026-07-25 - The libdecoy/gendecoy A/B already IS the scope-item-1 experiment

**The decoy sequences are identical between the two modes.** Compared every decoy
sequence in the Stellar Carafe pairing manifest
(`D:\test\osprey-runs\stellar-libdecoy\osprey_library_db_pairing.tsv`) against what
`DecoyGenerator.GenerateAllWithCollisionDetection` would produce for the same targets:

```
target   -> decoy  : 218,871 pairs -- 218,805 reversed + 66 cycled, 0 mismatch (100.0000%)
p_target -> p_decoy: 218,871 pairs -- 218,797 reversed + 74 cycled, 0 mismatch (100.0000%)
```

Exact agreement on all 437,742 pairs, including the 140 that fall through to the
cycling fallback. Carafe uses the same C-term-preserving reversal Osprey does.
(Script: scratchpad `check_decoy_sequences.py`; the production path builds
`new DecoyGenerator()` = `Enzyme.Trypsin`, so `DetectEnzyme` is not involved.)

Consequence: **the existing libdecoy-vs-gendecoy FDRBench comparison already holds the
decoy sequence set exactly constant**, so the ~12-16% vs ~0.8-1.3% gap is attributable
entirely to how the decoy's spectrum and RT are produced -- which is precisely what
scope item 1 asks to measure. It does not require building a new re-predicted decoy
library with Carafe.

| | decoy sequence | fragment m/z | relative intensity | RT |
|---|---|---|---|---|
| gendecoy (Osprey) | reverse / cycle | recomputed, b<->y swap | **copied from target fragment** | **copied from target** |
| libdecoy (Carafe) | *identical set* | model-predicted | model-predicted | model-predicted |

The named structural weakness: an Osprey generated decoy is a deterministic function of
its target in intensity and RT space -- not an independent draw from the false
distribution. `DecoyGenerator.cs:385-386` copies `target.RetentionTime` /
`target.RtCalibrated`; `DecoyGenerator.cs:625` copies `frag.RelativeIntensity`.

### 2026-07-25 - The same pattern exists in Skyline-mProphet (verified in code)

Skyline generates decoys in-tool the same way, so a "gendecoy is a dead end" verdict in
Osprey is also a verdict about Skyline's mProphet decoys:

* `Model/DecoyGenerator.cs:241` -- decoy transitions are built with `nodeTran.QuantInfo`,
  which carries `TransitionLibInfo` (rank + intensity), so **decoy transitions inherit
  the target transition's library intensity verbatim**.
* `Model/DecoyGenerator.cs:203` -- the decoy precursor inherits `nodeGroup.LibInfo`.
* `Model/DecoyGenerator.cs:114` -- the decoy peptide inherits `nodePep.ExplicitRetentionTime`.
* Open / unverified: how a decoy's *iRT-predicted* RT is derived at scoring time.
  `Irt/IrtDbManager.cs:231` only establishes that decoys are excluded from the
  regression fit. Nail this down before filing the Skyline issue.

Conditional deliverable (Brendan, this session): if Osprey retires or hard-gates
gendecoy, **file a new Skyline issue to make it possible to avoid generated decoys in
Skyline-mProphet** (i.e. accept decoys supplied by a predictive model). Not yet filed --
gated on the Osprey decision.

### 2026-07-25 - VERDICT: scope item 1 answered by the paired decoy-win coin

The `--model-diagnostics` **paired decoy-win fraction** settles it without any new run.
Within each target-decoy pair (shared base_id), an honest decoy beats a *known-false*
entrapment target ~50% of the time. Values read out of the committed HTML reports under
`D:\test\osprey-runs\_mdiag\*\stellar.model-diagnostics.html` (key `nullBandEnt` /
`nullBandReal`, low-score null band):

| run | decoy source | entrapment coin | real coin |
|---|---|---|---|
| `stellar` | Carafe-predicted (`--decoys-in-library`) | **0.5007** | 0.4778 |
| `stellar-pfdr` | Carafe-predicted (+ `--protein-fdr`) | **0.5007** | 0.4778 |
| `stellar-noentrap` | Carafe-predicted, no entrapment | n/a | 0.4708 |
| `stellar-gendecoy` | **Osprey-generated** | **0.2051** | 0.1612 |

Library-supplied decoys are a fair coin to within 0.07 percentage points. Generated
decoys lose to a known-false target four times out of five.

**This A/B is internally controlled, which retires the sequencing worry above.** Both
arms are the same binary, same features, same feature conditioning, and (proven above)
the same decoy sequences. So the un-logged intensity-feature conditioning
(`fix/intensity-feature-log-conditioning`) cannot be what makes generated decoys
non-exchangeable -- predicted decoys are exchangeable under the identical code path.
The intensity fix may move absolute FDP in both arms; it cannot move 0.5007 to 0.2051.

The paired coin is also a *within-pair ordering* test, so unlike the marginal composite
densities it carries no population/marginal confound, and it is decoy-independent (the
ground truth is entrapment, not decoy counts) -- not circular.

Mechanism consistent with all of it: a generated decoy's b<->y-transposed ion ladder
carrying the target's copied intensities is systematically less able to match anything
in the spectrum than a model-predicted spectrum for the same sequence. An entrapment
target -- also absent from the sample -- still has a Carafe-predicted spectrum, so it
wins. Under libdecoy both sides of the pair are model-predicted and the coin is fair.

**Conclusion: mechanical in-tool decoy generation is a dead end (issue scope item 3),
not salvageable (item 2).** An honest decoy spectrum requires a spectrum model. Osprey
has none by design; the "better generator" the issue contemplates *is* the predictive
model. The remaining question is disposition (remove vs hard-gate) plus whether Osprey
should offer out-of-process Carafe decoy generation -- see
[[project_osprey_carafe_library_selfsufficiency]].

### 2026-07-25 - Exact algorithm comparison vs Skyline (Brendan's redirect)

Before discarding, establish how Osprey's generator compares to Skyline's, and whether
Skyline's 2015-standard approach carries the same bias. Skyline has no entrapment oracle
and no paired-coin diagnostic, so the only way to put it on a real oracle is to
reproduce its algorithm inside Osprey and measure.

Skyline: `pwiz_tools/Skyline/Model/DecoyGenerator.cs` (`Reverser` is the analog;
`Shuffler` and `MassShifter` are the other two modes).
Osprey: `pwiz_tools/Osprey/Osprey.Scoring/DecoyGenerator.cs`.

| step | Osprey gendecoy | Skyline `Reverser` |
|---|---|---|
| sequence permutation | `reverse(seq[:-1]) + seq[-1]` | **same formula** (`SequenceMods.Reverse()`, `:330`) |
| degenerate guard | none up front; reversal -> cycling -> exclude | skip if `seq[:-1]` has <= 1 distinct residue (`:54`) |
| collision policy | reversed must differ from target AND not be in the **target sequence set**; else cycle 1..10; else exclude | dedups only against **other decoys** (`setDecoyKeys`, `:135`); `Reverser` is deterministic so its 10 retries never re-roll |
| precursor m/z | **copied from target** (`:384`); reversal preserves composition so the mass is genuinely equal | **shifted +10** (`ALTERED_SEQUENCE_DECOY_MZ_SHIFT`, `:189`) unless `PreservePrecursorMass` |
| product ion identity | **b<->y swap**, ordinal remapped to `n - ordinal` (`:585-593`) | **same IonType + CleavageOffset** (`:238`) -- a target b3 yields a decoy b3 |
| product m/z | recomputed from the decoy sequence | recomputed from the decoy sequence; **no** product mass shift for altered sequences |
| library intensity | **copied from the target fragment** (`:625`) | **copied via `nodeTran.QuantInfo` -> `TransitionLibInfo`** (`:241`) |
| predicted RT | **copied from target** (`:385-386`) | **resolved through the target's sequence**: `ChangeSourceKey` (`:130-131`) -> `GetSourceTarget` -> `PeptideSettings.cs:479`, `Irt/RCalcIrt.cs:117` |
| other modes | none | `Shuffler` (random permutation of `seq[:-1]`, multi-cycle), `MassShifter` (sequence kept, random precursor shift +-30 + random product shifts) |

**Shared root property -- the one the paired coin punishes: neither predicts a decoy
spectrum; both copy the target's library intensities, and both give the decoy the
target's predicted RT.** That is the same structural defect, arrived at independently.
So Skyline-mProphet is a priori exposed to the same bias.

Two differences could change its magnitude, and neither is obviously benign:
* **No b<->y swap** -- Skyline keeps the ion index, so the copied intensity lands on the
  same-numbered ion of a different sequence.
* **+10 precursor shift** -- Skyline moves the decoy into a *different isolation window*,
  so it extracts a genuinely different chromatogram. Osprey's decoy shares the target's
  window and RT and differs only in fragment m/z.

### Planned experiment: put Skyline's algorithm on the oracle

Reproduce Skyline's decoy construction inside Osprey behind a diagnostic-only switch
(default OFF, so production output stays byte-identical and the regression golden is
untouched), then run the Stellar 3-file `--model-diagnostics` cell and read
`nullBandEnt`. Variants, so the two differences are separable rather than confounded:

| variant | b<->y swap | precursor shift | expected artifact |
|---|---|---|---|
| A: Osprey today | yes | none | 0.2051 (measured) |
| B: same-ion intensity | no | none | isolates the ion-assignment choice |
| C: full Skyline equivalent | no | +10 | the number that decides the Skyline bug |
| reference: libdecoy | n/a | n/a | 0.5007 (measured) |

If C is also far from 0.50, file the Skyline issue: mProphet needs to move to
library-supplied (model-predicted) decoys rather than the 2015 in-tool standard.

### 2026-07-25 - RESULT: the b<->y swap is the defect; the earlier dead-end call is WRONG

Implemented the two knobs (`OSPREY_DECOY_SAME_ION_MAP`, `OSPREY_DECOY_PRECURSOR_MZ_SHIFT`,
both default-off and folded into `SearchParameterHash` only when set) and ran the 2x2 on
Stellar 3-file. Reports under `D:\test\osprey-runs\_mdiag\stellar-gendecoy-{B,C,D}-*\`.

**Reading caveat:** current master emits TWO paired-coin blocks per report; the Jul-6
reference runs emit one. The first block is a small-population view (~500-6,400
entrapment pairs); the references' single block has ~238K, matching the variants' SECOND
block on both population and null-band bounds. Compare block 2. (A first pass at these
numbers used block 1 and inverted the conclusion.)

| variant | ion map | precursor | entrapment coin | real coin | ent pairs |
|---|---|---|---|---|---|
| libdecoy (Carafe) | -- | -- | **0.5007** | 0.4778 | 238K |
| B: same ion, no shift | same | +0 | **0.4733** | 0.4526 | 243K |
| C: Skyline equivalent | same | +10 | **0.4600** | 0.4322 | 239K |
| A: Osprey today | b<->y swap | +0 | **0.2051** | 0.1612 | 231K |
| D: swap + shift | b<->y swap | +10 | **0.1949** | 0.1504 | 229K |

1. **The b<->y swap is the entire defect.** Dropping it alone moves the coin 0.2051 ->
   0.4733, from "decoy loses four times out of five" to nearly fair. Confirms the
   predicted mechanism: the swap transplants the target's intense y-ion intensities onto
   the decoy's b-ions and the weak b-ion intensities onto its y-ions, inverting the
   intensity structure relative to any real peptide.
2. **The +10 precursor shift is nearly irrelevant** (0.4733 -> 0.4600; 0.2051 -> 0.1949),
   so the isolation-window difference does not drive this on 4 m/z Stellar data.
3. **Skyline's construction is essentially unbiased here** (0.4600 vs Carafe 0.5007).
   **No Skyline bug is warranted on this evidence** -- the 2015 standard holds up. The
   conditional Skyline deliverable recorded earlier is therefore NOT triggered.
4. **Generated decoys are NOT a dead end.** This supersedes the dead-end conclusion
   above: fixing the swap recovers a near-honest null with no predictive model, so issue
   scope item 2 (salvageable -- ship the better generator) is the live branch, not item 3.

Scope caveat: this measures Skyline's decoy *construction* inside Osprey's feature set
and Percolator SVM, not Skyline-mProphet end to end (mProphet uses its own peak-scoring
features and an LDA). It is evidence about the construction, not about shipped Skyline FDR.

### 2026-07-25 - FDP axis: confirms the fix, and walks back the "no Skyline bug" call

Read the in-process FDP calibration curve ("Pass 2 - experiment-wide") out of each
report at the point where reported q first reaches 1% (scratchpad `read_fdp.py`):

| cell | reported q | combined FDP | paired FDP | accepted |
|---|---|---|---|---|
| libdecoy (Carafe) | 0.0095 | **1.47%** | 1.32% | 30,242 |
| B: same ion, no shift | 0.0096 | **2.40%** | 2.39% | 32,329 |
| C: Skyline equivalent | 0.0094 | **3.19%** | 3.18% | 33,447 |
| A: Osprey today | 0.0099 | **10.86%** | 10.84% | 35,477 |
| D: swap + shift | 0.0100 | **20.40%** | 20.37% | 48,276 |

A at 10.86% reproduces the on-record 12-16% ballpark, confirming this in-process FDP
measures the same quantity as the FDRBench jar. Removing the swap cuts true FDP 10.9% ->
2.4% (4.5x), so the coin result carries to reported-q calibration.

**The two diagnostics disagree about Skyline, and FDP is the user-facing one.** C's coin
is nearly fair (0.4600 vs 0.5007) yet its FDP is 3.19% against libdecoy's 1.47%. A fair
paired coin is necessary but not sufficient for calibrated q: the coin tests within-pair
ordering inside the null band, while FDP integrates the whole accepted ranking.

So the earlier "no Skyline bug is warranted" is **withdrawn as too strong**. Defensible
statement: Skyline's construction is far better than Osprey's current swap (3.2% vs
10.9%) but still ~2x worse than model-predicted decoys and ~3x anti-conservative in
absolute terms -- a real, reportable bias, but not a 10x one.

Note no cell is perfectly calibrated (libdecoy reads 1.47% at a claimed 0.95%), and the
anti-conservative cells accept more IDs (D: 48,276 vs libdecoy's 30,242) -- the expected
signature.

### 2026-07-25 - Fidelity bug in my own C/D variants (Brendan caught it)

Skyline does NOT shift the decoy precursor by an integer m/z. `SequenceUtil.cs:145`:

```csharp
public const double MASS_PEPTIDE_INTERVAL = 1.00045475;
public static double GetPeptideInterval(int? massShift)
    => massShift.HasValue ? massShift.Value * MASS_PEPTIDE_INTERVAL : 0.0;
```

and `TransitionDocNode.cs:72` adds `GetPeptideInterval(DecoyMassShift)` to the **m/z**
(charge-independent, NOT to the neutral mass). So the real shift is
10 x 1.00045475 = **10.0045475 m/z**. Shifting by integer units would put the decoy off
the peptide mass-defect line, making it distinguishable from a real peptide by m/z alone
-- a systematic handicap of exactly the kind that produced the b<->y result.

My first C and D runs used a flat +10.0, so **they are not faithful and their numbers
(3.19% / 20.40%) are likely pessimistic**. Re-ran as C2/D2 after changing the knob to
`OSPREY_DECOY_PRECURSOR_SHIFT_UNITS` (integer units x `MassPeptideInterval`).

### The three-axis picture, and why Skyline shifts at all

Brendan: the shift was Dario Amodei's innovation, not carried by other mProphet
implementations. Intent was (a) make it likely the decoy's fragments come from a
DIFFERENT MS/MS isolation window than its target, and (b) stop the decoy inheriting good
MS1 signal at the target's unchanged predicted RT.

| | fragment intensity map | decoy RT | precursor m/z |
|---|---|---|---|
| Osprey gendecoy | b<->y swap (broken) | copied from target | **same as target** |
| Skyline | same ion | copied via `SourceKey` | **shifted** |
| Carafe libdecoy | model-predicted | **independently predicted** | same as target |

Osprey's decoy keeps the target's precursor m/z AND the target's RT, so its MS1 evidence
IS the target's own MS1 peak -- a free pass making decoys look too good, running opposite
to the b<->y swap making them look too bad. The two partially cancel.

Carafe breaks the MS1 coincidence via RT (a reversed sequence gets its own predicted RT).
Skyline cannot (it copies RT), so it breaks it via the precursor shift. **Osprey adopted
Skyline's RT-copying without Skyline's compensating shift.**

Prediction recorded before the C2/D2 numbers landed: a faithful shift should make
**C2 beat B**, reversing the unfaithful-shift ordering.

### 2026-07-25 - C2/D2: the mass-defect fix is a no-op here, and my prediction was wrong

C2 is **byte-identical to C** (`stellar_fdrbench.tsv` compares equal), and D2 to D. On
unit-resolution Stellar with 4 m/z windows, 4.5 mDa is below every threshold that
matters: window assignment, fragment binning (fragments are not shifted at all), and the
precursor tolerance. So the earlier C/D numbers stand as measured, and my claim that the
integer shift made them pessimistic is **refuted**. The fix was still correct to make --
at Astral HRAM ppm tolerances 4.5 mDa is ~7.5 ppm at m/z 600 and would matter -- but it
is immaterial on this dataset.

Final table, all cells faithful:

| cell | ion map | precursor | coin (ent) | FDP @ 1% q | accepted |
|---|---|---|---|---|---|
| libdecoy (Carafe) | model-predicted | same | 0.5007 | **1.47%** | 30,242 |
| B: same ion, no shift | same | same | 0.4733 | **2.40%** | 32,329 |
| C2: Skyline faithful | same | +10 units | 0.4600 | **3.19%** | 33,447 |
| A: Osprey today | b<->y swap | same | 0.2051 | **10.86%** | 35,477 |
| D2: swap + shift | b<->y swap | +10 units | 0.1949 | **20.40%** | 48,276 |

**The recorded prediction (C2 beats B) is falsified.** The shift makes calibration WORSE
in both rows. Plausible mechanism: a shifted decoy is extracted from a window whose
co-isolated species its target never faced, so it samples a less competitive environment
than a real false target does -- a weaker, less representative null. This is not a
refutation of Dario's design intent, which was formed in a different scoring context;
it is a measurement inside Osprey's DIA feature set and Percolator SVM.

**The RT axis remains untested and is the likely home of the residual gap.** Every
variant run so far copies the target's RT. Carafe is the only cell that breaks the RT
coincidence (a reversed sequence gets its own predicted RT) and the only one under 2%.

### 2026-07-25 - Quote Pass 1, not Pass 2 (Brendan's directive)

Every FDP number above is **Pass 2 - experiment-wide**, which is the inflated view: the
pass-2 Percolator retrain is known to inflate FDR
([[project_osprey_pass2_recalibration_inflates_fdr]]) and is being replaced by `transfer`
or `transfer-compete`. `percolator` remains the shipped default only because the choice
between the two transfer methods is unmade and switching needs new golden training. So
pass-2 FDP overstates the true error rate for every cell, and the decision must rest on
Pass 1.

Pass 1 available so far (only the two Jul-6 reference runs carry Pass 1 views):

| cell | Pass 1 FDP | reported q | accepted |
|---|---|---|---|
| libdecoy (Carafe) | **0.90%** | 0.0099 | 26,775 |
| A: Osprey today | **11.81%** | 0.0098 | 35,627 |

On Pass 1 the Carafe reference is essentially calibrated -- in fact slightly BELOW the
line (0.90% at a claimed 0.99%) -- which sharpens the comparison rather than weakening it.

The B/C2/D2 runs used `--fdrbench-pass 2` (copied from the reference command line) and so
emitted only Pass 2 views. Re-running B/C/D plus an A baseline on the current binary with
`--fdrbench-pass both` (dirs `*-A3/B3/C3/D3-*`); A3 doubles as a control that the current
binary reproduces the Jul-6 reference.

Brendan's read of the diagnostics, which the data supports: the b<->y swap is the biggest
issue, and the 2016 Navarro multicenter standard was NOT similarly 10x off in its FDR
estimation.

### 2026-07-25 - DEFINITIVE Pass 1 table

Parser root cause first: reports from the current binary carry **two** `fdpViews` arrays
(FirstJoinTask writes one blob, MergeNodeTask appends another) and the passes are split
across them -- the FIRST blob holds Pass 2, the SECOND holds Pass 1. The extractor used
`html.find('"fdpViews"')`, took only the first, and therefore reported Pass 2 while
concluding "Pass 1 is absent" for B/C2/D2. Older reports use a single blob with all four
views, which is why the references worked. Fixed to scan and merge every array; B then
reads 1.47% @ 28,490, matching the rendered report exactly.

Same structure explains the two paired-coin blocks: the large one sits in the Pass 1
blob, so **the coin numbers reported earlier were already Pass 1** -- that open question
is closed.

| cell | ion map | precursor | Pass 1 coin | **Pass 1 FDP @1% q** | discoveries |
|---|---|---|---|---|---|
| libdecoy (Carafe) | model-predicted | same | 0.5007 | **0.90%** | 26,775 |
| B: same ion, no shift | same | same | 0.4733 | **1.47%** | 28,490 |
| C2: Skyline faithful | same | +10 units | 0.4600 | **1.96%** | 29,454 |
| A: Osprey today | b<->y swap | same | 0.2051 | **11.81%** | 35,627 |
| D2: swap + shift | b<->y swap | +10 units | 0.1949 | **14.96%** | 37,145 |

1. **The b<->y swap is the whole problem**: 11.81% -> 1.47% from that one change (8x).
   A's 11.81% reproduces the issue's "12-16%" figure, confirming the measurement.
2. **The 2016 Navarro multicenter standard was NOT similarly off**: Skyline's construction
   is ~2x over the line (1.96%) against Osprey's ~12x.
3. Carafe remains best and slightly conservative (0.90%).
4. The precursor shift costs a little on both rows (1.47->1.96, 11.81->14.96), so on this
   DIA data it is a small net negative inside Osprey's feature set.

### 2026-07-25 - Null-alignment density ratio: how to read it, and what it says

The report's "Null-alignment density ratio (non-parametric)" panel answers "is there a
slight shift between the target-false distribution and the decoys / entrapment?".

* **purple = target : decoy** density ratio per score bin (log axis). Flat across the
  null-dominated left region means the decoys track the false-target null in SHAPE;
  sloping means they do not. It rises where real hits begin -- healthy.
* **green = p_target : p_decoy** -- entrapment target vs its own decoy, both known-false,
  so it is a MATCHED NULL: what the statistic looks like when the null is honest by
  construction. It should ride ~1 flat and never rise (entrapment has no true hits).
* HTML keys: `flatnessSlope` (the "tilt" tile), `refFlatnessSlope` (reference tilt),
  `plateauRatio` (pi0), `nullRegionLo/Hi/Bins`, and `pass`.

Pass 1 values (`read_tilt.py`; B3 == B and C3 == C2 exactly, so reruns reproduce):

| cell (Pass 1) | tilt | pi0 | ref tilt | tilt / ref |
|---|---|---|---|---|
| B: same ion, no shift | 0.305 | 0.682 | 0.179 | **1.70x** |
| C2: Skyline faithful | 0.411 | 0.637 | 0.306 | **1.34x** |
| D2: swap + shift | 4.421 | 0.091 | 4.254 | 1.04x |

So yes -- B has a slight residual shift, ~1.7x the floor set by the matched null. That
residual is the natural suspect for B's 1.47% vs Carafe's 0.90%.

Two reading cautions:
* **The ratio is only meaningful when the reference tilt is small.** D2's tilt (4.42) is
  enormous but so is its floor (4.25), so the ratio collapses to ~1 and looks fine. It is
  not: `pi0` = 0.091 (only 9% of targets appearing null) shows the statistic has gone
  degenerate. Do not read D2's 1.04x as healthy.
* **This is a MARGINAL check**, as the panel states: a target-side score boost that leaves
  the decoy and entrapment marginals intact is invisible here. The paired decoy-win
  fraction covers exactly that, which is why the two are complementary, not redundant.

Gap: the panel postdates the Jul-6 reference reports, so there is no tilt for A (Osprey
today) or for libdecoy (Carafe), the honest reference. A3 is in the running batch;
`Run-LibdecoyRef.ps1` queues a Carafe re-run on the current binary
(`_mdiag/stellar-L3-libdecoy`).

### Next

- [ ] Decide the real fix: make same-ion-map the Osprey default (a golden rebaseline,
      since generated-decoy output changes) rather than hard-gating gendecoy
- [ ] Decide whether B's residual 2.4% (vs libdecoy 1.47%) still justifies preferring
      library decoys by default, even with the swap fixed
- [ ] Cross-check variant B against the FDRBench jar (`Run-FdrBench.ps1 -DecoySource
      Generated`) rather than the in-process curve alone, before any code decision
- [ ] Decide whether to file the Skyline issue on the weaker (3.2% vs 1.5%) evidence
- [ ] Confirm what the small-population first block in the report actually is, and
      whether the report should label the two blocks more clearly
- [ ] Item 4 (move the regression onto libdecoy) still stands on its own merits
