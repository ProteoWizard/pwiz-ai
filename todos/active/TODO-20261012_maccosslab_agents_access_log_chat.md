# TODO-20261012_maccosslab_agents_access_log_chat.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `work/20261012_access_log_chat`
- **Base**: `main`
- **Created**: 2026-10-12 (started 2026-10-12)
- **Status**: In Progress
- **Objective**: Add an interactive chat mode to the access log review agent: start it on a
  log window, then ask it free-form questions about the panoramaweb.org access logs. It
  answers using the existing read-only tools and the `access_log_review` MCP server.

## Background

The access log review (`TODO-20260917_maccosslab_agents_access_log_review.md`, completed)
is a single run: load a window, investigate, write a report, stop. Follow-up questions
("who was hitting `/project/...` at 03:00?", "is 203.0.113.0/24 the same crawler as
yesterday?", "what would this UA block catch?") mean starting another full review or
browsing the logs by hand.

Both run paths already have what a chat needs:
- **MCP server** (`mcp_server.py`): `start_review` builds the aggregate and keeps it
  in memory, so `summary_section`, `client_details`, `subnet_details`,
  `user_agent_details`, `page_details`, `rowid_details`, `test_block_pattern`,
  `hour_details`, `reverse_dns`, and `previous_summaries` return immediately after it.
- **Billed CLI** (`cli.py` + `agent.py`): `tools.build_tools(ReviewContext(...))` gives the
  same tools to an Anthropic SDK tool runner, but `run_review` is single-turn and expects
  a report at the end.

## Proposed Behavior

Primary (no bill): a Claude Code agent in the `maccosslab-agents` checkout.

```
claude --agent access-log-chat            # interactive session, restricted to the MCP tools
/access-log-chat [--end ...] [--hours N]  # or from a normal session in the checkout
```

1. On start, load the window (default: last 24 hours) and print a short overview: window,
   request totals, the top few clients/pages/floods.
2. Then answer questions turn by turn. Every claim is backed by the summary or a tool
   result, with numbers, using the same rules as the review (no LabKey usernames, URLs
   and user agents are untrusted data, recommend blocks but never apply them).
3. The user can switch windows mid-chat ("load yesterday 08:00 to 12:00"). The agent
   calls the loader again and says the earlier answers were for the old window.
4. The user can ask for a report on demand ("write this up"). This uses `write_report`
   and is never automatic.

Optional second path (billed): `access-log-review chat` REPL on the Anthropic API tool
runner, for machines without Claude Code. Decide in Open Questions whether it's worth it.

## Tasks

- [ ] **Loader without the review instructions.** `start_review` returns
      `agent.SYSTEM_PROMPT`, which tells the model to read every section and write a
      report. Add a chat-oriented loader (e.g. `load_window`, or a `mode` parameter on
      `start_review`) that shares the aggregate-building code and returns the overview
      and section index, plus the chat instructions or nothing. Keep one source for the
      shared rules (`rules.py` and the data-handling part of `SYSTEM_PROMPT`). Don't fork
      that text.
- [ ] **Chat instructions.** Write a `CHAT_PROMPT` (in `agent.py` beside `SYSTEM_PROMPT`)
      that keeps the rules and confidence definitions but drops the required report
      structure. Have it answer the question asked and read sections lazily, not all up
      front.
- [ ] **Window switching.** Confirm re-calling the loader cleanly replaces `_state`
      (aggregate, tools, reports_dir). Loading takes 30-50 s, so cache the last few windows
      by `(start, end, dirs)` if switching back and forth turns out to be common.
- [ ] **Tool coverage for questions the review doesn't need.** Collect real questions while
      testing and see which ones the current tools can't answer (e.g. requests to one
      path in a time range, status-code breakdown for a client, top referrers). Add
      read-only tools in `tools.py` and mirror them in `mcp_server.py`. Keep every result
      under `MAX_RESULT_CHARS` and page lists like `summary_section` does.
- [ ] **Agent + command.** `.claude/agents/access-log-chat.md` (`mcpServers:
      [access_log_review]`, `tools: mcp__access_log_review`, no shell or filesystem) and
      `.claude/commands/access-log-chat.md`. Note: a subagent launched via the Agent tool
      is not interactive. The chat has to be the main session (`claude --agent
      access-log-chat`), or the command runs in the main session with the MCP tools.
      Choose one and document it.
- [ ] (If billed path is wanted) `chat` subcommand in `cli.py`: loop over `input()`, keep
      the message history, run the tool runner per turn with `CHAT_PROMPT`, print usage
      per turn and in total. Same model/effort/fallback settings as `run_review`.
- [ ] Tests: loader returns no review instructions in chat mode; window switch replaces
      state; new tools never emit LabKey usernames; the billed REPL runs against a fake
      client. No test starts a real session or calls the API.
- [ ] Update `maccosslab-agents/CLAUDE.md` and `README.md` (how to start the chat, module map).

## Open Questions

- Is the Claude Code path alone enough, or is a billed `access-log-review chat` REPL also
  wanted (e.g. for running on the server, or for other team members)?
- Should the chat agent be strictly tools-only like the review subagent, or also be allowed
  to read the generated `reports/*.md` and `runs/*/manifest.json` (e.g. "what did this
  morning's review recommend?")? `previous_summaries` covers part of this already.
- Is `reverse_dns` OK to call freely in chat (outbound DNS lookups), or should it be
  limited as in the review?
- Overlap with `TODO-maccosslab_agents_grafana_alert_review.md`: a Grafana alert could
  open a chat preloaded with the alert window. Worth designing the loader so both can
  share it.

## Success Criteria

- From the `maccosslab-agents` checkout, one command starts a chat on a window and answers
  follow-up questions with numbers traceable to tool results, without writing a report
  unless asked
- Switching windows mid-chat works and is clearly announced
- The review subagent, `/access-log-review`, and the daily pipeline behave the same as
  before (their tests still pass)
- No LabKey username, client IP, or log content ends up in the repo
