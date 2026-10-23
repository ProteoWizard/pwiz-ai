# TODO-20261019_osprey_one_command.md  -  Phase 2

## Branch Information
- **Branch (4d)**: `Skyline/work/20261023_osprey_download` in `C:\proj\pwiz` (from master 89648e66b5, 2026-10-23)
- **Base**: `master`
- **Created**: 2026-10-19
- **Phase 2 started**: 2026-10-23
- **Status**: In Progress - PR 4d merged 2026-10-23 as #4909 (59f90882bd): Osprey chooses its libtorch
  runtime when it runs, the CUDA runtime a download shared with Skyline's AlphaPeptDeep, the device
  logged. PR 4 (parts H, I, J) is complete. Next: the measurement that follows PR 4 (one command vs the
  four-step workflow on Stellar, Astral and ZT Scan; tuning on searched vs held-out runs), then the
  second-pass levers with Mike and Osprey as Skyline's download
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4909](https://github.com/ProteoWizard/pwiz/pull/4909) (PR 4d, merged 2026-10-23 as 59f90882bd)
- **Checkout**: `C:\proj\pwiz`

## Phase History

See [TODO-20261019_osprey_one_command-phase1.md](TODO-20261019_osprey_one_command-phase1.md)
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

### Where things stand in the code (2026-10-23)

- **Skyline (#4849)** ships the CPU libtorch in `torch\cpu` (Skyline.csproj: both libtorch packages
  referenced with `ExcludeAssets="all"`, the CPU natives linked as Content) and writes
  `torch\libtorch-cuda-12.8-win-x64.packages.txt` through `CarafeSharp\LibTorchPackageSet.targets` (the
  CUDA package's part packages with the SHA-512 NuGet recorded). `Model\Lib\AlphaPeptDeep\TorchRuntimes`
  finds the driver (`CudaDriver.Find`), explains why the GPU cannot be used (localized), installs the CUDA
  runtime into `ToolDescriptionHelpers.GetToolsDirectory()` with `HttpClientWithProgress` and
  `LibTorchRuntimeInstaller`, and `Load(useCuda)` loads one `LibTorchRuntime` per process.
  `LibTorchRuntime.Load` refuses when another libtorch sits beside TorchSharp.dll or under
  `runtimes\<rid>\native` there.
- **Osprey** today takes the other path: `UseLibTorch=true` (`CarafeSharp\LibTorch.targets`) references
  the libtorch package for the backend chosen at build time (`Build-Osprey.ps1 -Torch cpu|cuda`), whose
  natives land under `runtimes\win-x64\native` beside TorchSharp.dll, where TorchSharp loads them by itself
  - exactly what `LibTorchRuntime` refuses. The same property copies the pretrained models and Chronologer
  beside the executable. `--device gpu|cpu` reaches `TorchDevice.Resolve` in `LibraryGenerator` and
  `ModelTrainer`, which log only the fallback ("No CUDA device is available to this build; running on the
  CPU"); nothing names the device a phase ran on. `Osprey.Test` has `UseLibTorch=true` too, for
  `SubsetPipelineTest`.
- **Packaging** exists: Osprey's per-commit TeamCity build (`tcbuild.bat`) runs `package.ps1 -Rid win-x64
  -Setup` and publishes `Osprey-<version>-win-x64.zip` and `Osprey-Setup-<version>.exe`; `tcpackage.bat`
  adds linux-x64. Skyline has no Osprey code yet (DIA-NN and EncyclopeDIA are downloaded into the Tools
  folder through `FileDownloadInfo` / `SimpleFileDownloaderDlg`; that UI is a later PR, not 4d).
- `CarafeSharp.Models` references no CommonUtil; `CarafeSharp.Tasks` does (through Contracts), so the
  shared runtime chooser with its download lives in Tasks, which Osprey references.

### Plan (mine; the decisions are flagged for Brendan in the PR, as 4a's were)

1. **One Osprey build, Skyline's runtime layout.** `LibTorch.targets` splits the natives from the models:
   `UseLibTorch` keeps today's meaning for CarafeSharp.exe and its tests (TorchSharp loads the natives it
   finds beside itself); a new `UseCarafeModels` copies only the models. Osprey.csproj and Osprey.Test.csproj
   set `UseCarafeModels`, reference `libtorch-cpu-<rid>` and `libtorch-cuda-12.8-<rid>` with
   `ExcludeAssets="all"`, link the CPU natives to `torch\cpu` and write `torch\<cuda package>.packages.txt`
   through `LibTorchPackageSet.targets` - the RID chosen as `LibTorch.props` does (win-x64 or linux-x64).
   `Build-Osprey.ps1 -Torch` is retired (the CUDA build stamp with it). `package.ps1` publishes the
   `torch` folder with the rest (Content with `CopyToPublishDirectory`).
2. **`TorchRuntimes` moves down** from Skyline to `CarafeSharp.Tasks` with the application and runtimes
   folders as constructor arguments and the "why not the GPU" answer as data (no driver / driver version /
   compute capability / no package list); Skyline's class becomes the thin wrapper that supplies the Tools
   folder and the localized text. `InstallCuda` (the package-by-package download with segments) moves with
   it; `HttpClientWithProgress` and `IProgressMonitor` are CommonUtil's already.
3. **Osprey chooses and logs the device.** Before the first library phase (the lazy seam: a search of a
   given library never touches libtorch) Osprey loads a runtime through `TorchRuntimes.Load`: the CUDA
   runtime when the driver can run it and it is installed, else the CPU one. The log names what ran:
   "Predicting on the GPU (<device name>, CUDA runtime <folder>)" or "Predicting on the CPU" with the reason
   when a GPU was asked for. `--device` gains the default `auto` (GPU when present and installed, CPU
   otherwise - Brendan's "one build, GPU when present"); `gpu` keeps falling back with the reason logged;
   `cpu` forces the CPU. A new `--install-cuda-runtime` downloads the runtime on the console with progress
   and exits (no prompt, so a script or an HPC login node can do it once); `--device gpu` without the
   runtime says to run it. **Decision 1**: `auto` as the default, or keep CPU the default until Mike has
   seen the GPU numbers. **Decision 2**: `--install-cuda-runtime` as an explicit step rather than a
   download on first `--device gpu`.
4. **Where the CUDA runtime lives: `--torch-runtimes <dir>`.** Default
   `<LocalApplicationData>\Osprey\torch` (a per-machine install under Program Files is not writable;
   on Linux it is `~/.local/share/Osprey/torch`). Skyline, when it hosts Osprey as a download, passes its
   Tools folder, so one CUDA install serves AlphaPeptDeep and Osprey. An HPC job points it at a shared
   folder. **Decision 3**: the default folder, and whether an environment variable
   (`OSPREY_TORCH_RUNTIMES`) should stand in for the option on a cluster.
5. **Tests.** `Osprey.Test` gets `torch\cpu` from the Osprey project's content and loads it where the
   pipeline does, so `SubsetPipelineTest` runs the real path; a unit test drives `TorchRuntimes` with a set
   `CudaDriver` (none, too old, GPU too old, runtime not installed) and asserts the choice and the reason
   without loading anything. Skyline's tests are unchanged. The TeamCity Osprey Windows .NET agent has no
   NVIDIA driver, so it is the "no driver" case; Osprey Linux .NET runs the same tests on the linux-x64 CPU
   natives in `torch/cpu` - the `.so` path through `LibTorchRuntime`.
6. **Gates**: the standing ones; `regression.ps1 -Dataset Stellar` byte-identical (the CPU natives are the
   same files, loaded differently); a local mode-1 run on the RTX 4090 through the new download into a
   fresh runtimes folder, its library compared with phase 1's `cuda-4c` GPU run; the package built with
   `package.ps1 -Rid win-x64,linux-x64` and the ZIP's `torch` folder checked; TeamCity Perf/Regression on
   `pull/<N>` (ask first).

Not in 4d: Skyline's Osprey search UI and the download of Osprey itself into Skyline's Tools folder
(a Skyline PR after this one, with the `--torch-runtimes` hand-off this PR defines); code signing.

### Tasks

- [ ] Plan above read by Brendan; decisions 1-3 taken (coded as proposed until then)
- [ ] 1. `LibTorch.targets` split; Osprey and Osprey.Test on Skyline's layout; `-Torch` retired; `package.ps1` carries `torch`
- [ ] 2. `TorchRuntimes` in `CarafeSharp.Tasks`; Skyline's wrapper; Skyline gates green
- [ ] 3. Osprey loads the runtime before the library phases; `--device auto|gpu|cpu`; `--install-cuda-runtime`; the device logged
- [ ] 4. `--torch-runtimes`, its default and the Skyline hand-off documented (Osprey docs, `Osprey-workflow.html`)
- [ ] 5. Tests: the runtime-choice unit test; `SubsetPipelineTest` on the new path; Linux on TeamCity
- [ ] 6. Gates; `/code-review medium`; PR; TeamCity Perf/Regression on `pull/<N>` (ask first)

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

### 2026-10-23 - PR 4d coded: one build, the runtime chosen at run time

Branch `Skyline/work/20261023_osprey_download`. Done as planned, with two placements settled by the
code: `LibTorchRuntimes` lives in `CarafeSharp.Models` beside `LibTorchRuntime` (Models already has
CommonUtil through `CarafeSharp.Core`, so Skyline needs no new reference), and the shared MSBuild layout
is `CarafeSharp\LibTorchRuntimeLayout.targets`, imported by Osprey.csproj and Skyline.csproj (Skyline's
inline block is gone; `UseCarafeModels` in `LibTorch.targets` copies the models alone). Osprey.Test gets
`torch\cpu`, the package list and the models from the Osprey reference; `UseLibTorch` stays for
CarafeSharp.exe and its tests. `Build-Osprey.ps1 -Torch` is retired, and the script cleans an output
folder the cuda build left (torch_cpu.dll under `runtimes\`, where only TorchSharp's own natives belong).
Osprey: `OspreyTorchRuntimes` (the default folder `%LOCALAPPDATA%\Osprey\torch`, `Load` with the device
logged, `Install` with console progress, the localized reasons), `--device auto|gpu|cpu`,
`--torch-runtimes`, `--install-cuda-runtime` (a command of its own, handled in Program right after the
parse), `LibraryBuildWorkflow.RunPhase` loads the runtime before the first phase and sets the device on
the library and training settings (`auto` never reaches CarafeSharp: its own default goes in and is
replaced). Tests: `LibTorchRuntimesTest` (CarafeSharp.Test: every reason, the list, the marker) and
`OspreyTorchRuntimesTest` (the options, the reasons' text, the CPU runtime loading from `torch\cpu`).
Docs: `20-command-line.md`, `ai/scripts/Osprey/README.md`. Committed as 46020fbf5e, then 41a04e37ad
(the generated help had embedded this machine's `%LOCALAPPDATA%` as the default folder - the usage text
now describes it in words; the install's console progress throttled to one line per package and one per
ten percent; the help pages regenerated by `TestCommandLineHelpDocumentation`; 2.9 GB in the docs, as the
package list says).

**Verified.** Osprey Debug 643/643 with inspection clean; CarafeSharp 107 passed / 8 skipped (the new
`LibTorchRuntimesTest` among them); Skyline Debug builds and `TestAlphaPeptDeepUseGpu`,
`TestAlphaPeptDeepBuildLibrary`, `TestLibTorchRuntimeInstall`, `CodeInspection`, `CheckForMissingResources`
pass; `regression.ps1 -Dataset Stellar` PASS (byte-identical). `Osprey --install-cuda-runtime` downloaded
the 16 packages (2.9 GB) from nuget.org and installed them in
`%LOCALAPPDATA%\Osprey\torch\libtorch-cuda-12.8-win-x64.2.10.0`. A mode-1 Stellar run with `--device gpu`
logged "Predicting on the GPU (NVIDIA RTX 4000 Ada Generation) with the NVIDIA CUDA runtime in ..." and
predicted the 484,908-precursor library in 43 s; its `osprey.predicted.blib` is identical to phase 1's
`cuda-4c\gpu-pretrained` GPU library in every spectrum (peaks and RT; `compare_blibs.py` in the session
folder), and the search ran through on the mzML copies (the Debug build has no vendor readers):
`D:\test\osprey-runs\4d\gpu-pretrained`. `package.ps1 -Rid win-x64 -NoZip` publishes `torch\cpu`
(256 MB, 8 files), the package list and `models` (25 MB) into `Osprey-26.1.1.296-win-x64`, with only
TorchSharp's own `LibTorchSharp.dll` beside `TorchSharp.dll`. Both CPU libtorch packages (win-x64 and
linux-x64) are self-contained on nuget.org, so the Linux layout fills `torch/cpu` the same way.

`/code-review medium`: 8 findings, 6 fixed (the tuned build's output library got no device - set with the
other two; `--install-cuda-runtime` ignored `--log-file` - `Program.OpenOutput` now serves both paths; a
stale libtorch beside TorchSharp.dll in an output folder built on the old layout - `LibTorch.targets`
deletes torch_cpu/torch_cuda from `runtimes\<rid>\native` and the output root before every build, for
agents and developers alike, so `Build-Osprey.ps1`'s cleanup went; a zero-size package list divided by
zero - refused with the list named; the not-installed reason re-read the list - uses the installer in
hand; the help's size was culture-formatted - invariant for the checked-in pages), 1 verified rather
than taken (the stale-file case, by planting torch_cpu.dll in both output folders: the build removed
them), 1 dropped (folding Skyline's and Osprey's reason switches into the base class: the two word and
case the reasons differently and Osprey has a case Skyline lacks; the enum is the shared contract).
Gates after the fixes: Osprey 643/643 and inspection clean, CarafeSharp 107/8, Skyline build and the
five tests.

**TeamCity on #4909.** Two findings, both fixed: the Skyline inspection flagged an unused `using System;`
in `TorchRuntimes.cs` (6df6ae6a07); Osprey Linux .NET failed `TestCommandLineHelpDocumentation` because the
help embedded the download size read from the build's own package list, and the linux-x64 CUDA set is
3.9 GB where win-x64's is 2.9 - the generated pages are checked in, so the size moved out of the help
and into the log, where it is computed at run time (b2622f64fc). Osprey Windows .NET, Core Windows and
the GitHub checks were green on the earlier head; the Linux run also showed `OspreyTorchRuntimesTest`
loading the CPU runtime from `torch/cpu` on Linux - the `.so` path through `LibTorchRuntime` works.
**Decisions (Brendan, 2026-10-23, by phone).** 1: `auto` is the default device. 2: the install stays an
explicit command, and `--device gpu` is a requirement: a run that cannot use the GPU fails before it
starts and says why (no NVIDIA GPU, driver or GPU too old, runtime not installed with the install command
named) - immediate failure beats a slow CPU run that needs troubleshooting. `OspreyTorchRuntimes.CheckGpu`,
asked in Program after `--task-files` and before the log opens, for a run that will predict (no stage
`--task`). 3: the default folder stays under local application data. Perf/Regression triggered on
`pull/4909` (build 4232635).

### 2026-10-23 - PR 4d merged

PR #4909 squash-merged by Brendan via `/pw-complete` as 59f90882bd (six branch commits; all 18 substantive
checks green on e2bfa92441: bt209 1823/1823, Osprey Windows and Linux .NET, Perf/Regression #343 116/116;
the Docker/Wine container status was still queued and was merged over). Shipped: one Osprey build with the
CPU libtorch in `torch\cpu` and the CUDA package list (`LibTorchRuntimeLayout.targets`, shared with
Skyline.csproj); `LibTorchRuntimes` in `CarafeSharp.Models` choosing and installing the runtime for both
applications, Skyline's `TorchRuntimes` a wrapper; `--device auto|gpu|cpu` (auto default; gpu fails before
the run starts when the GPU cannot be used), `--torch-runtimes`, `--install-cuda-runtime`; the device
logged per library phase; `LibTorch.targets` removing a stale libtorch beside TorchSharp.dll; `Build-Osprey.ps1
-Torch` retired. Not in 4d, on purpose: Skyline downloading Osprey into its Tools folder and a search UI (a
Skyline PR, with the `--torch-runtimes` hand-off this PR defines); code signing; the old-driver case and a
Linux GPU run remain untested. This TODO stays active for the measurement that follows PR 4.
