# TODO-20261019_osprey_one_command.md  -  Phase 2

## Branch Information
- **Branch (4d)**: to be cut from `master` (89648e66b5, 2026-10-23) as `Skyline/work/20261023_osprey_download`
- **Base**: `master`
- **Created**: 2026-10-19
- **Phase 2 started**: 2026-10-23
- **Status**: In Progress - PR 4d: Osprey as a separate download for Skyline, sharing #4849's libtorch
  runtime folder and CUDA installer, the device logged; installers and TeamCity artifacts
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (none yet)
- **Checkout**: `C:\proj\pwiz`

## Phase History

See [TODO-20261019_osprey_one_command-phase1.md](../completed/2026/10/TODO-20261019_osprey_one_command-phase1.md)
for 2026-10-19 to 2026-10-22: the design (options, stages and the workflow layer, files, resume, libtorch
and packaging, HPC), Brendan's decisions of 2026-10-19, the second-pass levers table for Brendan and Mike,
the PR plans for 4a-4c, and the progress log through six merged PRs: #4877 (option spelling) and #4876
(PR 4a, modes 1 and 3), #4878 (CarafeSharp doc sweep), #4885 (PR 4b, mode 2 and resume), #4895
(clean-up), #4898 (PR 4c: HPC addressing, task declarations, one chain shape), #4904 (`.libcache`
retirement). Nick's #4849 (AlphaPeptDeep via CarafeSharp, the libtorch runtime and CUDA installer 4d
builds on) merged 2026-10-23 as 946a33909f, with #4906 after it.

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

Modes 1-3 shipped in phase 1. Phase 2 is how a Skyline user gets Osprey and its GPU.

## PR 4d - Osprey as a download, one CUDA runtime shared with AlphaPeptDeep

**Direction (Brendan, 2026-10-22).** Osprey becomes a separate download for Skyline, like the other
search engines: Skyline's ZIP installers are under 100 MB and most users will not want Osprey, so it cannot
ride in Skyline's install. Once Osprey is a download, the user chooses CUDA as they do for AlphaPeptDeep.
The mechanism is #4849's, in `CarafeSharp.Models`, which Osprey already references: `LibTorchRuntime` loads
a chosen libtorch folder (CPU or CUDA) into the process before TorchSharp needs it (one runtime per process,
never beside TorchSharp.dll); `LibTorchRuntimeInstaller` downloads the CUDA 12.8 runtime on demand (~2.9 GB
from nuget.org, 4.1 GB installed, SHA-512 verified) into `Tools\libtorch-cuda-12.8-win-x64.2.10.0`;
`CudaDriver` explains a missing or old driver or GPU. So 4d is: Osprey (standalone and as Skyline's
download) uses the same runtime folder and installer - one CUDA download shared by Skyline's AlphaPeptDeep
and Osprey - and logs the device; then the untested cases (no driver, old driver, Linux). Installers and
TeamCity artifacts (moved here from 4c) need TeamCity configuration and installer work a session cannot
verify alone.

**Measured for 4d (2026-10-22, phase 1).** The CPU and CUDA builds differ only in the native libtorch payload
(`runtimes/win-x64/native`: 271 MB vs 4.1 GB); the managed assemblies are the same, and the CUDA payload
carries its own `torch_cpu.dll`. `TorchDevice` already falls back (`TryInitializeDeviceType(CUDA) &&
cuda.is_available()`). The CUDA build with `CUDA_VISIBLE_DEVICES=-1` and `--device gpu` logged "No CUDA
device is available to this build; running on the CPU" and wrote a library whose RefSpectra and
RefSpectraPeaks are IDENTICAL to the CPU build's (484,908 spectra). Run:
`D:\test\osprey-runs\cuda-4c\gpu-hidden-pretrained`. Not yet tested: a machine with no NVIDIA driver at all
(a TeamCity cloud agent), a driver too old for CUDA 12.8, Linux, and pointing TorchSharp at a native folder
chosen at run time.

### Plan

(to be written after reading the code #4849 merged: `LibTorchRuntime`, `LibTorchRuntimeInstaller`,
`CudaDriver`, Skyline's `Use GPU` path in `BuildLibraryDlg`, Osprey's lazy libtorch seam and `--device`,
and how Skyline installs its other search engines as downloads)

### Tasks

- [ ] Plan written and agreed with Brendan
- [ ] Osprey loads libtorch through `LibTorchRuntime` from the shared runtime folder; the device is logged
- [ ] Osprey offers the CUDA download through `LibTorchRuntimeInstaller` (standalone) and Skyline's prompt (hosted)
- [ ] Osprey as a Skyline download (the search-engine tool pattern); installers and TeamCity artifacts
- [ ] The untested cases: no driver, old driver, Linux
- [ ] Gates below; `/code-review medium`; TeamCity Perf/Regression on `pull/<N>` (ask first)

## Gates

Every PR, before `gh pr create` (then `/code-review medium` on the branch):
- `pwsh -File C:/proj/ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot C:/proj/pwiz -Configuration Debug -RunTests -RunInspection -Summary`
- `pwsh -File C:/proj/ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -SourceRoot C:/proj/pwiz -RunTests -RunInspection -Summary`
- `pwsh -File C:/proj/ai/scripts/BiblioSpec/Build-BiblioSpec.ps1 -SourceRoot C:/proj/pwiz -RunTests -Summary` (the shared reader and writer gate)
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` - byte-identical: `-l` searches do not move
- Before merge: `regression-parallel.ps1 -Dataset All` locally and the TeamCity Perf/Regression
  config on `pull/<N>` (ask first), once per merge candidate.
- Skyline, when the download or the Build Library path changes: `Build-Skyline.ps1 -SourceRoot C:/proj/pwiz -Summary`
  and the tests the change names (`TestAlphaPeptDeepUseGpu`, `TestLibTorchRuntimeInstall`, `CodeInspection`,
  `CheckForMissingResources`).

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
- Phase 1 follow-ups Brendan raised on #4849, not 4d's: isolate `CarafeCommandLine` so Skyline never
  loads it; maybe move `ScopedAction` to CommonUtil; the "Add All..." email to Mike and Nick.

## Progress Log

### 2026-10-23 - Phase 2 opened

The phase 1 file passed 1,300 lines over seven PRs; it moved to `completed/2026/10` as `-phase1` and this
file carries 4d on, as `TODO-20260409_osprey_sharp` did in April. Master is at 89648e66b5 (#4849 and #4906
in). Next: read the code 4d builds on and write the plan above.
