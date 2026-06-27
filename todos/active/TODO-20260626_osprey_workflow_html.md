# TODO-20260626_osprey_workflow_html.md -- OspreySharp docs refresh: workflow diagram, README, generated CLI usage page

> Make OspreySharp's documentation a good landing page for its current
> state (now the path forward, end-to-end bit-identical to Rust, faster),
> and stand up a published, drift-proof command-line usage page so the
> email to Mike Riffle (NextFlow HPC POC) and eventually skyline.ms can
> point at HTML rather than "build it and run --help".

## Branch Information

- **Branch**: `Skyline/work/20260626_osprey_workflow_html`
- **Base**: `master`
- **Created**: 2026-06-26
- **Status**: In progress -- pre-commit gate green, opening PR
- **GitHub Issue**: (none)
- **PR**: (pending)

## Scope

1. **`Osprey-workflow.html`** -- make it a current-state landing page.
   - Trimmed the historical "log of what has gone before" while keeping the
     performance tables/facts; updated the source-line-count table.
   - Reworked the HPC `--task` boundaries: each of the four workers now has a
     header banner naming the task plus its input / output files and the
     rehydration sidecars (drawn from each task's `Inputs()`/`Outputs()`), with
     flow arrows terminating at banner edges instead of piercing them.
   - Added the previously-missing 4th worker, `PerFileRescoring`
     (PerFileScoring -> FirstPassFDR -> PerFileRescoring -> SecondPassFDR).
2. **`README.md`** -- rewrote the stale status/perf/pipeline sections (it had
   claimed "not shippable", "C# ~2.4x slower", Stages 6/7 "missing/stubbed");
   added a Linux `dotnet publish` build section and an HPC quickstart with the
   four worked commands + workflow-engine notes.
3. **Generated CLI usage page** -- enriched `OspreyCommandArgs.GenerateUsageHtml()`
   with a `<title>`/meta, an intro, and a drift-proof "Distributed execution (HPC)"
   worked example; committed the output to
   `pwiz_tools/OspreySharp/Documentation/Help/en/CommandLine.html` (mirrors
   Skyline's `Documentation/Help/<lang>/` layout) and added
   `TestCommandLineHelpDocumentation` to validate committed == generated
   (record via `OSPREY_RECORD_USAGE_HTML=1`).

## Follow-ups (separate pushes, noted for later)

- `.resx`-ize the inline `OspreyArgUsageProvider` descriptions so ja / zh-CHS
  can be generated; extend the test with a per-language loop like Skyline's.
- Publish `CommandLine.html` + `Osprey-workflow.html` to skyline.ms.
- Possible `Documentation/Tutorials/` modeled on the SkylineAiConnector
  `tool-inf/docs` (self-contained index.html + screenshots).

## Progress Log

### 2026-06-26 - Implemented; gate green

Workflow HTML redesign, README rewrite, and the generated/validated
`CommandLine.html` + test all complete. Full pre-commit gate green
(build + 437 tests pass, 0 inspection warnings). Updated the Mike Riffle
draft email to point at the githack-rendered workflow + CommandLine pages.
Opening the PR next.
