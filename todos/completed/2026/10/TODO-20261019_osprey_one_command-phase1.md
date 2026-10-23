# TODO-20261019_osprey_one_command.md  -  Phase 1

Phase 1 (2026-10-19 to 2026-10-22): the design, the decisions, PRs 4a-4c, the clean-up PR and the
`.libcache` retirement. Phase 2 (PR 4d onward) continues in
[todos/active/TODO-20261019_osprey_one_command.md](../../../active/TODO-20261019_osprey_one_command.md).
This file is the reference for everything below; it is no longer edited.

## Branch Information
- **Branch (4c)**: `Skyline/work/20261022_osprey_hpc_cuda` in `C:\proj\pwiz` (from master 22626556a4, 2026-10-22 night)
- **Branch**: `Skyline/work/20261019_osprey_one_command` (PR 4a; later PRs get their own
  `Skyline/work/YYYYMMDD_...` branches off `master`, listed under their PR section as they start)
- **Base**: `master`
- **Created**: 2026-10-19 (designed in the morning; the branch was cut the same evening after
  #4867 and #4868 merged)
- **Status**: Phase 1 complete 2026-10-23 - PR 4a merged 2026-10-20 as #4876 (modes 1 and 3), with #4877 before it; 4b merged 2026-10-21 as #4885; the clean-up PR merged 2026-10-21 as #4895; 4c (HPC addressing, task declarations, one chain shape) merged 2026-10-22 as #4898 (46af8ac754). `.libcache` retirement merged 2026-10-22 as #4904 (f4f24aefad). #4849 (AlphaPeptDeep via CarafeSharp) merged 2026-10-23 as 946a33909f. Phase 2 (4d: Osprey as a download using #4849's libtorch runtime) continues in the active TODO of the same name.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4877](https://github.com/ProteoWizard/pwiz/pull/4877) (merged 2026-10-20) (option spelling), then
  [#4876](https://github.com/ProteoWizard/pwiz/pull/4876) (merged 2026-10-20) (PR 4a);
  [#4878](https://github.com/ProteoWizard/pwiz/pull/4878) (doc sweep, merged 2026-10-20);
  [#4885](https://github.com/ProteoWizard/pwiz/pull/4885) (PR 4b, merged 2026-10-21 as 7819a9b6ac);
  [#4895](https://github.com/ProteoWizard/pwiz/pull/4895) (clean-up, merged 2026-10-21 as 22626556a4);
  [#4898](https://github.com/ProteoWizard/pwiz/pull/4898) (PR 4c, merged 2026-10-22 as 46af8ac754);
  [#4904](https://github.com/ProteoWizard/pwiz/pull/4904) (`.libcache` retirement, merged 2026-10-22 as f4f24aefad)
- **Checkout**: `C:\proj\pwiz`
- **Companion**: folded into `pwiz_tools/Osprey/Osprey-workflow.html` as part 1 ("Building the
  library") in PR 4b (#4885); the draft `TODO-20261019_osprey_one_command-workflows.html` is deleted.
  `Carafe-workflow.html` (the six-stage script view) folded in with 4c as part 1's sections 1.1-1.3
  (on a cluster, inside the library phases, CarafeSharp and Carafe 2.2.0) and deleted
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
| Predict the training library | `PredictTrainingLibrary` (`PredictLibraryTask`) | CarafeSharp, GPU | `--fasta` (digested in memory, entrapment-free), pretrained or `--model` | `<out>.library/initial.blib` | 2 |
| Search the tuning runs | `TrainingSearch` (selector: the four stages over `--training-input` with `--training-export`) | Osprey | `initial.blib`, the tuning runs | `<out>.library/training/<stem>.training.parquet` per run, plus that analysis's own artifacts and `training.blib` | 2 |
| Tune | `TrainModel` (`TrainTask`) | CarafeSharp, GPU | the exports, pretrained or `--model` | `<out>.carafemodel` (plus Carafe's model folder under `<out>.library/model/`) | 2 |
| Predict the library | `PredictLibrary` (`PredictLibraryTask`) | CarafeSharp, GPU | `--fasta` (digested in memory, with `--entrapment` as quartets), pretrained / `--model` / the tuned model | `<out>.library.blib` | 1, 2, 3 |
| Search | the canonical four | Osprey | `<out>.library.blib`, `-i` | `out.blib` and sidecars, as today | all |

Modes 1 and 3 are PredictLibrary then Search; mode 2 is all five. **The digest is not a phase
(decision 7)**: it is an `IEnumerable` of (peptide, source proteins, kind, pair id) produced
from `--fasta` inside the prediction task - cleavage by `Digester`/`EnzymeTable`, decoys and
entrapment by `EntrapmentFastaBuilder`'s generation steps - which the predictor consumes and the
blib writer takes its `Proteins` and `DecoyPairs` from. It is seconds of CPU and deterministic
(seeded), so the predicted `.blib` is the first checkpoint and the prediction task's validity key
(FASTA identity plus the digest settings, which `CarafeValidity.Key` already hashes) covers it.
This also ends CarafeSharp's second digest: `LibraryDatabase` re-digests `-db` inside prediction
today, reproducing Java's HashMap order for the `ProteinID` text (`JavaHashOrder`), because in
Carafe the FASTA builder and the predictor are separate runs; in-process one digest feeds both
and the Java-order reproduction is needed only by the parity tests. Without `--entrapment` the
training library and the final library are predicted from the same digest; only the model
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
  pairing.tsv                              only with --entrapment: the FDRBench quartets, until
                                           DecoyPairs can carry the entrapment partner (open question)
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

The library phases are single-node tasks (`--task PredictTrainingLibrary`, `TrainModel`,
`PredictLibrary`), each with a declared file contract; the digest runs inside the two prediction
tasks (decision 7). The two analyses are the
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
  what the companion HTML of this TODO is the draft of. (Done in 4c: part 1, sections 1.1-1.3; the
  CarafeSharp page is deleted.)

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
7. **The digest is an enumerable, not a task (Brendan, 2026-10-19 evening).** Too small for a
   sidecar of its own; the predictor and the blib writer consume it in memory (section 2).
   Skyline's own `Enzyme` (its protease table, mixed-enzyme digestion, semi-cleavage, ragged ends)
   is the better general model but lives inside Skyline.exe, and the shared `ProteomeDb` digester
   drags NHibernate along; merging the digesters is too complicated for this sprint, so
   CarafeSharp's Carafe-parity `Digester` stays. `CarafeSharp --build_entrapment_fasta` keeps
   writing the peptide FASTA and manifest for whoever wants the files.
8. **Decoy source in mode 1: predicted decoys, as the lab workflow has them (proposed).**
   With the digest in memory, mode 1 could hand CarafeSharp only targets and let Osprey's
   `DecoyGenerator` reverse them at load (half the prediction time, no `DecoyPairs`); keep
   CarafeSharp predicting the decoy peptides and writing the pairs as the default (the
   StellarLibDecoy shape; generated decoys are the less reliable mechanism, Brendan 2026-10-17),
   with the generated route available as it is for `-l`.
9. **Option spelling: standard pwiz hyphens, Carafe's underscores accepted (proposed, Brendan
   leaning yes 2026-10-19 evening).** 57 of CarafeSharp's 97 options use underscores
   (`--build_entrapment_fasta`, `--miss_c`, `--lf_top_n_frag`, `--rt_model`, `--log_file`, ...);
   Osprey and Skyline have none. We need not match Java Carafe's spelling: the help, the docs and
   Osprey's library sections spell them `--build-entrapment-fasta`, `--miss-c`, and one grammar
   rule makes `_` and `-` equivalent when a name is matched, so every recorded Carafe command
   line (which the parity tests replay from `parameter.txt`) still runs and the "OTHER FORMS
   ACCEPTED" paragraph says so - no per-option alias list. CarafeSharp's own additions that
   duplicate an Osprey option under Carafe's style (`--log_file` for `--log-file`) take Osprey's
   name outright. Word-level renames (`--miss-c` to `--missed-cleavages`) are a separate choice,
   not made here.
10. **The predicted library is `<out>.predicted.blib` (Brendan, 2026-10-20).** `<out>.library.blib`
   beside `out.blib` did not say how the two differ; `out.blib` holds what the search detected, and
   the other a predicted spectrum for every precursor the search looked for. The working folder is
   `<out>.predicted/` so the pair sorts together. Renamed in 4b before it merged; decision 3 and
   the design sections above still say `.library` and mean this.
11. **One workflow page (Brendan, 2026-10-20).** The library build is part 1 of
   `Osprey-workflow.html` and the search pipeline part 2, one page with a contents bar: the one
   command is one run and the four stages are its last phase.
12. **A resume demonstration at real scale (Brendan, 2026-10-20).** `OSPREY_STOP_AFTER_TASKS=N`
   ends a run cleanly after N tasks have run; `regression.ps1 -StepwiseOneCommand` (opt-in, mode 13)
   runs the tuned one command on Stellar that way, one task per run, against a straight-through run.

## Second-pass levers - for Brendan and Mike (2026-10-22)

Brendan: the minimum search is the first pass with a cut-off applied, written to a `.blib`; everything
the second pass adds is a factor that changes that result. Decide with Mike which of these a USER may
turn off (options, in `--help`) and which only a DEVELOPER may (`OSPREY_*` variables, for testing), and
whether "no second pass at all" is a user option. What exists today (2026-10-22, master + #4898):

| Step (task) | What it changes | Switch today |
|---|---|---|
| First pass: SVM, run and experiment q-values (FirstPassFDR) | the baseline every later step starts from | always on; classifier `OSPREY_FDR_MODEL` (dev), C selection `OSPREY_SVM_C_TOLERANCE` (dev), experiment aggregation `OSPREY_EXPERIMENT_AGG` (dev) |
| Compaction gate (FirstPassFDR) | which precursors reach the second pass | `--reconciliation-compaction-fdr` (user) |
| Cross-run consensus and reconciliation (FirstPassFDR plans, PerFileRescoring re-picks) | moves peaks to the consensus RT, imputes boundaries | none: `ReconciliationConfig.Enabled` exists but no option sets it (only a unit test); with one run it has nothing to do |
| Multi-charge consensus (PerFileRescoring) | re-scores a run's charge states together; applies to one run too | none |
| Gap-fill (PerFileRescoring) | adds peaks missing from a run | none |
| Per-run second pass (PerFileRescoring) and experiment fold (SecondPassFDR) | the reported q-values | `OSPREY_PASS2_QVALUE` (dev): `protein-compact` (default, a constrained re-competition) or `transfer` (carries the first-pass values; no re-competition, but the second-pass machinery still runs); `OSPREY_PASS2_VERIFY_WORKER` (dev, test instrument) |
| Protein inference and protein FDR (SecondPassFDR) | protein groups, protein q gate | `--protein-fdr`, `--shared-peptides`, `--fdr-level` (user) |
| `.blib` write (SecondPassFDR) | the output | always |

Gaps to decide: (1) no switch for "first pass + cut-off -> .blib" (the minimum search); the nearest is
`OSPREY_PASS2_QVALUE=transfer`, which still runs Stage 6. (2) Reconciliation, multi-charge consensus and
gap-fill have no switch at all, not even for developers. (3) Whether the user-facing ones belong in a
"Second pass" help section. Mechanics: the task chain no longer assumes reconciliation (#4898 removed
FirstPassFDR's refusals of one run and of reconciliation off), so turning steps off is a matter of
switches, not of the HPC chain's shape.

## PR plan

| PR | Holds | Gate beyond the standing ones |
|---|---|---|
| **4a** `--fasta` modes 1 and 3 | the options and CarafeSharp's sections in Osprey's help (hyphenated per decision 9); the workflow layer with PredictLibrary over the in-memory digest and the search; the file layout; the lazy libtorch seam; docs 20 and 00; `SubsetPipelineTest` mode-1 and mode-3 cases on the subset FASTA (CPU prediction, seconds) | CarafeSharp's chained leg unchanged; a mode-1 Stellar run against `Run-CarafeSharpWorkflow.ps1 -Stages 1a,2,6` (same library bytes, same result) |
| **4b** `--training-input` mode 2 | PredictTrainingLibrary, TrainingSearch, TrainModel; the model beside `-o`; resume across the chain; `--model` + `--training-input`; `regression.ps1` gains a one-command leg that replaces CarafeSharp's chained leg as the end-to-end gate | the mode-2 Stellar run against the six-stage script (same `.carafemodel` content, same library, same result); `SubsetPipelineTest` resume cases |
| **4c** HPC and packaging | the `--task` names, `--training-search`, the file contracts and harness staging (the backlog item); installers and TeamCity artifacts with CarafeSharp and libtorch CPU; `Run-CarafeSharpWorkflow.ps1` reduced; the workflow page folded | the HPC chain of the regression on mode 2; package size recorded; a mode-0 run on a build without libtorch |

**4c split (Brendan, 2026-10-21 night):** 4c is HPC addressing and harness staging, the opt-in
CUDA build (`Build-Osprey.ps1 -Torch cuda`; the default build stays CPU libtorch) with the one
command measured on the GPU, `Run-CarafeSharpWorkflow.ps1` reduced, and `Carafe-workflow.html`
folded (done: `Osprey-workflow.html` part 1, sections 1.1-1.3). Installers and TeamCity artifacts move to **4d** (they need TeamCity configuration and
installer work a session cannot verify alone). The default-models `.model.zip` is not in 4c (it moves
the MannLabs SHA-256 pin and needs the Carafe parity reference data).

Measurement after 4b, no PR of its own: one-command Stellar / Astral / ZT Scan against today's
four-step workflow - IDs at matched entrapment FDP and wall time; tuning on searched vs held-out
runs (the overtraining question), recorded here with the run folders.

## Gates

Every PR, before `gh pr create` (then `/code-review medium` on the branch):
- `pwsh -File C:/proj/ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot C:/proj/pwiz -Configuration Debug -RunTests -RunInspection -Summary`
- `pwsh -File C:/proj/ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -SourceRoot C:/proj/pwiz -RunTests -RunInspection -Summary`
- `pwsh -File C:/proj/ai/scripts/BiblioSpec/Build-BiblioSpec.ps1 -SourceRoot C:/proj/pwiz -RunTests -Summary` (the shared reader and writer gate)
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` - byte-identical: `-l` searches do not move
- `pwsh -File ./pwiz_tools/CarafeSharp/regression.ps1 -Leg Chained` (retired in 4b: the chain is
  `SubsetPipelineTest.TestSubsetLibraryBuildTuned` now)
- Before merge: `regression-parallel.ps1 -Dataset All` locally and the TeamCity Perf/Regression
  config on `pull/<N>` (ask first), once per merge candidate.

## Open questions

- Mike: the CommonUtil dependency (assumed since 2026-10-14).
- Whether `--fasta` with `-l` should ever mean anything (DIA-NN re-annotates proteins from the
  FASTA; Carafe's library already carries them).
- The pretrained archives' size in the package, and whether Chronologer's `.pt` ships or converts.
- A later toolkit sprint, not this one: one shared enzyme table and digester (Skyline's rules and
  protease list, Carafe's table as presets) that Skyline, CarafeSharp and the BiblioSpec port use;
  the Carafe parity tests would need a Carafe-rules mode, as the similarity gate has one.
- `DecoyPairs` and the entrapment partner (the BLIB sprint's open schema question): until it is
  answered, `--entrapment` keeps writing the pairing manifest beside the library for FDRBench.

## PR 4a plan (2026-10-19 evening, after reading the code the design names)

What the code looks like today, where it bears on 4a, and the shape each piece takes. Checked
boxes are done on the branch.

### Where things stand in the code

- CarafeSharp's tasks (`CarafeTask`, `PredictLibraryTask`, `TrainTask`, `EntrapmentFastaTask`,
  `ReconcileManifestTask`), their context, driver, validity and stamp reader, and the two engines
  (`LibraryGenerator`, `ModelTrainer`) all live in the **exe** project `CarafeSharp/CarafeSharp`,
  `internal`. Osprey.exe cannot reference an exe cleanly, so they move to a library.
- `LibraryGenerator` digests `-db` twice (`LibraryDatabase.DigestPeptides` for the forms,
  `MapPeptidesToProteins` for the `ProteinID` text in Java HashMap order) and plans `DecoyPairs`
  from the pairing manifest **file** (`DecoyPairPlanner.ReadManifest`). The library's output path is
  `OutputDirectory + carafe_spectral_library.blib`, fixed.
- `EntrapmentFastaBuilder.Run()` is already the digest-and-generate pipeline the design wants in
  memory (digest targets with sources, assign entrapment, assign decoys, drop unusable, sort) with
  the FASTA and manifest writes at the end of the same method.
- The shared parser matches option names ordinally (`CommandLineParser.MatchOption`); the grammar is a
  process-wide static (`ArgUsage.Grammar`, `ArgUsage.Provider`), installed by each tool's static
  constructor. `ArgumentBase` has no constructor that copies another declaration.
- `CarafeCommandLine.Interpret` reads its records by **string name** (`Has(@"miss_c")`), 100-odd sites;
  `Record` is private.
- Osprey: `OspreyConfig` (Osprey.Core) cannot see CarafeSharp.Proteome; `Program.Run` validates, logs
  the banner, then `new AnalysisPipeline().Run(config, pipeline)`. `OspreyCommandArgsTests.
  TestEveryArgIsGroupedAndDescribed` counts every static `OspreyArgument` field against the groups
  and demands Osprey resx text for each.
- libtorch comes in through `UseLibTorch=true` in CarafeSharp's `Directory.Build.targets` (plus the
  pretrained model files), keyed on properties in CarafeSharp's `Directory.Build.props`; Osprey's tree
  imports neither.
- Test data: `Osprey.Test/TestData/StellarSubset.zip` has three 7-minute single-window mzMLs and a
  358-precursor TSV library with synthetic proteins; there is no protein FASTA for it.
  `CarafeSharp.Test/TestData/Stage1Inputs.zip` has `hela-filtered.fasta` (3.1 MB). The CarafeSharp
  regression's `StellarSubset` leg predicts a 1752-record peptide FASTA on the CPU in seconds.

### Decisions taken for 4a (mine; flag to Brendan in the PR)

- **CarafeSharp.Tasks** is the new library project (namespace `pwiz.CarafeSharp.Tasks`), holding the
  tasks, context, driver, validity, stamps and both engines; `CarafeSharp.exe` keeps `Program.cs`.
  Osprey.exe references it (and so Proteome, Training, Models). Mirrors `Osprey.Tasks`.
- **libtorch for Osprey**: the backend properties and the `UseLibTorch` item groups factor into
  `CarafeSharp/LibTorch.props` / `LibTorch.targets`, imported by both trees' `Directory.Build.*`;
  `Osprey.csproj` and `Osprey.Test.csproj` set `UseLibTorch=true` (CPU; the bin-cuda split stays
  CarafeSharp's). Packaging is 4c.
- **Hosting the declarations**: a copy constructor on `Argument<TContext>` (name, value example,
  listed values, optional-value and variadic flags copied from another `ArgumentBase`) lets Osprey
  wrap each surfaced Carafe declaration as an `OspreyArgument` whose handler records into a
  `CarafeCommandLine` the host owns; `CarafeCommandLine` exposes the surfaced sections
  (`HostedDigestArguments`, `HostedPredictionArguments`), a public `Record`, a public description
  lookup, and `InterpretHostedLibrary(fasta, device, model)` that fills the derived values and
  returns `LibrarySettings` (+ the digest settings). Osprey's usage provider falls through to
  Carafe's text for a hosted name. The static-constructor order (Carafe's runs during Osprey's
  field initialisation, Osprey's body installs last) is made explicit with a comment and a
  `RuntimeHelpers.RunClassConstructor` call.
- **Decision 9 implemented**: `CommandLineGrammar.NameSeparatorsEquivalent` (`_` matches `-` in a
  name), on for Osprey and CarafeSharp; CarafeSharp's declarations renamed to hyphens
  (`miss-c`, `lf-top-n-frag`, ...; camelCase names `minLength`, `fixMod`, `I2L` untouched - a
  word-level rename is not this PR); resx keys unchanged (`_miss_c`); `Interpret` reads by
  declaration (`Has(ARG_MISS_C)`) instead of by string. Error-message literals keep Carafe's
  spelling (the deferred resx extraction).
- **The in-memory digest**: `EntrapmentFastaBuilder` splits into `Build()` (returns the kept,
  sorted quartets; no I/O) and the two writers; a new `LibraryPeptides` (Proteome) is built from
  the quartets - unique peptides, peptide-to-proteins text (`db|ACC|ENTRY` joined by `;`, **no**
  `_pepNNNNN` counter: that counter kept peptdeep from deduplicating FASTA entries by accession,
  which an in-memory digest never meets; Osprey's `CarafeProteinIdNormalizer` already strips it on
  the file route), protein N-term peptides, and the pairing as in-memory
  `DecoyPairPlanner.ManifestEntry` rows. `LibraryGenerator` takes it through a `Peptides` property
  (null = digest `-db` as today) and `LibrarySettings.OutputFile` overrides the fixed name. The
  digest runs inside the prediction task's `Run`, so a resumed run never digests.
- **Osprey's options for 4a**: `--fasta`, `--model`, `--device gpu|cpu`, `--entrapment [<ratio>]`,
  `--entrapment-fasta <foreign.fasta>` in a new "Library Build" group, then the two hosted sections
  "Library Digest" and "Library Prediction". `--training-input` and the tuning section are 4b.
  `--task` and `--export-library` with `--fasta` are refused in 4a (HPC addressing is 4c).
- **Products** land under `--output-dir` when given, else beside `-o`, named from the `-o` stem:
  `<out>.library.blib`, `<out>.library/pairing.tsv` (only with `--entrapment`, for FDRBench).
- **The workflow** is `LibraryBuildWorkflow` in Osprey.exe: phase 1 runs `PredictLibraryTask`
  through a driver that logs `[TASK] PredictLibrary:starting|skipping|done` lines like the search
  stages; phase 2 is `AnalysisPipeline.Run` over the same config with `LibrarySource` = the built
  blib and `DecoysInLibrary` = true. The library's `carafe.command` metadata records Osprey's
  command line.
- **Test fixture for modes 1 and 3**: a synthetic protein FASTA is built in the test from the
  Stellar subset library's peptides (each synthetic protein group's peptides concatenated, so
  trypsin returns them), predicted with `--min-pep-mz/--max-pep-mz` set to the subset's isolation
  window so the library is tiny and the prediction takes seconds on the CPU. Mode 3 predicts from
  a `.carafemodel` the test writes from the pretrained models (`CarafeModelFile.Write`).

### Tasks

- [x] CommonUtil: `NameSeparatorsEquivalent` on the grammar + parser; `Argument<T>` copy constructor
      (`ArgumentBase(ArgumentBase template)`); `CommandLineParserTest` cases (equivalent separators,
      hosted declarations) - the Skyline CommonTest run is still owed (gates)
- [x] CarafeSharp.Tasks project (git mv of the 13 sources, namespace `pwiz.CarafeSharp.Tasks`),
      `InternalsVisibleTo` CarafeSharp and CarafeSharp.Test; `CarafeTask`, `CarafeContext` (plus a
      host constructor with no command line), `CarafeDriver`, `PredictLibraryTask` public
- [x] CarafeSharp declarations hyphenated (104, by script; camelCase names untouched); `Interpret`
      by declaration (`Has(ARG_MISS_C)`); `InterpretDigest` factored; hosted API
      (`HostedDigestArguments`, `HostedPredictionArguments`, `Record`, `GetDescription`,
      `CreateHosted`, `InterpretHostedLibrary`); grammar flag; usage text names options in the
      standard form; "OTHER FORMS ACCEPTED" states the Java Carafe compatibility; `CommandArgsTest`
      (Carafe's list compared hyphenated, four spellings of `--miss-c`, two misspellings refused);
      help HTML regenerated; docs/08
- [x] `EntrapmentFastaBuilder.Build()` split from the writes (`ValidateOutputs` separate,
      `WriteManifest` and `ProteinLabel` public); `LibraryPeptides`; `LibraryGenerator.PeptideSource`
      + `ReadPairing` + `OutputFile` (`BlibOutput`); `PredictLibraryTask(settings, digest)` with the
      digest settings and foreign FASTA in the key; `LibrarySettings.CommandLine` `[JsonIgnore]` (see
      the progress entry); CarafeSharp tests green (104 passed, 8 without data)
- [x] LibTorch.props/targets factored out of CarafeSharp's Directory.Build.*, imported by Osprey's;
      Osprey.csproj on CarafeSharp.Proteome + CarafeSharp.Tasks with `UseLibTorch`; Osprey.Test.csproj
      likewise
- [x] Osprey: `LibraryBuildConfig` on `OspreyConfig` (+ `OptionsWithoutFasta`); `--fasta`, `--model`,
      `--device`, `--entrapment [ratio]`, `--entrapment-fasta` in "Library Build"; the hosted
      "Library Digest" and "Library Prediction" sections; 21 resources + 5 usage strings (resx and
      Designer); `Program.LibraryBuildError`; the banner; `LibraryBuildWorkflow` with its `[TASK]`
      driver; `Program.Run` dispatch; `NotSupportedException` a usage error
- [x] Osprey tests: `OspreyCommandArgsTests.TestEveryArgIsGroupedAndDescribed` knows the hosted
      arguments; `SubsetPipelineTest.LibraryBuild.cs` - `TestSubsetLibraryBuild` (mode 1, warm,
      digest change, underscore spelling, entrapment + pairing.tsv, six refusals) and
      `TestSubsetLibraryBuildSavedModel` (mode 3 from a saved model minted from the pretrained
      weights, warm, missing model refused); help pages regenerated (en, ja, zh-Hans)
- [x] Docs: 20-command-line.md ("Library build", the spelling note), 00-pipeline-architecture.md
      ("A workflow above the pipeline"), CarafeSharp docs/08
- [x] Gates (all green 2026-10-19 evening): Osprey Debug 645 tests + inspection clean; CarafeSharp
      105 passed, 8 without perf data, inspection clean; BiblioSpec 142; Skyline CommonTest
      `TestCommandLineParserGrammars`; `regression.ps1 -Dataset Stellar` PASS (mode 1 vs golden,
      1c, 4, 6); CarafeSharp `regression.ps1 -Leg Chained` PASS
      (`pwiz_tools/CarafeSharp/TestResults/regression/stellar-chained-cpu-20261019-184210`); the
      mode-1 Stellar comparison (`D:\test\osprey-runs\one-command-stellar`, see the progress entry)
- [x] `/code-review medium` (9 findings: 6 fixed in 5d71b74c11, 3 dropped - see the progress entry),
      PR #4876 opened 2026-10-19 evening
- [x] `regression-parallel.ps1 -Dataset All`: 48 PASS / 0 FAIL in 36:38 wall (2026-10-19 evening,
      on the one-command head before the split)
- [x] TeamCity Perf/Regression build 4226386 on `pull/4876` (SUCCESS), and 4226729 on the final head
- [x] Split (Brendan): #4877 holds the spelling work, #4876 the one-command work, stacked (below)
- [x] Merge #4877; re-target #4876 to master and `git merge origin/master`; human review; merge

## PR 4b plan (2026-10-20, after reading the code 4a left)

Branch `Skyline/work/20261020_osprey_one_command_training` in `C:\proj\pwiz`, off master 6aaa29a684.

### Where things stand in the code

- `LibraryBuildWorkflow.Run` (Osprey.exe) runs one `PredictLibraryTask` through `LibraryPhaseDriver`
  (the `[TASK]` lines), writes `pairing.tsv` with `--entrapment`, then sets `LibrarySource` and
  `DecoysInLibrary` on the run's config and calls `AnalysisPipeline.Run`. `OspreyConfig.ShallowClone`
  exists for the derived training config.
- `TrainTask(TrainingSettings)` (`internal`) runs `ModelTrainer`: reads the exports
  `TrainingExportLocator.Find(Identifications, MsFiles)` selects, fine-tunes, writes Carafe's model
  folder and `<OutputDirectory>/<CarafeModelFile.DEFAULT_FILE_NAME>` (stamped), and with
  `Library` set predicts the library from the folder it just wrote. Its key hashes the settings and
  the exports', base model's and pretrained archive's identities (name, length, mtime).
- **The two prediction routes after training are not the same code.** Stage 4-5 of
  `Run-CarafeSharpWorkflow.ps1` (one `CarafeSharp -db -i -ms` call) predicts from the trained folder
  with `ApplyTrainingRunMeta` (precursor window, NCE, instrument and rt_max from the training run's
  `meta.json`) and `PreferSafetensors`; mode 3 (`--model x.carafemodel`) applies the saved model's
  NCE, instrument and rt_max but keeps the command line's m/z window.
- `CarafeCommandLine.InterpretTraining` is private and reads `-i`, `-ms`, `-o`, `-fdr`, `-cor`,
  `-n_ion_min`, `-c_ion_min`, `-lf_frag_n_min`, `-nf`, `-min_n`, `-valid`, `-no_masking`, `-tf`,
  `-seed`, `-device`, `-nce`, `-ms_instrument`, `-activation`, `-analyzer`, `-rt_max`, `-ms2_model`,
  `-model`, `-pretrained`, `-rt_model`, `-rt_align`, `-rt_select`; there is no hosted training API.
- Defaults differ from the lab's workflow: TrainingSettings has Carafe's code defaults (`-cor 0.75`,
  `-n_ion_min 0`, `-c_ion_min 0`, `-valid` off); the script passes `-cor 0.8 -n_ion_min 2
  -c_ion_min 2 -valid -nf 4 -min_n 4 -tf all`.
- A fine-tune of the Stellar subset takes 44 s on the CPU in Release (chained leg,
  `pwiz_tools/CarafeSharp/TestResults/regression/stellar-chained-cpu-20261019-184210`, 20 epochs);
  CarafeSharp's own tests shorten it through `ModelTrainer.ConfigureFineTune` (internal).

### Shape (proposed)

| Phase | Task class | Settings | Checkpoint |
|---|---|---|---|
| PredictTrainingLibrary | `PredictLibraryTask` | the run's library, no entrapment, pretrained or `--model` | `<out>.library/initial.blib` |
| TrainingSearch | `AnalysisPipeline.Run` over a `ShallowClone` | `InputFiles` = `--training-input`, `-o` `<out>.library/training/training.blib`, `--output-dir` that folder, the initial library with its decoys, `--training-export` on, the run's `--cache-dir` | `<stem>.training.parquet` per tuning run, Osprey's own stamps |
| TrainModel | `TrainTask` (made public), `Library` = null | `-i` the training folder, `-ms` the tuning runs, `-fdr` from `--training-export-max-q`, `--model` as the base model, the hosted tuning options | Carafe's folder `<out>.library/model/`, and the model file written as `<out>.carafemodel` (a `TrainingSettings.ModelFile` override, as 4a's `LibrarySettings.OutputFile`) |
| PredictLibrary | `PredictLibraryTask` | the run's library with entrapment, `ModelDirectory` = the trained folder, `ApplyTrainingRunMeta`, `PreferSafetensors`, the training type - stage 4-5's prediction exactly, as a separate task | `<out>.library.blib` |
| Search | the canonical four | as 4a | `out.blib` |

- Separate TrainModel and PredictLibrary (not `TrainTask` with `Library`) so a change to
  `--entrapment` or `-i` never re-trains; the trained folder is the final prediction's key input.
- `--training-input` (variadic, as `-i`) in "Library Build"; a new hosted "Library Tuning" section
  (`--tf`, `--cor`, `--n-ion-min`, `--c-ion-min`, `--nf`, `--min-n`, `--valid`, `--no-masking`,
  `--rt-align`, `--rt-select`, `--rt-reference`, and `--seed` if it does not collide); an
  `InterpretHostedTraining(exports, runs, output, baseModel, device, fdr)` beside
  `InterpretHostedLibrary`. `--rt-reference` refused without `--training-input`.
- `LibMetadata` gets `osprey.training_input` (decision 4); `SpectrumSourceFiles` names `-i` only.
- Test seam: the subset test needs a short fine-tune; an epoch override reachable from Osprey.Test
  (not an option, not an env var).

### Questions for Brendan before coding (answered 2026-10-20: both as proposed)

1. Tuning defaults: CarafeSharp's (Carafe's code defaults, one declaration set) or the lab
   workflow's (`-cor 0.8 -n_ion_min 2 -c_ion_min 2 -valid`)? Proposed: CarafeSharp's; the Stellar
   comparison passes the script's values explicitly.
2. The `regression.ps1` one-command leg the PR plan names: the skill now puts pipeline mechanics in
   `SubsetPipelineTest` and keeps `regression.ps1` for real-data results, and a mode-2 Stellar
   leg trains on the CPU on the TeamCity agent. Proposed: the chained leg's structural checks move
   into a `SubsetPipelineTest` mode-2 case and the chained leg retires; the real-scale mode-2 run
   stays the hand comparison against the six-stage script.

### Tasks

- [x] Questions above answered (Brendan: CarafeSharp's defaults; the gate in `SubsetPipelineTest`,
      chained leg retired)
- [x] CarafeSharp: `TrainTask` public (with a host-set name and `ConfigureFineTune`),
      `PredictLibraryTask` host-set name, `TrainingSettings.ModelFile` (`ModelTrainer.ModelFilePath`),
      `HostedTrainingArguments` and `InterpretHostedTraining` (paths left to the host),
      `CheckModelTrainingType` factored out of `Interpret`. No `CommandArgsTest` case: the hosted
      tuning is covered end to end by the Osprey tests
- [x] Osprey: `--training-input` (variadic) in "Library Build"; hosted "Library Tuning" section (12
      options); `LibraryBuildSettings` (library + training) out of `ParseArgs`; refusals (a tuning
      option without `--training-input`, the runs without `--fasta`, a missing tuning run, duplicate
      stems); the banner's tuning line; export settings apply to the tuning search without
      `--training-export`; 5 resources + 1 usage string
- [x] `LibraryBuildWorkflow`: PredictTrainingLibrary, the tuning search (a `ShallowClone`, its own
      `--output-dir`, a FRESH task set - see the progress entry), TrainModel, PredictLibrary from the
      trained folder; `ArtifactPaths.CacheFallbackDir` so both analyses share the spectra cache;
      `osprey.training_input` in the result's LibMetadata
- [x] `SubsetPipelineTest.LibraryTuning.cs`: `TestSubsetLibraryBuildTuned` (cold, the chained
      leg's checks, mode 3 from the saved model with the same spectra, warm, `--entrapment`, model
      deleted, `--seed`, `-i` only, four refusals) and `TestSubsetLibraryBuildTunedHeldOut` (a tuning
      run absent from the output; `--model` + `--training-input` naming its base by SHA-256)
- [x] Docs 20 and 00; help pages regenerated (en, ja, zh-Hans)
- [x] Gates: Osprey Debug 648 + inspection; CarafeSharp 105 (8 without data) + inspection;
      `regression.ps1 -Dataset Stellar` PASS; CarafeSharp `regression.ps1 -Dataset StellarSubset`
      PASS after the retirement; the mode-2 Stellar comparison (progress entry). BiblioSpec not run:
      `BiblioSpec.IO` untouched
- [x] Chained leg retired (Brendan): `regression.ps1`, `tcregression.ps1`, `RegressionTest`,
      CarafeSharp docs 04/06, `ai/scripts/CarafeSharp/Measure-CumulativeCoverage.ps1`; after #4878
      merged, so the doc edits did not conflict
- [x] `/code-review medium`: 10 findings, 8 fixed in b9bf53b1cb (`--rt-reference` checked before
      any phase; a lost model folder tunes again; folder-format tuning runs accepted; stems checked
      across inputs and tuning runs; `ArtifactPaths.ResolveCacheAs` replaces `CacheFallbackDir` so
      the tuning search resolves the cache exactly as the output's search, no data-dir probe;
      `training.blib` records no `osprey.training_input`; a misplaced doc comment; `TrainTask`'s name
      fallback), 2 dropped (the further-tuning metric check exists in `FineTuneLoopTest`; the second
      in-memory digest is seconds, decision 7). Gates re-run green (Osprey 648, CarafeSharp 105)
- [x] PR [#4885](https://github.com/ProteoWizard/pwiz/pull/4885) opened 2026-10-20
- [ ] `regression-parallel.ps1 -Dataset All` (running); TeamCity Perf/Regression on `pull/4885`
      (ask first); human review; merge

## Progress Log

### 2026-10-19 - Designed
Written in the design window while #4868's Skyline Perf and Tutorial run (the last check on the
#4867 + #4868 chain) finishes; the six decisions settled with Brendan the same afternoon (section
"Decisions"). Nothing coded. Next: merge the chain
(handoff `ai/.tmp/handoff-20261019_skyline_blib_io.md` has the order), `/pw-complete` the BLIB
sprint's TODO, move `TODO-20261014_osprey_carafe_integration.md` to `completed/2026/10` with a
closing entry that points here, then `git mv` this TODO and its HTML to `active/` with the date
and create PR 4a's branch.

### 2026-10-19 evening - Branch cut, plan written
#4867 merged 21:03 UTC and #4868 at 22:26 UTC; the two predecessor TODOs were already in
`completed/2026/10`. Created `Skyline/work/20261019_osprey_one_command` off `origin/master` in
`C:\proj\pwiz`, moved this TODO and its HTML to `active/`, and read the code the design names
(parsers, pipeline contract, `LibraryGenerator`, `EntrapmentFastaBuilder`, the test fixtures, the
chained regression leg). The "PR 4a plan" section above records what was found and the decisions
taken for the PR. Coding starts with the CommonUtil grammar change.

### 2026-10-19 night - PR 4a coded: modes 1 and 3 run end to end on the subset
Brendan (mid-session): "Carafe and Osprey help documentation should list arguments in the standard
form noting compatibility with the Java tool form" - decision 9 confirmed; both helps now list
`--miss-c` and say `-miss_c` is accepted for Java Carafe compatibility.

What runs, on the Stellar subset in `SubsetPipelineTest` (CPU, Debug): the one command predicts
674 precursors (337 targets + 337 decoys at the window's charges, from 651 digested peptides)
in about a second, searches them, and reports **136 precursors at 1% FDR** against about 177
from the curated subset library; a warm re-run skips all five tasks; `--miss-c 0` predicts again
(552 precursors) and the search follows; `--miss_c 0` after it skips everything (same library);
`--entrapment` doubles the library and writes `output.library/pairing.tsv` with `p_target` rows;
a saved model minted from the pretrained weights (`--model`) reports the same as mode 1. The two
tests take 9 s and 2 s. Hand runs are under `D:\test\osprey-runs\one-command-subset\run1`
(Chronologer, 136 reported) and `run2` (`--rt-model alphapeptdeep`, 15 reported).

Findings worth keeping:
- **The AlphaPeptDeep RT model collapses this window: 15 reported against Chronologer's 136**,
  with the same first pass (259 vs 349 targets at 1% run FDR) - the loss is in the second pass.
  Carafe's default RT model would be the wrong default here, which is what #4759 found at
  scale; the mode-3 fixture therefore saves Chronologer, as CarafeSharp's training does.
- **`LibrarySettings.CommandLine` was in the validity key** (CarafeValidity hashes the whole
  settings object), so the same options spelled differently (`--miss_c` for `--miss-c`, a
  different order) re-predicted the library. It is `[JsonIgnore]` now: provenance, not a
  setting. CarafeSharp.exe keys change with it, so a library CarafeSharp predicted before this
  branch is predicted again once - a version change already does that.
- `EntrapmentFastaResult.PTargetEntries` is counted while writing the FASTA, so a build without
  files has none; `LibraryPeptides.HasEntrapment` reads the quartets instead.
- The Osprey package (`package.ps1` publishes per RID) now carries libtorch CPU (about 330 MB)
  and the pretrained models; 4c measures and decides the layout, but the TeamCity artifact
  grows on this PR already. Say so in the PR.
- `--task` with `--fasta` is refused with a message naming the two-step alternative; the
  addressing is 4c.

Gates at the end of the session: Osprey Debug tests (645) + inspection, CarafeSharp tests +
inspection, BiblioSpec (142) all green. Running when Brendan ended the session, outcome unrecorded:
the mode-1 Stellar comparison (`D:\test\osprey-runs\one-command-stellar`, reference prediction at
79%), `regression.ps1 -Dataset Stellar -NoBuild`, and the Skyline build for
`TestCommandLineParserGrammars`. Not yet run: CarafeSharp `regression.ps1 -Leg Chained`. The branch
is uncommitted; commit message and PR body are drafted in the session folder.

### 2026-10-19 late evening - Gates green, the Stellar comparison read, one fix from it
The three gates left running finished green (task list above). The mode-1 Stellar comparison
(`ai/.tmp/sessions/20261019-one-command/Compare-StellarOneCommand.ps1`; reference = the lab
workflow's stages 1a, 2 and 6 on the CPU with Chronologer, `hela-filtered.fasta`, 437,794 peptide
forms) is under `D:\test\osprey-runs\one-command-stellar`:

- **Search results identical** in every content table (`compare-result*.txt`: RefSpectra 33,194,
  RefSpectraPeaks, RetentionTimes 99,582, Proteins 4,633, RefSpectraProteins, Modifications);
  only LibMetadata (command, validity key), LibInfo (name, time) and the library file name in
  SpectrumSourceFiles differ. Per-run counts 26,424 / 26,911 / 27,148 at 1% run FDR, both ways.
- **Library identical as content** (`compare-library-content-one-command-2.txt`, ids excluded):
  483,560 spectra (sequence, charge, m/z, RT, peaks), 483,554 DecoyPairs rows and 179,426 pair
  groups by sequence, 510,388 peptide-to-accession rows with the reference's `_pepNNNNN` counter
  stripped. `compare_blib.py` still says DIFFERENT because it hashes ids: 8 of 483,560 spectra
  are isobaric ties (DEELEER / EELEEDR / EEEEEVR; LQQQEQR and its group) that the two routes
  order differently, so their ids and the DecoyPairs rows naming them swap. The Proteins table
  is 21,294 rows against the reference's 379,182 (one accession per protein, no counter).
- **One defect found and fixed**: the first run (`one-command/`) lacked 3 of the 510,388 protein
  rows, all decoy accessions (`EEEEEVR` under `decoy_sp|P35579|MYH9_HUMAN` and `MYH10`,
  `QEQQQLR` under `decoy_sp|Q8N8S7|ENAH_HUMAN`): a sequence generated twice (a cycle decoy that
  is also another target's reverse) kept only its first quartet's proteins, where the FASTA
  route's `MapPeptidesToProteins` unions every record's. `LibraryPeptides.Add` now merges the
  later record's labels into the text (`MergeProteins`); CarafeSharp and Osprey gates re-run
  green and the re-run (`one-command-2/`) has all 510,388.
- Wall: prediction 112-140 s on the CPU at 16 threads, the search 2-3 min; the one command
  6.1 min against the reference's 1a+2 (2.9 min predict) + 6 (3.1 min) with copies between.

Scripts kept in the session folder: `peek_blibs.py`, `diff_blib_columns.py` (per-column diff
joined on id), `hash_blib_content.py` and `diff_pairs_proteins.py` (id-independent content
comparison), `Rerun-OneCommandStellar.ps1`. Worth folding the id-independent comparison into
`compare_blib.py` as a mode if the one-command leg becomes a regression leg in 4b.

Committed (ac26edd5fc, 61 files) and pushed; `/code-review medium` returned 9 findings, each
checked against the code:
- Fixed (5d71b74c11): the `--task` refusal formatted `LibraryPath(config)` before `-o` was
  validated (null path; now spelled as the help does, `<output>.library.blib`, with a test case);
  the entrapment pairing manifest was written only after the stamped library was committed, so a
  failed write left a current library that never got one (now written after a skipped prediction
  too, from the same seeded digest); `--rt-reference` was hosted although it works only with a
  model trained on aligned runs and fails deep in prediction with a stack (dropped from the
  hosted set; 4b hosts it with tuning); the "CarafeSharp only." suffix read wrong in Osprey's
  help (now "Not in Java Carafe." in both helps) and `--rt-model`'s text named `--model-dir`;
  `MIN_ENTRAPMENT_RATIO` was declared twice (Osprey uses `EntrapmentFastaSettings`'s).
- Dropped: "the refusal tests check only the exit code" - wrong, `RunOspreyExpecting` asserts
  exactly one `Error:` line and no exception text; "error messages spell Carafe's underscores"
  - the deferred resx extraction, recorded in the 4a plan; "exception classification lives in
  three places" - CarafeSharp's refusal types are a CarafeSharp item, not this PR; "UseLibTorch
  on Osprey.exe grows every build and shares cpu/cuda bins" - packaging is 4c and the PR says
  so; Osprey is CPU-only in 4a.
PR #4876 opened with the body in the session folder.

### 2026-10-19 late evening (2) - Split into two PRs; messages spell options as the help does
Brendan: the argument refactoring (hyphenated declarations, the grammar rule, the help) is its
own thing, extensive enough to obscure the one-command changes, so it merges first on its own.
And: "Error messages should spell things the way the help spells them, not the way that Java
Carafe spells them" - the deferral in the 4a plan is withdrawn.

- **#4877** (`Skyline/work/20261020_carafesharp_arg_spelling`, built in `pwiz-work1` so the
  all-datasets regression could keep running in `pwiz`): the grammar rule
  (`NameSeparatorsEquivalent`, on for CarafeSharp and Osprey), the hyphenated declarations,
  `Interpret` by declaration, the help in standard form with the Java Carafe note, "Not in Java
  Carafe", `LibrarySettings.CommandLine` out of the validity key, docs/08 and 06 - and every
  message naming an option through its `ArgumentText` (the parse helpers take the declaration;
  ~45 literal messages in `CarafeCommandLine`, `ModelTrainer`, `LibraryGenerator`,
  `CarafeModelFile`, `CarafeModelOrigin`, `EntrapmentPairingValidator`, `LibraryOutputs`; the
  Training and Models assemblies, below the declarations, carry the literal standard form). The
  parser's own errors (unknown option, missing value) still quote the token as typed, by design.
  Script: `ai/.tmp/sessions/20261019-one-command/spell_options_as_help.py` (asserts every
  replacement's count; strips the raw-string `\'` it once left in five lines). Gates green:
  CarafeSharp 105 + inspection, Osprey 643 + inspection, Skyline `TestCommandLineParserGrammars`.
  `/code-review medium`: 9 findings, 8 fixed (two false doc claims about Osprey, fixed by giving
  Osprey the rule; usage lines from `ArgumentText`; docs/08 spellings; the saved-models doc's
  quoted warning; `--rt-model` text names "a saved model or model folder"; the one-time key change
  noted; two stale framework comments), 1 dropped (literal `--i`/`--tf` in assemblies that cannot
  see the declarations).
- **#4876** re-based on #4877 by merging its branch in twice (one conflict round:
  `CarafeCommandLine.cs`, docs/08, `CommandLineParserTest.cs`, all resolved as the one-command
  side plus the spelling script) and re-targeted onto #4877's branch. Gates on the merged tree:
  CarafeSharp 105 + inspection, Osprey 645 + inspection, Skyline parser test. Not in #4876 any
  more: the copy constructor is still there (hosting needs it), but the hyphenation, grammar and
  message work are #4877's.
- Still open in the CarafeSharp docs: `01-model-spec.md`, `03-performance.md`, `04-testing.md`,
  `06-saved-models.md`, `07-chronologer.md` show Carafe's spelling in their command-line examples
  (about 120 tokens); they run as typed, and 08 states the rule. A doc sweep, not this PR.
- Copilot refused both PRs (quota); `/code-review medium` is the AI review on each. GPU: CarafeSharp
  runs on this machine's RTX 4000 Ada from the `-Torch cuda` build with nothing installed
  (`ai/docs/osprey-library-generation-guide.md`, "GPU (CUDA) setup"; StellarSubset 0.41 min GPU
  vs 0.91 min CPU).

### 2026-10-20 - #4877 merged; #4876 on master

- #4877 merged as commit fd839c04cb (night session, squash message approved by Brendan). All 20
  checks green, including Osprey Perf/Regression 4226410 and Skyline PR Perf and Tutorial 4226705.
  Branch deleted local + remote; `C:\proj\pwiz-work1` left detached at master. This TODO stays
  active for #4876.
- #4876 re-targeted to master and brought current: merged #4875 (e9e349fd34, clean; Osprey Debug
  646 + inspection 0), then master after #4877's squash (e614040a15). The squash-merged-parent
  conflicts (CarafeCommandLine.cs, docs/08, CommandLineParserTest.cs) resolved to the branch side;
  the resulting tree is identical to e9e349fd34's (a69a08ad4b), and master's 26 #4877 files equal
  #4877's head, so the gated content is what is pushed.
- TeamCity Perf/Regression on `pull/4876`: 4226386 (pre-split head, SUCCESS); 4226729 (final head,
  run 2 of 2).

### 2026-10-20 - PR 4a merged

PR #4876 merged as commit 6aaa29a684 (squash message approved by Brendan). All 18 checks green on
head e614040a15, including Perf/Regression 4226729; master's tree after the merge equals that
head's tree (a69a08ad4b). Shipped: modes 1 and 3 of the one-command library build. No Skyline PR
Perf and Tutorial check ran on #4876 (that config came to #4877 from the nightly trigger only).
This TODO stays active: PR 4b (mode 2, `--training-input`) and 4c (HPC and packaging) follow on
new branches off master.

### 2026-10-20 - CarafeSharp doc sweep opened as #4878

- [#4878](https://github.com/ProteoWizard/pwiz/pull/4878) (branch
  `Skyline/work/20261020_carafesharp_doc_spelling`, documentation only): docs 01/03/04/06/07 name
  every option in the standard form (110 lines). Only single-dash tokens naming a declared
  CarafeSharp option changed; PowerShell parameters, the Python trainer's flags (`--tf_type`,
  `--seed`) and Osprey's `--training-export` did not. Script:
  `ai/.tmp/sessions/20261019-one-command/spell_docs_sweep.py`. No TeamCity builds triggered by hand
  (Brendan: docs only, the Osprey unit tests are enough).
- Next: PR 4b (mode 2, `--training-input`) in a fresh session, on a new branch off master; see
  "PR plan", "Gates" and "Open questions" above.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261020_osprey_one_command_4b.md` before starting work.

### 2026-10-20 - PR 4b branch cut, plan written
Cut `Skyline/work/20261020_osprey_one_command_training` from master 6aaa29a684 in `C:\proj\pwiz` and
read the code 4a left (`LibraryBuildWorkflow`, `PredictLibraryTask`, `TrainTask`, `ModelTrainer`,
`CarafeCommandLine.InterpretTraining`, `CarafeValidity`, the six-stage script, the chained leg). The
"PR 4b plan" section records the shape and two questions for Brendan; nothing coded.

### 2026-10-20 - PR 4b coded and gated; chained leg retired

Brendan answered both plan questions as proposed (CarafeSharp's tuning defaults; the end-to-end gate
in `SubsetPipelineTest`, chained leg retired), and approved merging #4878 (fb5afc569d) so the
retirement's doc edits would not conflict. Branch commits: be73f44f51 (mode 2), 496811f3b7 (master
merged), 92a673a61f (chained leg retired).

Findings worth keeping:
- **Osprey's task objects carry state between their stages**: `PerFileRescoreTask._poolPlan` (the
  survivor plan SecondPassFDR rebuilds against) is an instance field. The first cut reused
  Program's task set for both analyses in one process, and the output's SecondPassFDR failed with
  "PerFileRescoring rebuild: reset 116 peaks ... but the rescore reset 126". The tuning search now
  gets `OspreyTasks.Create().PipelineFor(null)` of its own (documented in 00-pipeline-architecture).
  Anything that runs two analyses in one process must do the same.
- **One subset run alone trains nothing**: tuned on one of the three Stellar subset runs, the first
  pass keeps 109 at 1% but the second pass keeps 0 of 155 reconciled targets, so the export is
  empty and TrainModel fails ("No RT training rows"). The full-size one-run tuning (the lab's
  habit) is fine (below). The tests tune on all three subset runs.
- Two one-epoch tunes in a row (the further-tuned test) report 22 precursors; the count floor
  applies only to a single tune.

**The mode-2 Stellar comparison** (`ai/.tmp/sessions/20261020-4b/Compare-StellarOneCommandTuned.ps1`;
reference = all six stages of `Run-CarafeSharpWorkflow.ps1` on the CPU with Chronologer; one command
`--training-input <_21> --entrapment` with stage 4-5's tuning values) under
`D:\test\osprey-runs\one-command-stellar-tuned`:
- **Tuned model identical** (`compare-model-one-command.txt`): `ms2.safetensors`, `rt.safetensors`,
  `rt_maps.json`, `meta.json` and the metrics byte-identical; the manifest differs only in the time,
  the creator's version, the stamp (task `TrainModel` vs `Train`) and the hashes of the training
  library and search files.
- **Final library identical as content** (`compare-library-content-one-command.txt`): 968,394 spectra
  identical; 968,332 DecoyPairs, 179,648 pair groups and 1,022,108 peptide-to-accession rows
  set-equal; ids differ by the isobaric ties 4a found. The training library matches 4a's.
- **Result identical** in every content table (`compare-result-one-command.txt`: RefSpectra 35,473,
  RetentionTimes 106,371, Proteins 4,518, RefSpectraProteins, Modifications); LibInfo, LibMetadata
  (one more row, `osprey.training_input`) and the library name in SpectrumSourceFiles differ.
- Wall: the one command 15.8 min (PredictTrainingLibrary 109 s, tuning search 77 s, TrainModel 416 s,
  PredictLibrary 214 s, search 132 s) against the script's 16.8 min (2: 1.9, 3: 1.5, 4-5: 10.7,
  6: 2.6 min), both on the CPU at 16 threads, sharing the machine with the Stellar regression.

Snapshots used: `D:\test\osprey-runs\_bin\one-command-4b-wip1` (Osprey) and
`D:\test\osprey-runs\_bin\carafesharp-4b-wip1` (CarafeSharp), both from be73f44f51's tree before the
commit.

### 2026-10-20 afternoon - Rename, resume demonstration, one workflow page (Brendan)

Brendan asked to land three more things in #4885 rather than a new PR (decisions 10-12), and
pointed out that before 4b mode 3 had only been tested with a model minted from the pretrained
weights; 4b's `TestSubsetLibraryBuildTuned` is the first Osprey-only test of a real tuned model
through `--model`. TeamCity build 4228048 on b9bf53b1cb was cancelled as superseded.

- **Rename**: `<out>.predicted.blib` and `<out>.predicted/` (`LibraryBuildWorkflow.PREDICTED_SUFFIX`);
  docs 20 and 00, help pages, and a paragraph in 20 on what the two `.blib` files hold.
- **Stop hook**: `OSPREY_STOP_AFTER_TASKS=N` (`OspreyEnvironment.StopAfterTasks`, read per access);
  `TaskBudget` counts tasks that RAN in both Osprey drivers (`OspreyPipelineDriver`,
  `LibraryPhaseDriver`) and throws `TaskBudgetSpentException` after the Nth task's `OnDone`;
  `AnalysisPipeline` and the workflow let it pass, Program logs `[TASK] stop:after N (...)` and
  exits 0. The shared `PipelineDriver` (CommonUtil, Skyline's too) is untouched.
- **Tests**: `TestSubsetLibraryBuildTunedStepwise` (12 runs: run k skips k tasks and starts exactly
  the next, in straight-through order; result equal to straight-through) in 12 s; regression
  **mode 13** (`regression.ps1 -StepwiseOneCommand`, opt-in, Stellar): PASS, 11 tasks one per run,
  straight 18:26 vs stepwise 19:08 over 12 runs
  (`ai/.tmp/sessions/20261020-4b/logs/regression-mode13.log`). The script's header rule now names
  the exception.
- **Workflow page**: `Osprey-workflow.html` part 1 "Building the library" (the draft's drawing, its
  `--task` labels changed to task names since the cluster addressing is 4c, the hosted option names
  corrected) and part 2 the search pipeline, with a contents bar
  (`ai/.tmp/sessions/20261020-4b/merge_workflow_pages.py`). Not seen in a browser this session
  (the extension was not connected); markup checked balanced.
- **regression.html** regenerated (Write-RegressionMatrix with mode 13 as an opt-in row) from the
  2026-10-20 lane logs, `-VerifyAgainst` clean: 48 lines; slower lane 37 min.

Commit f63bcfd169. Gates: Osprey Debug 649 + inspection (after the rename and the hook); the help
test re-run after regeneration.

### 2026-10-20 evening - Second review, TeamCity

`/code-review medium 4885` (second cycle, triage reported before fixing): 9 findings; Brendan approved
fixing 3 in 9719d88da2 - a failed task no longer counts toward `OSPREY_STOP_AFTER_TASKS` (it was
reported as a clean stop, exit 0); `--model` naming the model the run writes (`<out>.carafemodel`)
is refused (it could be deleted, and a re-run never converged to a skip); the model-folder check
compares each packed file's SHA-256 with the model file's, not just its name. Dropped 6: a late (not
silent) failure for `--rt-reference` with an AlphaPeptDeep saved model; held-out runs without a
source but with a cache (a feature gap); the tuning search's unread protein and summary reports
(seconds); the budget in CommonUtil's shared driver (Skyline's too; finding 1's fix removed the bug
the reviewer tied to the placement); the `ArtifactPaths` static swap (existing design); a redundant
`?? TASK_NAME`. Osprey Debug 649 + inspection green. TeamCity Perf/Regression 4228241 on
`pull/4885` (9719d88da2) queued.

GPU (Brendan's question): CarafeSharp has run on this machine's RTX 4000 Ada from a `-Torch cuda`
build (currently only in `pwiz-scanmajor`); every run this session was on the CPU, and Osprey.exe
links only the CPU libtorch, so `--device gpu` in the one command falls back to the CPU. **4c**:
give Osprey a CUDA build (`Build-Osprey.ps1 -Torch cuda`, as CarafeSharp's) with the packaging, and
measure the one command on the GPU.

### 2026-10-21 - PR 4b merged

PR #4885 merged as commit 7819a9b6ac (squash message approved by Brendan). All 16 checks green on
head 4614fdde38, including Osprey Linux .NET 4229243; TeamCity Perf/Regression 4228241 SUCCESS on
9719d88da2 (the later commit changed only a subset test). Shipped: mode 2 (`--training-input`), the
`<out>.predicted.blib` name, `OSPREY_STOP_AFTER_TASKS` with the stepwise subset test and opt-in
regression mode 13, the retired chained leg, and the library build as part 1 of
`Osprey-workflow.html`. `C:\proj\pwiz` is left detached at master (master is checked out in the
`pwiz-scanmajor` worktree); branch deleted local + remote. This TODO stays active (Brendan: a
checkpoint, the sprint continues).

The Linux failure (4228252) was `TestSubsetLibraryBuildTunedHeldOut`: its further tuning (a second
one-epoch tune at the first's learning rate) left a model so marginal that on Linux nothing passed
1% in the output's search, and PerFileRescoring then threw "The saved first-pass model carries no
list of precursor candidates from proteins with 2 or more detections ... Run --task FirstPassFDR
again". The test now tunes further at learning rate 0 (4614fdde38).

**Next item (Brendan, 2026-10-21): a search that detects nothing fails with an error, never an
empty result.** Two defects, both before this branch:
- An empty protein stratum is indistinguishable from a missing one: `FirstPassModelIO.SaveStratum`
  writes no file for an empty stratum, `LoadStratum` reads an empty one as missing, and
  `PerFileRescoreTask.CreatePass2Worker` (`PerFileRescoreTask.cs:1147`, from #4816) refuses with a
  message advising a re-run that cannot help. `FirstPassFdrTask.cs:2151` reads the same field for
  resume.
- SecondPassFDR's "No precursors pass the FDR threshold. Writing an empty .blib." succeeds with
  output that only a later step can notice (Brendan: "It is generally a bad idea to succeed with
  useless or nominally correct output").
Shape: when nothing passes (first pass, or the reported set), the run ends with a clear error
naming what passed nothing and why (precursors at the run FDR, the library and runs), with a
failure exit code and no `.blib`; a subset test where nothing passes asserts exactly that. Own PR,
since it changes FirstPassFDR's artifacts and the empty-result contract. The one command's own
phases should get the same rule (a tuning search with an empty export already fails in TrainModel,
with "No RT training rows"; check its message names the tuning runs).

### 2026-10-21 - Handoff: a clean-up PR first, then 4c

Brendan's plan for the next session: a grab-bag clean-up PR of things left from earlier sessions,
then the next full PR (4c: packaging and GPU use). The clean-up PR's items:

1. **A search that detects nothing fails with an error** (the "Next item" in the merged entry
   above): the empty-stratum refusal in PerFileRescoring and SecondPassFDR's empty `.blib` both
   become one clear error, failure exit code, no `.blib`; a subset test where nothing passes.
2. **Reconsider `.carafemodel`** (Brendan: long, and the format is not evident). What it is today:
   a ZIP archive (`CarafeModelFile`, `CarafeSharp.Proteome`; `EXTENSION`, `DEFAULT_FILE_NAME`
   `carafe_fine_tuned_model.carafemodel`) holding `manifest.json` (stamp, lineage, per-entry
   SHA-256), the safetensors (`ms2.safetensors`, `rt.safetensors`, optional base MS2), `rt_maps.json`,
   `meta.json` and `model_evaluation_metrics.json`. Bring Brendan options (a shorter extension; say
   in the help and docs/06 that it is a ZIP) and decide whether old files keep opening.
3. **Command-line help review, for consistency with Skyline** (leave `--name=value` vs
   `--name value` alone): value placeholders as Skyline writes them (`--in=path/to/file.sky`), so
   `--input-list path/to/list.txt` and `--work-dir path/to/dir`, not `<list.txt>` / `<dir>`; then a
   full read of every group's text (Osprey's resx usage strings and the hosted CarafeSharp ones,
   e.g. `--tf` still names `--model-dir`, which Osprey does not have). Regenerate the help pages.
4. **The HPC section of the help names no library-build tasks.** The cluster addressing of
   PredictTrainingLibrary / TrainModel / PredictLibrary is 4c; until then the section should at
   least say `--fasta` runs as one process and is refused with `--task` (check whether 4c lands
   soon enough that this is only a sentence).

Then **4c**: HPC addressing and harness staging, packaging (installers, TeamCity artifacts, CarafeSharp
+ CPU libtorch; measure the package), Osprey's CUDA build (`Build-Osprey.ps1 -Torch cuda`) and the
one command measured on the GPU, `Run-CarafeSharpWorkflow.ps1` reduced, `Carafe-workflow.html`
folded into `Osprey-workflow.html`. The rulesets note: no Osprey check is required on master (only
Core and Skyline), so watch the Osprey Linux and Windows checks by hand before every merge.


### 2026-10-21 - Clean-up PR: item 1 coded; a protein-compact defect found

Branch `Skyline/work/20261021_osprey_one_command_cleanup` (from master 7819a9b6ac), uncommitted.

**Item 1 (a search that detects nothing fails) - done, gates green.** FirstPassFDR's compaction
gate (`CompactFromSidecars`, shared by compute and resume) logs one Error: naming the library,
`--reconciliation-compaction-fdr` and `--protein-fdr` when no precursor survives, exit 1, so the
run stops before the second pass. SecondPassFDR throws `UserMessageException` (caught beside
`BlibOutputException`) when nothing passes `--experiment-fdr`: Error:, exit 1, no `.blib`; the
"Writing an empty .blib" warning and its resource (with ja/zh-Hans) are gone. An empty stratum is
now written and read back as empty (`FirstPassModelIO.SaveStratum`/`LoadStratum`), and
`PerFileRescoreTask.CreatePass2Worker` and `Pass2FdrSidecar.ComputePass2FrozenCompetition` refuse
only a missing one. `OspreyArgNames` gained `EXPERIMENT_FDR`, `RECONCILIATION_COMPACTION_FDR`,
`PROTEIN_FDR`. `SubsetPipelineTest.TestSubsetNothingPasses`: thresholds 0 (first pass), experiment
FDR 0 (second pass), and one protein per peptide (empty stratum, ends in the second-pass error).
Gates: Osprey Debug 650/650 + inspection 0; `regression.ps1 -Dataset Stellar` PASS.

**Defect found, its own item (Brendan, 2026-10-21: a defect, not this PR).** Protein-compact never
reports a first-pass passer outside the stratum unless reconciliation moved its peak:
`StreamingFdr.CompeteOneFile` admits only stratum members and changed peaks, the worker stamps
everything else run q = 1.0 (`Pass2PerFileWorker.cs:235`), and `FoldAndPublishExperimentScope`'s
best-run floor raises the carried pass-1 experiment q to that 1.0. The comments say the opposite
(`Pass2FdrSidecar.cs:1182` "report = pass1 U stratum passers ... never drops an already-passing
peptide"; `FinishRecord`). Evidence: the one-protein-per-peptide subset search had 179 first-pass
passers, "Raised 179 of 358 experiment-level precursor candidate q-values", 0 reported
(`ai/.tmp/sessions/20261021-cleanup/nothing-passes-1.log`). On real data this drops peptides of
single-hit proteins; a fix moves the goldens. Measure the Stellar loss before choosing a fix.

**Item 2 decided (Brendan): `.carafemodel` becomes `.model.zip`.** Old files keep opening: the
reader goes by content (`manifest.json` format `carafemodel-1/2`), not the name.

Committed: 5b75e2f9b0 (item 1), 8b5dea4a69 (item 2). Gates: Osprey 650/650 + inspection 0 (help
pages regenerated), CarafeSharp 105 passed + inspection 0 (8 Carafe parity tests NotExecuted: no
reference data on this machine). **#4849 (Nick, draft)** lists a folder's models with
`"*" + CarafeModelFile.EXTENSION` in `CarafeModelChooserDlg`; whichever merges second switches it to
`CarafeModelFile.FilePatterns` so `.carafemodel` files stay listed. **#4823** touches
`Pass2FdrSidecar`, `SecondPassFdrTask`, `ExperimentQFloors`, the tasks resx: expect small conflicts.

**4c candidate (Brendan asked, 2026-10-21): ship the default models as a `.model.zip`.** A tuned
file is the same networks with fine-tuned weights plus a manifest; a model absent from it is the
pretrained one. Packaging the pretrained MS2/RT/CCS (and Chronologer) as one default model file
makes mode 1 mode 3 with the default, answers the package-size and Chronologer `.pt` questions, and
`SubsetPipelineTest.WriteSavedModelFromPretrained` already does it. Cost: the MannLabs archive's
SHA-256 pin moves into the manifest, and the Carafe parity tests must show identical predictions.

**Item 3 decided (Brendan): follow Skyline** - placeholders from resources (`path/to/file` +
extension, `path/to/folder`), translated as Skyline's are.

**Items 3 and 4, and what Brendan's help review added (2026-10-21, uncommitted):**
- Placeholders as Skyline's (`OspreyResources` `OspreyCommandArgs_PATH_TO_FILE/FOLDER`,
  `<integer>`, `<number>`, with Skyline's ja/zh); CarafeSharp's as literals (it has no
  translations). USAGE lines and the missing-argument errors built from the declarations
  (`OspreyCommandArgs.UsageInput/Library/Output/Fasta`; `Program.USAGE_*` removed).
- The program is `Osprey` (osprey is maccoss/osprey) in the help and docs/20.
- Carafe's camel-case options hyphenated (`--min-length`, `--fix-mod`, `--i2l`, `--print-ptm`, ...);
  `CommandLineGrammar.NamesMatch` (shared CommonUtil) treats a lower-to-upper boundary as a
  separator and ignores case, so Carafe's spelling still parses (`StandardName`). Our own scripts
  and tests use the documented spelling (Brendan: no history to keep for our own scripts); the
  parity tests' recorded Carafe command lines and `Run-CarafeOspreyWorkflow.ps1` (Java Carafe)
  keep Carafe's.
- Descriptions rewritten from what the code does (Brendan: "Resource file -> Creates a new resource
  file" is the anti-pattern): `-i` (any ProteoWizard format), `-l` (.blib first; decoys generated
  unless `--decoys-in-library`; how each format pairs), `-o` (what the blib holds, the two reports
  beside it), `--export-library` (self-contained blib, searches back with no manifest),
  `--resolution`, `--fragment-tolerance/-unit`, `--no-prefilter`, `--run-fdr` (Skyline ID lines per
  run, Percolator train/test), `--experiment-fdr`, `--fdr-level`, `--shared-peptides`,
  `--work-dir/--output-dir/--cache-dir`, `--protein-fdr` (default 0.01), `--tf` (no `--model-dir`).
  Their ja/zh entries removed where the meaning changed (the next translation pass redoes them).
- `--report` removed: it only named a fallback report stem used when there is no `-o`, which a
  search requires (`OspreyReportWriter.ReportStem`); also from the Demux scripts in ai/scripts.
- **`--resolution auto` removed; the default is `hram` (Brendan).** `auto` detected nothing: the
  scorer and bins treated it as unit while the unit tolerances applied only to an explicit `unit`,
  so a search without `--resolution` scored unit bins at 10 ppm. Detection is
  [#4893](https://github.com/ProteoWizard/pwiz/issues/4893).
- Item 4: the HPC section's preamble says `--fasta` runs as one process and is refused with `--task`.

### 2026-10-21 evening - Clean-up PR coded and committed (4 commits); review and PR next

Branch `Skyline/work/20261021_osprey_one_command_cleanup` (not pushed): 5b75e2f9b0 (empty result
fails), 8b5dea4a69 (.model.zip), 773b91c9dc (help rewrite, hram default, --training-input-list,
--report removed), bf61571ed7 (value tables, OSPREY_DIANN_REPORTS, more help). Gates on bf61571ed7:
Osprey 650/650 + inspection 0, CarafeSharp 105 + inspection 0 (8 Carafe parity NotExecuted: no
reference data here), Skyline TestCommandLineParserGrammars 0 failures; Stellar regression PASS
(on 773b91c9dc + the env-var change; bf61571ed7 is help-only). Help page reviewed by Brendan
(artifact https://claude.ai/artifact/SFhdVjKSCqBFzx32xewzuS v5, "Looks much better").

Also in bf61571ed7, from Brendan's review: `--enzyme` takes a name; the enzymes and modifications
are compact reference tables generated from `EnzymeTable` / `CarafeModification` (new shared
`pwiz.Common.CommandLine.TableUsageBlock`: caption, column groups, right-aligned numbers, indented,
borderless); `--threads` first in Performance and `--parallel-files` says it is for NUMA servers;
examples lead with vendor files and `.blib`, `.tsv` last as the DIA-NN comparison form;
`<output>.protein_groups.tsv` / `.stats.tsv` only under `OSPREY_DIANN_REPORTS` (they hold nothing
the .blib lacks); `--cache-dir`, `--export-library` (the same file as the .tsv library's cache, minus
the validity hash), decoy options and `--log-file` rewritten.

Issues filed (Brendan): [#4893](https://github.com/ProteoWizard/pwiz/issues/4893) detect
`--resolution` from the data; [#4894](https://github.com/ProteoWizard/pwiz/issues/4894) search .blib
RefSpectra lacks the predicted RT and CCS, in Osprey AND BiblioSpec's DIA-NN reader (March 2025
design: RefSpectra = the predictions, RetentionTimes = the measured observations; only the spectrum
half was implemented). Not filed (Brendan): phosphate neutral loss (AlphaPeptDeep's modloss head is
masked in CarafeSharp). Proposal not acted on: move Carafe's training-curation levers (~16 hosted
options) behind one `OSPREY_CARAFE_ARGS` variable - ask Mike.

**Held in the ai repo, uncommitted until the PR merges** (they use spellings only this branch
accepts): `scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1` (documented `--hyphen` spellings),
`scripts/Osprey/Demux/Run-DemuxSearchArms.ps1` and `Run-EclipseSearch.ps1` (`--report` dropped,
`OSPREY_DIANN_REPORTS=1` set for Compare-DemuxSearches.py).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261021_osprey_one_command_cleanup.md` before starting work.

### 2026-10-21 night - Clean-up PR reviewed, fixed, opened

`/code-review medium`: 10 findings, 6 fixed in be229fd949 (a search that writes no .blib removes an
earlier run's .blib of that name; `--help <section>` brings the tables after the digest options;
`--enzyme` errors name the option, an out-of-range index included; `--training-input-list` read only
with `--fasta`; the stale `_report` Designer property; `.carafemodel` left in comments). Dropped:
`--resolution` default `hram` (Brendan's decision, a behavior change the PR states); the "nothing
passed" message naming only `--experiment-fdr` (every output gate is an experiment-level q-value
against that threshold); re-runs not finding a tuned `<out>.carafemodel` (one-command tuning merged
the same day, so no user has one); `WriteProteinReport`/`WriteSummaryReport` always true
(pre-existing); `CarafeModelFile.FilePatterns` unused (for #4849). Gates on be229fd949: Osprey 650 +
inspection 0, CarafeSharp 105 (8 without data) + inspection 0, Stellar regression PASS.
`regression-parallel.ps1 -Dataset All` 48 PASS / 0 FAIL in 35:24. Osprey Windows .NET 4229787 failed
`TestSubsetLibraryBuildTuned`: its two-run resume step detected nothing at 1% on a cloud agent
(105 first-pass passers, 0 reported - the single-hit protein defect above), which this PR now
fails; d17e23f4f2 gives that step `--experiment-fdr 1` (it checks which tasks run).

**Defect, its own item (Brendan, 2026-10-21): the tuned result depends on the CPU.** Required:
the same command and seed give the same model on any machine; "which CPU" must never be needed
to reproduce a result. Seen twice, both in the subset's one-epoch tuning: #4885's
`TestSubsetLibraryBuildTunedHeldOut` (Windows pass, Linux fail) and 4229787 above (this machine
pass, TeamCity Windows cloud agent fail). `-l` searches match their goldens at 1e-9 across this
machine and the agent, so the variation most likely enters in CarafeSharp's libtorch training
or prediction. Not verified: MKL/oneDNN choose kernels by ISA (AVX2 vs AVX-512) and reduce in a
different order (`MKL_CBWR`, `ONEDNN_MAX_CPU_ISA`); thread count splitting reductions; libtorch's
deterministic-algorithms switch. Method: one seeded tuning on two CPUs, weights compared after
step 1; the first differing tensor names the op; then whether pinned kernels remove it and the
speed cost. Also check the prediction alone (pretrained models, no tuning) across the two.

**Root cause (night session 2026-10-22, reproduced on this machine, no fix committed).** libtorch's
intra-op thread count is never set (no `set_num_threads` in CarafeSharp or Osprey; Osprey's `--threads`
does not reach torch), so it is the machine's core count (24 here, i9-14900K), and the large reductions
split across threads sum in a thread-count-dependent order. The same seeded one-epoch tuning (test
settings, seed 2024, Stellar _21 export): 8 vs 8 threads 0/66 RT and 0/96 MS2 tensors differ; 8 vs 4
threads 27/66 and 73/96 (RT epoch-1 loss 0.0422 vs 0.0377, MS2 PCC 0.920 vs 0.936). First differing
tensors: Chronologer Conv1d weight gradients (1e-9..1e-8); the forward is identical at 8 vs 4 (dropout
mask included), differs at 16 vs 24. Thread-dependent ops: `sum`/`mean`, linear/layer_norm/conv1d
weight backward; thread-invariant: linear/bmm/softmax/layer_norm forward, embedding backward, dropout.
Prediction alone also varies (22 of 48,764 TSV lines, 4th-decimal intensities and near-tied fragment order).
- A constant thread count removes core-count dependence: 8 torch threads in a process confined to 4
  logical CPUs gives weights bitwise identical to unconfined 8 threads.
- ISA is a second source, not testable here (AVX2, no AVX-512): at fixed 8 threads `MKL_CBWR=COMPATIBLE`
  changes GEMM/bmm, `ONEDNN_MAX_CPU_ISA=SSE41` changes conv, `ATEN_CPU_CAPABILITY=default` changes nearly
  everything. Pinning `MKL_CBWR=AVX2 ONEDNN_MAX_CPU_ISA=AVX2 ATEN_CPU_CAPABILITY=avx2` is bitwise identical
  to default here (free on AVX2; unmeasured on AVX-512). In-process: on Windows .NET `SetEnvironmentVariable`
  reaches MKL/oneDNN but not ATen (CRT copy; `_putenv_s` reaches all three); on Linux needs libc `setenv`;
  must precede the first torch op. `torch.use_deterministic_algorithms` throws NotImplemented in TorchSharp 0.106.
- Not removable by settings: Windows vs Linux libtorch builds, AMD vs Intel (MKL dispatch), libtorch version, GPU.
- Speed: tuning does not scale with threads (4: 71 s, 8: 86 s, 16: 64 s, 24: 82 s; perturbed, one run
  each); oversubscription is costly (8 threads on 4 CPUs 428 s vs 141 s); prediction scales (full
  hela-filtered 548 s at 8, 347 s at 24), so pinning prediction low costs ~1.6x on big machines.
- Choices for Brendan: (1) pin intra-op threads to a small constant (e.g. 4, min with cores) around all
  of `ModelTrainer.Run` on the CPU (it includes the RT-alignment Chronologer prediction that feeds the
  targets) - removes core-count dependence at no measured cost; (2) add the ISA pin before torch loads
  (needs an AVX-512 machine to verify); (3) whatever 1-2 give, make the subset tuning tests not depend on
  bitwise models across OS (a one-epoch tune turns tiny weight differences into a discrete outcome).
- Harness and runs: `D:/test/cpudet/harness` (train.ps1, probe_chrono.ps1, Probe.cs, stcompare.py,
  opscompare.py, envtest.ps1, speed.sh), `D:/test/cpudet/runs` (full_t8_a/b, full_t4_a, full_t8_pinavx2,
  full_t8_atendefault, full_t8_aff4, full_t4_aff4, ops_*, pred_sub_t{4,8,24}, speed_*); log
  `ai/.tmp/agent-cpudet-status.md`. Worktree `D:/Dev/pwiz-cpudet` unchanged at 22626556a4.

### 2026-10-21 night - Clean-up PR merged

PR #4895 merged as commit 22626556a4 (squash message approved by Brendan). All 18 checks green on
head d17e23f4f2; TeamCity Perf/Regression 4229803 SUCCESS on be229fd949 (the later commit changed
only `TestSubsetLibraryBuildTuned`). Shipped: a search that detects nothing fails (no `.blib`, an
earlier one removed), `.model.zip`, the rewritten help with the enzyme and modification tables,
`--resolution` default `hram`, `--training-input-list`, `--report` removed, DIA-NN reports under
`OSPREY_DIANN_REPORTS`. The held ai scripts (`Run-CarafeSharpWorkflow.ps1`, `Run-DemuxSearchArms.ps1`,
`Run-EclipseSearch.ps1`) committed with this entry. `C:\proj\pwiz` is on master at 22626556a4; branch
deleted local + remote. This TODO stays active: 4c tonight, then 4d.

**Night session handoff (4c)**: read `ai/.tmp/handoff-20261022_osprey_4c_night.md` before starting work.

### 2026-10-22 night - PR 4c in progress (night session)

Branch `Skyline/work/20261022_osprey_hpc_cuda`. fa48e766f9: `--task PredictTrainingLibrary|TrainModel|PredictLibrary`
run one library phase (names in `LibraryBuildConfig.PHASES`, listed in `--task` after SpectraCache); with
`--fasta` a stage task searches the analysis `LibraryBuildWorkflow.StageConfig` derives (the output's, or
with `--training-search` the tuning runs'); `PredictLibrary` alone before `TrainModel` is refused; the
`--fasta`+`--task` refusal is gone; `--task-files` prints a node's declared inputs/outputs and exits.
`TestSubsetLibraryBuildTunedHpcChain`: the tuned command node by node (per-file stages one node per run)
equals straight-through (both libraries' spectra, both searches' blibs), and each phase node re-run skips.
Found while writing it: a `--task PerFileRescoring` node stamps `;libfrag=0` (no fragment release on that
leg), so a later in-process run re-runs the rescoring over a node-built directory - pre-existing, with or
without `--fasta`; content identical. f9f8f221d0: Carafe-workflow.html folded into Osprey-workflow.html
(1.1 On a cluster, 1.2 Inside the library phases, 1.3 CarafeSharp vs Carafe 2.2.0).
`Run-CarafeSharpWorkflow.ps1` reduced to one Osprey invocation (`-Mode Tuned|Pretrained`, `-Task`,
`-TrainingSearch`, `-ExtraArgs`), held uncommitted in pwiz-ai until 4c merges; `-NoSimilarityGate` and
Carafe's `--nm`/`--na`/`--fast`/`--itol`/`--rf` are gone (Osprey decides or has no spelling for them).
In flight: declarations completed + regression HPC chain staged from `--task-files` (agent); GPU vs CPU
timing (agent, worktree D:\Dev\pwiz-cuda); CPU-dependent tuning root cause (agent, D:\Dev\pwiz-cpudet).

**GPU vs CPU, the one command on Stellar (RTX 4000 Ada, master 22626556a4, 2026-10-22 night).** Built
with `Build-Osprey.ps1 -Torch cuda|cpu -VendorReader` in worktree `D:\Dev\pwiz-cuda`; snapshots
`D:\test\osprey-runs\_bin\master-22626556a4-cuda` (4.3 GB) and `...-cpu` (482 MB). Runner
`Run-DiannComparison.ps1 -Steps osprey-library,osprey-search` (gained `-LibraryMode tuned|pretrained`,
uncommitted), 16 threads, `.raw` from `D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-v2\stellar`,
tuning run _21. Quiet runs (other CPU < 5%) except where noted:

| arm | library | phases (s) | search | total |
|---|---|---|---|---|
| GPU, pretrained | 42.7 s | PredictLibrary 41.9 | 213 s | 4.3 min |
| CPU, pretrained | 143.9 s | PredictLibrary 143.4 | 216 s | 6.0 min |
| GPU, tuned | 5.7 min | PredictTrainingLibrary 64, tuning search 135, TrainModel 77, PredictLibrary 54 | ~230 s | ~9.6 min |
| CPU, tuned | 24.8 min | PredictTrainingLibrary 263 (overlapped a build; 143 quiet), tuning search 191, TrainModel 855, PredictLibrary 178 | 246 s | 28.9 min |

The GPU makes the fine-tune 11x faster (855 s to 77 s) and prediction 3.3x; the library build is 3.4x
(pretrained) and 4.3x (tuned) faster, and the tuning run's search (CPU) is now the largest part of the
GPU-tuned library. The search is the same 3.6-4.1 min in every arm. GPU use confirmed by nvidia-smi
(Osprey.exe at 50-66%, 3.0-3.5 GB); no CPU-fallback warning. Run folders
`D:\test\osprey-runs\cuda-4c\<arm>\` (gpu-pretrained, gpu-tuned [contended, 8.5 min], gpu-tuned-rerun,
cpu-pretrained, cpu-tuned), each with osprey.log, contention.tsv, command.txt and timing.tsv.
Gap: Osprey/CarafeSharp log no line naming the device a phase ran on; only the fallback warns.

**One build, GPU when present (measured 2026-10-22, for 4d).** The CPU and CUDA builds differ only in the
native libtorch payload (`runtimes/win-x64/native`: 271 MB vs 4.1 GB); the managed assemblies are the
same, and the CUDA payload carries its own `torch_cpu.dll`. `TorchDevice` already falls back
(`TryInitializeDeviceType(CUDA) && cuda.is_available()`). The CUDA build with `CUDA_VISIBLE_DEVICES=-1`
and `--device gpu` logged "No CUDA device is available to this build; running on the CPU", predicted the
pretrained Stellar library in 160.6 s (CPU build 143.4 s; a regression ran alongside), and wrote a library
whose RefSpectra and RefSpectraPeaks are IDENTICAL to the CPU build's (484,908 spectra; the GPU library
differs in every spectrum, as expected). Run: `D:\test\osprey-runs\cuda-4c\gpu-hidden-pretrained`. Not yet
tested: a machine with no NVIDIA driver at all (a TeamCity cloud agent), a driver too old for CUDA 12.8,
Linux, and pointing TorchSharp at a native folder chosen at run time.
Proposal (Brendan's goal: no second build or install, GPU when present, CPU otherwise): one managed build
in-process; the CPU payload ships as now; the CUDA payload is an on-demand download (Skyline's tool-download
pattern) into a folder of its own; before the first torch call (the lazy seam already guarantees it is the
library phases) Osprey loads the natives from that folder when an NVIDIA driver is present and the payload
is installed, else the shipped CPU ones, and says which in the log (today nothing names the device a phase
ran on). A separate GPU CarafeSharp.exe process is the fallback only if the native folder cannot be chosen
in-process (or a host has already loaded CPU libtorch); the library phases are already file-in/file-out
tasks, so that fallback is cheap.

**4d direction (Brendan, 2026-10-22).** Osprey becomes a separate download for Skyline, like the other
search engines: Skyline's ZIP installers are under 100 MB and most users will not want Osprey, so it cannot
ride in Skyline's install. Once Osprey is a download, the user chooses CUDA as they do for AlphaPeptDeep.
The mechanism exists in Nick's [#4849](https://github.com/ProteoWizard/pwiz/pull/4849) (open), in
`CarafeSharp.Models`, which Osprey already references: `LibTorchRuntime` loads a chosen libtorch folder
(CPU or CUDA) into the process before TorchSharp needs it (one runtime per process, never beside
TorchSharp.dll); `LibTorchRuntimeInstaller` downloads the CUDA 12.8 runtime on demand (~2.9 GB from nuget.org,
4.1 GB installed, SHA-512 verified) into `Tools\libtorch-cuda-12.8-win-x64.2.10.0`; `CudaDriver` explains a
missing or old driver or GPU. So the in-process design above is proven there, and 4d is: Osprey (standalone
and as Skyline's download) uses the same runtime folder and installer - one CUDA download shared by Skyline's
AlphaPeptDeep and Osprey - and logs the device; then the untested cases (no driver, old driver, Linux).
4d follows #4849's merge. Perf/Regression on pull/4898 triggered 2026-10-22 morning (Brendan): build 4230580.

**Next, before #4849: retire `.libcache` completely (Brendan, 2026-10-22).** A cache is rebuilt from its
source, never upgraded or imported in place - a `.spectra.bin` after a schema change is rebuilt from the
raw file (and fails without it), not converted. The derived `<lib>.tsv.blib` was a cache-format change with a
new name, so the "read-only for one release" path in `LibraryCache.cs` / `LibraryLoader` was wrong in
principle, not just unneeded (Osprey was never released). Small PR after #4898: remove `LoadCache`,
`SaveCache` and their `IOTest` tests, the loader's honoured-first branch and its unchanged-hash notes; once
the derived `.blib` is written, delete `<library>.libcache` at exactly the path Osprey wrote it (no sweep),
logging the file, as an overwrite would have; drop `Copy-LibraryDerivedInto`'s `.libcache` relay in
`regression.ps1`; add the rule to `docs/00-pipeline-architecture.md` (a cache is rebuilt from its source; a
renamed cache format removes its predecessor). Gates: Osprey Debug + inspection, `regression.ps1 -Dataset
Stellar` (a .tsv library through this path). Also pending for 4c's docs: the mode 3 row of
`regression.html` should say nodes are staged from `--task-files` and a missing declared input or output
fails the leg.

**Later the same night.** 7a7c451bc3 (agent): every stage task's `Inputs` completed to what it reads
(library and manifest everywhere; FirstPassFDR + calibration; PerFileRescoring + spectra cache, scores,
calibration, model, stratum under protein-compact, experiment and retained-ids sidecars; SecondPassFDR +
reconciliation plans, model/stratum under protein-compact, pass-1 diagnostics with `--model-diagnostics`),
and `regression.ps1`'s HPC chain stages each node from `--task-files` (`Get-DeclaredTaskFiles`,
`Copy-DeclaredInputs`, `Invoke-HpcNode`; a missing declared input fails staging). Found by withholding:
SecondPassFDR does not need `<stem>.calibration.json` (chain == straight at 1e-9 without it); the pass-1
diagnostics JSON goes straight to phase 4. `OspreyDatasetRun.psm1 -LinkFrom` links declared files
(held in pwiz-ai, uncommitted; dry runs of 8 shapes and one real link, no SEA-AD run). Limitation: under
`--demux` the declaration names the plain `.spectra.bin`. a18192152d: `--training-search` with no
`--task` is the tuning runs' whole search on one node - needed because `--task FirstPassFDR` refuses one
input, and the lab tunes on one run; `regression.ps1` mode 14 (`-HpcOneCommand`, opt-in, Stellar): the
tuned one command as 12 nodes in one directory, each node's declared inputs present before and outputs
after, PASS against straight-through (node by node 19:21 wall, straight 21:01). `/code-review medium`:
8 findings, 6 fixed in 62b68b9cfc (FASTA/model/foreign FASTA checked only where read, so a stage or
TrainModel node staged from its declarations runs; tuned PredictLibrary declares the model file it
requires; `--fasta` + stage task without `-o` reports `-o`; `--task-files` answers before `--log-file`
and creates nothing; a dead test branch), 2 dropped (the TrainModel export path is built as the
locator's stem rule names it; a duplicated scope-exit helper). Gates on 62b68b9cfc: Osprey Debug
651/651 + inspection 0; CarafeSharp 105 + 8 NotExecuted (no Carafe reference data here) + inspection
0; BiblioSpec 142/142; mode 14 PASS (on a18192152d; the fixes do not touch its path). `regression-parallel.ps1
-Dataset All` on 62b68b9cfc: 48 PASS / 0 FAIL in 36:25 (`ai/.tmp/sessions/20261022-4c/reg-all.log`).
PR [#4898](https://github.com/ProteoWizard/pwiz/pull/4898) opened 02:15. Reduced `Run-CarafeSharpWorkflow.ps1` run for real: `-Mode Pretrained -Device cpu` on Stellar .raw with the branch exe (vendor build, snapshot
`D:\test\osprey-runs\_bin\4c-62b68b9cfc-vendor`): one Osprey call, PredictLibrary 220 s and the four stages, 7.07 min, FDRBench input and pairing written (`D:\test\carafesharp-runs\4c-script-pretrained`); `-Task PredictLibrary` on
the same folder skips (outputs valid). Commit it, `OspreyDatasetRun.psm1` (-LinkFrom from declarations) after #4898 merges.
CI on #4898: all 16 checks green (Osprey Windows .NET build 4230347 and Linux .NET on 62b68b9cfc; TeamCity picked the
PR up ~2 h after it opened). Left for Brendan: TeamCity Perf/Regression on pull/4898 (ask-first), review, merge.
Morning handoff: `ai/.tmp/handoff-20261022_osprey_4c_morning.md`.

### 2026-10-22 morning - One chain shape whatever the run count (Brendan)

Brendan's review: a workflow manager should not have to count the tuning runs to choose the chain's shape.
8e6a3a7338: `--task FirstPassFDR` accepts one input (the refusal said its files were "only useful when there
are other runs to reconcile against", but Stage 5 trains the first-pass model and q-values for any count);
`--training-search` again needs a stage task (its whole-search form, a18192152d's workaround, is gone).
With one run PerFileRescoring is not a no-op: it re-scores the run's multi-charge consensus, gap-fills and
writes its half of the second pass. `TestSubsetHpcTaskChainOneRun`: the one-run `-l` chain equals one-run
straight-through (blib, every FDR sidecar, both experiment sidecars byte-identical). d1df38fa29: the
reconciliation-off refusal removed too (no option can turn reconciliation off; FirstPassFDR has no
ValidateSelection of its own now). Gates: Osprey 652/652 + inspection 0; mode 14 PASS on 8e6a3a7338 with
15 nodes, Stellar's single tuning run as four stage nodes (node by node 20:26). Pushed; #4898 body updated.
See "Second-pass levers" (above the PR plan) for the Mike discussion this raised.

### 2026-10-22 - PR 4c merged

PR #4898 merged as commit 46af8ac754 (squash approved by Brendan). All 17 checks green on d1df38fa29; TeamCity Perf/Regression 4230580 SUCCESS (triggered at Brendan's request). Shipped: `--task PredictTrainingLibrary|TrainModel|PredictLibrary`, `--training-search`, `--task-files`, completed stage declarations with the regression HPC chain staged from them, `--task FirstPassFDR` accepting one run and reconciliation off, regression mode 14, the folded workflow page. Not in 4c (moved on): installers and TeamCity artifacts (4d), and the CUDA build was measured rather than packaged (4d via #4849). The held pwiz-ai scripts (`Run-CarafeSharpWorkflow.ps1` reduced to one Osprey call, `OspreyDatasetRun.psm1 -LinkFrom` from `--task-files`) committed with this entry. This TODO stays active for the `.libcache` retirement, #4849 and 4d.

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20261022_osprey_libcache_and_4849.md` before starting work (.libcache retirement PR, then finishing #4849, then 4d).

### 2026-10-22 - `.libcache` retired (branch `Skyline/work/20261022_osprey_retire_libcache`, off 46af8ac754)

The rule (Brendan, above): a cache is rebuilt from its source, never upgraded or imported in place, and a
renamed cache format removes its predecessor. `Osprey.IO/LibraryCache.cs` deleted outright (`LoadCache`,
`SaveCache`, the v6 format), with its 9 `IOTest` cases and 7 resx strings (en/ja/zh-Hans); `LibraryLoader`
lost the honoured-first branch, `LogCachedPairingSummary`, `RecoverPairingStats`, and `LibraryCompositionHash`
folded into `DerivedLibraryHash` (same hashed text, so every existing derived `.blib` stays valid). Once the
derived library is in place - written by the load, or read by it - the loader deletes `<lib>.libcache` at
exactly the cache-dir path the old writer used (`LibraryLoader.RETIRED_CACHE_EXT`), logs `Removed the library
cache '<path>': the derived library replaces it.`, and touches nothing else; a failed delete is a warning.
Pinned in `SubsetPipelineTest.TestLibraryLoadsIdenticallyFromTsvAndBlib` (`DerivedLibraryDifferences` plants
one, asserts it gone and the line logged once, not on the second load). `regression.ps1`
`Copy-LibraryDerivedInto` relays the `.blib` only; `regression.html` mode 3 row says nodes are staged from
`--task-files` and a missing declared input or output fails the leg. Docs: P18 in `00-pipeline-architecture.md`
("Eighteen rules"), `.libcache` rows and notes out of 00/01/13/14, the workflow page's stage-1 box and task
header, and the code comments. pwiz-ai (uncommitted until the PR): the active `ai/scripts/Osprey` relays
copy `<lib>.blib` where they copied `<lib>.libcache`; guide and README wording.
Gates: Osprey Debug 642/642 (651 - 9 cache tests) + inspection 0 (first inspection run reported 50
`CSharpErrors` in untouched files after "Roslyn Worker process exited unexpectedly"; the re-run was clean).
`regression.ps1 -Dataset Stellar` PASS (mode 1 vs golden, 1c, 4, streamed join, 6; straight-through 02:59,
warm 0.2 s). `/code-review medium`: 6 findings, 2 fixed (the round-trip test now plants the `.libcache` again
before the read load and pins the read-arm delete; `RETIRED_CACHE_EXT`'s doc names its retirement point: after
the first public release, which no `.libcache` will predate), 4 dropped - a cache with its source missing is
not trusted, by the rule (`.spectra.bin` fails without its raw too; the derived path already required the
source; HPC staging declares the library an input); a double "Removed" log when two workers race on one cache
dir is harmless and the same race as the derived write; the `regression.html` mode 3 sentence is 4c's pending
doc item, folded in on purpose; ja/zh-Hans pick new keys up in the translation pass, as the derived-library
strings did. Committed as 37d30526cb; PR [#4904](https://github.com/ProteoWizard/pwiz/pull/4904) opened.
TeamCity Perf/Regression #341 (4231041) on `pull/4904`: SUCCESS (triggered at Brendan's request). Left: review, merge.

### 2026-10-22 - .libcache retirement merged (#4904)

PR #4904 merged as f4f24aefad (squash approved by Brendan; 17/17 checks, TeamCity Perf/Regression #341 SUCCESS). Shipped: `LibraryCache` gone with its tests and strings; `LibraryLoader` reads the derived `.blib` only and deletes `<lib>.libcache` at its exact path once the derived library is in place; `regression.ps1` relays the `.blib` only; P18 in `00-pipeline-architecture.md`; the `regression.html` mode 3 note. Not done, on purpose: a `.libcache` beside a `.blib` SOURCE is left alone (no successor file). This TODO stays active for #4849 and 4d.
