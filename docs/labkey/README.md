# LabKey / Panorama Development

Entry point for LabKey Server module development at the MacCoss lab — the
`MacCossLabModules` (`testresults`, `panoramapublic`) and `targetedms`
modules that power skyline.ms and Panorama Public.

This subdomain is intentionally **low-profile** in pwiz-ai: most developers
work on Skyline (pwiz repo) and never touch LabKey. The handful who do
should start here.

## Setup

- **[labkey-setup/README.md](../labkey-setup/README.md)** — phased Windows
  setup for LabKey enlistment, IntelliJ, Postgres, and the dev loop. Driven
  by `state.json`; designed for resuming across sessions.
- **`/pw-configure-labkey`** slash command — kicks off the phased setup flow.

## Daily workflow

- **[labkey-feature-branch-workflow.md](labkey-feature-branch-workflow.md)** —
  branch naming (`fb_*`, `XX.Y_fb_*`), cross-repo branch-name matching for
  TeamCity, SNAPSHOT release branches.
- **`labkey-development`** skill — auto-loads when working on
  MacCossLabModules or targetedms.

## Coding patterns

- **[labkey-modules-coding-patterns.md](labkey-modules-coding-patterns.md)** —
  general action types, form binding, DOM builder, unit tests.
- **[labkey-selenium-testing-guide.md](labkey-selenium-testing-guide.md)** —
  `BaseWebDriverTest`, helpers, common patterns for Selenium tests.

## Module architecture

- **[testresults-module.md](testresults-module.md)** — nightly test results
  dashboard on skyline.ms, run tracking, anomaly detection, email
  notifications. (`MacCossLabModules` repo layout.)
- **[panoramapublic-module.md](panoramapublic-module.md)** — Panorama
  Public submission pipeline, ProteomeXchange integration, DOI assignment,
  Journal abstraction.

## Panorama Public

Deeper docs for `panoramapublic`-specific work live under
[`panoramapublic/`](panoramapublic/):

- `panoramapublic-coding-patterns.md` — form class hierarchy and
  panoramapublic-specific patterns (delta from the general patterns doc).
- `private-data-reminders-overview.md` — submitter-nudge subsystem for
  unmade-public data.
- `spec-private-data-publication-search/` — feature spec set
  (`SPEC.md`, `SPEC-SUMMARY.md`, `PIPELINE-JOB-FLOW.md`).

## Related cross-cutting docs

- **[../version-control-guide.md](../version-control-guide.md)** — commit
  message format applies here too (LK-prefixed TODOs use the standard format).
- **[../mcp/tool-hierarchy.md](../mcp/tool-hierarchy.md)** — LabKey MCP tools
  (`mcp__labkey__*`) are used heavily by daily reports and triage, separate
  from the dev work covered here.
