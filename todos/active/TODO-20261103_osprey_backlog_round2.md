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
- 13:11-13:30 (night session, Fable 5.1 parent): origin/master had moved to 049d045e98 (#4967 merged;
  #4950, #4968, #4969 still open, so the hold list stands). Fast-forwarded all four worktrees to it.
  Launched agents A-D (Opus) from inside their worktrees with the brief file as their instructions;
  each writes `ai/.tmp/agent-<X>-status.md`. Budget log: `ai/.tmp/night-session-budget.md`.
- 13:50: Agent D opened PR #4982 (osprey: Moved the full-size CarafeSharp parity tests to a developer-run
  script; reviewer maccoss). Script/test-only, no FDR or scoring code: no Perf/Regression gate queued
  (decision 8). D's SEA-AD 82-file measurement for #4577 started 13:16 and is re-scoring all 82 files
  (caches invalid for this build); expected to finish ~18:00. Log:
  `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactagentD4577-20261103_131639\run.log`.
- 14:15: Agent D handed back (report in `ai/todos/active/TODO-20261103_carafesharp_parity_script.md` and
  `TODO-20261103_osprey_stage7_fragments.md`; design notes say the 6->7 narrowing is likely a 1-3% lever).
  Its SEA-AD run continues detached; the parent reads it ~18:00 ("Resume here" in the stage7 TODO).
  Launched Agent E (item 7 as re-scoped, `C:\proj\wt-manifest`). Context 83% free, burn ~7%/h.
- 15:40: Agent E opened PR #4985 (test-only: shrinking Stage 6 work-set check in SubsetPipelineTest;
  the Stage 5 manifest premise is gone since #4863, WriteTaskSidecars gone since #4809). No gate queued.
  FLAG for Brendan: the PR says `Fixes #4601`, which closes the issue on E's judgement; option (b) and the
  #4597 compaction risk stay unbuilt. Backlog TODO-task_file_contract_from_declarations.md folded and removed.
  Two slots free: launched Agent F (#4361 Phase B, `wt-carafe`) and Agent G (#4464 diagnostics-only
  slice, `wt-manifest`); sections added to the brief.
- 15:55: Agents A and B opened PR #4984 (ProgressReporter Run wrappers) and PR #4983 (env-var catalog,
  --help-env); both touch FDR/scoring files, so Perf/Regression queued: build 4249213 for pull/4984,
  build 4249212 for pull/4983 (https://teamcity.labkey.org/build/<id>). A is gating #4489 (item 2);
  B is gating parity rows (item 2, A10-A13/A17 and parts of A18 deferred with reasons in its TODO).
  Master moved again: #4968 and #4969 merged; #4950 still open (hold list stands for Percolator/GBT).
- 16:03: Agent B handed back: PR #4986 (parity-only arms of five switches removed; A10-A13, A17 and the
  rest of A18 deferred with re-checked blockers). Perf/Regression queued: build 4249273 for pull/4986.
  Expected merge conflict: #4983 and #4986 both edit OspreyEnvironment.cs (second to merge drops the
  retired EnvVar declarations; both TODOs say how). B's slot stays open: every remaining open osprey
  issue is held, assigned, or item 6 (DIA-NN fixture still absent). Four agents running: A, C, F, G.
- Agent A handed back: PR #4987 (decoy-based per-k FDP; diagnostics only, three goldens unchanged,
  no gate per decision 8). Entrapment and decoy curves agree on StellarLibDecoy and StellarGenDecoyEntrap
  (k=1: 3.41 vs 3.76%, 4.60 vs 3.93%). Decisions for Brendan in its TODO: no pass-2 decoy curve
  (gap-fill bias), plain D/T estimator, and #4984 leaves the ProgressReporter constructor public until
  the Percolator sites convert. Slots A and B idle; C, F, G running.
- Agent F handed back: PR #4988 (Linux path identity + LF calibration.json; #4361 left open with a
  status comment, TeamCity activation still pending). Perf/Regression queued for pull/4988 (build 4249301,
  16:23). Not run on Linux: the WSL build failed in build/VendorPinsGenerator and the agent
  stopped rather than bypass the direct-build hook. Open gap for Brendan: on Windows, `Run1`/`run1` in one
  output dir are still unrefused (precise fix in its TODO).
- Agent G handed back: PR #4989 (equal-chance alarms card in --model-diagnostics; "Partially addresses
  #4464"; diagnostics only, 35/35 parallel regression, no gate). No alarm fires on any gate dataset
  (current gendecoys are near-calibrated; the F instrument is the way to a positive case). Four
  thresholds are the agent's own numbers (location 0.5 sigma, scale x1.5, coin 10 points, granular <50).
- 17:00: Agent C was stalled since 14:00 on a hung TestData.dll test process (PID 173296, 175 CPU-s in
  3 h; 50 earlier failures look like vendor raw import in the fresh worktree, first TestCommandLineNoJoin;
  TestMs1Tutorial "Expected document to have results"). Resumed C with the facts and told it to kill the
  process, classify the failures, and finish Item 1. SEA-AD run: Stage 5 done 16:54 (fragments released
  for 4,667,143 of 6,175,389 precursors; 754,359 base_ids retained), Stage 6 running.
- 17:05: Agent C root-caused the stall: the worktree has no Directory.Build.user.props, so Skyline
  built with vendor support DISABLED and the 50 TestData failures + TestMs1Tutorial are environmental.
  Rebuilding with -VendorLicenses and re-running. Lesson for the next round's briefs: Skyline-module
  worktrees must build with -VendorLicenses (memory `worktrees-lack-vendor-props`).
- Agent C handed back: PR #4990 (skyline: UniModCompiler reads unimod.obo, UniModData.cs 1172 -> 1554
  ids, 6 protein-terminal-only ids excluded, TestUniModAgreesWithObo; "Part of #4980") and PR #4991
  (pwiz: MzTabReader resolves UNIMOD ids from the embedded obo; unimod.xml stays until #4990 merges).
  Skyline CI runs on the PR; no Osprey gate. FLAGS for Brendan: (1) `Pwiz.Data.Common.Unimod` keys
  specificities by `spec_N`, which the obo repeats per site group, so it keeps one site per group
  (Phospho loses T) - affects Osprey and BiblioSpec, not filed (roadmap step 2); (2) ~410 new hidden
  entries now take part in mass matching on import; (3) ~50 entries differ from UniMod's six-decimal
  mass by 1-26e-6 Da with Skyline's element masses (step 3 question).
- 18:55: SEA-AD run for #4577 finished (exit 0, 5:33). 6->7 release still frees 0 (754,359 base_ids
  retained). Stage 7 floor is now 4.4 GB managed (peak 8.6, private 13.6) against a run peak of 38.9 GB
  private in Stage 5, so the ~0.4-0.7 GB fragment lever is 2% of peak: DEFERRED with a status comment
  on #4577 and the read recorded in TODO-20261103_osprey_stage7_fragments.md. No PR for item D2.
- 18:52: Gates PASSED for #4983 (build 4249212) and #4984 (build 4249213). #4986 (4249273) running,
  #4988 (4249301) queued behind it. The Perf/Regression config does not report to the PR's GitHub
  status; check TeamCity by build id.
- 19:35: Gate PASSED for #4986 (build 4249273). #4988 (4249301) started 19:31, ~65 min.
- 20:50: Brendan awake. Gate PASSED for #4988 pending the final step (build 4249301 at 100%). Item 6
  fixture: Brendan created `M:\home\brendanx\data\MacCoss\Osprey\DIA-NN`; wrote `request.md` there
  for the MACS2 session. Finding: BiblioSpec's `DiaNNSpecLibReader.LoadSpecLibFromParquetAsync` already
  reads the DIA-NN v2 library parquet (same columns); the backlog TODO omitted it. The tree's test inputs
  have only PSM `report.parquet` + `.skyline.speclib`, no library parquet, so the fixture is still needed.
- 20:55: Gate PASSED for #4988 (build 4249301). All four queued gates green; every PR of the wave is
  ready for /pw-complete (#4982 awaits Mike's review).
- 21:20: DIA-NN fixtures arrived from MACS2 (`M:\home\brendanx\data\MacCoss\Osprey\DIA-NN`, README with
  measured format facts: first row group always empty, RT on the predicted scale in both shapes,
  Source.Id only on decoys, trailing Trace column in empirical libraries). Item 6 launched as Agent H
  (`wt-progress`, branch `Skyline/work/20261103_osprey_diann_parquet_loader`); brief section added.
- 21:45: Brendan reviewed the completion plan (artifact AzeCh12WKV9ngitSM4LhyR). Tier 1 merged via
  /pw-complete: #4985 -> 940df9220f, #4990 -> 165bf9bffb, #4991 -> de6beefa92; TODOs moved to
  completed/2026/11; branches deleted. #4982 held: Brendan wants GPU support in the parity script,
  the Astral leg run here, and the script surfaced in the osprey-development skill like the cross-impl
  comparison (it is not today); follow-up agent D2 launched on the PR branch in wt-carafe. With #4990
  and #4991 both merged, pwiz/data/common/unimod.xml has no reader and can be deleted.
- 22:40: #4987 merged (8f7c835d99) and finalized. Merged master into #4989's branch (one conflict,
  docs/README.md rows; template auto-merged); merged branch 651/651 + inspection clean
  (`ai/.tmp/sessions/20261103-parent/build-4989-merged.log`). Agent H opened PR #4994 (DIA-NN 2.x
  library .parquet via -l; shared column reader moved into BiblioSpec.IO; 1.56 M-precursor load in
  23 s, peak managed 4.1 GB). Perf/Regression queued: build 4249971 for pull/4994.
- 2026-11-04 00:10: Tier 2 merged: #4987 -> 8f7c835d99, #4989 -> 0bec7caeef (after a master merge
  resolved by the parent; both cards confirmed in a re-rendered Stellar report). #4982 follow-up
  posted (PR comment 6624465850): CPU 12/12 on Stellar+Astral; CUDA fails the RT comparisons because
  of TF32 (decision for Brendan: GPU tolerances vs disabling TF32 in inference). Tier 3 starts with
  the #4983 conflict (OspreyEnvironment.cs vs #4968) - agent B2 in wt-envvar.
