# Agent brief for TODO-20261103_osprey_backlog_round2 (copy the preamble verbatim, then one agent section)

## Common preamble

You are one of four parallel agents producing ProteoWizard pull requests on BRENDANX-UW8 (32 threads,
128 GB). Work autonomously to a finished, reviewed, opened PR. Brendan (the developer) is not available
for questions; if something genuinely needs his decision, record it in your TODO's Status field, take
the conservative option, and keep going. Record progress in the TODO as you go: a later session must be
able to resume from it alone.

Checkout: your worktree is the directory you were started in (a git worktree of `C:\proj\pwiz`, already
on your branch, cut from origin/master). Work ONLY there. Never touch `C:\proj\pwiz`, `C:\proj\pwiz-*`
or another `C:\proj\wt-*` worktree (other agents use them). Project root for shared tooling is `C:\proj`;
the `ai/` repo is `C:\proj\ai`. Invoke shared scripts by absolute path. The git stash is shared across
worktrees: never bare `git stash`; use a WIP commit to set work aside.

Read first (do not skip): invoke the `osprey-development` and `version-control` skills (and
`skyline-development` for a Skyline-module item) with the Skill tool; `C:\proj\ai\CLAUDE.md`,
`C:\proj\ai\CRITICAL-RULES.md`, `C:\proj\ai\STYLEGUIDE.md` (open it: CRLF, `_camelCase`, braceless
bodies single-line only, helpers after the public methods that use them, resource strings for user-facing
text), `C:\proj\ai\WORKFLOW.md`, `C:\proj\ai\TESTING.md`, `C:\proj\ai\docs\long-running-jobs-guide.md`,
`C:\proj\ai\scripts\Osprey\PRE-COMMIT.md`. Read the issue(s) in full with
`gh issue view <N> --repo ProteoWizard/pwiz --comments`.

Verify before building: classify what the issue asks against the code at your base commit. If an item
is already fixed on master, say so in a comment on the issue (ending with the trailer below) and do not
open a PR for it.

Files you must not edit this round (Brendan's open PRs #4950, #4967, #4968, #4969 own them):
`Osprey.FDR/PercolatorTrainer.cs`, `PercolatorEngine.cs`, `PercolatorScorer.cs`, `PercolatorConfig.cs`,
`Osprey.ML/GradientBoostedTrees.cs`. No change may move a regression golden; if yours would, stop and
record why in the TODO.

Build, test, gates:
- Osprey pre-commit: `pwsh -File C:/proj/ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot <your worktree> -Configuration Debug -RunTests -RunInspection` (`-SourceRoot` is mandatory; without it the script builds `C:\proj\pwiz` and "succeeds" against the wrong tree).
- Skyline-module work: `pwsh -File C:/proj/ai/scripts/Skyline/Build-Skyline.ps1 -SourceRoot <your worktree>` and `Run-Tests.ps1 -SourceRoot <your worktree> -TestName <Name>`; Skyline's CodeInspection test must pass.
- Golden unchanged: `pwsh -File <your worktree>/pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` (read its header; it builds Release itself; run detached per the long-running-jobs guide and poll the log). Add `-Dataset StellarLibDecoy` when you touch pass-2, resume or diagnostics code. Do not rebuild while a run holds the exe; snapshot it to `D:\test\osprey-runs\_bin\<tag>` if you must.
- Never `cd` into a TestResults folder. Files are CRLF: Edit tool only, never `sed -i` or PowerShell backtick-n writes.

TODO, commits, PR:
- Create `C:\proj\ai\todos\active\TODO-20261103_<slug>.md` per `ai/WORKFLOW.md` (Branch Information with `- **Module**: ...`, GitHub Issue, Objective, Tasks, Progress Log).
- pwiz-ai commits: `git -C C:/proj/ai` ..., stage BY PATH only (never files you did not write), `git pull --rebase --autostash origin master`, then check `git diff --cached --stat` lists only your files, commit with `-F <file>` written with the Write tool, ending with exactly `Co-Authored-By: Claude <noreply@anthropic.com>` (a hook refuses any other attribution; no Claude-Session line, model name or emoji), `git push origin master`. Push the TODO BEFORE `gh pr create`.
- pwiz commits (in the worktree): past-tense title, `* ` bullets, `See TODO-20261103_<slug>.md in pwiz-ai/todos`, the same trailer, max 10 lines, `-F` file. Never commit code you have not built and tested. No `git add -A`.
- Before opening the PR, run `/code-review medium` from the worktree (the Skill tool, `code-review`, args `medium`). Verify each finding against the code; fix the real ones; record dropped ones with a reason in the TODO. If the skill is blocked, spawn a fresh general-purpose reviewer agent on `git diff origin/master...HEAD` instead and say so in the TODO.
- Open the PR from the worktree: `gh pr create --label <module> --title "<module>: <Past-tense title>" --body-file <file>`, PR format from the version-control skill (Summary bullets, `Fixes #N`, Test plan `- [x]`, TODO as a markdown link to `https://github.com/ProteoWizard/pwiz-ai/blob/master/todos/active/<file>`, trailer last). Do NOT trigger any TeamCity build by hand (the parent session queues the gate). Do NOT merge, force-push, or rebase after the PR exists (merge origin/master in if needed).

Report back: PR URL and title; what changed in two or three sentences; gate evidence with on-disk log
paths; decisions Brendan might revisit; anything deferred. Under 40 lines.

## Agent A (worktree `C:\proj\wt-progress`, branch `Skyline/work/20261103_osprey_progress_run`)

Item 1: #4979, `ProgressReporter.Run()` / `Run<T>()`. Pure refactor on top of #4955. Design in the
issue: the wrapper creates the reporter, runs the body, calls `Complete()` only when the body returns,
disposes in a `finally`; no `catch`. Convert the 43 `using (var progress = new ProgressReporter(...))`
scopes in Osprey and CarafeSharp (value-returning bodies take `Run<T>`; a lambda cannot `yield` or
capture `ref`/`Span<T>`, so read each body); the 5 field-held or parallel-loop reporters get their own
treatment; then make the constructor and `Complete()` non-public. Log output must be identical: Stellar
golden plus `pwiz_tools/Skyline/CommonTest/ProgressReporterTest.cs` and `MultiProgressReporterTest.cs`
(link or run them; Skyline CI runs them on the PR). Module `osprey`. Note: `PercolatorScorer.cs` and
`PercolatorEngine.cs` hold reporters but are off-limits this round; leave those sites on the explicit
`Complete()` and say so in the PR, to be converted after Brendan's PRs merge.

Item 2 (new branch `Skyline/work/20261103_osprey_per_k_fdp` from origin/master): #4489, the decoy-based
per-k FDP for the run-count histogram in `--model-diagnostics`. Diagnostics only, JSON keys additive,
a card in the report, definition in the diagnostics docs page; keep the entrapment line where it exists
so both show on StellarGenDecoyEntrap. Gate: Stellar, StellarLibDecoy and StellarGenDecoyEntrap.

## Agent B (worktree `C:\proj\wt-envvar`, branch `Skyline/work/20261103_osprey_env_var_catalog`)

Item 1: `C:\proj\ai\todos\backlog\TODO-osprey_env_var_cataloging.md`, read in full; the design is
settled there (Brendan, 2026-08-29): a `CommandArg`-shaped base, an `EnvVar` registration next to each
read replacing the scattered `IsSetAndNotZero(@"OSPREY_...")` calls in `OspreyEnvironment`,
`FdrDiagnostics` and `OspreyFileDiagnostics`; group and description required by the constructor;
`--help-env` prints the table grouped by kind; startup logs every non-default switch; a source-scan test
in the `TestNoUnstableSort` style forbids raw environment access outside the accessor; an out-of-set enum
VALUE on a behavior switch hard-fails (and fix the `Pass2FdrSidecar` message that lists half the valid
values). Decide and state whether the descriptions are RESX-bound (the TODO flags it as an explicit call;
default to RESX, since `--help` is). The unknown-`OSPREY_*`-name startup check is a warning. Cataloging
only: do not promote switches to CLI arguments. Module `osprey`. Fold the backlog TODO into your dated
TODO and `git rm` it in the same pwiz-ai commit.

Item 2 (new branch `Skyline/work/20261103_osprey_parity_rows` from origin/master):
`C:\proj\ai\todos\backlog\TODO-osprey_parity_path_retirement.md` rows A5, A9-A18 (A1-A4, A6-A8 were done
by the October resident-pool sprint): delete each switch's OFF arm and its tests, keep the Category B
diagnostics, verify every row's "removal blockers" against current code before deleting. Gate:
`regression-parallel.ps1 -Dataset All` once. Update the catalogue (rows removed) in pwiz-ai.

## Agent C (worktree `C:\proj\wt-unimodgen`, branch `Skyline/work/20261103_unimod_compiler_obo`)

Item 1: #4980 step 1 and its enforcement comment (read the issue and both comments). Repoint
`pwiz_tools/Skyline/Executables/DevTools/UniModCompiler` at `pwiz/data/common/unimod.obo` (parse with
`Pwiz.Data.Common.Unimod` if the compiler can reference it, else read the obo directly); keep the Mascot
`get_params.pl` and ProteinPilot inputs as the overlay they are; regenerate
`pwiz_tools/Skyline/Model/DocSettings/UniModData.cs` (expect 388 new ids, all hidden unless the Mascot
list shows them) and review the diff for anything other than additions and obo-driven value changes.
Add a Skyline test in the `TestNoUnstableSort` style: every `UniModData` entry's id exists in the obo,
its formula's monoisotopic mass equals `delta_mono_mass` at six decimals, and its sites and terminus are
among the obo specificities; every obo id absent from the table is on an explicit committed exclusion
list with a reason (should be empty after regeneration). Module `skyline`; the skyline-development skill
applies (Skyline CodeInspection, tutorial tests that list modifications may need their expected data
refreshed; run `Run-Tests.ps1 -TestName CodeInspection` and any test that fails on the first full run).
Document the regeneration step in the compiler README and in the CV-update procedure.

Item 2 (new branch `Skyline/work/20261103_mztab_unimod_obo` from origin/master, module `pwiz`):
`pwiz_tools/BiblioSpec/src/BiblioSpec/MzTabReader.cs` reads `pwiz/data/common/unimod.xml`; move it to
`Pwiz.Data.Common.Unimod` like `DiaNNSpecLibReader` and `TSVReader`, and run
`Build-BiblioSpec.ps1 -SourceRoot <worktree> -RunTests` (the reference checks). Leave `unimod.xml` in
place if anything else still reads it; say what does in the PR.

## Agent D (worktree `C:\proj\wt-carafe`, branch `Skyline/work/20261103_carafesharp_parity_script`)

Item 1: #4978 (read the issue and its decision comment). Move the eight full-size CarafeSharp parity
tests out of `CarafeSharp.Test` into a developer-run script modeled on
`ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1` (put it beside CarafeSharp's other scripts in
`pwiz_tools/CarafeSharp/scripts` or under `ai/scripts/CarafeSharp`, whichever the CarafeSharp README
convention favors; say which and why). The script fetches the packages (`build.ps1 -TestData Fetch` or
`testdata.json`) and runs the eight comparisons, reporting per comparison as the tests did; the subset
twins stay as unit tests; `tcregression.ps1` stops running the full tests and keeps the golden regression
legs; `docs/04-testing.md` moves the full-size parity description to the script. The per-commit pass then
reads `Passed 108` with nothing skipped. Module `osprey`. Request `maccoss` as reviewer on the PR
(`gh pr create --reviewer maccoss`).

Item 2 (no PR until the measurement is read): #4577. Re-measure the library-fragment retained set through
Stage 7 on the 82-file SEA-AD cohort on this machine: read `C:\proj\ai\scripts\Osprey\SEA-AD\README.md`
and `ai/docs/memory-band-guide.md` first; use `Run-SeaAd.ps1` (never your own runner), `-WhatIf` to
confirm paths, then the real run with `--timestamp --memstamp` and `OSPREY_LOG_MEMORY=1`, detached per
the long-running-jobs guide (hours; snapshot the exe first). Report the Stage 5->6 and 6->7 release
lines, the Stage 7 peak and floor from `ai/scripts/perfviz.py <log> --files 82`, and whether the second
release still frees zero. Then write the design in your TODO (which entries Stage 7 actually needs
fragments for, and how the retained set can narrow at the 6->7 boundary). Implement only if the
structure is clear and the change is output-locked by the golden; otherwise the TODO and a status comment
on #4577 are the deliverable.

## Agent E (worktree `C:\proj\wt-manifest`, branch `Skyline/work/20261103_osprey_stage6_manifest`)

Item 7, re-scoped 2026-11-03 after measuring what #4898 did. Read `C:\proj\ai\todos\backlog\TODO-task_file_contract_from_declarations.md`
and `gh issue view 4601 --comments` in full. Already on master (do not redo): `--task-files` prints each
task's declared inputs/outputs (`Program.PrintTaskFiles`), `OspreyTask.IsPerFileWorker` is the per-file/join
distinction, `regression.ps1`'s HPC chain (`Get-DeclaredTaskFiles`) and `Run-SeaAd.ps1 -LinkFrom`
(`ai/scripts/Osprey/Common/OspreyDatasetRun.psm1`) both stage from `--task-files` and fail on a missing
declared input; SecondPassFDR no longer declares `<stem>.calibration.json`; #4621/#4646 made Stage 6 write a
`.scores-reconciled.parquet` for every run with an `osprey.rescored` footer fact, and `AnyReconciledParquet`
reads the fact (option (a) of #4601 landed).

Step 1 (measure, record in your TODO): verify each remaining #4601 checkbox and each backlog-TODO task
against your base commit; cite file:line. Expected open items: (i) Stage 5 does not publish the Stage 6
work manifest it computes; (ii) `AnalysisPipeline.WriteTaskSidecars` stamps every declared output that
merely exists (defense-in-depth gap); (iii) no regression leg covers two runs in one output directory
with different PerFileRescoring validity keys and a shrinking work set; (iv) option (b) sidecar-only
attestation. Also check whether `<each>.reconciliation.json` is still declared by SecondPassFDR and
whether it is read on the default path.

Step 2 (implement what is open, golden-unchanged): the work manifest as an analysis-wide sidecar written by
FirstPassFDR (name it in the existing `output.<pass>.*` style; JSON; per stem: consensus / reconciliation /
gap-fill flags and a `hasWork` summary), declared in `Outputs` so `--task-files` prints it; the driver stamps
only outputs this run produced or verified current; a `regression.ps1` opt-in mode (NOT in the default or
`-Dataset All` set, no TeamCity change this round) that runs Stellar twice in one directory with a key change
that shrinks the work set and asserts the second blib equals a clean-directory run. Option (b) is a design
note in the TODO unless it falls out trivially. Skip the `1st-pass.model.json` stratum split (it is #4581
territory, held). Gate: Stellar and StellarLibDecoy. Module `osprey`. Fold the backlog TODO into your dated
TODO (what #4898 already delivered, what you did, what is left) and `git rm` it in the same pwiz-ai commit.
