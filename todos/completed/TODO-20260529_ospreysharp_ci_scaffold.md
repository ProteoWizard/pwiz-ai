# TODO-20260529_ospreysharp_ci_scaffold.md -- Wire OspreySharp into pwiz CI

## Status

Completed -- PR merged. TeamCity build-config wiring deferred to Matt
(tracked in "Open questions for Matt" below).

## Branch Information

- **pwiz branch**: `Skyline/work/20260529_ospreysharp_ci_scaffold`
- **PR**: [#4247](https://github.com/ProteoWizard/pwiz/pull/4247) (merged 2026-06-08)
- **ai branch**: `master`

## Background

OspreySharp's 347-test unit-test suite (345 pass / 2 skip post #4246)
runs locally on every developer machine via `Build-OspreySharp.ps1
-RunTests` but is not yet wired into pwiz's TeamCity CI.  Matt's
recommendation (forwarded by the user): add a self-contained
`tcbuild.bat` at the project root, modeled on the same pattern
already used by pwiz-sharp.  TeamCity invokes the batch; the
batch handles build, test, dotCover coverage, and TeamCity service
messages.  Build scripts live with the code (versioned alongside
the project), not in the ai/ tooling tree.

## Objective

Land a small, focused PR adding three files at
`pwiz_tools/OspreySharp/`:

* `build.ps1`     -- self-contained build/test/coverage driver
* `build.bat`     -- local-dev wrapper (forwards args to build.ps1)
* `tcbuild.bat`   -- TeamCity entry point (-TeamCity -Coverage
                     -Configuration Release -Framework net8.0)

Self-containment matters: the pwiz repo must build and test
without an ai/ checkout, since CI agents pull only the pwiz
repository.  The richer LLM-driven dev wrapper at
`ai/scripts/OspreySharp/Build-OspreySharp.ps1` (line-ending fix,
ReSharper inspection, dataset-aware test runs) stays put as the
local-dev sidekick.

After the PR merges, Matt wires up the TeamCity build config:
working directory `pwiz_tools/OspreySharp/`, build step
`tcbuild.bat`, file trigger `pwiz_tools/OspreySharp/**` so this
config only fires for OspreySharp changes.

## Verification

Local smoke test on the branch HEAD:

* `build.bat` -- exit 0, 345/347 tests pass, TRX written at
  `pwiz_tools/OspreySharp/TestResults/OspreySharp.Test-Release-net8.0.trx`.
* `build.ps1 -TeamCity` -- service messages emit correctly:
  - `##teamcity[progressMessage 'Building OspreySharp.sln (Release||x64)']`
  - `##teamcity[progressMessage 'Running tests (net8.0)']`
  - `##teamcity[importData type='vstest' path='...trx']`

## Open questions for Matt

These are coordination details for the TeamCity build config, not
blockers for the PR:

1. dotCover Global Tools install state on the target agent
2. GitHub status reporting mechanism (presumably the same hook
   other pwiz configs use)
3. Smart-trigger glob: `pwiz_tools/OspreySharp/**` proposed
4. Whether CI should test net8.0 only or both net8.0 + net472
   (PR ships net8.0 to keep the initial config small)

## Progress Log

### 2026-05-29 -- Drafted PR

`build.ps1` + `build.bat` + `tcbuild.bat` written at
`pwiz_tools/OspreySharp/`.  Self-contained (no ai/ dependency).
Local smoke verified.  Pushed to
`Skyline/work/20260529_ospreysharp_ci_scaffold` (commit
`083b8914`).  PR to follow.

### 2026-06-01 -- PR opened

PR [#4247](https://github.com/ProteoWizard/pwiz/pull/4247) is open
(found during a `/pw-uptodos-complete` scan; the TODO had no PR
reference yet).  Still **active** -- awaiting Matt's TeamCity build-
config wiring (working dir `pwiz_tools/OspreySharp/`, step
`tcbuild.bat`, file trigger `pwiz_tools/OspreySharp/**`).

### 2026-06-08 -- Merged

PR #4247 merged as commit `16fea56` (squash). Shipped the three
self-contained build-driver files at `pwiz_tools/OspreySharp/`
(`build.ps1`, `build.bat`, `tcbuild.bat`), no `ai/` dependency.
Merged over one unrelated failing check ("teamcity - BiblioSpec
subset source tarball" ERROR) -- the team's most frequent
intermittent failure, already raised with Matt Chambers; the other
22 checks were green.

**Deferred (not blockers, carried forward to Matt's wire-up step):**
the actual TeamCity build config and the `tcbuild.bat` end-to-end run
on a real agent (PR test-plan item left unchecked), plus the four
"Open questions for Matt" above (dotCover Global Tools install state,
GitHub status hook, smart-trigger glob, net8.0-only vs net8.0+net472
matrix).
