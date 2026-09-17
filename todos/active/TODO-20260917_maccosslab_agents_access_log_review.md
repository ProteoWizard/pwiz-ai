# TODO-20260917_maccosslab_agents_access_log_review.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `main` (initial scaffold)
- **Base**: `main` (new repository)
- **Created**: 2026-09-16 (started 2026-09-17)
- **Status**: In Progress
- **PR**: (none yet)
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

- [x] Input directory `--logs-dir` with `apache/` and `tomcat/` subdirectories (the layout of
      the samples). Assumes the copy process uses the same layout
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
Do the heavy lifting in ordinary code, not in the LLM; the logs are too large to feed in raw
(~90 MB for 8.5 hours).
- [x] Apache and Tomcat parsers (done in Phase 1, `records.py`)
- [ ] Common record: time, client IP, method, URL, normalized controller-action, container,
      status, bytes, duration (Tomcat only), user agent, referrer, LabKey user where available
- [ ] Correlate Apache and Tomcat records using the doc's matching rule (normalized request +
      client IP + start time; nearest unused match), so each Apache request gets a duration and
      a LabKey user where available
- [ ] Slow-page aggregates (from Tomcat timings): per controller-action (and container):
      count, p50/p95/max duration, total time consumed, error rate
- [ ] Bot aggregates: per IP, /24 and /16 subnet, ASN, and user agent: request count, rate,
      burstiness, 404/403/429/408 ratios, crawl patterns (sequential IDs, deep query strings,
      the same URL across many IPs), robots.txt compliance, verified crawlers
      (reverse-DNS-checked Googlebot/Bingbot) vs. spoofed user agents
- [ ] Rate-limit summary. The 429s come from one `mod_qos` rule: a **global** limit of 25
      concurrent `Panorama%20Public` requests (details in the doc). Report:
  - flood windows (minutes with 429s) and the clients and user agents driving them
  - likely real users caught by the global limit during a flood
  - traffic that bypasses the rule: `/__r<N>/` URLs, `%2520` and `+` spellings, and
    folders other than Panorama Public. There is no API to map `/__r<N>/` to a folder, so
    report that traffic grouped by `<N>` (requests, clients, user agents)
- [ ] Recommendations for `mod_qos` (currently only the one global Panorama Public limit
      plus `QS_ErrorResponseCode 429`; no per-client limits), e.g. per-client limits (`QS_ClientEventLimitCount` or
      similar), a regex fix (`[Pp]`, and covering the other spellings)
- [ ] User-agent block review: new crawlers that get past the `mod_rewrite` rules (no "bot"
      in the name, e.g. Baiduspider), and which agents the catch-all blocks. Recommend changes
      in the same `RewriteCond`/`RewriteRule` form
- [ ] Unit tests with small anonymized fixtures cut from the sample log

### Phase 3: Agent analysis and report
- [ ] Agent receives the aggregated summaries (not raw logs) and can drill into specific
      URLs, IPs, subnets, and user agents through tools
- [ ] Slow pages section: top offenders, the LabKey controller-action, query parameters,
      time-of-day pattern, and whether bots are driving the load
- [ ] Bots section: ranked candidates with evidence, a confidence level, and a recommended
      action (block IP/range, rate-limit, robots.txt entry) with Apache config snippets ready
      to paste in. Recommend only; never apply
- [ ] Flag risk of blocking legitimate institutions (university/shared NAT ranges)
- [ ] Trend comparison with previous days' reports (new vs. recurring offenders)
- [ ] Write the report (HTML and/or markdown) to the local `reports/` directory, dated

### Phase 4: Scheduling
- [ ] Run daily on the separate machine (cron), after the log copy process finishes
- [ ] Failure logging if the run fails or the input logs are missing

## Open Questions
- None at present

## Success Criteria
- Private `uw-maccosslab/maccosslab-agents` repository exists with a documented structure
- A daily run produces a local report covering the previous 24 hours of panoramaweb.org
  Apache and Tomcat logs
- Report identifies the slowest pages with enough detail for a developer to start on a fix
- Report identifies likely bots, including distributed ones, with evidence and
  block recommendations staff can act on
- Parsing/aggregation is covered by tests using anonymized log fixtures
