# JsonToolServer cannot tell an AI Connector (MCP) caller from an external tool

## Branch Information
- **Branch**: `Skyline/work/20261118_json_tool_caller_kind`
- **Base**: `master`
- **Created**: 2026-11-18
- **Status**: In Progress
- **GitHub Issue**: [#5053](https://github.com/ProteoWizard/pwiz/issues/5053)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `I:\git_i\sky_mcpconnections`

## Objective

`JsonToolServer` serves two callers through one pipe and one set of verbs and cannot tell them
apart:

- **The AI Connector (Skyline MCP)** - an LLM behind every call. Wants short, bounded calls that
  return "issued, still finishing, poll" rather than block, and errors as `LlmInstruction`s that
  name the next tool to call.
- **External tools** (`$(SkylineConnection)`) - programs with no AI behind them at run time. Expect
  a call to be done when it returns; text they get back may be shown to a user at Skyline.

Verbs need to know which kind of caller they serve and behave accordingly. Design reference:
`ai/docs/skyline-mcp-design-guide.md`, section 0 "Two kinds of callers".

## Prerequisite (from Nick's issue comment)

The issue assumes a long-lived connection that can carry per-connection attributes. Today:
- `JsonToolServer` accepts **one connection at a time** (`maxNumberOfServerInstances = 1` passed to
  `NamedPipeServerStream`).
- So the MCP opens a new connection per method call and drops it after 30 s whether or not the
  call completed; `JsonToolServer` does extra work to notice a dropped connection.
- PR #4546 fixes methods that do not notice a dropped connection.

Changing to `-1` (unlimited, as the legacy `IToolService` does) is likely the first step, and may
simplify drop detection since the server can accept a new connection while one job runs.

## Tasks

- [ ] Change `JsonToolServer` to accept multiple concurrent connections (`maxNumberOfServerInstances = -1`); check interaction with #4546
- [ ] Per-connection caller kind (`SetClientInfo` or equivalent); MCP server declares itself; default = tool
- [ ] Waits: bounded + "still finishing" for MCP; complete-or-fail for tools
- [ ] Error and result text: `LlmInstruction` for MCP, localized user-facing text for tools
- [ ] Audit verbs an external tool is likely to call (selection, replicate, show graphs, settings, document ops)
- [ ] Tests for both caller kinds on a representative verb (`ShowFullScan` is a good first one)
- [ ] External Tools documentation for the contract

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional (likely)
- **Fails on master**: n/a - enhancement
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-18 - Session Start

Starting work on this issue. Branch created from origin/master in `sky_mcpconnections`.
