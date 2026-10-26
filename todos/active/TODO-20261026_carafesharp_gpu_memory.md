# TODO-20261026_carafesharp_gpu_memory.md

## Branch Information
- **Branch**: `Skyline/work/20261026_carafesharp_gpu_memory`
- **Base**: `master` (d476f8a120)
- **Created**: 2026-10-26
- **Status**: PR open (#4918, 24babd5e17): measured, reviewed (/code-review max, 15 findings addressed), gates green.
- **GitHub Issue**: none
- **Module**: `osprey`
- **PR**: [#4918](https://github.com/ProteoWizard/pwiz/pull/4918)
- **Checkout**: `D:\Dev\pwiz-carafe-vram` (blencathra: i9-9900K, 64 GB, GTX 1650 4 GB)

## Objective

Keep CarafeSharp's GPU prediction inside the card's memory on Windows. Mike (2026-10-26): fix it first, in its own PR,
before going on with the ZT Scan whole-run comparison (TODO-20261021_osprey_stellar_demux.md).

## The problem

The ZT Scan library step of the whole-run comparison (Osprey e1b2446b83, `--device gpu`, GTX 1650 4 GB; charge 2-4,
392-900 m/z; `D:\test\osprey-runs\ztscan-full-20261025\osprey-library\osprey.log`) took 218 min: the training library
(4.54M precursors) 21 min and the final library (9.08M, entrapment and decoys predicted) 181 min. Time per 200k-form
batch rose from 12 s to 280 s in the first and from 135 s to 850 s in the second; the Stellar library on the same GPU
ran at 5,300 precursors/s throughout.

## Root cause (measured, `D:\test\osprey-runs\ztscan-full-20261025\gpu-probe*`)

`gpu-probe.ps1` re-runs the training-library prediction (PredictTrainingLibrary only) and samples every 5 s the
process's dedicated and shared GPU memory (Windows `GPU Process Memory` counters), GPU use, CPU and private bytes.

- Dedicated VRAM climbs about 280 MB a minute (141 MB to 3.4 GB in 8 min); at the card's limit the shared memory (system
  RAM the driver backs the allocation with) grows to 6 GB and batches 12-14 take 200-330 s instead of 33-66 s. The
  slowdown reproduces exactly (1,423 s; original 1,267 s).
- Not a leak: TorchSharp's `DisposeScopeManager.Statistics` on the predicting thread shows 208 live tensors (the
  models) throughout and every in-scope tensor disposed in scope; a forced GC after each batch leaves the VRAM curve
  identical.
- It is libtorch's CUDA caching allocator: with `PYTORCH_NO_CUDA_MEMORY_CACHING=1` VRAM stays at 300-580 MB (1.8x slower).
- Not batch shapes: padding every batch to a power of two (at most 10 shapes per peptide length) left the growth and the
  slowdown unchanged (1,563 s). `max_split_size_mb:128` no effect.
- `PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:4`: no spill, peak 2.97 GB, batches 12-14 at 66/41/33 s, the
  training library in 702 s (2.0x faster than the unchanged 1,423 s).
- Why only Windows: where a full card makes `cudaMalloc` fail (Linux), libtorch empties its cache and retries; the
  Windows driver backs the allocation with system memory instead, so the cache is never emptied.
- Carafe (Java + Python) is not affected: `AIGear` writes 200,000-peptide input files and `AIWorker` runs `ai_pred.py`
  once per file as its own process, which also calls `torch.cuda.empty_cache()` after each model. TorchSharp 0.106 has
  no `empty_cache` (its `torch.cuda` has only device_count, is_available, is_cudnn_available, manual_seed(_all),
  synchronize; LibTorchSharp exports no allocator functions).

## The fix

`TorchDevice.Resolve` sets `PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:4` before CUDA starts, on Windows, unless the
user set the variable. It must go through the C runtime (`ucrtbase` `_wputenv_s`): set with
`Environment.SetEnvironmentVariable` it had no effect (VRAM followed the unchanged curve exactly), because libtorch reads
the C runtime's copy of the environment.

## Measured after the first commit (0eabbc27b9)
- `gpu-probe-crtenv`: the setting made through ucrtbase `_wputenv_s` in-process takes effect through Osprey.exe (VRAM curve
  identical to the env-var run; set through `Environment.SetEnvironmentVariable` it had none, `gpu-probe-netenv`).
- `gpu-probe-final`: the 9.08M-precursor final library in a fresh process, 1,411 s, peak 2,971 MB, no spill. (The
  original 10,876 s was in-process after a spilled training library, so it is not a like-for-like baseline; the
  matched fresh-process pair is the training library, 1,423 s vs 702 s.)
- Rounding does not bound the cache: it steps up per tensor-size class (847 ... 2,971 MB), ~410 MB under the spill.
  `per_process_memory_fraction:0.75` alone (`gpu-probe-fraction`): libtorch empties its cache at the cap (2.8 -> 1.3 GB
  and so on), no spill, 700 s. `roundup_power2_divisions:1` is the default rounding, not a fallback.
- Both the CPU and the CUDA c10.dll parse `roundup_power2_divisions:4,per_process_memory_fraction:0.75` (rounding 4).

## /code-review max (2026-10-26): 15 findings, all addressed in the second commit
- Skyline ships an app-local ucrtbase.dll (Shared/Lib/VendorNativeCrt.targets); `DllImport("ucrtbase.dll")` bound to it, so
  the setting never reached libtorch in Skyline (reproduced with c10's parsed config: 0 vs 4). Now bound through
  `api-ms-win-crt-environment-l1-1-0.dll`, the API set c10.dll imports (`CrtEnvironment`).
- libtorch 2.10 reads PYTORCH_CUDA_ALLOC_CONF, PYTORCH_HIP_ALLOC_CONF, PYTORCH_ALLOC_CONF, the first one set winning: a
  user's PYTORCH_ALLOC_CONF was being replaced. Now any of them set is left alone, read from the C runtime; one set
  through .NET after start is passed on to it.
- The default is kept out of the process environment (child processes, e.g. Skyline's tools, inherited it).
- The cap added: `roundup_power2_divisions:4,per_process_memory_fraction:0.75`.
- Test rewritten: calls `ConfigureCudaAllocator` directly from a cleared environment, restores it; covers CPU request, the
  three user variables, the .NET-set case, Linux no-op.
- Out of scope, noted: Skyline holds its CUDA cache for the session after a GPU AlphaPeptDeep build (pre-existing).

## Related, for Nick (not this PR)
- Skyline's AlphaPeptDeep build forces AlphaPeptDeep RT when no fine-tuned model is given
  (`AlphapeptdeepLibraryBuilder.cs:299-300`, #4849); CarafeSharp's default is Chronologer. Mike (2026-10-26): Chronologer
  should be the default. Draft an issue for Nick if Mike agrees.

## Tasks
- [x] Reproduce and measure (above)
- [x] Fix in `TorchDevice`, review, rework
- [x] Whole library step in one process with the settings (`gpu-probe-whole-step`): 218 -> 52 min, peak 3.04 GB,
      no spill (training library 749 s, tuning search 771 s, fine-tune 180 s, final library 1,396 s)
- [x] Reworked build through Osprey (`gpu-probe-apiset`): settings take effect in-process, 700 s, no spill
- [x] Build, tests, inspection (CarafeSharp and Osprey); PR #4918 to master (label osprey)
