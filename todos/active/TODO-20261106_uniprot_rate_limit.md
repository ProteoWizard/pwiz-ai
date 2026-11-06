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
- [ ] Release-branch backport to `Skyline/skyline_26_1_1` (the only release branch; .NET 4.7.2
      and diverged, so manual rather than the cherry-pick label)
- [ ] Update UniprotApiVersionCheck.RECORDED_API_DEPLOYMENT_DATE once web tests are re-checked

## Notes

- UniProt publishes no rate-limit numbers. Locally, ~140 sequential single-term searches at
  ~0.5s each preceded the first 429. UNIPROTKB_RATELIMIT (10ms between requests) left as is.
- Several nightly machines behind one outbound IP may share one rate-limit budget (untested).
