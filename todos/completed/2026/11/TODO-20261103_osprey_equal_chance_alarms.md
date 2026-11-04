# TODO-20261103_osprey_equal_chance_alarms.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_equal_chance_alarms`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: Completed
- **GitHub Issue**: [#4464](https://github.com/ProteoWizard/pwiz/issues/4464)
- **Module**: `osprey`
- **PR**: [#4989](https://github.com/ProteoWizard/pwiz/pull/4989) (merged 2026-11-04)
- **Worktree**: `C:\proj\wt-manifest` (agent G, night session 2026-11-03)

## Objective

The diagnostics-only slice of #4464: automated equal-chance detectors in `--model-diagnostics`
ONLY. (A) a decoy-independent `f_false` null from a two-component Gaussian mixture fit of the
target composite score, with an ill-conditioning guard; (B) decoy-vs-`f_false` location/scale
mismatch plus a binned symmetric divergence, diagFDR's q-band decoy-fraction check, and a KPI
badge; (C) the paired-coin alarm when entrapment is present; (D) decoy support at the operating
cutoff with a "granular regime" badge.

Out of scope this round (brief): no console warning on the FDR path, no edits under
`Osprey.FDR` or `Osprey.ML`, no `OSPREY_BOOST_TARGET_DISCRIMINANT` instrument (F), no E
(comparative entrapment alarm), no decoy-null size floor (#4363 territory).

## Design (as built)

- `Osprey.Tasks/ModelDiagnostics/EqualChanceMixtureFit.cs`: two-Gaussian EM on the binned
  target (real + entrapment) composite histogram, four deterministic quantile starts, variance
  floored at bin-width variance; lower-mean component = `f_false`.
- `Osprey.Tasks/ModelDiagnostics/EqualChanceAlarms.cs`: `EqualChanceThresholds` (every number in
  one place), `EqualChanceView` with four checks (nullAlignment, qBandBalance, pairedCoin,
  decoySupport), each `ok | alarm | cannot_assess | not_applicable`.
- `ModelDiagnosticsHtml.SerializeData` splices `equalChance: {pass1, pass2}` into the page JSON
  at render time; sidecars unchanged, so `--task ModelDiagnostics` re-renders carry it.
  `TestReportJsonIsAdditive` pins that every other key is byte-for-byte what it was.
- Template: "Equal-chance alarms" card on the Summary tab (KPI badges + table + note),
  re-sourced by the Pass 1 / Pass 2 switch.
- Docs: `pwiz_tools/Osprey/docs/equal-chance-diagnostics.md` (new; README row). A new page
  rather than a section of `fractional-entrapment.md`, to stay clear of agent A's #4489 edits.
- Pass 2 has no retrained model (#4528), so its null-alignment / q-band checks are n/a; the
  card says to read them on pass 1. Pass-2 decoy support reads the final per-file counts.
- Decoy support (D) is per-run `D_alpha` from `perFile[].decoys`. diagFDR's boundary window
  `(alpha, 1.2 alpha]` needs per-entry q that the report's reduced views do not carry; it would
  need an FDR-side accumulator change (off-limits this round), so it is not computed.

## Thresholds (calibrated before wiring)

Probe on earlier regression JSONs (copies in `ai/.tmp/sessions/20261103-agentG/json`):
libdecoy location -0.10 sigma, gendecoy -0.18; entrapment -0.10 / -0.07 (validates `f_false`);
q-band 46.2% / 43.9%; entrapment coin 50.1% / 46.7%; per-run D_alpha 230-1000. Chosen:
|location| > 0.5 sigma or scale beyond x1.5; |delta_balance| > 0.15 (issue); |coin - 50%| > 10
points; granular below 50 decoys (FDP CV 20%). Nothing trips on today's gendecoy: it is close
to calibrated now (entrapment FDP ~1.2% at 1% q in pass 1); the issue's 22% coin predates the
decoy-generator fixes. Astral's mixture is not separated (Ashman D 0.32) -> cannot assess.

## Tasks

- [x] Prototype metrics on existing regression diagnostics JSONs (calibrate thresholds)
- [x] `Osprey.Tasks/ModelDiagnostics/EqualChance*.cs`: data model, mixture fit, alarms, constants
- [x] Attach `equalChance` (additive JSON key) at render time; report card + badges
- [x] Unit tests (synthetic histograms) - `Osprey.Test/EqualChanceAlarmsTest.cs`
- [x] Docs page with definitions
- [x] Build-Osprey -RunTests -RunInspection (651/651, 0 warnings)
- [x] regression-parallel Stellar, StellarLibDecoy, StellarGenDecoyEntrap; read badges on each
- [x] /code-review medium (triage below)
- [x] PR #4989

## Progress Log

### 2026-11-03

- Read the brief, the issue and its 2026-09-18 status comment.
- Constraint found: the data model (`ModelDiagnosticsData`) lives in `Osprey.FDR`, which is
  off-limits. So the detectors are a pure derivation over the already-built data
  (`scores` histogram, `winFraction`, `perFile`) computed in `Osprey.Tasks` at render time,
  and spliced into the page JSON as a new top-level `equalChance` key. No sidecar or FDR change.

### Code review (/code-review medium), 9 findings

Fixed: unconverged fits now report the weight/separation reason first (`not_converged` last);
a null fit reports a new `degenerate` guard; no-decoy input is `not_applicable` before the
target-count guard; the template's null-alignment row explains `not_applicable`; the duplicate
moment code is one `EqualChanceMixtureFit.Moments`; `QBAND_BREAKS` is read-only.

Dropped:
- "Use the exact DecoyMean/DecoyStd": deliberate. `f_false` is fitted on the binned, clipped
  histogram; the decoys are measured on the same bins so both sides share truncation. Comment added.
- "Coin pair count misses the partial bin": the count only gates `cannot_assess` at 100 against
  ~200k pairs on real data; counting bins by center is a documented lower bound.
- "JObject doubles serialization memory": the page data is ~200 KB; not worth a writer rewrite.

### Gates

- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`, after the review fixes:
  651/651, 0 inspection warnings (`ai/.tmp/sessions/20261103-agentG/gate2.log`).
- `regression-parallel.ps1 -Dataset Stellar,StellarLibDecoy,StellarGenDecoyEntrap` at 6664e8a0a7:
  35 PASS / 0 FAIL in 35:46, goldens unchanged (`ai/.tmp/sessions/20261103-agentG/regression-gate.log`).
  The review-fix commit touched only the report derivation, not pipeline output.
- Badges, pass 1 (pass 2: null alignment / q-band / coin n/a, decoy support ok on all):
  - Stellar (rendered after the gate with `--task ModelDiagnostics`, `OSPREY_VERSION_OVERRIDE=26.1.1.0`):
    0 alarms. Null alignment ok, location -0.30 sigma, scale 0.93, Ashman D 3.00; q-band 46.3%;
    coin n/a (no entrapment); min run D_alpha 261.
  - StellarLibDecoy: 0 alarms. Location -0.10, scale 0.95, D 3.24; entrapment -0.10; q-band 46.2%;
    coin 50.1%; D_alpha 230.
  - StellarGenDecoyEntrap: 0 alarms. Location -0.18, scale 0.98, D 2.13; decoys -0.11 below
    entrapment; q-band 43.9%; coin 46.7%; D_alpha 239.
  - Reports under `C:\proj\wt-manifest\pwiz_tools\Osprey\TestResults`:
    `regression-20261103_161227_125652/Stellar/straight`, `regression-20261103_162102_125652/StellarLibDecoy/straight`,
    `regression-20261103_161227_34604/StellarGenDecoyEntrap/straight` (`output.model-diagnostics.html`).

### For Brendan

- No alarm fires on any gate dataset: the gendecoy that motivated the issue (22% coin) is
  calibrated now. The guard path is exercised on Astral (not separated). The thresholds are
  untested against a real positive; the `OSPREY_BOOST_TARGET_DISCRIMINANT` instrument (F, held
  this round) is the way to produce one.
- Thresholds chosen without an issue number: location 0.5 sigma, scale x1.5, coin 10 points,
  granular 50 decoys. All in `EqualChanceThresholds`.

### 2026-11-04 - Merged

PR #4989 merged as commit 0bec7caeef. Shipped: EqualChanceMixtureFit and EqualChanceAlarms (A+B null alignment and q-band balance, C paired coin, D decoy support) under a new equalChance JSON key, the Summary-tab card, docs/equal-chance-diagnostics.md; goldens unchanged on all three gate datasets; merged after a master merge that brought in the #4987 per-k card (one docs/README.md conflict, both cards confirmed in a re-rendered Stellar report). Deferred: the FDR-path console warning, E, F, diagFDR's boundary window, the decoy-null size floor (#4363). No alarm has yet fired on real data; the thresholds are the agent's numbers. #4464 stays open (Partially addresses).
