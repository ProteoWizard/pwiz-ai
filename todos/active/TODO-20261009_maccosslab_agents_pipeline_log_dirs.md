# TODO-20261009_maccosslab_agents_pipeline_log_dirs.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `work/20261009_pipeline_log_dirs`
- **Base**: `main`
- **Created**: 2026-10-09
- **Status**: In progress
- **PR**: (not opened)
- **Objective**: Let `access-log-review-pipeline` take the Apache and Tomcat log
  locations as options, instead of always reading `<logs_dir>/apache` and
  `<logs_dir>/tomcat`

## Background

Every path through the review assumes one `logs_dir` with fixed `apache/` and `tomcat/`
subdirectories (default `logs/panoramaweb.org`). On a machine where the copy job puts the
two logs elsewhere (or for an ad-hoc run against logs kept somewhere else), there is no way
to point the pipeline at them. The only setting today is `logs_dir` in `config.toml`, and it
still forces the subdirectory names.

## Where the `apache/` / `tomcat/` join happens

- `validate.check_coverage(logs_dir, window)` - the validate phase
- `pipeline.review_command` - passes `logs_dir` to the headless session's prompt
- `mcp_server.start_review(logs_dir=...)` - reads `logs/"apache"` and `logs/"tomcat"`
- `cli._analyze_prolonged_floods(agg, window, logs_dir)` - re-reads both for long floods
  (shared by the CLI and the MCP server)
- `cli.main` - the billed CLI's `--logs-dir`
- `pipeline._print_dry_run` - prints the logs location

## Plan

- [x] Pipeline options `--apache-dir` and `--tomcat-dir`; matching optional `config.toml`
      keys `apache_dir` / `tomcat_dir` under `[review]`. Precedence: option > config key >
      `<logs_dir>/apache` / `<logs_dir>/tomcat`. Relative paths resolve against the
      checkout root, like `logs_dir`
- [x] Pass the two resolved directories (not `logs_dir`) to `check_coverage` and
      `_analyze_prolonged_floods`
- [x] `start_review`: add optional `apache_dir` / `tomcat_dir` parameters that override
      `logs_dir`'s subdirectories; update its docstring (the tool description the subagent
      sees). The pipeline's prompt passes both absolute paths
- [x] Dry run prints both directories
- [x] `config.example.toml`, README, CLAUDE.md
- [x] Tests: option and config precedence, validate on non-standard directories, prompt
      contains both paths, `start_review` honors overrides

## Progress

- 2026-10-09: Scoped; branch created.
- 2026-10-09: Implemented and committed (`f72b851`, not pushed). `pipeline.log_dirs()` resolves the pair once;
  `check_coverage(apache_dir, tomcat_dir, window)` and
  `_analyze_prolonged_floods(agg, window, apache_dir, tomcat_dir)` take the two
  directories. The billed CLI also got `--apache-dir` / `--tomcat-dir` (it shares
  `_analyze_prolonged_floods`). Dry run prints `Apache:` / `Tomcat:` lines instead of
  `Logs:`. 141 tests pass; dry run against the checkout shows the overrides in the prompt.
  Next: `/code-review`, push, PR.
