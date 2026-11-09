# TODO-20261106_uniprot_rate_limit.md

## Branch Information
- **Branch**: `Skyline/work/20261106_uniprot_rate_limit`
- **Base**: `master`
- **Created**: 2026-11-06
- **Status**: In Progress
- **GitHub Issue**: (none - from nightly perf tests)
- **Module**: `skyline`
- **PR**: [#5008](https://github.com/ProteoWizard/pwiz/pull/5008)
- **Checkout**: `C:\Dev\WebStuff`

## Objective

Stop the UniquePeptides*PerfTest hangs that began 2026-11-05 on master and release
(e.g. Performance Tests run 86568). UniProt's API deployments of 05-Nov and 06-Nov-2026
(release 2026_04) added:

- HTTP 429 Too Many Requests with `Retry-After: 60` and a JSON body, after a burst of requests
- HTTP 400 "Too many OR conditions in query. Maximum allowed is 100."

The importer treated a 429 as a generic transient error: 5 retries one second apart, then
abandon the pass, which the background loader reschedules at once - back into the limit.
The GiveUpOnUnresponsiveWebService seam did not cover that path, so the test sat in
"Accessing web services" until its 360s timeout. The UniprotApiVersionCheck canary
(July 2026) fired in the run log as designed.

## Approach

- `NetworkRequestException.RetryAfter`, filled from the response's Retry-After header
  (delta or date) in `HttpClientWithProgress.CreateResponseFailedException`.
- `WebEnabledFastaImporter`: new outcome and `WebSearchFailureReason.rate_limited` for 429.
  Seam off (production): wait out Retry-After (cancelable, default 60s, cap 5 min), then end
  the pass retry-eligible. Seam on (tests): wait and retry, give up after
  MAX_CONSECUTIVE_WEBSERVICE_FAILURES. Applies to Entrez as well as UniProt.
- UniProt batch cap 200 -> 100 (the new OR limit).

## Tasks

- [x] Unit test `TestWebServiceRateLimit` in `TestFastaImport` (seam on, seam off, no Retry-After)
- [x] Fix
- [x] Build; TestFastaImport, TestProteomeDb, TestOlderProteomeDb, TestNewerProteomeDb,
      TestImportValidFasta, ProteinMetadataFunctionalTests, CodeInspectionTest green
- [x] UniquePeptides0-4PerfTest green against live UniProt (42-58s each; no 429 seen in that run)
- [x] TestOlderProteomeDbWeb green live. TestFastaImportWeb fails on an NCBI Entrez 429 -
      identical on unpatched master (pre-existing QueryEntrez burst, not this change)
- [x] Committed 451b75b580 (local, not pushed)
- [x] /code-review medium - fixed 3 (seam-on wait capped at 60s; date Retry-After measured
      from the server's Date header; GetRetryAfter made public on NetworkRequestException and
      tested), dropped 6 (no progress text during the wait, 503 handling, MapHttpRequestException
      path, delay carried in a field, shared give-up counter, cap placement). Commit 97e5b59d5a
- [x] PR #5008 opened (label skyline)
- [x] Second /code-review medium: fixed HasWebAccess (uncancelable probe waited out a 429, then
      cached "no internet") - a 429 now ends the probe at once and counts as access; test
      TestWebAccessProbeRateLimited went red then green. Dropped the rest (repeats, test-only,
      efficiency, HTTP-layer redesign). tcinspect RedundantNameQualifier fixed; tcinspect clean.
      Pushed ab098f51b5, cd1ad8851a
- [x] Copilot (real review): add coverage for cancelling the real WaitForRateLimit - added
      TestRateLimitWaitCancellation; thread replied and resolved
- [x] Third /code-review medium: the production wait ran under ProteinMetadataManager's
      lock(_processedNodes), which ClearCache takes on the UI thread at close - production wait
      capped at 15s (MAX_RATE_LIMIT_DELAY; tests MAX_TEST_RATE_LIMIT_DELAY 60s); zero/past
      Retry-After floored at 2s. Rejected alternative: a "not before" gate with no sleep, which
      depends on the loader's reschedule cadence (possible busy loop). Pushed 4660acb611
- [x] Copilot re-review: approval recommended, no open issues. Fourth /code-review medium:
      tightened the cancellation test bound 30s -> 5s (30s could not catch a broken cancel on
      the 15s production wait); a live probe confirmed 100 OR'd terms returns 200, so the
      batch cap needs no margin; the rest repeats/dropped. Pushed ccd3a7151e
- [x] Entrez: TestFastaImportWeb failed live on NCBI 429 (Retry-After 2; limit 3/s without an
      API key) because a lookup's summary and full requests went out back to back. Every Entrez
      request now starts >= 400ms after the last (ENTREZ_REQUEST_INTERVAL); TestEntrezRequestSpacing
      red (0.25ms gap) then green. TestFastaImportWeb, TestOlderProteomeDbWeb, UniquePeptides1PerfTest
      green live; RECORDED_API_DEPLOYMENT_DATE -> 06-November-2026. tcinspect clean. Pushed a7784c7f89
- [x] Release-branch backport to `Skyline/skyline_26_1_1`: PR
      [#5010](https://github.com/ProteoWizard/pwiz/pull/5010), branch
      `Skyline/work/20261106_uniprot_rate_limit_release` in `C:\Dev\backport` (b3b4dfca73). Applied
      by hand: release stores WebEnabledFastaImporter.cs and FastaImporterTest.cs as CRLF (whole-file
      conflict), lacks IsTransient, and .NET Framework has no HttpStatusCode.TooManyRequests (added
      HTTP_TOO_MANY_REQUESTS = 429). Offline, live web and inspection tests green
- [x] Fifth review round: the 333ms per-batch Entrez wait duplicated WaitForEntrezRequestInterval,
      so it was removed (ENTREZ_RATELIMIT 0). That exposed a real gap: the Entrez clock was per
      importer, so a new importer's first request was not spaced from the previous one's last
      (live Entrez 429 in record mode; TestEntrezRequestSpacing extended to two importers went red
      at 342ms, then green). The clock is now static under a lock. Dropped: routing the spacing
      through the cancellable WaitForRateLimit seam (at most 400ms), MapHttpRequestException not
      copying RetryAfter (that path never carries a 429 response). RECORDED_API_DEPLOYMENT_DATE
      kept at 06-November-2026 and its doc reworded: a re-record experiment changed only data
      drift in WebData.json (ContentType spacing, row order, a few unreviewed entries), no new
      URLs or format, so the recordings were left alone. #5008 pushed ec2915f747; ported to
      #5010 ce22f2b149 (build, FASTA/ProteomeDb tests incl. live web, -RunInspection 0/0)
- [x] UniProt deployed new API code on 07-November-2026; live web tests passed against it, so
      RECORDED_API_DEPLOYMENT_DATE -> 07-November-2026. #5008 376282c23b, #5010 ab997675b4
- [x] /code-review high (whole PR): a 429 with Retry-After 60 cost a request every 15s pass, and
      each importer (metadata loader, digest loader, protein association) kept its own wait. Added
      RateLimitGate on WebSearchProvider (static for the real services; test providers that fake a
      429 own one): every 429 closes the service until Retry-After; in normal use each pass waits
      at most MAX_RATE_LIMIT_DELAY for it and sends nothing until it has passed. The probe and the
      give-up seam bypass it. TestRateLimitOutlastsPass red (2 requests) then green. Moved the
      static Entrez fields ahead of instance fields. Dropped: 503 Retry-After (repeat), probe flag
      race, seam-on per-pass cost, uncancellable 400ms sleep, dead ENTREZ_RATELIMIT entries,
      250ms poll, timing-test flakiness. Both inspections clean. #5008 143789c4a4, #5010 d51e513c73
- [x] /code-review high on that commit: a closed Entrez gate aborted the whole pass, holding up
      UniProt for the full Retry-After - now it skips only its own service, and all waiting in a
      pass shares one MAX_RATE_LIMIT_DELAY allowance. Gate closure capped at MAX_RATE_LIMIT_HONORED
      (10 min). HasWebAccess treats a closed UniProt gate as reachable instead of asking again.
      Asserted the real providers share one gate. Each test went red first (cap 1h > 10min;
      UniProt 0 requests; probe 2 requests). Dropped: seam-on bypass (test-only), merging gate with
      the Entrez clock (redesign), redundant post-refusal wait, no failure reason on gated
      proteins, duplicated test RequestCount. #5008 c0f62bd85a, #5010 4b04b06148 (one hunk
      hand-applied: release has HTTP_TOO_MANY_REQUESTS beside MAX_TEST_RATE_LIMIT_DELAY)
- [ ] Carry any later #5008 review changes over to #5010; merge #5010 after #5008

## Notes

- UniProt publishes no rate-limit numbers. Locally, ~140 sequential single-term searches at
  ~0.5s each preceded the first 429. UNIPROTKB_RATELIMIT (10ms between requests) left as is.
- Several nightly machines behind one outbound IP may share one rate-limit budget (untested).
