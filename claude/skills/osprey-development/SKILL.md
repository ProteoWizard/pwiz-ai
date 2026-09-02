---
name: osprey-development
description: ALWAYS load when working in pwiz_tools/Osprey (C# port), on maccoss/osprey (Rust), or debugging Osprey-Rust parity issues.
---

# Osprey Development Context

Two trees, two convention sets:

- **Osprey** (`C:\proj\pwiz\pwiz_tools\Osprey`) - the C#
  implementation, now the path forward for the Osprey DIA proteomics
  search tool. Lives in the pwiz repo. **Follows Skyline conventions
  in full.**
- **Rust osprey** (`C:\proj\osprey` -> `maccoss/osprey`) - the
  original Rust implementation. Maintained for cross-impl parity
  validation against Osprey. Follows upstream osprey
  conventions, NOT Skyline's.

Which convention set applies depends on which tree you are touching.
The sections below are organized along that split.

## Osprey (C#) - Skyline Conventions Apply

**Changing what a task reads, writes, or keeps? Read
`pwiz_tools/Osprey/docs/00-pipeline-architecture.md` FIRST.** It is the pipeline's
architecture and sidecar file contract: which artifact is per-run vs experiment-wide,
which task may read it, what an HPC node must be shipped, and the fifteen principles
that keep a 500-run cohort inside 64 GB and let a fan-out task batch at any size. The
per-stage algorithm index is `pwiz_tools/Osprey/docs/README.md`.

Those live with the code because docs are classified by SUBJECT: *what the code does*
ships in `pwiz_tools/Osprey/docs`, *how we work on it* (gates, datasets, machine paths,
env vars, run layout) is in `ai/docs`.

When working in `pwiz_tools/Osprey`, all Skyline development
rules apply. Read the same files the `/skyline-development` skill
points at:

1. **`ai/CRITICAL-RULES.md`** - absolute constraints: NO async/await,
   resource strings for user-facing text, CRLF line endings,
   `_camelCase` private fields, helpers AFTER public methods that use
   them.
2. **`ai/STYLEGUIDE.md`** - **MUST READ before writing or editing ANY
   C#.** Actually open the file - these one-line summaries are a table
   of contents, NOT a substitute for reading it. C# coding conventions:
   file headers with AI attribution, using-directive ordering,
   `new[] { ... }` inferred array literals, control-flow rules
   (braceless bodies are single-line ONLY - this applies to `using`,
   `foreach`, `for`, `while`, `lock`, `fixed`, not just `if`/`else`).
3. **`ai/WORKFLOW.md`** - git workflow, TODO system, commit message
   format (past-tense title, `* ` bullets, `See TODO-... in pwiz-ai/todos`,
   `Co-Authored-By: Claude` line). Osprey commits go through the
   pwiz repo workflow (feature branches under `Skyline/work/...`).
4. **`ai/TESTING.md`** - translation-proof tests, consolidated
   `[TestMethod]` structure, `AssertEx` over `Assert`.

**Running a large named dataset (SEA-AD, TDP-43) - DO NOT write your own run script:**
- Each cohort has ONE sanctioned runner beside its README:
  `ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1` and `ai/scripts/Osprey/TDP43/Run-Tdp43.ps1`,
  sharing `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1`. Decoy arm, entrapment ratio and
  pass-2 mode are PARAMETERS, not separate scripts. **Read the folder's README first**, and
  run `-WhatIf` to confirm path resolution before committing to a multi-hour job.
- **A `ai/.tmp/run-*.ps1` script is a previous session's shortcut, not a template** - even
  when a handoff points at one. Rolling your own re-acquires traps these folders document:
  `--work-dir` relocates the `.spectra.bin` cache and rebuilds every file (~70 min / ~340 GB
  at 82 files - the runners pass `--output-dir`); `--fdrbench-pass` is inert without
  `--fdrbench <input.tsv>`; and the peak-pick model is nowhere in Osprey's log, so only the
  runner's banner / START line / directory name record which discovery set produced a number.
- Choosing a NEW large dataset (what exists, size, access, download budget):
  **`ai/docs/osprey-large-datasets.md`**.
- Full detail: "Large named datasets" in `ai/docs/osprey-development-guide.md`.

Memory or scaling work ("does this fit at N files?", a run that looks hung) needs:
- **`ai/docs/memory-band-guide.md`** - run with `--timestamp --memstamp`, then
  `ai/scripts/perfviz.py <log> --files N` for the numbers (peak, memory-floor drift per
  file, every reporting gap over 30s) or `ai/scripts/perfviz.html` for the plot. A sawtooth
  whose FLOOR returns to the same level is bounded; a rising floor is O(files) accumulation.
  Shared with Skyline - both emit the format from the same `CommandStatusWriter`. The guide
  also covers `OSPREY_LOG_MEMORY=1` post-GC probes, which are what answer "will it fit"
  (`--memstamp` includes uncollected garbage, so it shows shape, not magnitude).

Spectral-library or entrapment work ("rebuild the library", "change the
entrapment", "why is measured FDP X?") needs:
- **`ai/docs/osprey-library-generation-guide.md`** - the Carafe recipe for building a
  library from a protein FASTA, its prerequisites, and the validation numbers from our
  own reproduction. Also covers **natural (foreign-species) entrapment**: shuffle
  entrapment is an anagram of its own target, so it shares the target's fragment masses,
  is over-identified, and over-estimates FDP by ~1.6x where real Arabidopsis peptides
  give ~1.1x. Driver: `ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1 -Preflight`.
  To *derive* a variant from an existing library instead of building one, use
  `ai/scripts/Osprey/SEA-AD/New-SeaAdLibrary.ps1` (no Carafe, no GPU).

Cross-impl parity work additionally needs:
- **`ai/docs/osprey-development-guide.md`** - steel-thread parity
  doctrine, Stage 1-5 diagnostic dumps, bisection methodology, and the
  **FDRBench entrapment validation** section (the independent
  correctness oracle -- read it before any change that moves the
  discovery set or reported q-values; the oracle wins over parity).
- **`ai/docs/osprey-crossimpl-validation-guide.md`** - validation
  guide for cross-impl test runs.
- **`ai/scripts/Osprey/Compare/README.md`** - the cross-impl
  bridge scripts (`Compare-EndToEnd-Crossimpl.ps1`), needed only for
  the rare "did this drift us from Rust?" check. Older per-stage
  comparators (`Compare-Percolator.ps1`, `Test-Features.ps1`) are
  archived under `Compare/archive/`.

Osprey and cross-impl TODOs live at
`ai/todos/active/TODO-*_osprey*.md`.

## Rust osprey - Upstream Conventions Apply

When working in `C:\proj\osprey`, Skyline rules do NOT apply. Read:

1. **`ai/docs/osprey-development-guide.md`** - the full Rust-side
   development guide. Workspace layout, build wrappers, HPC CLI
   flags, env-var reference, bisection methodology, determinism
   patterns, steel-thread parity doctrine, commit/PR conventions
   vs. Skyline.
2. **`C:\proj\osprey\CLAUDE.md`** - Rust-side project overview:
   architecture, CI requirements, critical invariants (fold splits
   keep target-decoy pairs together; protein FDR uses raw SVM score;
   etc.).
3. **`ai/WORKFLOW.md`** - read ONLY to understand what *differs* on
   the Rust side. Skyline's commit format, branch naming, and TODO
   conventions do NOT apply to maccoss/osprey work.

Rust-side key constraints:
- **`cargo fmt --check` + `clippy -D warnings` + `cargo test`** all
  gate the CI. Test modules must be the last item in their file
  (`clippy::items-after-test-module`).
- **LF line endings** - not CRLF. Do NOT run `fix-crlf.ps1` on the
  Rust tree. (CRITICAL-RULES.md's CRLF rule is Skyline / Osprey
  only.)
- **Upstream-style commit prose**, no Skyline 10-line cap, no
  `Co-Authored-By: Claude` unless maintainer opts in.
- **Parity gate after scoring/calibration changes**: confirm
  Osprey still matches Rust with the cross-impl gate
  `ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1`
  on Stellar + Astral; see `Compare/README.md` for the tolerance.
  (The former per-PIN-feature `Test-Features.ps1` is archived under
  `Compare/archive/`.)

Rust-only TODOs live at `ai/todos/active/TODO-OR-*.md`
(`OR` = osprey rust).

## Continuing Work on a TODO

1. Call `mcp__status__get_project_status()` to see branch state
   across `C:\proj\osprey` and the relevant pwiz worktree.
2. Rust-only TODOs: `ai/todos/active/TODO-OR-*.md`.
3. Osprey and cross-impl TODOs:
   `ai/todos/active/TODO-*_osprey*.md`.

## Build, Test, and Commit

**Starting a long run? Snapshot the exe first.** Windows locks a running executable, so a
regression or large-file run holds `Osprey\bin\x64\Release\net8.0\Osprey.exe` and **every
build fails until it finishes** - you cannot address review feedback or try a fix mid-run.
Copy that output dir (~27 MB, one second) to **`D:\test\osprey-runs\_bin\<tag>`** (the
canonical spot - don't invent a new one per session) and pass `-Exe <snapshot>\Osprey.exe`;
the build tree stays free, and the snapshot doubles as a pinned baseline for an A/B. Do NOT
rebuild while a `regression.ps1` gate is running even if the build succeeds - it launches the
exe from the build tree per phase and would mix binaries.

**Consuming artifacts written by another day's build? Set `OSPREY_VERSION_OVERRIDE`.** Osprey
stamps a daily version into every `.scores.parquet` / `.osprey.task` and REFUSES a mismatch, so
a `-LinkFrom` resume silently re-runs Stage 1-4 for hours (or hard-fails in a way that reads
like a code bug). Read the version out of a source `.osprey.task` and pin it. See "Long runs
lock Osprey.exe" in ai/docs/osprey-development-guide.md for both traps in full.

You can and should build, test, and run Osprey yourself - the wrapper
scripts in `ai/scripts/Osprey/` exist for exactly that. Do not ask the
developer to build what you can run. `ai/scripts/Osprey/PRE-COMMIT.md`
and `README.md` are the authoritative gate references.

- **Osprey pre-commit** (build + tests + zero-warning inspection, ~30s):
  `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- **C#-side refactor / algorithm-affecting changes** (scoring, calibration,
  LOESS/KDE, SVM, FDR, decoy generation, blib) and every OOP/structural
  refactor: pass two standing gates.
  - **Correctness** (output unchanged): the self-contained straight-through
    regression vs a committed C# golden + a resume leg, both at 1e-9 (no Rust
    checkout):
    `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar`
    (`-Dataset All` before a behavior/perf-sensitive merge). Also the overnight
    TeamCity gate.
  - **Performance** (speed not degraded): a same-session A/B of the branch vs the
    pinned `pwiz-perfbase` baseline worktree (3-rep median, fails only on a real
    regression with non-overlapping bands):
    `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar`.
  `Test-Full-Regression.ps1` / `Test-Snapshot.ps1` are the stage-isolated
  bisection drill-down for WHERE a red correctness gate diverged, not the
  first-line gate. See `PRE-COMMIT.md`.
- **Rust osprey**:
  `pwsh -File ./ai/scripts/Osprey/Compare/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`
  (mirrors maccoss/osprey CI gates).
- **Cross-impl drift check** (rare; "did we drift from Rust?", e.g. after porting
  a Rust algorithm change):
  `pwsh -File ./ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1 -Files All`
  on Stellar + Astral (re-runs Rust). This replaces the old `-SkipRust` routine
  use, which `regression.ps1` superseded. See `Compare/README.md`.

## TeamCity Perf/Regression gate (manual - ask, then trigger)

The **Osprey Windows .NET Perf/Regression Tests** config runs `tctest.bat`, i.e.
`regression.ps1 -TeamCity -Dataset All`, plus a perf leg (~1 hour). It is manual
and does NOT start on PR open or push, but it must run before human review /
merge.

**It runs EVERY mode on ALL FOUR datasets** - no `-Skip*` switch is passed, so
whatever `regression.ps1` gains, this config runs. That is modes 1, 1b, 2, 3, 4,
5 and 6 today. (This paragraph said "mode1/2/3" for months after modes 4-6 were
added; if you are about to quote a mode list from here, check `tctest.bat`
instead - the invocation is one line and cannot go stale.)

"Four datasets" is **two acquisitions searched four ways**, not four acquisitions:
`stellar` (3 mzML, unit) and `astral` (3 mzML, hram), 6 distinct files total. The
Stellar mzML is searched three times against two library files:

| Dataset | mzML | Library | Decoys |
|---|---|---|---|
| `Stellar` | stellar, 3 | default stellar lib | generated, no entrapment |
| `StellarLibDecoy` | the same 3 | `stellar-libdecoy` as-is | supplied by the library - `DecoyGenerator` never runs |
| `StellarGenDecoyEntrap` | the same 3 | the SAME file, `StripDecoys` | generated, entrapment retained as a true-FDP oracle |
| `Astral` | astral, 3 | astral lib | generated, no entrapment |

The third is the only leg that guards `DecoyGenerator` against a true-FDP oracle:
the library-decoy leg never calls it, and the entrapment-free legs have nothing to
measure FDP against. All but `Stellar` carry `--model-diagnostics`.

**Claude MAY trigger it - but ASK FIRST, every time**, and ask again before any
re-trigger. Always `branch="pull/<N>"`, never the named `Skyline/work/...`
branch (a named branch silently builds master).

**NEVER on an internal commit before the PR candidate is ready.** Commits made
while iterating - WIP, review fixes, a rebase - are verified LOCALLY
(`regression.ps1 -Dataset Stellar`, then `-Dataset All`). The gate runs once, when
the branch is a genuine merge candidate. Firing it per commit is what produced a
queue Brendan had to hand-cancel and drew complaints from other developers waiting
on the shared agent.

Full rules - why the gate exists, MCP availability, the trigger call, and what
the run uniquely buys over the local Stellar gates - are in
**ai/docs/osprey-development-guide.md** ("TeamCity Perf/Regression gate").

Backlog overview: `ai/scripts/Osprey/Get-OspreyBacklog.ps1` (see the guide's "Osprey backlog overview").

## Key Repositories

- `C:\proj\pwiz\pwiz_tools\Osprey` - the C# implementation.
  Lives in `ProteoWizard/pwiz`. Branches and PRs follow Skyline
  conventions (`Skyline/work/YYYYMMDD_*`, past-tense title,
  Co-Authored-By).
- `C:\proj\osprey` -> `maccoss/osprey` (SSH). Primary Rust repo. New
  Rust branches and PRs go here
  (`gh pr create --repo maccoss/osprey`).
- `C:\proj\osprey-fork` -> `brendanx67/osprey`. Retired; do not
  extend.

## Slash Commands Available

Type `/pw-` to see project-wide commands. Most are Skyline-focused
and apply to Osprey work as well (commit, TODO, build wrappers,
review). They do NOT apply to Rust osprey work - the Rust side does
not use the Skyline TODO system or commit format.
