# TODO-20260917_maccosslab_agents_access_log_review.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `work/20261006_scheduled_review` (Phase 4 pipeline, PR #2, pushed). Phases 0-3
  and the local no-bill run path are on `main` (`9e7dd8c`, PR #1 merged 2026-10-06)
- **Base**: `main`
- **Created**: 2026-09-16 (started 2026-09-17)
- **Status**: In Progress (Phase 4 remaining)
- **PR**: https://github.com/uw-maccosslab/maccosslab-agents/pull/2 (Phase 4, open). Earlier:
  https://github.com/uw-maccosslab/maccosslab-agents/pull/1 (merged 2026-10-06)
- **Objective**: Create a new `maccosslab-agents` repository and build an agent that reviews
  the last 24 hours of panoramaweb.org Apache and LabKey Server access logs and produces a
  report that helps Skyline staff fix slow pages and block bots

## Background

panoramaweb.org (LabKey Server behind Apache) receives a mix of real user traffic, crawlers,
and abusive bots. Today, finding slow pages or bad actors means someone manually digging
through access logs. A daily agent-generated report would surface the worst offenders so
staff can act on them directly: optimize a slow page, or add a block rule for a bot.

This is the first project in a new `maccosslab-agents` repository, which is intended to hold
operational agents for MacCoss Lab infrastructure (separate from pwiz and pwiz-ai).

## Decisions

| Topic | Decision |
|-------|----------|
| Repository | `uw-maccosslab/maccosslab-agents`, **private** (reports contain IPs and user details) |
| Servers in scope | **panoramaweb.org** only (others may follow later) |
| Where it runs | A separate machine, not the web server |
| Log acquisition | Out of scope. A separate process copies the logs over daily into a local, **gitignored** directory; the agent only reads from there |
| Blocking | **Recommend only.** The agent never applies blocks; the report includes rules for staff to apply |
| Report delivery | **Write to a local file** (gitignored `reports/` directory). Email/Slack delivery deferred |
| Client IP | Apache `%h`; Tomcat's rightmost X-Forwarded-For entry. No CDN in front of Apache since July 2026 |
| Apache config | Edited by hand; recommendations are Apache config snippets |
| Bot blocking policy | Broad by design: all "bot" user agents (except Dubbotbot), including search engines and link-preview bots, stay blocked |
| Apache timing | Apache logs have **no request duration**. Slow-page timing must come from the LabKey (Tomcat) access log; Apache is used mainly for bot analysis |

## Log Formats

**Reference: `ai/docs/websites/panoramaweb.org/access-logs.md`.** It covers the architecture,
both log formats, verified parsing regexes, edge cases, and profiles of the sample logs. Read
it before writing parsers; don't repeat the analysis.

Architecture: Apache and Tomcat (LabKey) run on the same Linux server. Apache is the public
reverse proxy and forwards to Tomcat over loopback.

### Apache (panoramaweb.org)

Sample: `examples/panoramaweb.org/access-logs/apache/access.log` (in the ai-dev project root,
not in a repo), 2026-09-16 00:00-08:31, 281K lines, 0 parse failures with the doc's regex.
Findings that shape the design:
- **Client IP is always Apache's `%h`** (Tomcat: the rightmost X-Forwarded-For entry). There
  is no CDN in front of Apache (Cloudflare was disabled in July 2026), and a scanner sent a fake
  `X-Forwarded-For: 127.0.0.1` on 3.5K requests. Record X-Forwarded-For as extra information
  only; never use it to pick a block target
- **Don't recommend blocking shared proxy addresses** (e.g. `163.116.x.x`, `147.161.x.x`
  corporate proxies carrying AutoQC traffic); that would block every user behind them
- **User-agent blocks** (`mod_rewrite`, see the doc): a named-agent list and a catch-all for any
  user agent containing `bot` (except Dubbotbot). Blocking Googlebot, Applebot, and
  link-preview bots this way is **intentional**; don't recommend exceptions. Baiduspider and
  MathPicDatasetCrawler get through
- **Bots rotate IPs**: 132K client IPs, 106K of them seen only once. Group by user agent,
  subnet, ASN, and URL pattern
- **Rate limiting**: 429s (12K responses across 9.5K IPs) come from a `mod_qos` rule (see the doc)
- **408 lines and garbage request lines** (TLS handshakes, bare `\n`) must parse without errors
- Exclude or label `check_http` monitoring; don't flag `autoQCPing.api` traffic

### LabKey Server (Tomcat access log)

Format, field table, parsing regex, and analysis notes are documented in
`ai/docs/websites/panoramaweb.org/access-logs.md`. Key points:
- `%D` gives request duration in **microseconds**, which is the source for all slow-page timing
- `%h` is always loopback. The client IP comes from `%{X-Forwarded-For}i`, whose **rightmost**
  entry is the peer Apache saw; entries to its left can be forged
- `%{LABKEY.username}s` gives the authenticated user (`-` if anonymous); `%S` the session ID
- Exclude `/_webdav/` from duration stats; treat `experiment-showFile.view` as a file download

Verified against `examples/panoramaweb.org/access-logs/tomcat/access_log.2026-09-14.log`
(752K lines, 428 MB) on 2026-09-16:
- [x] The original regex in the doc failed on ~9.6K lines (1.3%): X-Forwarded-For lists
      (`client, proxy`, 9,376 lines) and `\"` escaped quotes (213 lines). The doc now has a
      corrected regex that parses every line
- [x] `%q` is `-` when there is no query string; `%S` is `-` with no session
- [x] File naming is `access_log.YYYY-MM-DD.log` (one file per day, Tomcat rotation). Apache
      uses logrotate, so the two need different file-selection logic
- [x] Exclude `/_websocket/` (101) and treat `targetedms-downloadDocument.view` as a download,
      alongside WebDAV and `experiment-showFile.view`
- [x] Durations top out near 3,600 s, which looks like a 1-hour timeout
- [x] Parse the timezone from each line (the sample is all `-0700`; winter is `-0800`); done in `timestamps.py`
- [ ] `%D` also counts time spent sending the response; report response size alongside duration
- [ ] Apache-only responses (429, 408) never reach Tomcat; the count difference is useful
- [x] Same-day samples (Tomcat 09-15 and 09-16 added) tested on 2026-09-17; see the doc's
      "Correlating the two logs". The regex parses all three Tomcat days. Findings:
  - **Tomcat `%t` is the finish time**; Apache `%t` is the start time. Request start in
    Tomcat = `%t` − `%D`
  - Tomcat's X-Forwarded-For = Apache's X-Forwarded-For (if any) + `, ` + Apache `%h`, on
    all matched requests
  - Tomcat logs the rewritten URL (partly percent-decoded, sometimes with doubled slashes);
    after normalizing, 99.96% of Tomcat requests match an Apache line
  - The 17.7K Apache-only lines are 429, 403, 408, 400, and Apache's own redirects
- Size: a full day is 200-430 MB of Tomcat log and ~240 MB of Apache log, so the parser must
  stream line by line

## Scope

### Phase 0: Repository setup
- [x] Created private repository `uw-maccosslab/maccosslab-agents` on 2026-09-17 and cloned it
      to `~/dev/ai-dev/maccosslab-agents`. README, .gitignore, and CLAUDE.md written. No
      license (private repository)
- [x] Stack: Python 3.11+ with the `anthropic` SDK (`>=1.6,<2`) **Tool Runner**, not the Claude
      Agent SDK. The agent only needs our own tools over aggregated data, with no shell or file
      access. Model `claude-opus-5`. pytest for tests
- [x] Virtual environment at the repository root (`.venv/`, gitignored), created with
      `python3 -m venv` (uv isn't installed). Install with `pip install -e ".[dev]"`
- [x] Layout: a `src/` package (`src/maccosslab_agents/<agent>/`) instead of top-level
      `agents/` and `lib/`, so the code installs as a normal Python package. Shared code will
      go in `src/maccosslab_agents/common/` when a second agent needs it. `tests/` at the root
- [x] `.gitignore` covers `.venv/`, `logs/` (input), `reports/` (output), `.env`, and `config.toml`
- [x] Secrets: API key from `ANTHROPIC_API_KEY` or an `ant auth login` profile; nothing in the repo
- [x] CLI entry point `access-log-review --logs-dir --reports-dir` (a placeholder until later
      phases). 2 pytest tests pass

### Phase 1: Log input
Development window: **2026-09-16 07:00 to 2026-09-17 07:00 PDT** (a run at 07:00 on 9/17),
using the samples in `~/dev/ai-dev/examples/panoramaweb.org/access-logs/` (`apache/`, `tomcat/`).

- [x] Input directory `--logs-dir` (default `logs/panoramaweb.org`, relative to the repository
      root) with `apache/` and `tomcat/` subdirectories, where the copy process writes the logs
- [x] File naming (`sources.py`):
  - Apache: current `access.log`, rotated `access.log.YYYY-MM-DD` (no `.log` suffix; the date
    is the **rotation** date, so the file holds the previous day). Other names, including
    `.gz`, are ignored
  - Tomcat: `access_log.YYYY-MM-DD.log`, same name while being written; the date is the day
    requests **finished**. Reads the next day's file too when the window ends within an hour
    of midnight
- [x] Select by request **start** time: Apache `%t`; Tomcat `%t` − `%D`. `--end` (ISO 8601 with
      offset, default now) and `--hours` (default 24) define the half-open window
- [x] A cut-off last line (no newline) is counted separately, not as an unparsed line
- [x] Errors when a source has no log files; warns when the logs start more than 15 minutes
      after the window start or end more than 15 minutes before its end
- [x] Parsers (`records.py`) with typed records; client IP rules as in the doc; fast cached
      timestamp parsing (`timestamps.py`)
- [x] 25 pytest tests with anonymized lines (documentation IP ranges, fake users)
- [x] Real samples, dev window: Apache 640,672 requests in window (908,937 lines), Tomcat
      616,659 (868,043 lines), 0 unparsed, no coverage warnings. 20.6 s, 17 MB peak memory
- [ ] Keep only what the report needs from IPs and user details; nothing beyond `reports/`
      (applies once reports are written, Phase 3)

### Phase 2: Parsing and aggregation (plain code)
Do the heavy lifting in ordinary code, not in the LLM; the logs are too large to feed in raw.
Modules: `urls.py` (page classification), `rules.py` (the server's Apache rules), `aggregate.py`
(single pass), `summary.py` (JSON for the agent). The CLI writes
`reports/access-log-summary-<end>.json`.

- [x] Apache and Tomcat parsers (done in Phase 1, `records.py`)
- [x] Page classification: current (`/<folder>/<controller>-<action>.view`) and older
      (`/<controller>/<folder>/<action>.view`) LabKey URLs, `.api`/`.post`, `/__r<N>/` row IDs,
      `/labkey/` prefix, WebDAV, WebSocket, static files. `experiment-showFile` and
      `targetedms-downloadDocument` count as downloads, kept out of slow-page statistics
- [x] **Decision: no request-by-request Apache-Tomcat matching.** Both logs carry the same
      client IP, so server time per client/user agent comes from Tomcat and Apache-only
      responses (429/403/408) from Apache. The doc's matching rule stays available if a later
      feature needs it
- [x] Slow pages (Tomcat) per controller-action: requests, total/p50/p95/max seconds, requests
      over 10 s, 5xx/4xx, signed-in requests, MB sent, top folders/clients/user agents by
      seconds, busiest hour, slowest examples. Also the 50 slowest page views overall, and
      hourly Apache/Tomcat volume and server time
- [x] Clients (Apache traffic + Tomcat server time): requests, statuses, first/last, peak per
      minute, distinct targets (capped at 2000), user agents, X-Forwarded-For (information only),
      Panorama Public and bypass requests, server seconds, number of signed-in users (never the
      names), distinct sessions
- [x] Subnets (/24 and /16; /48 and /32 for IPv6), built from the client statistics after
      reading; user agents (distinct IPs, statuses, server seconds, which block rule applies,
      declared crawler); declared crawlers with their 403 share and matching block rules;
      internal monitoring (`check_http`) counted separately
- [x] Rate limiting: floods (minutes with at least 10 429s, gaps of 2 minutes or less merged)
      with their top IPs and user agents; signed-in clients that were rate-limited; bypasses
      (other spellings of Panorama Public, `/__r<N>/` requests grouped by row ID, projects with no
      limit)
- [x] **Prolonged flood analysis** (`ratelimit.py`), requested 2026-09-17: floods longer than
      5 minutes are re-read in a second pass (the flood plus a 5-minute lead-in; Tomcat from 65
      minutes earlier for long requests). For each flood:
  - Volume (Apache, matching requests): rate vs the median normal minute and the lead-in,
    rate-limited share, distinct IPs, one-request and new-client shares, top IPs, subnets,
    user agents, pages, folders
  - Slot time (Tomcat, served matching requests clipped to the flood): average and busiest-
    minute concurrency, minutes near the limit (at least 90% of 25), top client and its share
    and concurrency, slow requests (at least 10 s) and their share, top pages, folders,
    clients, user agents by slot time
  - A per-minute timeline (matching requests, 429s, average concurrency)
  - Concurrency is reported only as minute averages: Tomcat's 1-second `%t` makes
    instantaneous peaks unreliable
- [x] Verified on the 09-16 04:48-05:22 flood (`--end 2026-09-17T00:00-07:00`): **one
      `curl/8.5.0` client downloading raw files over WebDAV held 98% of slot time (~22.7 of 25
      slots)**. Volume was only 1.65x normal. Details in the doc. Run time 54 s with the second pass
- [x] Memory: per-client collections are created only when needed, targets and sessions stored
      as hashes, and user-agent strings shared. Dev window peak 930 MB -> 451 MB; run time 33 s
- [x] 50 pytest tests (urls, rules, aggregation, summary floods, flood cause analysis, and a
      check that usernames never reach the summary)
- [ ] Deferred to Phase 3 tools or later: ASN lookup (needs an offline database), reverse-DNS
      verification of crawlers (network calls), robots.txt compliance (needs the site's
      robots.txt), sequential-ID crawl detection
- [ ] Recommendations for `mod_qos` (currently only the one global Panorama Public limit
      plus `QS_ErrorResponseCode 429`; no per-client limits), e.g. per-client limits
      (`QS_ClientEventLimitCount` or similar), a regex fix (`[Pp]`, and covering the other
      spellings). Phase 3 (agent), using the summary's `rate_limiting` section
- [ ] User-agent block review: new crawlers that get past the `mod_rewrite` rules (no "bot"
      in the name, e.g. Baiduspider), and which agents the catch-all blocks. Recommend changes
      in the same `RewriteCond`/`RewriteRule` form. Phase 3 (agent), using `crawlers`

Dev window results (2026-09-16 07:00 to 2026-09-17 07:00):
- `targetedms-showpeptidelist`: 4,957 requests, 102K server seconds (54% of all page time),
  2,722 over 10 s; one Panorama Public folder alone 20.7K s. Next: `targetedms-showinstrument`
  (30.8K s, p50 16 s), `targetedms-showprecursorlist` (15.8K s)
- Downloads: `experiment-showfile` 55.7K s, `targetedms-downloaddocument` 31.8K s
- 271K client IPs, 220K with a single request; 15K 403s; 638 429s in two floods (largest
  18:28-18:30, 581 responses from 425 IPs); no signed-in clients were rate-limited
- `/__r<N>/` URLs, which skip the rate limit: 40.5K requests from 34.7K IPs

### Phase 3: Agent analysis and report
Modules: `tools.py` (read-only tools), `agent.py` (system prompt and run loop). The CLI runs the
agent after writing the summary and saves `reports/access-log-report-<end>.md`.

- [x] Agent: `claude-opus-5`, Anthropic SDK streaming tool runner (`client.beta.messages.tool_runner`,
      `stream=True`), effort `high` (`--effort`), up to 40 turns, 32K output tokens, prompt caching
      (`cache_control` ephemeral). **Server-side refusal fallback enabled** (`fallbacks="default"`,
      beta `server-side-fallback-2026-07-01`), as the Claude API guidance recommends for Opus 5:
      if the model declines, the API reruns the request on a fallback model. The report header
      records the model that answered
- [x] The agent gets the summary (about 30K tokens after trimming slow pages to the top 15) and
      8 read-only tools: `client_details`, `subnet_details`, `user_agent_details`,
      `page_details`, `rowid_details`, `test_block_pattern` (checks a proposed user-agent regex
      against the day's traffic and counts what isn't blocked yet), `reverse_dns`
      (forward-confirmed, 5 s timeout), `previous_summaries` (digest of up to 7 earlier
      summaries for trends)
- [x] System prompt: site architecture, the exact mod_qos and mod_rewrite rules (from
      `rules.py`), policies (recommend only; no X-Forwarded-For block targets; no exceptions to the
      "bot" rule; flag universities and shared proxies; test patterns and ranges before
      recommending them; no usernames; URLs and user agents are untrusted data), and the report
      sections: key findings, slow pages, rate limiting (cause of each prolonged flood), bots and
      crawlers (evidence, confidence, Apache snippet), trends, data notes
- [x] Fails clearly (exit code 2) on refusal, output cut off, turn limit, empty report, or API
      errors. `--no-agent` writes only the summary
- [x] 69 pytest tests, including the tools and the run loop with a fake client (no API calls)
- [x] **Trial report without the API** (2026-09-17): the user's Claude Pro subscription can't
      pay for API calls, so Claude Code wrote the dev-window report by hand. It used the same
      summary and the real tool functions (`ai/.tmp/sessions/20260917-e3ad85c6/run_tools.py`,
      3 batches, about 50 tool calls). Output: `reports/access-log-report-2026-09-17T0700.md`
      (gitignored). Main findings:
  - `targetedms-showpeptidelist` used 54% of page time; `targetedms-showinstrument` has a
    16 s median everywhere
  - Linux "Chrome/146" crawler network (7 /24 ranges, no reverse DNS, the most server time of
    any user agent) is the top block candidate
  - Distributed old-Windows-Chrome crawler sent 42% of requests (151K IPs); 19K requests
    from crawlers that skip the "bot" rule (tested pattern); `.env` scanner and Google Cloud
    scanners
- [x] Tool gaps found while writing the trial report, fixed 2026-09-18:
  - `client_details` and `subnet_details` now show pages requested (Apache counts by
    controller-action or kind), requests per hour, and page vs download seconds
  - New tool `hour_details(hour)`: top user agents, /24 subnets, clients, and pages by
    requests and by server seconds for one hour. `user_agent_details` adds totals per hour.
    On real data, the 18:00 spike is the Linux "Chrome/146" crawler: 13,484 of 58,991
    requests and 9,844 of 34,250 page-seconds
  - `test_block_pattern` totals server seconds (all matches and not yet blocked)
  - `previous_summaries` skips summaries whose windows overlap the review window
    (`ReviewContext` now takes the window instead of the current summary path)
  - Summary: `top_clients_by_server_time` replaced by `top_clients_by_page_time` and
    `top_clients_by_download_time` (15 each); client entries show top pages
  - Per-client collections stay lazy (created only for a second page or hour). Dev window:
    33 s, peak RSS 547 MB (was 451 MB). 72 tests pass
- [x] Phase 3 committed locally 2026-09-18 (`f25af73`), not pushed
- [x] WebDAV tool gap, fixed 2026-09-18 (found in the report for the window ending
      2026-09-17T00:00): WebDAV time wasn't counted per client, so `client_details` showed 0 s
      for the curl client that held 46,258 slot-seconds in the 04:48 flood. Now tracked
      separately from server seconds (which stay page views + downloads): per client
      (`webdav_requests`, `webdav_seconds`), per user agent, per hour by client. Shown in
      `client_details`, `subnet_details`, `user_agent_details`, `hour_details`
      (`clients_by_webdav_seconds`) and the summary (`tomcat_webdav_seconds`,
      `top_clients_by_webdav_time`). 75 tests pass. Real data (window ending 09-17 00:00):
      543,873 WebDAV seconds, more than pages + downloads (287,969 s). Top WebDAV clients:
      `panorama-inventory/2.0` (160.62.2.16, 297,114 s, outside Panorama Public) and the curl
      client (180,863 s). 54 s run, 606 MB peak RSS. Committed `336448b`
- [x] Report output (2026-09-18, `4aa8739`): the CLI writes both `access-log-report-<end>.md`
      (the agent's Markdown, with a metadata comment) and `.html` (a self-contained page with
      light/dark styles). `render.py` uses markdown-it-py (new dependency) with raw HTML
      disabled, so user agents and URLs from the logs are escaped and `javascript:` links are
      dropped. The prompt tells the agent not to use raw HTML. Metadata (window, model, token
      usage) is at the bottom of both formats. 78 tests pass
- [x] Medium-effort comparison (2026-09-18): cold-start subagents (Opus 5, `effort: medium`,
      `SYSTEM_PROMPT` as system prompt, the 9 tools through a runner script) wrote
      `reports/access-log-report-2026-09-17T{0700,0000}-medium.{md,html}` (85 and 107 tool
      calls, about 10 min each). They found things the hand-written reports missed (the full 12
      Chrome/146 /24s, a Chrome/48 crawler, Lightpanda, the correct passport protein IDs
      19802130/19802162, which were then fixed in the hand-written report). But the two runs
      disagreed on the biggest block decisions, and one leaned on outside knowledge and
      misattributed 18:28 slot use to non-Panorama-Public requests
- [x] Prompt changes from that comparison (`dd4336e`): confidence definitions for block
      recommendations (high needs a non-browser string or a range with `signed_in_clients` 0;
      ordinary browser strings are at most medium; outside knowledge never raises confidence),
      a check-before-writing step, and "only requests matching the pattern hold the slots".
      `subnet_details` now returns `signed_in_clients`. 79 tests pass. Not yet validated by a
      rerun (the trial agent definition and its working files were deleted at the user's request)
- [x] Trial reports written 2026-09-18 by hand from SYSTEM_PROMPT, all in `reports/`
      (gitignored): `access-log-report-2026-09-17T0700-2.md` (dev window) and
      `access-log-report-2026-09-17T0000.{md,html}` (covers the 34-minute flood and WebDAV)
- [x] Docs (`ebd13ec`): README module map and `--hours`; CLAUDE.md notes on the prompt location,
      server vs WebDAV seconds, usernames, and HTML escaping. maccosslab-agents pushed
- [ ] Unknown WebDAV client `160.62.2.16` (`panorama-inventory/2.0`, 297,114 WebDAV seconds on
      09-16): staff should identify the owner (whois) before any action
- [ ] The mod_qos snippets in the trial reports (separate WebDAV pool, per-IP limit, row-ID
      pool) are untested proposals; staff must try them on staging
- [x] **Local no-bill run path** (MCP server + Claude Code subagent, `/access-log-review`):
      first end-to-end run succeeded 2026-10-06; merged in PR #1 (`9e7dd8c`)
- [ ] **First live API run** on the dev window: needs `ANTHROPIC_API_KEY` (or `ant auth
      login`) and approval, since it is billed. Compare with the trial report, then review with
      staff and tune the prompt
- [ ] Trend comparison improves once daily summaries accumulate in `reports/`

### Phase 4: Scheduling
Branch `work/20261006_scheduled_review`. Design agreed 2026-10-06, modeled on the PR report
pipeline (`ai/docs/pr-report-guide.md`, `ai/scripts/Invoke-PRReport.ps1`), for Linux/WSL2.
Only this TODO changes in pwiz-ai; everything else lives in maccosslab-agents.

| Topic | Decision |
|---|---|
| Pipeline | Python entry point `access-log-review-pipeline`, 3 phases each runnable alone (`--phase validate\|review\|email\|all`, `--end` for backfill, `--dry-run`); manifest + logs in gitignored `runs/<date>/`, kept 30 days |
| validate | Plain Python, head/tail of each file, no Claude. Fails on missing source, unreadable file, late start, early end, or a hole between files |
| review | `claude -p --agent access-log-review`, strict MCP config (access_log_review only), the 11 tools listed explicitly, `--permission-prompts none`, `--output-format json`; skipped if validate fails |
| email | **Plain Python** `smtplib`: full report inline as HTML with inline styles + Markdown plain text; `[ERROR]` email when validate or review failed. Recipients, sender, SMTP host in `config.toml`; password and `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`) in `~/.config/maccosslab-agents/env` |
| Incomplete logs | Error email immediately, no retry; rerun by hand with `--end` |
| Scheduler | Both: systemd user timer (`Persistent=true`, linger) on native Linux; Windows Task Scheduler running `wsl.exe` on WSL2, because the WSL VM shuts down when idle |

- [x] Step 1: `validate.py` + 6 tests (`ee403ee`). Real data: 0.02-0.05 s per window
- [x] Step 2: `pipeline.py` (`b517266`): `config.toml` + arguments, `runs/<date>/`
      manifest and log, ff-only `main` update, validate, headless review (reuses `.mcp.json`
      with `--strict-mcp-config`; tool list read from the MCP server), `--dry-run`, 30-day
      cleanup. 105 tests pass. Real run (user, 2026-10-07, window ending 2026-10-05 08:00):
      passed, 43 turns, 307 s; CLI cost estimate $1.80
- [x] Step 3: `mailer.py` (`82ff9da`; named so it can't shadow the stdlib `email` package):
      inline-style HTML from the shared markdown-it parser, metadata comment as footer,
      `[ERROR]` email (gaps / review reason, log path, rerun command), SMTP with STARTTLS and
      retries on transient errors only. `--phase email` reuses the saved manifest.
      120 tests pass. Real 10-05 report as email: 51.7 KB HTML (Gmail clips at ~102 KB)
- [ ] Step 3 test send: needs `[email]` in `config.toml` and `SMTP_PASSWORD` in the env file
- [x] Step 4: `schedule.py` (`c977880`). Changed from the plan at the user's request:
      `--schedule [HH:MM]` only **writes** the files to gitignored `schedule/` and prints the
      install/check/run/remove commands; it installs nothing. Linux: systemd user
      `.service` + `.timer` (`Persistent=true`, 2 h limit, linger). WSL2: Task Scheduler XML
      (UTF-16; StartWhenAvailable, 2 h, InteractiveToken) running `wsl.exe -d <distro> -u
      <user> --cd <root> -- .venv/bin/access-log-review-pipeline`; installed with
      `schtasks.exe /Create /XML`. Run time from `[schedule] run_at` (default 07:30).
      126 tests pass
- [ ] Step 4 install and trigger: done by the user (instructions given 2026-10-07)
- [x] Step 5: README (daily pipeline section, setup, scheduling, module map) and CLAUDE.md
      (pipeline rules, gitignored `runs/`/`schedule/`, `mailer.py` naming, `--schedule`
      installs nothing); also corrected the CLI's default effort to `medium` (`e932239`)
- [x] Pushed `work/20261006_scheduled_review` and opened PR #2
      (https://github.com/uw-maccosslab/maccosslab-agents/pull/2), 2026-10-07
- [ ] User setup: SMTP account and sender, `claude setup-token` on the run machine, the log
      copy job's schedule (defaults until known: window end 07:00, run 07:30)

## Open Questions
- None at present

## Progress Log

### 2026-09-17
- Created the repository and finished Phases 0-2 (4 local commits on `main` in
  maccosslab-agents, not pushed).
- Built Phase 3 (agent, tools, tests; 69 tests pass). **Uncommitted** in maccosslab-agents:
  `agent.py`, `tools.py`, `tests/test_agent.py`, `tests/test_tools.py`, plus changes to
  `cli.py`, `summary.py`, `aggregate.py`, `tests/test_cli.py`, `README.md`.
- No API credentials on this machine. The user's Claude Pro subscription doesn't cover API
  use, so the trial report was written in Claude Code instead.
- The user asked for local commits only; nothing has been pushed in either repo (pwiz-ai
  master is 5+ commits ahead of origin).

### 2026-09-18
- Fixed the five tool gaps (9 tools now), verified on the dev window, and committed Phase 3
  locally (`f25af73` in maccosslab-agents).
- Added WebDAV time per client, the HTML report, and the confidence rules and verification
  step in the prompt (after a medium-effort comparison run). Updated README (module map,
  `--hours`) and CLAUDE.md (prompt location, server vs WebDAV seconds, usernames, HTML
  escaping).
- **Pushed maccosslab-agents `main` to GitHub** (`ebd13ec`, first push; the repository was
  empty) and pwiz-ai `master` (rebased onto origin, `8c0ad689`). Both repos are clean and in
  sync.
- 79 tests pass. Reports now come out as Markdown and HTML.
- Next:
  1. The first live API run on the dev window (needs `ANTHROPIC_API_KEY` or `ant auth login`,
     and approval, since it is billed). Compare it with the trial reports, especially whether
     the new confidence rules keep block decisions consistent.
  2. Phase 4: daily cron run on the separate machine, plus failure logging.
- Blocker: no API credentials on this machine (the user's Claude Pro plan doesn't cover the
  API).

### 2026-09-25 (built but not logged at the time)
- Added a second, **no-API-bill** way to run the review: an MCP server (`mcp_server.py`, new
  `access-log-review-mcp` entry point) driven by an `access-log-review` Claude Code subagent
  on the session's model, so no Anthropic API bill. `mcp_server.py` is a thin adapter over
  the same `sources`/`aggregate`/`tools`/`render` pipeline; its `start_review` returns
  `agent.SYSTEM_PROMPT` verbatim, so the prompt has one source. Added `tests/test_mcp_server.py`
  (wiring only). New dependency `mcp>=1.2`. This solves the "no credentials" blocker for
  running the review locally.
- Also changed the billed CLI's `EFFORT` from `high` to `medium` in `agent.py`.
- This work was left **uncommitted** and its wiring was placed in the wrong repos: the
  `.mcp.json` sat at the non-git ai-dev root (with hardcoded absolute paths), and the subagent
  and slash command were untracked in the pwiz-ai repo under `ai/claude/`.

### 2026-10-01
- **Relocated all the subagent/MCP wiring into the `maccosslab-agents` repo** so it owns the
  feature end to end (the previous session had scattered it). `maccosslab-agents` is now a
  **self-contained Claude Code project**: in-repo `.mcp.json` (relative command
  `.venv/bin/access-log-review-mcp`, no hardcoded paths — the server's base dir defaults to
  the checkout root), `.claude/agents/access-log-review.md`, `.claude/commands/access-log-review.md`,
  and `.claude/settings.json` (auto-approves the MCP tools). You now **launch Claude Code from
  the maccosslab-agents checkout** to run `/access-log-review`.
- Removed the out-of-place files: the ai-dev-root `.mcp.json` and the two untracked
  `access-log-review.md` files under `ai/claude/` (pwiz-ai left clean).
- Updated `maccosslab-agents` README/CLAUDE.md to document the self-contained layout; added
  `.claude/settings.local.json` to its `.gitignore`.
- Diagnosed why the local run failed earlier: the `access_log_review` MCP server was never
  connected in the ai-dev-root session (project `.mcp.json` server sat unapproved,
  `enabledMcpjsonServers=[]`), so the subagent spawned with zero tools. The server itself is
  healthy (clean stdio `initialize`). Fixed by the relocation + launching from the checkout.
- 84 tests pass. Committed the relocation + the 09-25 work on branch
  `work/20261001_access_log_review_local_run` (`8daba2d`, off `main`); **not pushed**, no PR yet.
- Next: from the maccosslab-agents checkout, approve the MCP server and run
  `/access-log-review --end 2026-09-17T07:00-07:00 --hours 24`; compare with the trial reports.
  This end-to-end run must happen in a session launched from the checkout (not the ai-dev root).

### 2026-10-05
- **Fixed the MCP output-cap blocker** (the user chose accessor tools over trimming or raising
  `MAX_MCP_OUTPUT_TOKENS`). `start_review` now returns compact JSON text (a dict result was
  serialized by the MCP library with `indent=2`) with `instructions` (SYSTEM_PROMPT, verbatim),
  `summary_layout`, and a **headline summary** (`headline_summary`): list entries keep their
  scalars, statuses, and short scalar lists; `top_clients_*` keep only ranking metrics;
  `slowest_requests` and `prolonged_flood_analyses` are omitted; `rate_limiting` keeps its
  counts, floods, and `prolonged_flood_count`.
- New tool **`summary_section(section, index=0)`** serves any full section from the summary
  held in memory; prolonged floods come back one per call, so many-flood days don't grow any
  single result. The subagent instructions now say to read `rate_limiting`, every prolonged
  flood, `crawlers`, `top_user_agents`, `slow_pages`, and `slowest_requests` in full.
- Measured (chars/3): dev window `start_review` ~47.7K -> **~15.3K tokens**; flood window
  ~15.5K; the largest section (`slow_pages`) ~9K; one flood ~4.3K. All
  under the 25K cap. Script: `ai/.tmp/sessions/20261005-access-log/measure_sections.py`.
- **Live run failed**: the user ran `/access-log-review` (24 h ending 2026-10-05 08:00) and
  Claude Code rejected `start_review`'s 50,358-character result as over the cap. So the
  chars/3 calibration was wrong: this JSON counts at **2 or fewer chars/token**. The
  instructions were in that result, so the subagent stopped after 2 calls.
- **Redesigned without relying on any ratio**: `start_review` returns only `instructions`,
  `summary_layout`, `overview` (window, inputs, totals), and a `sections` index (~9.3K
  chars). `summary_section(section, start=0)` serves every other section, paging lists so
  each result is at most `MAX_RESULT_CHARS` = 20,000 (follow `next_start`). Headline
  summaries were dropped. The subagent reads every section (16 calls on both test windows;
  largest result 18.4K chars, `slow_pages` in 2 pages).
- 86 tests pass (including a paging test that each page fits the limit). README and
  CLAUDE.md updated.

### 2026-10-06
- **Live end-to-end run succeeded** (run by the user in a fresh session launched from the
  checkout). Committed `b5fcca7`, pushed the branch, and opened PR #1
  (https://github.com/uw-maccosslab/maccosslab-agents/pull/1).
- **PR #1 merged** into `main` as `9e7dd8c` (2026-10-06). It contains the MCP server and
  subagent run path (`8daba2d`) and the output-limit fix (`b5fcca7`). The local no-bill run
  is now the working way to produce reports: launch Claude Code from the maccosslab-agents
  checkout and run `/access-log-review [--end <ISO8601+offset>] [--hours N]`.
- Cleanup done: the checkout is on `main` at `9e7dd8c`, and the merged
  `work/20261001_access_log_review_local_run` branch is deleted locally and on GitHub.
- Next:
  1. Compare the live report with the trial reports in `reports/`, review with staff, and
     tune the prompt (still open in Phase 3).
  2. Phase 4: daily cron run on the separate machine after the log copy, plus failure
     logging. Decide whether the scheduled run uses the billed CLI or a headless Claude Code
     run of the subagent.

- Started Phase 4 on `work/20261006_scheduled_review`: agreed the pipeline design (see the
  Phase 4 section) and finished step 1, the validate phase (`ee403ee`, 92 tests pass).
- **Data finding from the validator**: `examples/.../apache/access.log` (linked from the
  checkout's `logs/`) now holds 2026-10-05 traffic, so the dev window (ending 2026-09-17
  07:00) has **no Apache requests from 09-17 00:00 to 07:00**. Dev-window runs since that
  file was replaced used incomplete Apache data. The full-read check in `sources.py` misses
  holes like this because it compares only the overall earliest and latest times. The
  window ending 2026-10-05 08:00 is complete in both sources. **That window is the reference
  window from now on** (user decision); the 09-17 Apache sample isn't restored.

### 2026-10-07
- Step 2 done and committed (`b517266`). The user ran the tests, `pip install -e .`, a dry
  run, and a real `--phase review --end 2026-10-05T08:00-07:00`: validate ok for both sources,
  review passed in 43 turns (307 s), report written. 105 tests pass.
- Step 3 built and committed (`82ff9da`), tested against a fake SMTP server; 120 tests pass.
  The real test send waits on the SMTP account, sender, and a test recipient.
- The test send is on hold (the user can't set up the email account yet).
- Step 4 built and committed (`c977880`); the user installs and triggers it themselves.
- Step 5 done (`e932239`). The branch has 5 local commits (`ee403ee`..`e932239`), not pushed.
- Pushed the branch and opened PR #2. Open: review and merge PR #2; the user's email test
  send and schedule install/trigger.

The handoff files (`ai/.tmp/handoff-20261002_…` and `handoff-20260918_…`) are obsolete; the
blocker they describe is fixed and merged.

## Success Criteria
- Private `uw-maccosslab/maccosslab-agents` repository exists with a documented structure
- A daily run produces a local report covering the previous 24 hours of panoramaweb.org
  Apache and Tomcat logs
- Report identifies the slowest pages with enough detail for a developer to start on a fix
- Report identifies likely bots, including distributed ones, with evidence and
  block recommendations staff can act on
- Parsing/aggregation is covered by tests using anonymized log fixtures
