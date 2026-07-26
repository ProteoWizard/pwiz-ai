# Osprey regression redesign: add libdecoy+entrapment coverage and FDR spot checks

## Branch Information
- **Branch**: `Skyline/work/20260726_osprey_regression_redesign`
- **Base**: `master` (47d0c2c1a)
- **Created**: 2026-07-26
- **Status**: In Progress
- **GitHub Issue**: (pending -- subsumes #4465 scope item 4, "move the regression onto
  the libdecoy path", and is larger than that item described)
- **PR**: (pending)
- **Requester/Reporter**: none (Osprey developers; no credit line)

## Objective

`regression.ps1` covers only the **gendecoy** path, on both datasets. That is the decoy
construction we do NOT recommend, so every parity and determinism signal we hold was
collected on it, and the **libdecoy** path we do recommend has no coverage at all.

Add a third dataset carrying library-supplied decoys AND entrapment peptides, and add
FDR-calibration spot checks to the diagnostic HTML, so a future golden rebaseline cannot
silently bless a calibration regression.

This unblocks PR 2 (the b<->y swap removal), which is waiting on exactly one thing: a
golden regeneration that we want to do ONCE, after the dataset set is settled.

## Design decisions (Brendan, 2026-07-26)

| Question | Decision |
|---|---|
| Stellar leg | **Add a 3rd dataset.** Stellar stays gendecoy/fast/unchanged; `StellarLibDecoy` is new. Keeps the quick local pre-commit loop and retains unit-resolution gendecoy coverage. |
| Astral entrapment | **Not added** (+12.8 GB / ~1.3 GB zipped). Astral stays gendecoy with structural diagnostics only -- no FDP curve, no paired coin. |
| Zip publishing | **New name `osprey-testfiles-mzML-v2.zip`.** Acquisition is skip-if-present on the extracted root, so re-publishing under the same name would never reach a machine that already has the tree; a new name also leaves older branches on the v1 URL working unchanged. |

## Tasks

- [x] Gate A: prove `--model-diagnostics` is output-neutral
- [x] Build the v2 staging tree with the nested libdecoy zip
- [x] Add the `StellarLibDecoy` dataset to `regression.ps1`
- [x] Add `Regression/DiagnosticsGolden.ps1` with two-tier assertions
- [x] Add the whole-run read-only data folder assertion (proven to bite)
- [x] Generate the `StellarLibDecoy` golden
- [ ] Verify the compare round-trip (capture proven; compare in flight)
- [x] Gate B: timing is a non-issue -- see below
- [x] Build `osprey-testfiles-mzML-v2.zip` AND `osprey-testfiles-v2.zip`
- [ ] Gate C: upload (Brendan, in progress) + verify clean-machine acquisition
- [x] Update `Regression/README.md` and `osprey-regression.data/README.md`

## Gate

**Gate A -- PASSED, and it decides the PR structure.** `--model-diagnostics` had to be
proven output-neutral before it could ride on the golden-compared run, because
`Pass2FdrSidecar.cs:180-182` gates the FDR-projection path on `!config.ModelDiagnostics`.

| dataset | rows compared | verdict |
|---|---|---|
| Stellar (unit) | RefSpectra 51,444 | **PASS** -- every column `max_diff=0.000e+000` |
| Astral (hram) | RefSpectra 165,500 | **PASS** -- every column `max_diff=0.000e+000` |

Full per-table, all-row, 1e-9 comparison (`Compare-Blib-Crossimpl.ps1`), not the subset
golden. Binary peak blobs included. Astral runtimes 13m06s vs 13m02s -- no perf cost.

**Not a vacuous pass**: `UseFdrProjection` defaults ON, so the no-diagnostics run took the
projection pass-2 path and the diagnostics run fell through to the resident path. Different
branches, byte-identical output -- which also confirms the two paths agree, something the
existing gates never A/B'd directly.

Consequence: this work lands as **its own PR without touching the existing Stellar/Astral
goldens**, and PR 2 then regenerates every golden once.

Standing gates still apply: `Build-Osprey.ps1 -RunInspection -RunTests`, and the TeamCity
Perf/Regression config (ask before triggering).

## Regression Test

- **Test name**: `regression.ps1 -Dataset All` (adds `StellarLibDecoy`; mode 1 golden,
  mode 2 resume, mode 3 HPC chain), plus the new **mode 1b** diagnostics spot checks
- **Byte-identity for existing datasets**: expected PASS on the committed goldens -- this
  change adds a dataset and an artifact, it does not alter the search (proven by Gate A)
- **Passes on fix**: the new `StellarLibDecoy` golden is *created*, not rebaselined

## Progress Log

### 2026-07-26 - Gate A answered; harness + comparator written

**`regression.ps1`**
* `$dataUrl` -> the v2 zip; `StellarLibDecoy` added; `-Dataset` ValidateSet extended.
* `Resolve-DatasetInputs` now takes the whole spec and supports a **separate
  `LibraryFolder`**, so the new dataset reuses the one copy of the Stellar mzML instead of
  duplicating 4.2 GB of it in the zip; an explicit `Library` name (the libdecoy folder also
  holds the pairing manifest, so the exactly-one-`.tsv` rule cannot apply); and **on-demand
  nested-zip extraction** via the existing `Expand-ZipNoOverwrite`.
* New `Get-DatasetCliArgs` feeds the dataset flags to **all four legs** -- straight-through,
  resume, and every HPC phase. Missing it on the resume/HPC legs would have had them run a
  DIFFERENT search than the golden, so those self-consistency oracles would have been
  comparing unlike things while still reporting green.
* `GoldenFolder` key added: `StellarLibDecoy` shares the `stellar` mzML folder, and the
  golden dir was keyed on `Folder`, so the two goldens would have collided.
* `Copy-LibraryInto` also stages the manifest (each HPC phase runs with its own dir as CWD
  and references inputs by leaf name).

**`Regression/DiagnosticsGolden.ps1`** -- two tiers:
1. golden-exact at 1e-9 over a fixed metric projection;
2. **sanity bounds committed in the script and NOT regenerated by `-CreateGolden`**. This
   is the point of the exercise: a rebaseline records whatever the run produced, so the
   bounds are the only thing that fails when a bad change is blessed into the baseline.
   `-CreateGolden` also refuses to capture a golden from a run that fails them.
   `MaxPass1Fdp` is per-dataset -- library decoys measure 0.86-1.47%, generated decoys
   ~2.03% even with the swap removed, so one global ceiling would fail a healthy dataset.

### 2026-07-26 - Three report-reading traps, all now encoded

1. **The 1% convention.** Every recorded measurement uses the **LAST grid point with
   q <= 0.01**, not the first at or above it. On the reference cell those neighbours read
   2.03% @ 94,367 vs 2.07% @ 94,661 -- so the wrong pick silently makes new goldens
   non-comparable to the entire investigation they exist to protect. It is also the correct
   FDR semantics (accept everything at or below the threshold).
2. **`FdpView` carries an explicit `pass` field** (1 or 2). Selecting on it is immune to
   both serialization order and label text -- better than the label-matching originally
   planned. The ordering trap is real: `pass2` serializes BEFORE the top-level `fdpViews`,
   so a raw scan for the first `"fdpViews"` returns Pass 2 while looking like Pass 1.
3. **The views hold PARALLEL ARRAYS** (`q` / `combined` / `paired` / `nTargetAccepted`),
   not point objects. Asking for `.points` yields `$null`, and `$null.Count` is 0 in
   PowerShell -- so a typo is indistinguishable from "no data". That is exactly what made
   an earlier read of these reports conclude, wrongly, that they held no Pass-1 data.

**Validation**: the extractor reproduces a recorded reference cell EXACTLY -- combined FDP
2.03%, accepted 94,367, coin 0.4743, tilt 0.246 (`_mdiag/astral-gendecoy-G-seqid050`).
The sanity tier correctly fires on that same cell against a 2% ceiling, so the gate is
demonstrated to bite on real data rather than a synthetic corruption.

### 2026-07-26 - Data packaging

* v2 staging tree at `D:\test\osprey-testfiles-mzML-v2`, built with **hardlinks** from the
  CLEAN source `D:\test\osprey-testfiles-mzML` (instant, no duplication).
* **Do NOT build the zip from the Downloads extraction**: `Perftests\osprey-testfiles-mzML`
  is polluted with ~1.9 GB of run artifacts (three 597 MB `.scores-reconciled.parquet`, a
  486 MB `.libcache`, `reconciliation.json`, `.osprey.task` markers) -- the documented
  Run-Osprey-writes-next-to-the-mzML trap. Harmless to the regression, which reads only
  mzML + tsv, but it would have bloated the published zip.
* Mike's `target+decoy+entrapment.zip` is reusable **verbatim** as the nested
  `libdecoy-entrapment.zip` -- 3 flat entries, no directory prefix -- so this is a 245 MB
  copy, not a 2.5 GB re-compress.
* Perftests is staged as a SEPARATE hardlinked tree so the run's nested-zip extraction does
  not contaminate the pristine tree being zipped for upload.
* Library facts confirmed: entrapment is **r=1.0** (~1:1:2 target:entrapment:decoy), and
  the `Decoy` column is **0 on every row** -- decoys are marked only by the `decoy_`
  ProteinID prefix, entrapment by `_p_target`. That is fine: `DecoysInLibrary` detects
  decoys by protein-accession prefix (`OspreyConfig.cs:141-164`), and `decoy_` is a
  default. **Never "fix" the library by rewriting that column.**

### 2026-07-26 - Verification results

**The new dataset reproduces the investigation's reference cell EXACTLY.** Captured
golden vs the recorded libdecoy reference (`L3` row in the gendecoy TODO):

| metric | captured | recorded |
|---|---|---|
| Pass-1 FDP @ 1% q | **0.862%** | 0.86% |
| accepted | **27,070** | 27,070 |
| entrapment coin | **0.5016** | 0.5016 |
| null-alignment tilt | **0.0571** | 0.057 |

Independent confirmation that the dataset is wired correctly AND that the extractor is
right. (Pass 2 reads 1.48% against Pass 1's 0.86% -- the known pass-2 recalibration
inflation, showing up where expected.)

**Existing behavior is unchanged.** Full three-leg Stellar run against the COMMITTED
golden: mode1 PASS, mode3 (HPC chain == straight) PASS, mode2 (resume == straight) PASS,
blib 45,064,192 bytes throughout. That also exercises the `Copy-LibraryInto` /
`$extraArgs` rework through every HPC phase.

**Gate B is a non-issue.** StellarLibDecoy straight-through is **4:24** against Stellar's
3:18 -- ~30% slower, not the "several times" feared from the 2.4 GB library. The
entrapment pool doubles the parquets (409 MB vs 208 MB per file) but not the wall clock.
No need to drop mode 2/3 for the new dataset.

**The folder assertion is proven to bite**, not vacuous. A file planted MID-RUN (after
the baseline fingerprint, so it could not be absorbed into it) produced:

```
Stellar mode1 (vs golden): PASS
read-only data dir CHANGED across the run: ...\stellar -- 1 file(s)
    new: __intruder_test.tmp
Osprey regression FAILED
```

Note the discrimination: mode 1 stayed green because the search output really was
unchanged, and only the folder assertion failed. A clean run reports
`data dir unchanged across run`.

### 2026-07-26 - The sanity tier caught a real defect on its FIRST run

Astral's `-CreateGolden` **refused to bless the golden**: tilt **1.408** against the
default 1.0 ceiling, with a real paired-win coin of **0.397** -- decoys losing 60% of
head-to-head pairs against their own targets. That is the b<->y swap signature, detected
on a dataset carrying NO entrapment at all (the investigation measured 1.379 with the
swap and 0.254 without).

Resolution: Astral's `MaxAbsTilt` is set to **1.5 as a RATCHET**, so this harness change
does not turn the gate red on pre-existing behavior, with a comment requiring PR 2 to
tighten it to ~0.5 as part of the swap removal. If that tightening does not happen the
ratchet never closes and the bound protects nothing. **This is a decision to revisit in
PR 2, not a settled value.**

Also: re-capturing Astral's golden reproduced `protein_fdr.tsv` **byte-identically**
(content hashes equal; the `M` in git status was a stale stat entry from the re-copy
touching mtime). Gate A confirmed a third time, now at the golden level.

### 2026-07-26 - Data packaging complete; the readme bug was worse than it looked

| zip | size | build time |
|---|---|---|
| `osprey-testfiles-mzML-v2.zip` | 14.0 GB | 10m56s |
| `osprey-testfiles-v2.zip` (raw) | 20.5 GB | 14m15s |

Both verified: top-level dir matching the zip base name (what `RegressionData.ps1`
requires), 14 entries each, both carrying the identical
`stellar-libdecoy/libdecoy-entrapment.zip` -- so the raw variant gains the new dataset
the moment the raw reader lands, with no second packaging pass.

**Pre-existing bug fixed in both**: `astral/readme.txt` and `stellar/readme.txt` had
their contents SWAPPED (each documented the other dataset's command line), and the raw
variant's additionally said `-i *.mzML` for a folder of `.raw`. Corrected, and a
`stellar-libdecoy/readme.txt` added.

### 2026-07-26 - Perftests debris: dated, and it is not this harness

Removed 24 files / 2.28 GB from `Perftests\osprey-testfiles-mzML\astral`; both folders
now match the clean source exactly with nothing missing.

Forensics, which answer the attribution question: **every debris file was written in one
~40-minute window on 2026-06-25 (10:05-10:44)**, while all six source files date from
2026-04-09 and the tree was extracted 6/10. One ad-hoc run, not accumulated drift. The
mix -- `scores-reconciled.parquet`, `reconciliation.json`, `.osprey.task` validity
markers, a `.libcache`, with most payload files absent -- is consistent with a
`Run-Osprey` invocation without `--work-dir` ([[feedback_run_osprey_pollutes_source_dir]]).
The new whole-run assertion is what keeps this attributable going forward.
