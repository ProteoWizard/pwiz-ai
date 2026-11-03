# TODO-20261103_osprey_backlog_round2.md

## Branch Information
- **Branch**: none yet - this TODO is the plan and handoff for a wave of agent-run branches, one per item below
- **Base**: `master` (origin/master c1242139bf at planning time)
- **Created**: 2026-11-03 (handoff written by the round-1 session)
- **Status**: READY TO LAUNCH - nothing started. Brendan answered every gating question (section "Decisions"); worktrees for the first four agents exist under `C:\proj\wt-*`. The next session launches wave A from the "Launch procedure" section.
- **GitHub Issue**: round-1 ranking https://claude.ai/artifact/4a2D4pryYFsVPpCdsPky2G ; round-2 plan page https://claude.ai/artifact/AzeCh12WKV9ngitSM4LhyR
- **Module**: `osprey` (items 4 and 5 below are `skyline` / `pwiz` module PRs)

## Objective

Repeat round 1 (2026-11-01 to 03: twelve PRs from parallel Opus agents, all merged) on the next set
of backlog items that need no decision mid-flight, while Brendan's FDR-gap work (#4950, #4967,
#4968, #4969) lands in parallel. Round 1 record: `todos/completed/2026/11/TODO-20261101_osprey_*.md`
and the memory note `osprey-backlog-wave1-2026-11-01`.

## Decisions (Brendan, 2026-11-03, interview)

1. **Goldens**: organize to minimize golden updates. Golden-moving changes are NOT done one PR at a
   time: stack them on one branch (or merge the PRs into one), squash once, one golden update. A
   golden change also needs the cross-impl test (`ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1`)
   and may need a Rust parity PR in maccoss/osprey. Combined with decision 2, no golden-moving item
   runs this round until Brendan's PRs merge.
2. **Sequencing**: agents stay OUT of `PercolatorTrainer`, `PercolatorEngine`, `PercolatorScorer`,
   `PercolatorConfig` and `Osprey.ML/GradientBoostedTrees` until #4950, #4967, #4968, #4969 merge.
3. **Mike's items**: #4978 may be done by an agent with Mike (`maccoss`) as reviewer. The blib schema
   work (#4894, #4622, #4561) stays Mike's; held.
4. **UniMod step 1 of #4980**: regenerate Skyline's `UniModData.cs` from the current obo NOW
   (388 new ids, hidden unless the Mascot list shows them), compiler repointed at the obo, overlay
   committed, obo-vs-table verifier test added. `skyline` module PR; `MzTabReader` off `unimod.xml`
   as a second `pwiz` PR.
5. **DIA-NN parquet fixture**: DIA-NN is NOT installed on UW8 (searched 2026-11-03). Brendan will ask
   his other session (MACS2) to copy `D:\Users\brendanx\test\diann\libformat-test`; may take hours.
   Item 6 starts only when a real DIA-NN 2.7 parquet is on this machine.
6. **TeamCity gate additions** (a `-DetectResolution` leg, un-cutting mode 3 on StellarGenDecoyEntrap):
   SKIP this round. Item 8 reduces to the parity-catalogue rows A5, A9-A18.
7. **#4577 on UW8**: yes. The SEA-AD cohort is local (`OSPREYDEV_SEAAD_DIR=D:\test\osprey-runs\sea-ad\mzml`,
   `OSPREYDEV_SEAAD_LIB=D:\test\osprey-runs\sea-ad\lib`, both present). Measure first, design second,
   code only if the structure is clear.
8. **Scale**: four agents at a time; queue each PR's Perf/Regression gate the moment the PR opens,
   for PRs that touch FDR or scoring code only (script-only, log-only, diagnostics-only PRs merge on
   local Stellar/LibDecoy evidence, as round 1 did).

## The wave (four agents, each in its own worktree; second items run after the first PR is open)

| Agent | Worktree (exists) | Branch (exists) | First item | Then |
|---|---|---|---|---|
| A | `C:\proj\wt-progress` | `Skyline/work/20261103_osprey_progress_run` | #4979 ProgressReporter `Run()` / `Run<T>()` wrappers | #4489 decoy-based per-k FDP (new branch from origin/master) |
| B | `C:\proj\wt-envvar` | `Skyline/work/20261103_osprey_env_var_catalog` | `--help-env` catalog (`todos/backlog/TODO-osprey_env_var_cataloging.md`) | parity catalogue rows A5, A9-A18 (`todos/backlog/TODO-osprey_parity_path_retirement.md`) |
| C | `C:\proj\wt-unimodgen` | `Skyline/work/20261103_unimod_compiler_obo` | #4980 step 1: UniModCompiler reads the obo, regenerate `UniModData.cs`, verifier test (`skyline` module) | `MzTabReader` off `unimod.xml` (`pwiz` module, new branch) |
| D | `C:\proj\wt-carafe` | `Skyline/work/20261103_carafesharp_parity_script` | #4978 full parity tests -> developer script (reviewer `maccoss`) | #4577: SEA-AD 82-file `--memstamp` measurement, then a design, code only if clear |

Next slots when one frees: item 7 (`--help-files` task contract from
`todos/backlog/TODO-task_file_contract_from_declarations.md` plus #4601's Stage 6 work manifest;
the agent first measures what #4898 already did), then item 6 (DIA-NN parquet loader) once the
fixture is here. Alternates: #4470 (golden-moving, so after decision 1 and 2 clear), #4464, #4361
(probably a doc PR and a close).

## Held (do not start)

- Golden-moving and Percolator/GBT files until Brendan's PRs merge: #4392, #4492 (determinism pair),
  #4596 (GBT NaN), #4812 (training cap), #4470. When they clear: ONE stacked branch, one golden
  update, cross-impl check, Rust parity PR if the parity datasets move.
- FDR-gap territory: #4538, #4580, #4581, #4572, #4466. Mike's branches: #4759, #4711, #4713, #4714.
- #4894, #4622, #4561 (Mike's blib schema). #4980 steps 2-5. #4469, #4471, #4467 remainder, #4511,
  `TODO-carafe_osprey_library_contract.md` (open design questions).

## Launch procedure (next session)

1. `mcp__status__get_project_status()`; the four `C:\proj\wt-*` worktrees appear as extra pwiz
   checkouts. Confirm each is still at its branch and clean; `git -C <wt> merge origin/master` if
   master moved (no rebase once a PR exists; none exists yet, so a fresh `git reset --hard origin/master`
   is also fine before the first commit).
2. **Spawn each agent with the session's working directory INSIDE its worktree** (`cd C:/proj/wt-progress`
   then the Agent call, and so on). Round 1 spawned from `C:\proj\ai`, where `Deny-CodeReviewInAiRepo.ps1`
   blocks `/code-review`, so every agent had to substitute a reviewer subagent. Worktrees under `D:\Dev`
   cannot be the session cwd (it resets to `C:\proj`), which is why these are under `C:\proj`.
3. Use the brief in `TODO-20261103_osprey_backlog_round2-brief.md` beside this file: the common
   preamble verbatim, then the per-agent section. Model: Opus. Four at once.
4. As each PR opens, the parent session queues the Perf/Regression gate for PRs with FDR or scoring
   code (`mcp__teamcity__trigger_build`, `ProteoWizard_OspreyWindowsNetPerfRegressionTests`,
   `branch='pull/<N>'`); items 1-8 are all golden-unchanged, so most need none. Then `/pw-complete`
   each PR one at a time with Brendan's yes on the squash message, as round 1 did.
5. pwiz-ai hygiene: stage by path, never `git add -A`; after any `git pull --rebase --autostash`,
   check `git diff --cached --stat` lists only files you changed before committing. A stale-checkout
   commit (0dafa855, 2026-11-02) reverted 28 pwiz-ai paths in round 1.
6. When a wave-A PR is done, the freed slot takes the next item from the table; keep four running.

## Progress Log

### 2026-11-03
- Plan drafted from the refreshed backlog (29 open osprey issues); Brendan answered the eight gating
  questions (section "Decisions"). Worktrees created under `C:\proj\wt-*` on their branches from
  origin/master c1242139bf. DIA-NN confirmed absent on UW8; SEA-AD cohort confirmed present.
  Nothing launched: this TODO and its brief are the handoff.
