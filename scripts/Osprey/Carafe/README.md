# Carafe library generation

Build Osprey spectral libraries ourselves, from a protein FASTA, instead of
depending on a delivered drop. Also builds the natural (foreign-species)
entrapment variant used for FDR-calibration work.

Full recipe, prerequisites, validation numbers, and open questions:
**[`ai/docs/osprey-library-generation-guide.md`](../../../docs/osprey-library-generation-guide.md)**.

## Layout

```
ai/scripts/Osprey/Carafe/
  README.md                        (this file)
  Run-CarafeOspreyWorkflow.ps1     6-stage end-to-end driver (Carafe + Osprey)
  tools/
    make_natural_entrapment.py     swap shuffle entrapment -> matched foreign peptides
    occupancy_test.py              precursor m/z saturation measurement
```

## Quick start

```powershell
# 1. Confirm this machine has the tools, and see what resolved. No work done.
pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 -Preflight

# 2. Full Stellar rebuild with the stock shuffle entrapment (~40 min + copies).
pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 -Dataset Stellar

# 3. Cheap smoke test: digest only, no mzML copy, no GPU.
pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 -Stages 1a,1b
```

## Stages

| Stage | What | Cost |
|---|---|---|
| `1a` | Digest FASTA -> target+decoy training peptides (entrapment-free) | seconds |
| `1b` | Digest FASTA -> target+decoy+entrapment quartets | seconds |
| `1c` | Replace 1b's shuffle entrapment with matched foreign peptides | ~1 min |
| `2` | Carafe predicts a GENERIC library from 1a | GPU, ~4 min |
| `3` | Osprey searches ONE training run with it -> blib | ~8 min |
| `4-5` | Carafe fine-tunes RT+MS2 on that blib, predicts the FINAL library from 1b/1c | GPU, ~12 min |
| `6` | Osprey searches ALL runs with the final library (+ FDRBench input) | ~13 min |

Timings are Stellar on an RTX 4070. Astral is several times larger.

Fine-tuning trains on the entrapment-FREE database on purpose - the RT and MS2
models never see entrapment sequences. The entrapment database is used only to
*predict* the final library.

## Natural (foreign-species) entrapment

Replaces Carafe's shuffle entrapment with real peptides from a distant species,
mass-matched 1:1 to each human target. Shuffle entrapment is an anagram of its
target, so it shares the target's exact fragment masses and gets over-identified;
real foreign peptides do not. See the guide for the measured effect.

```powershell
pwsh -File ./ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 `
    -Stages 1b,1c,4-5,6 -EntrapmentSource natural -EntrapmentRatio 0.1 `
    -ForeignFasta D:\test\entrapment\arabidopsis\UP000006548.fasta
```

`-EntrapmentRatio` below 1.0 makes the entrapment a small overlay rather than
half the library, which measures FDP without perturbing the target search.

Stage 1c is **idempotent**: it restores `*.shuffle.bak` before rewriting, so
re-running it never draws foreign peptides against an already-foreign manifest.

## Machine configuration

Everything resolves from parameters first, then environment variables, then
conventional locations. `-Preflight` prints what resolved.

| Variable | Meaning | Default searched |
|---|---|---|
| `OSPREY_CARAFE_JAVA` | JDK 21+ `java` | `JAVA_HOME`, PATH, bundled JetBrains JBR |
| `OSPREY_CARAFE_JAR` | Built `carafe.jar` | `<root>/Carafe-mm/target/carafe-*/carafe-*.jar` |
| `OSPREY_CARAFE_VENV_PYTHON` | AlphaPeptDeep venv python | `~/.carafe/.venv/...` |
| `OSPREY_CARAFE_ROOT` | Carafe checkout | `<project root>/Carafe-mm` |
| `OSPREY_CARAFE_WORKDIR` | Output root | `D:\test\carafe-repro` |
| `OSPREY_TESTFILES_DIR` | Read-only mzML/FASTA drop | `D:\test\osprey-testfiles-mzML` |

Osprey itself resolves through `Dataset-Config.ps1` (`Get-OspreyExe`), so
`PWIZ_ROOT` / `OSPREY_PROJECT_ROOT` work here as they do elsewhere.

## Related

- [`ai/docs/osprey-library-generation-guide.md`](../../../docs/osprey-library-generation-guide.md) - the recipe and its validation
- [`../SEA-AD/New-SeaAdLibrary.ps1`](../SEA-AD/New-SeaAdLibrary.ps1) - *derive* a variant
  (entrapment ratio subset, decoy strip) from an existing library, no Carafe needed.
  Use that when you already have a library; use this folder when you need a new one.
- [`../Run-FdrBench.ps1`](../Run-FdrBench.ps1) - the FDP oracle that consumes stage 6's
  `FDRBench-Input.tsv`
