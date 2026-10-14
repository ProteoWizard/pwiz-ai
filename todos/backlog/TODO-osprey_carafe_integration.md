# TODO-osprey_carafe_integration.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_osprey_carafe_integration`
- **Module**: `osprey`
- **Depends on**: CarafeSharp in `pwiz_tools/CarafeSharp` (PR #4717)
- **Related**: `TODO-carafe_osprey_library_contract.md` (the library Carafe writes and Osprey loads,
  with one shared validator). This TODO is the other half: the training records Osprey writes and
  Carafe trains on, and running the two as one pipeline.
- **Objective**: Osprey and CarafeSharp work as one tool from the user's side: given a FASTA and the
  runs to search (and optionally separate runs to train on), Osprey builds, searches, fine-tunes and
  re-searches in one command, using CarafeSharp's classes in-process rather than running Carafe.

## Why (Brendan, 2026-10-13)

Osprey has to win over users of fully integrated tools (DIA-NN, Spectronaut), who supply a FASTA and
their runs and get results. Today the lab's workflow is four steps across two tools (Mike, 2026-10-12:
"1) generate the library as the default model, 2) search the middle file, 3) fine tune the library and
4) search all 3 files. This is basically the lab workflow we use for everything."), driven by
`ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1`. The lab commonly trains on part of the search
data, not the whole dataset (Brendan's concern: overtraining when the training runs are also searched).

The training records are not an interface between two tools: Osprey writes a report whose content the
training defines. The dependency runs from Osprey to the training side, not the reverse.

## What PR #4717 leaves (2026-10-13)

The training export schema is defined twice, by hand, with nothing shared:
- **Writer**: `pwiz_tools/Osprey/Osprey.IO/TrainingExportParquet.cs` (columns, `FORMAT_VERSION = 2`),
  `Osprey.Tasks/TrainingExportWriter.cs` (footer keys: `osprey.rt_max`, `osprey.isolation_mz_min`,
  `osprey.ms2_scan_window`, `osprey.collision_energies`, ...), `Osprey.Core/TrainingRecord.cs` (ion flag bits).
- **Reader**: `pwiz_tools/CarafeSharp/CarafeSharp.IO/OspreyTrainingExport.cs` (about 40 column names, the
  footer keys, `FORMAT_VERSION = "2"` as a string), `OspreyTrainingRecord.cs` (`OspreyIonFlags`, the same
  eight bits value for value).
- **Shared by convention only**: the slot layout (`4*(L-1)`, `slot = p*4 + t`, Osprey `docs/22-training-export.md`),
  the position-0 N-terminal modification rule (`CarafeSharp.Training/OspreyModificationMapper.cs`), the
  FDRBench pairing manifest columns (`EntrapmentFastaBuilder.cs` writes, `Osprey.IO/DecoyPairingManifest.cs`
  reads), and the decoy rule (`EntrapmentSequences.cs` follows `Osprey.Scoring/DecoyGenerator.cs`).

A renamed column or a format bump fails loudly; a change of meaning without a bump (a flag bit reassigned,
slots reordered, a footer key's units) does not. Until this TODO lands, the nightly chained leg
(`regression.ps1 -Leg Chained`: the current Osprey writes an export, CarafeSharp reads it) is the guard; the
per-commit `TestRegressionSubset` reads a frozen export. PR #4717 deliberately added no stop-gap (a linked
constants file or a source-scraping test) that this design would undo.

## Design

### 1. One training-record assembly, owned by the training side

A small assembly (working name `CarafeSharp.Training.Records`, net10.0, no TorchSharp) holding:
- the record type (one per precursor per run) and its ion slots, flags and per-ion evidence;
- the schema: column names, footer keys, format version, slot layout, modification position rules;
- the Parquet writer and reader (both tools already use `Shared/Lib/Parquet/ParquetNet.targets`).

Osprey references it and writes records through it; CarafeSharp reads through it. Osprey's
`TrainingRecord`/`TrainingExportParquet` and CarafeSharp's `OspreyTrainingRecord`/`OspreyTrainingExport`
are deleted. Renaming or renumbering then changes both or fails the build. The pairing manifest's schema
belongs in it or beside it (see the library contract TODO, which wants a shared validator too; one shared
"Osprey-Carafe contracts" assembly may serve both).

### 2. In memory first; the file is the stage's checkpoint

The seam is a sequence of records per run: the training search produces it, the fine-tune consumes it.
`<stem>.training.parquet` stays, as that stage's rehydration file, like Osprey's other stage files, so a
lost machine loses no completed stage. The format version then guards resuming across builds rather than
compatibility between tools.

| Stage | Checkpoint (rehydration) |
|---|---|
| FASTA -> target/decoy/entrapment FASTA, pairing manifest | the FASTA and manifest (`-build_entrapment_fasta`) |
| Predict the starting library | `.blib` |
| Search the training runs | `<stem>.training.parquet` per run |
| Fine-tune | `.carafemodel` |
| Predict the final library | `.blib` |
| Search all runs | Osprey's existing stage files |

Each stage is a candidate Osprey task (`--task`) for the HPC chain, with its file contract declared (see
`TODO-task_file_contract_from_declarations.md`).

### 3. Keep libtorch out of Osprey's core

TorchSharp and libtorch are about 330 MB (CPU) and 4 GB (CUDA 12.8). `CarafeSharp.Models` and
`CarafeSharp.Training` stay separate assemblies, loaded only by the library stages, so a search with a
user-supplied library never loads libtorch, and Osprey's Linux and Windows packages can ship the CPU
runtime without the CUDA one. The GPU choice (`-device`) becomes an Osprey option. Note the
reproducibility work in #4717: the alignment reference predicts in float64 on the CPU, and the CUDA
generator is seeded, so a training stage repeats exactly on each system and device.

### 4. Command line

```
Osprey --fasta proteome.fasta --input run1 run2 run3 [--training-input run2] [--library existing.blib]
```
- No `--library`: Osprey builds one (stages above).
- No `--training-input`: decide the default with Mike. The lab trains on one run that is also searched
  ("search the middle file"); a default of "every search run" trains on all of them. Brendan's concern:
  training on the runs then searched risks overtraining, which the entrapment FDR should measure.
- `CarafeSharp.exe` stays as a thin front end for library-only use and Carafe command-line compatibility.

### 5. Shared infrastructure instead of reimplementations (survey 2026-10-13)

CarafeSharp references nothing in `Shared/` but the Parquet targets; it reimplements what the project already has,
and Osprey does too in places. Brendan (2026-10-13): too many ways of doing one thing give developers the chance to
pick the one where a bug was not fixed. Fold in, as part of this work:
- **One atomic file writer in CommonUtil.** Today there are three: Osprey's `Osprey.Core/FileSaver.cs` (a port of
  SharedBatch's, whose own comment proposes the move), CarafeSharp's `CarafeSharp.Core/PartialFile.cs` (a fixed
  `<name>.partial` temp that two processes writing one output would delete under each other; not `IDisposable`), and
  `CarafeModelFile.cs:145` (its own `.tmp` and move). Keep `PartialFile.CommitAs`'s "name (N)" fallback on top.
- **`CommonExceptionUtil`** in `CarafeSharp/Program.cs` (today every exception prints `ERROR: message`, so a
  programming defect loses its stack trace), and **`CommandStatusWriter`** for its output, so in-process stages write
  to Osprey's sink with its timestamps and log file.
- **No second parser:** new options go into `OspreyCommandArgs`; `CarafeCommandLine` stays as the Carafe-compatible
  front end (Carafe's Java-style grammar does not fit `ArgumentBase`).
- **Progress:** adopt Osprey's `ProgressReporter` once it leaves `Osprey.Core`; do not build a third.
- Linux is no obstacle: CommonUtil is plain net10.0 and Osprey ships its dependencies on Linux (never call its DPAPI methods there).

## Tasks
1. Agree the design with Mike (default training runs, the stage split, where the contracts assembly lives).
2. Extract the training-record assembly; move Osprey's writer and CarafeSharp's reader onto it; delete the
   duplicates. Gate: Osprey regression and CarafeSharp regression unchanged, byte for byte.
3. Fold the pairing manifest schema into it (coordinate with the library contract TODO).
4. Run the stages in-process from Osprey with checkpoints and resume; the workflow script becomes one command.
5. HPC tasks for the new stages, with declared file contracts.
6. Packaging: libtorch CPU in Osprey's packages; CUDA as an optional download.
7. Measure: one-command Stellar/Astral/ZT Scan runs against today's four-step workflow (IDs at matched
   entrapment FDP, time), and training on searched vs held-out runs (the overtraining question).
