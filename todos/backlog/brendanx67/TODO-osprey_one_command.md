# TODO-osprey_one_command.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_osprey_one_command` (PR 4a; later
  PRs get their own `Skyline/work/YYYYMMDD_...` branches off `master`, listed under their PR section
  as they start)
- **Base**: `master`
- **Created**: 2026-10-19 (design day; the sprint starts after #4867 and #4868 merge)
- **Status**: Design. Moves to `active/` as `TODO-YYYYMMDD_osprey_one_command.md` with its companion
  `TODO-YYYYMMDD_osprey_one_command-workflows.html` when the first branch is created.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **Checkout**: `C:\proj\pwiz`
- **Companion**: `TODO-osprey_one_command-workflows.html` (the three modes drawn as the workflow
  pages are; folds into `pwiz_tools/Osprey/Osprey-workflow.html` as its library-build chapter when
  the sprint ends)
- **Continues**: `TODO-20261014_osprey_carafe_integration.md` (completed with #4868's merge; its
  PR 4 - parts H, I, J - is this TODO) and `TODO-20261016_bibliospec_io_unification.md` (the BLIB
  sprint that ran between)
- **Folds in**: `backlog/TODO-task_file_contract_from_declarations.md` item 3 (harness staging from
  the declarations, PR 4c)

## Goal

One Osprey command goes from a protein FASTA and a set of DIA runs to a `.blib` ready for Skyline,
the way DIA-NN's command line does from `--fasta` and `--f`: no Carafe step the user runs, no
script that chains tools, no second executable to install. Three modes, chosen by the options
given, on top of today's library search:

| Mode | Command (shape) | What runs |
|---|---|---|
| 0. search (today) | `Osprey -i runs... -l library.blib -o out.blib` | the four Osprey stages |
| 1. predict | `Osprey -i runs... --fasta proteome.fasta -o out.blib` | digest, predict with the pretrained models, search |
| 2. tune | `Osprey -i runs... --fasta proteome.fasta --training-input run2 -o out.blib` | digest, predict, search the tuning runs with the training export, fine-tune, predict again with the tuned model, search everything |
| 3. saved model | `Osprey -i runs... --fasta proteome.fasta --model tuned.carafemodel -o out.blib` | mode 1 with a saved fine-tuned model instead of the pretrained ones |

Mode 2 always saves its model (`<out>.carafemodel`), so every tuned run is a mode 3 input later;
`--model` together with `--training-input` fine-tunes the saved model further (CarafeSharp supports
it today). The library the output was searched with is a first-class product too
(`<out>.library.blib`), reusable with `-l` as DIA-NN's `--out-lib` is.

## Why (Brendan, 2026-10-19)

Osprey has to win over users of DIA-NN and Spectronaut, who give a FASTA and their runs and get
results. The lab's own workflow is still four steps across two tools behind
`Run-CarafeSharpWorkflow.ps1` (Mike, 2026-10-12: generate the library with the default model,
search the middle file, fine-tune, search all files). The integration sprint of 2026-10-14 put both
tools on one toolkit, one task contract, one command-line grammar, one blib writer, one blib
reader and one set of contracts precisely so this could be built without a child process, a copied
schema or a second reader. Mode 2 is what DIA-NN cannot do (its `--reanalyse` builds an empirical
library from a first pass; it never adapts the predictor), and mode 3 makes the tuning reusable:
a lab tunes once per instrument and method and predicts any proteome with it after that.

## Where this starts from

What the two sprints before delivered, and what this TODO therefore does not have to build:

- CarafeSharp's stages are already tasks on the shared contract (`PipelineTask`, `TaskContext`,
  `PipelineDriver` in CommonUtil; `EntrapmentFastaTask`, `PredictLibraryTask`, `TrainTask`,
  `ReconcileManifestTask` in `pwiz_tools/CarafeSharp/CarafeSharp`), each with inputs, outputs and a
  validity key, and a stamp slot in what it writes (`osprey_validity` first in the
  `.carafemodel` manifest; `LibMetadata.osprey.validity` in the blib). Resume and skip come for free.
- Osprey's `OspreyTask` is the same base; `OspreyTasks.Create()` declares the canonical four-stage
  pipeline plus selector-only tasks (`SpectraCache`, `TrainingExport`, `ModelDiagnostics`), so a
  task set with more members is a declaration, not a new mechanism (`Osprey.Tasks/OspreyTasks.cs`).
- One command-line parser with a grammar per tool, and both tools' options declared as
  `Argument` objects with help text in resx (`CarafeCommandLine`, `OspreyCommandArgs`), so Osprey
  can present CarafeSharp's library-build options without re-declaring them.
- One blib writer and reader (`BiblioSpec.IO`): the library CarafeSharp predicts is the library
  Osprey searches, with `DecoyPairs` and `LibMetadata`, and `LibraryContract` refuses a bad one at
  write and at load. A `.blib` loads in 3.4 s at 243k precursors (PR A's measurement) and is read
  directly since #4865 retired the `.libcache`, so an in-process chain has no TSV and no cache
  file in it.
- The training export (`<stem>.training.parquet`, `CarafeSharp.Contracts/TrainingExportParquet`)
  is one schema written by Osprey and read by CarafeSharp; the pairing manifest likewise.
- The dependency direction is settled (decision 4 of the integration TODO): Osprey.exe links
  CarafeSharp's assemblies; CarafeSharp.exe references nothing in Osprey and stays the library-only
  front end that accepts Carafe's command lines.
- `Osprey --export-library` writes a searched library back out as a blib; `--training-export`,
  `--decoys-in-library`, `--fdrbench` and the entrapment oracle all exist.

What has to be built is therefore the composition: the options, the workflow that sequences the
tasks and two Osprey analyses, the files between them, the HPC addressing of the new stages, and
the packaging that puts CarafeSharp and libtorch into Osprey's distribution.

## The user's view

### Command lines

```
# 1. predict: the pretrained models (AlphaPeptDeep MS2, Chronologer RT by CarafeSharp's default)
Osprey -i run1.raw run2.raw run3.raw --fasta human.fasta -o out.blib --resolution hram

# 2. tune on one run that is also searched (the lab's "search the middle file")
Osprey -i run1.raw run2.raw run3.raw --fasta human.fasta --training-input run2.raw -o out.blib

# 2'. tune on runs that are NOT in the output (held-out tuning; the overtraining question)
Osprey -i cohort/*.raw --fasta human.fasta --training-input tune1.raw tune2.raw -o out.blib

# 3. a saved model from an earlier mode-2 run, any proteome
Osprey -i run1.raw run2.raw --fasta mouse.fasta --model out.carafemodel -o mouse.blib

# 2 + 3: tune a saved model further on new runs
Osprey -i run4.raw run5.raw --fasta human.fasta --model out.carafemodel --training-input run4.raw -o out2.blib

# the lab's validation arm: entrapment in the final library, FDRBench input out
Osprey -i runs... --fasta human.fasta --training-input run2.raw --entrapment 1.0 --fdrbench fdrbench.tsv -o out.blib
```

### What a user gets

| Product | Path | Modes |
|---|---|---|
| The search result for Skyline | `-o` (`out.blib`) and its sidecars, as today | all |
| The library the result was searched with | `<out>.library.blib` beside it (`-l` takes it next time) | 1, 2, 3 |
| The tuned model | `<out>.carafemodel` beside it (`--model` takes it next time; `CarafeSharp --model_info` describes it) | 2 |
| The working files | `<out>.library/` (peptide FASTAs, pairing manifests, the initial library, the training analysis) | 1, 2, 3 |

### Against DIA-NN's command line (what the field expects)

| DIA-NN | Osprey | Note |
|---|---|---|
| `--f run.raw` (repeated) / `--dir` | `-i run1 run2 ...` / `--input-list` | exists |
| `--fasta x.fasta --gen-spec-lib --predictor` | `--fasta x.fasta` | mode 1; the predictor is implied by having no `-l` |
| `--lib x.tsv` | `-l x.blib` | mode 0; exists |
| `--out-lib x.tsv` | `<out>.library.blib` | always written when Osprey built the library |
| `--out report.tsv` | `-o out.blib` (`--report` for the TSV) | exists |
| `--reanalyse` (MBR second pass) | the second pass is Osprey's own cross-run reconciliation | exists; no option |
| no analog | `--training-input`, `--model` | modes 2 and 3 |
| `--cut K*,R*,!*P`, `--missed-cleavages`, `--min-pep-len`, `--max-pep-len`, `--min-pr-charge`, `--max-pr-charge`, `--min-pr-mz`, `--max-pr-mz`, `--var-mods`, `--unimod4`, `--met-excision` | CarafeSharp's digest and modification options (`--enzyme`, `--miss_c`, `--min_pep_len`, `--max_pep_len`, `--min_pep_mz`, `--max_pep_mz`, `--fixed_mod`, `--var_mod`, `--clip_n_m`, ...) | decision 2 below: Carafe's names, surfaced in Osprey's help |
| `--qvalue`, `--threads` | `--run-fdr` / `--experiment-fdr`, `--threads` | exist |

## Design

### 1. Options

New on Osprey's command line (Osprey's own, in `OspreyCommandArgs`, with resx text and
`20-command-line.md` rows):

| Option | Value | Meaning |
|---|---|---|
| `--fasta` | `<proteome.fasta>` | Build the library from this proteome. Refused with `-l` (a library is either given or built; protein re-annotation of a given library is not a case we have). |
| `--training-input` | `<run ...>` (variadic, as `-i`) | Tune the predictor on these runs first. A run may be in `-i` or not; a run not in `-i` is searched for tuning only and is absent from the output. Requires `--fasta`. |
| `--model` | `<file.carafemodel>` | Predict with this saved model; with `--training-input`, start the tuning from it. Requires `--fasta`. |
| `--entrapment` | `[<ratio>]` | Add entrapment peptides to the final library (the lab's validation arm; shuffled, or `--entrapment-fasta <foreign.fasta>` for natural entrapment). The training library never carries entrapment. |
| `--device` | `gpu \| cpu` | Where CarafeSharp predicts and trains; `gpu` falls back to the CPU with a warning when no CUDA runtime is present (CarafeSharp's rule). |

The library-build parameters themselves - digest (enzyme, missed cleavages, length, N-terminal M
clipping), modifications, charges, precursor and fragment m/z windows, fragments per spectrum,
NCE, instrument, RT model, and the training hyperparameters (`--tf`, `--rt_align`, `--seed`,
`--cor`, ...) - are CarafeSharp's declarations, included in Osprey's parse as help sections of
their own (`LIBRARY DIGEST`, `LIBRARY PREDICTION`, `LIBRARY TUNING`), under Osprey's grammar
(`--miss_c 1` or `--miss_c=1`). One declaration set, two front ends; Carafe's names, because they
are the names a Carafe user and `CarafeSharp --help` know, and a second name for every one of
them is the "two ways of doing one thing" the toolkit sprint was fought over. The ones Osprey
derives are NOT surfaced: CarafeSharp's `-i` (the exports), `-ms` (the runs), `-o` (the folder),
`-db` (the FASTA), `-pairing_manifest`, `-model_dir`, `-lf_type` (always blib), `-fdr` (Osprey's
`--training-export-max-q` is that threshold), `-se`, `-mode`, the unported and ignored Carafe
options. Collisions to resolve in code: both tools declare `-i`, `-o`, `-h`, `--seed`, a thread count
(`--threads` / `-nt`) and `--device`; Osprey's declaration wins and CarafeSharp's settings are
built from Osprey's value.

How: `CarafeCommandLine` is split so its declarations and `Interpret` (declarations to
`LibrarySettings` / `TrainingSettings`) can be driven by a host parser: Osprey constructs one,
registers the surfaced groups with its own parser, and after the parse calls `Interpret` with the
derived values filled in. CarafeSharp.exe keeps doing what it does. `CommandArgsTest` (CarafeSharp)
and `OspreyCommandArgsTests` pin both front ends; the Osprey help test regenerates
`Documentation/Help/en/CommandLine.html` with the new sections.

### 2. Stages, tasks and the workflow layer

Osprey's pipeline stays a fixed four-element list per analysis (the invariant
`00-pipeline-architecture.md` is built on). The one command is a **workflow** above it: a sequence
of phases, each either a CarafeSharp task run in-process through the shared driver, or an Osprey
analysis (`AnalysisPipeline` over a derived config: its own inputs, output directory, library and
export setting). The workflow for each mode, with every phase's checkpoint file (the next phase's
input, and what a resumed run finds current):

| Phase | Task (`--task`) | Owner | In | Out (checkpoint) | Modes |
|---|---|---|---|---|---|
| Digest | `DigestFasta` (`EntrapmentFastaTask`) | CarafeSharp, CPU | `--fasta` | `<out>.library/peptides.fasta` + `pairing.tsv`; with `--entrapment` also `training-peptides.fasta` + `training-pairing.tsv` (entrapment-free, for the training library) | 1, 2, 3 |
| Predict the training library | `PredictTrainingLibrary` (`PredictLibraryTask`) | CarafeSharp, GPU | training peptides, pretrained or `--model` | `<out>.library/initial.blib` | 2 |
| Search the tuning runs | `TrainingSearch` (selector: the four stages over `--training-input` with `--training-export`) | Osprey | `initial.blib`, the tuning runs | `<out>.library/training/<stem>.training.parquet` per run, plus that analysis's own artifacts and `training.blib` | 2 |
| Tune | `TrainModel` (`TrainTask`) | CarafeSharp, GPU | the exports, pretrained or `--model` | `<out>.carafemodel` (plus Carafe's model folder under `<out>.library/model/`) | 2 |
| Predict the library | `PredictLibrary` (`PredictLibraryTask`) | CarafeSharp, GPU | peptides, pretrained / `--model` / the tuned model | `<out>.library.blib` | 1, 2, 3 |
| Search | the canonical four | Osprey | `<out>.library.blib`, `-i` | `out.blib` and sidecars, as today | all |

Modes 1 and 3 are Digest, PredictLibrary, Search; mode 2 is all six. Without `--entrapment` the
training library and the final library are predicted from the same peptide FASTA; only the model
differs. The spectra cache is shared between the two analyses (`--cache-dir`), so a tuning run
that is also searched is parsed once.

`ReconcileManifest` stays a CarafeSharp command-line mode, not a phase (the blib's `DecoyPairs`
carries the pairs; the manifest is kept only for the FDRBench entrapment partner, which
`DecoyPairs` cannot express yet - the "fourth row" schema question from the BLIB sprint, not this
one).

### 3. Files

```
out.blib                       the result (-o), sidecars as today
out.library.blib               the library it was searched with (modes 1-3)
out.carafemodel                the tuned model (mode 2)
out.library/                   working files of the library build
  peptides.fasta, pairing.tsv              digest (final library)
  training-peptides.fasta, training-pairing.tsv   only with --entrapment
  initial.blib                             the training library (mode 2)
  training/                                the training analysis: its parquets, sidecars,
                                           <stem>.training.parquet, training.blib
  model/                                   Carafe's model folder (what --model_dir reads)
```

`--output-dir` relocates all of it as it relocates today's sidecars; `--work-dir` likewise. The
two user-facing products sit beside `out.blib` because they are what a user reuses; everything
else is under one folder a user can delete.

### 4. Resume and validity

Nothing new in mechanism. Each CarafeSharp task's key is a hash of its settings and inputs
(`CarafeValidity.Key`); each Osprey analysis stamps its artifacts as today. The workflow walks the
phases in order through the shared driver and each phase skips when its outputs are current, so:
a crashed mode-2 run resumes at the phase it died in; changing a digest option re-runs everything;
changing `--training-input` re-runs the training search and after; changing `-i` alone re-runs
only the final search. `OSPREY_VERSION_OVERRIDE` and the daily stamp cover the model file as they
cover the parquets (the stamp is already in the manifest).

### 5. libtorch, the GPU and packaging (part J)

Design 3 of the integration TODO holds: TorchSharp and libtorch (about 330 MB CPU, 4 GB CUDA)
load only in the prediction and tuning phases. `Osprey.exe` references `CarafeSharp.Proteome` (the
digest; no torch), `CarafeSharp.Training` and `CarafeSharp.Models`; the types of the last two are
used only inside the two task classes the workflow instantiates for those phases, so the runtime
loads the native library when a method of those classes is first JIT-compiled and never for a
`-l` search. Verify with a test that a mode-0 run on a build without the native library succeeds.

Packaging: Osprey's Windows and Linux packages ship CarafeSharp's assemblies, the CPU libtorch
and the pretrained model archives (`pwiz_tools/CarafeSharp/models`; sizes to record here); CUDA
stays an optional download, found by CarafeSharp's existing device resolution. The installer's
file lists and TeamCity artifacts change; measure the package size before and after.

### 6. HPC (part I)

The library phases are single-node tasks (`--task DigestFasta`, `PredictTrainingLibrary`,
`TrainModel`, `PredictLibrary`), each with a declared file contract. The two analyses are the
existing four-task chains; the training analysis is addressed by adding `--training-search` to a
stage task (`--task PerFileScoring --training-search`), which selects the tuning runs, the
training output directory, the initial library and the export, exactly as the in-process workflow
derives them. Library prediction fans out inside the task (batches of peptidoforms across GPU
nodes, merged into one library) when the cluster has several GPUs - not a new task boundary
(decided 2026-10-15). Harness staging from the declarations is item 3 of
`TODO-task_file_contract_from_declarations.md` and lands here, in PR 4c.

### 7. What stays as it is

- `CarafeSharp.exe`: the library-only front end, Carafe's command lines, `--model_info`.
- `-l` searches: untouched; the regression goldens do not move (the gate).
- `Run-CarafeSharpWorkflow.ps1`: reduces to one Osprey invocation per dataset preset, kept as the
  harness that names the presets and the validation arm (`-Stages` goes; `--task` is the stage
  selector now).
- `Carafe-workflow.html` folds into `Osprey-workflow.html` as the library-build chapter, which is
  what the companion HTML of this TODO is the draft of.

## Decisions (Brendan, 2026-10-19)

1. **No tuning unless `--training-input` names the runs.** The default is the pretrained model
   (mode 1). The user must specify the fine-tuning training set even when it is just files of the
   current run (`--training-input` with some or all of `-i`); nothing is inferred. The lab's
   one-run habit is `--training-input <middle file>`. Mike's view on a default was never needed:
   there is none.
2. **Library-build options are CarafeSharp's declarations, Carafe's names**, surfaced as sections
   of Osprey's help (section 1). The aim is not to look like DIA-NN; it is to offer what DIA-NN
   offers - a complete end-to-end solution with library generation in it - under one command.
3. **The model and the library land beside `-o`** as `<out>.carafemodel` and `<out>.library.blib`,
   no new options. Reasonable especially now that `.blib` is the format and needs no `.libcache`
   beside it (#4865 retired the cache: a `.blib` is read directly).
4. **`--training-input` runs absent from `-i` are allowed**, searched for tuning only (the
   held-out case; the overtraining measurement after PR 4b). The output blib's
   `SpectrumSourceFiles` names only `-i`; `LibMetadata` records the tuning runs under
   `osprey.training_input`.
5. **CarafeSharp's RT default stays** (Chronologer; `--rt_model alphapeptdeep` is there).
6. **Three PRs** (4a modes 1 and 3, 4b mode 2, 4c HPC and packaging), each gated, no PR per
   topic - as specified to the session that wrote the integration TODO this one supersedes.

## PR plan

| PR | Holds | Gate beyond the standing ones |
|---|---|---|
| **4a** `--fasta` modes 1 and 3 | the options and CarafeSharp's sections in Osprey's help; the workflow layer with Digest, PredictLibrary and the search; the file layout; the lazy libtorch seam; docs 20 and 00; `SubsetPipelineTest` mode-1 and mode-3 cases on the subset FASTA (CPU prediction, seconds) | CarafeSharp's chained leg unchanged; a mode-1 Stellar run against `Run-CarafeSharpWorkflow.ps1 -Stages 1a,2,6` (same library bytes, same result) |
| **4b** `--training-input` mode 2 | PredictTrainingLibrary, TrainingSearch, TrainModel; the model beside `-o`; resume across the chain; `--model` + `--training-input`; `regression.ps1` gains a one-command leg that replaces CarafeSharp's chained leg as the end-to-end gate | the mode-2 Stellar run against the six-stage script (same `.carafemodel` content, same library, same result); `SubsetPipelineTest` resume cases |
| **4c** HPC and packaging | the `--task` names, `--training-search`, the file contracts and harness staging (the backlog item); installers and TeamCity artifacts with CarafeSharp and libtorch CPU; `Run-CarafeSharpWorkflow.ps1` reduced; the workflow page folded | the HPC chain of the regression on mode 2; package size recorded; a mode-0 run on a build without libtorch |

Measurement after 4b, no PR of its own: one-command Stellar / Astral / ZT Scan against today's
four-step workflow - IDs at matched entrapment FDP and wall time; tuning on searched vs held-out
runs (the overtraining question), recorded here with the run folders.

## Gates

Every PR, before `gh pr create` (then `/code-review medium` on the branch):
- `pwsh -File C:/proj/ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot C:/proj/pwiz -Configuration Debug -RunTests -RunInspection -Summary`
- `pwsh -File C:/proj/ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -SourceRoot C:/proj/pwiz -RunTests -RunInspection -Summary`
- `pwsh -File C:/proj/ai/scripts/BiblioSpec/Build-BiblioSpec.ps1 -SourceRoot C:/proj/pwiz -RunTests -Summary` (the shared reader and writer gate)
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` - byte-identical: `-l` searches do not move
- `pwsh -File ./pwiz_tools/CarafeSharp/regression.ps1 -Leg Chained` (until 4b replaces it)
- Before merge: `regression-parallel.ps1 -Dataset All` locally and the TeamCity Perf/Regression
  config on `pull/<N>` (ask first), once per merge candidate.

## Open questions

- Mike: the CommonUtil dependency (assumed since 2026-10-14).
- Whether `--fasta` with `-l` should ever mean anything (DIA-NN re-annotates proteins from the
  FASTA; Carafe's library already carries them).
- The pretrained archives' size in the package, and whether Chronologer's `.pt` ships or converts.
- `DecoyPairs` and the entrapment partner (the BLIB sprint's open schema question): until it is
  answered, `--entrapment` keeps writing the pairing manifest beside the library for FDRBench.

## Progress Log

### 2026-10-19 - Designed
Written in the design window while #4868's Skyline Perf and Tutorial run (the last check on the
#4867 + #4868 chain) finishes; the six decisions settled with Brendan the same afternoon (section
"Decisions"). Nothing coded. Next: merge the chain
(handoff `ai/.tmp/handoff-20261019_skyline_blib_io.md` has the order), `/pw-complete` the BLIB
sprint's TODO, move `TODO-20261014_osprey_carafe_integration.md` to `completed/2026/10` with a
closing entry that points here, then `git mv` this TODO and its HTML to `active/` with the date
and create PR 4a's branch.
