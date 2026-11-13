# TODO-20261113_maccosslab_agents_log_replay.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `log-replay` (pushed 2026-11-13; commits `cf6e5e5`..`91e68b3`)
- **Base**: `main`
- **Created**: 2026-11-13 (tool first committed 2026-11-10)
- **Status**: In progress
- **PR**: https://github.com/uw-maccosslab/maccosslab-agents/pull/7
- **Objective**: Replay production Tomcat traffic against panoramaweb-dr with `log-replay`,
  make its report trustworthy, and use it plus the production logs to find why
  panoramaweb.org pages are slow.

## Background

`log-replay` (`src/maccosslab_agents/log_replay/`, see the repo's CLAUDE.md "Log replay" and
README) replays up to 15 minutes of the Tomcat access log against
`https://panoramaweb-dr.gs.washington.edu` in headless Chromium and compares with
production `%D`. Runs land in `runs/log-replay/<timestamp>/` (gitignored). The Docker
image `log-replay` (`docker/log-replay/Dockerfile`) is how the developer runs it.

Runs so far (window 2026-11-05 07:50-08:00 PST, given as `--start 2026-11-05T08:50:00-07:00`):
- `20261111-150438`: `--max-concurrency 8`. Fell 124 s (p50) behind schedule; not a load test.
- `20261112-173543`: `--max-concurrency 40`, `--save-downloads`. Kept schedule (p50 1 ms
  late), DR peaked at 37 in flight vs production's 35. Made with the OLD image, so it has
  no `content_type` / `prod_disconnect_signature` columns.

## Tasks

### Report and tool fixes (done, uncommitted on `log-replay`)
- [x] Run summary: "Started behind schedule (p50 / p90 / max)" row, plus a warning when
      p50 >= 1 s that compares slots with production's peak concurrency
- [x] Network floor (5th percentile TTFB) noted under "By action"; "Top regressions"
      ranked by replay - prod %D - floor ("Slower by"), not by ratio
- [x] Timing sections use only comparable rows: same status as production, downloads
      that returned a file, production not cut short
- [x] `content_type` recorded per response (`replay._media_type`); downloads that return
      `text/html` with the production status are flagged ("Downloads that returned a page")
- [x] Client-disconnect detection: `select.disconnect_signature()` (200, >= 10 s, ends
      within 50 ms after an even second), written as `prod_disconnect_signature`; the
      report calls a row cut short only if the replay also returned the same status with a
      body > 10% larger ("Cut short on production" section)
- [x] One shared httpx client for `.api`/downloads (`replay.new_http_client`),
      `HTTP_KEEPALIVE_S = 10` (DR keeps idle connections 12-15 s, measured), cookie jar
      that stores nothing (each request sends its slot's cookies itself)
- [x] Tests: `tests/test_log_replay_report.py` (many new), `tests/test_log_replay_http.py`
      (new), browser test asserts `content_type`. 308 passed locally; browser tests pass
      in the Playwright image
- [x] README documents the new fields, sections and the cut-short rule
- [x] Docker image `log-replay` rebuilt with all of the above (2026-11-13)
- [x] Committed on `log-replay` (2026-11-13): `3e7973c` report timing comparisons,
      `d8026df` cut-short detection, `5bc623c` shared keep-alive HTTP client (no connection
      cap after review), `91e68b3` review fixes (next-page/download clicks no longer folded
      into the page, library timeouts count as timeouts, cut short needs the encoded size)
- [x] `/code-review medium` on the whole branch; PR #7 opened against `main`
- [x] Rebuilt the `log-replay` Docker image at `91e68b3` (2026-11-13 10:20, image `af507afc53c0`)
- [ ] Optional: `--report-only RUN_DIR` to re-render a run's report (currently done with a
      one-off script calling `report.write_report`)
- [ ] Optional: report flag for cut-short requests on actions other than query grids
      (passport-protein clients give up but the server cannot tell; see findings)

### Next replay
- [ ] Run the new image at `--max-concurrency 40 --save-bodies --save-downloads`; check the
      API TTFB drop (expected ~326 ms -> ~95 ms for calls within 10 s of another)
- [ ] Replay a busier window: 08:50-09:00 PST had ~3x the showPeptideList traffic of 07:50-08:00
- [ ] Downloads can't be tested until DR has the file store (`/data/labkey/files`)

### Production issues to raise
- [ ] showPeptideList: ~300 requests per 2 h from crawlers that follow old folder URLs,
      wait 18-68 s and disconnect; 7.2 h of server time per 2 h on slow showPeptideList
- [ ] passport-protein: Aging cohort (aging-mouse-ev-2026) pages take 30 s median, up to
      16 min; a distributed crawler (03:06-18:17 on 11-05, ~1 address per request) asks
      again every ~13 s while the first is still running, so the same page renders 2-3
      times at once (45.5 h of server time on 11-05; 17.4 h if each page rendered once)
- [ ] LabKey's `HTTP request timeout` logs a long download every 5 s but does not stop it
      (one ran 8 h on thread #916101 on 2026-11-05)

## Findings (2026-11-11 to 2026-11-13)

**Replay vs DR**
- With 40 slots DR handled production's load: median response +4%, p90 +19% vs 8 slots.
- Most "slower" ratios are the ~92 ms network floor on 1-3 ms production requests.
- API calls took ~326 ms because each was a new TCP+TLS connection (fixed above).
- Every download failed on DR because the data files are missing: 7 returned 200 with
  "Unable to find Skyline file ... does not exist", 10 a 404 "Data file" page, 2 "No such
  folder". 106 view 404s and 37 302s are folders missing or not public on DR (TPAD2.0,
  2026 Panorama Public folders).

**Client disconnects (showPeptideList, executeQuery)**
- Query grid pages write every 2 s while waiting on the database, so a disconnected client
  is found at the next write: %D ends just after an even second, ~9-10 KB sent, logged 200.
  On 2026-11-05, 1,276 of 1,321 slow, small showPeptideList 200s ended this way; other
  actions end that way 2.5% of the time (chance). labkey.log has no entries for them.
- "DR is 7x slower" on Passport 35623 / CPTAC 147601 was wrong: production never finished
  those pages (clients left at 18-68 s); DR rendered them in full in 120-171 s.

**showPeptideList on production, 07:00-09:00 PST** (706 requests, none signed in)
- No point where it turns slow: 55-95% of 200s took >= 10 s in every 10 minutes.
- 304 cut short (208 right after a 302 from the page's old folder URL), 257 redirects,
  58 slow full pages (up to 7.9 min), 87 fast (~40 ms). 215 different slow pages.
- Busiest: 08:55-09:00 (85 requests). The replayed 07:50-08:00 window was quiet (27).

**passport-protein on production, 07:00-09:00 PST** (1,216 requests, all 200)
- One data set: Aging cohort (aging-mouse-ev-2026, Aging_Cohort folder) is 297 requests,
  median 29.7 s, max 980 s, 85% of passport-protein's 6.2 h of server time. Everything else
  median 2.6 s; a CPTAC control family held 2.7-3.1 s every 10 minutes.
- 142 of 167 repeated Aging cohort requests started (~13 s after the previous) while the
  earlier one was still running. passport-protein writes nothing while working, so it
  cannot detect a disconnect and has no 2 s signature.
- Open: Aging cohort median fell from 53 s before 07:50 to 21 s after; partly smaller pages
  (different proteins), but also ~2x faster per KB. Cause not found.

**passport-protein on production, all of 2026-11-05** (5,548 requests; page
`ai/.tmp/sessions/20261113_log_replay/passport-prod-24h/passport-protein-prod-20261105-24h.html`)
- 49 h of server time; 93% (45.5 h) was the Aging cohort, all between 03:06 and 18:17,
  none before or after.
- That traffic is a distributed crawler: 2,551 requests from 2,546 client addresses, rotating
  Chrome versions, 1,066 protein pages. It asks for a page again ~13 s later (1,314 of 1,485
  repeats while the first was still running; 598 pages 3+ times). One render per page would
  have been 17.4 h, so the repeats cost ~28 h. Aging pages got slower per KB through the day
  (1.3 s/KB at 03:00, 2.0 at 17:00, 2.8 at 18:00) as passport-protein in flight rose to ~16.
- Other pages were not slowed: CPTAC median 2.6 s during the crawl, 2.8 s outside; the
  UVicPC_Borchers MousePlasma assay held 2.7-3.3 s per 10 min.
- So the ~13 s re-requests seen 07:00-09:00 are this crawler's retries, not people.

**Data handling**
- Do not publish anything to claude.ai (developer's instruction 2026-11-13); charts are
  local HTML. Never print client IPs or LabKey usernames from the logs.
- Tomcat `%t` is the END time to the whole second; start = end - %D, so starts are +/- 1 s.

## Progress Log

### 2026-11-13 - Report fixes, disconnect finding, production analysis
- Reviewed runs `20261111-150438` and `20261112-173543`; made the report fixes above;
  found the disconnect signature in labkey.log/access logs; fixed API keep-alive; rebuilt
  the Docker image.
- Built local chart pages (DR and production, showPeptideList and passport-protein); copies
  with data and templates in `ai/.tmp/sessions/20261113_log_replay/`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261113_maccosslab_agents_log_replay.md` before starting work.
