# TODO-20261101_osprey_chain_orphan_kill.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_chain_orphan_kill`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: In Progress
- **GitHub Issue**: [#4503](https://github.com/ProteoWizard/pwiz/issues/4503)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

An aborted mode-3 chain phase left an `Osprey.exe` running that locked the build output and broke
the next TeamCity build. Make `regression.ps1` reclaim the processes it launches.

## What was measured first (harness below)

- A phase aborted by a throw in its output pipeline does NOT orphan the exe in pwsh 7: PowerShell
  waits for the native process before the throw unwinds (returned after the full run time).
- A pipeline Stop (Ctrl+C, host Stop) does not orphan it either: pwsh kills the native child.
- What does orphan it is the pwsh itself being killed (TeamCity timeout, OOM kill, a reaped
  session): no `finally` runs, and Windows does not end a child with its parent. That is the
  only mechanism found that matches the issue (script gone, exe alive, lock on the build output).

## Change

- `Stop-LaunchedOsprey`: kills (`taskkill /T /F`) and waits for any `Osprey.exe` whose parent is
  THIS pwsh. Called in the `finally` of every launch (straight-through runs, `--task` phases,
  `--task-files`, the `--export-library` step, now wrapped in try/finally) and in the script's
  own `finally`. On the normal path it finds nothing (one CIM query, ~0.1 s).
- `Stop-OrphanedOsprey`, run before the build: kills an `Osprey.exe` running from THIS build
  tree's exe path whose parent process is gone (or whose parent PID was reused by a newer
  process). Covers the killed-pwsh case, which no `finally` can. A process with a live parent -
  another regression-parallel lane, a developer's run - is left alone.

## Decision Brendan might revisit

- The startup sweep kills rather than refuses. On TeamCity only killing heals the agent; locally,
  an exe from the build tree with a dead parent would break the build anyway. If a developer
  launches long runs from the build tree via a launcher that exits (CIM / WmiPrvSE recycled), the
  sweep would end that run - the guide already says to run long jobs from a `_bin` snapshot.

## Tasks

- [x] Harness: `ai/.tmp/sessions/20261101-quickwins/orphan-harness.ps1 -Regression <regression.ps1>`
      loads the three helpers from the script via the AST, uses a copy of PING.EXE named
      Osprey.exe, and checks: (1) pipeline-abort behavior, (2) a running child is reclaimed and the
      exe is no longer locked, (3) the normal path finds nothing and keeps LASTEXITCODE, (4) the
      orphan sweep stops a dead-parent exe and spares a live-parent one. All pass against the
      branch's regression.ps1.
- [x] regression.ps1 -Dataset Stellar: PASSED; -Dataset StellarLibDecoy -NoBuild (the leg that runs
      mode 3, the HPC chain): PASSED, 17 checks, no WARN: stopping line on the normal path
- [x] Build-Osprey gate not applicable: only regression.ps1 changed (no C#); script parse-checked
- [x] Review: `/code-review` is blocked from this agent's pinned cwd (`C:\proj\ai`), so an
      independent reviewer read the diff with the same brief. No defects (checked definition
      order, LASTEXITCODE capture, lane isolation, CIM filters, Wait-Process on a gone PID, the
      export try/finally). Dropped: a hand-started run from this bin whose console closed is
      swept (that is the decision above); Wait-Process on a reused PID costs at most 60 s; logging
      the killed process's command line is cosmetic.
- [ ] PR

## Progress Log

### 2026-11-01
- Implemented and harness-tested. Commit 9878650e40.
