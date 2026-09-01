# TODO-20260821_fastaimport_hang.md

## Branch Information
- **Branch**: `Skyline/work/20260821_fastaimport_hang` (UIbug)
- **Module**: `skyline` - the hang is in Skyline's protein metadata lookup; the
  `HttpClientWithProgress` change is in `Shared/CommonUtil` in support of it
- **Base**: `master` @ `51ec80a968`
- **Created**: 2026-08-21
- **Status**: Completed
- **PR**: [#4607](https://github.com/ProteoWizard/pwiz/pull/4607) (merged 2026-09-01)

## Problem

The 2026-08-21 nightly hung on `TestFastaImport` on six machines - four on master
(`43b5aaf06`, en) and two on the release branch (`8e96260a6`, fr). The 18th, 19th and
20th had zero hangs. Two different code bases hanging the same night, with the test
file untouched since 2026-07-10, pointed outside our code.

Two distinct defects, either of which is enough to hang a run.

### 1. A request could wait forever (product)

`HttpClientWithProgress` waits for response headers with
`SendAsync(..., ResponseHeadersRead, token).Result` against a shared client whose
timeout is infinite. `ReadTimeoutMilliseconds` guards only the body, per chunk, and
`RequestTimeout` was a documented no-op, so nothing bounded the wait. A server that
accepts the connection and never answers blocks the calling thread indefinitely.

TeamCity build 4145027 (`pull/4552`, `UniquePeptides2PerfTest`) captured the stack:

```
Task.GetResultCore <- HttpClientWithProgress.WithExceptionHandling
  <- GetResponseHeadersRead <- DownloadToStream <- DownloadData
  <- WebSearchProvider.GetWebResponseStream <- QueryUniprot
  <- ExecuteLookupIteration <- DoWebserviceLookup
  <- BackgroundProteomeManager.Load
```

That is the production path behind Peptide Settings, with the user watching
"Accessing web services to retrieve details for 188 proteins (77%)". Not test-only.

`GiveUpOnUnresponsiveWebService` exists to stop exactly this, but is read at
`WebEnabledFastaImporter.cs:1032`, after `lookupResult` exists - downstream of a wait
that never returns. #4340 fixed retrying forever; waiting forever survived it.

### 2. An offline test reached the live web (test)

`TestFastaImport` calls `DoTestFastaImport(false, doNegTests: true)`, commented "Run
with simulated web access". #3679 (2025-11-23) added a first branch to
`CreateNormalHelper`, `if (scope != null) return scope.Helper;`.
`ConditionalHttpRecordingScope` is a wrapper that is always non-null - only its inner
`_scope` is null for negative tests - so it returned a null helper, which means real
network, and made `BeginLegacyPlayback` unreachable for the very case its own comment
("Fallback for negative tests") names. Before #3679 those tests fell through to it.

The nightly runs with `AllowInternetAccess` false (no `internet=` argument, TestRunner
defaults to off; `TestFastaImportWeb` correctly no-ops in 0 sec in the same log). So
this pass was making live UniProt and NCBI calls in a run that had disabled internet
access - not coverage, a contract violation.

## Trigger

No evidence of a discrete UniProt change. `X-API-Deployment-Date` is 29-July-2026 and
`X-UniProt-Release` is 2026_02 / 10-June-2026, both unchanged and weeks before onset.
The stall is intermittent and per-request, not host-wide: a probe to the same host from
the same machine returned 200 in 2.67 s while a test connection sat frozen. Observed
durations ranged from ~45 s (completed, 63 s total) to over 6 minutes (killed).

Most defensible reading: UniProt/EBI latency got intermittently worse, and code with no
timeout had no margin to absorb it. Server-side throttling config would not show in
those headers, so "no release on 8/21" is not "nothing changed there".

## Fix

**Product** (`HttpClientWithProgress.cs`)
* Added `ResponseTimeoutMilliseconds` (120 s, settable so tests need not wait it out)
  and bounded the header wait with it, using the `Task.WaitAny` idiom `ReadChunk`
  already uses: only the wait is abandoned, never the request. Deliberately generous -
  it exists to break an endless wait, not to hold a server to a latency target.
* Bounded the error-status body read (`CreateResponseFailedException`), which had the
  same unbounded wait one branch over and would still hang on any non-2xx.
* `RequestTimeout` left as the no-op it was, doc corrected to say what actually bounds
  things. Honoring it was tried and reverted - see Rejected below.

**Test** (`FastaImporterTest.cs`)
* Added `HasRecordingScope` and gated the short-circuit on it, so a scope that was
  never created stops masquerading as one and negative tests reach legacy playback.
* Added an invariant in `ExecuteLookupScenario`: a pass with `useNetAccess` false must
  have a test helper installed, since a null helper means live network.

## Rejected: honoring RequestTimeout

The first fix made `RequestTimeout` live. `/code-review max` caught that `_batchsize`
starts at 1 for all search types, so `GetTimeoutMsec(1)` is 10 s on the first request
of every document load - against measured latencies of 0.65-7.4 s normal and ~45 s
stalled. Those values were authored against a property the infrastructure ignored and
have never been exercised. In production `GiveUpOnUnresponsiveWebService` is false, so
one timeout sets `abort = true` and defers the whole pass; on a slow link metadata
resolution could stop converging. Reverted in favor of the generous bound above.

The `WaitAny` rewrite also removed three further findings: the CancelAfter/Dispose race
(reproduced 1-in-3000), loss of mid-body user cancellation, and misclassification as
"No network connection detected" when an abort surfaces as `HttpRequestException`.

## Verification

* Reproduced: unfixed test passes in 52 s with internet off, stalls with it on, opening
  a `rest.uniprot.org` socket at exactly +52 s with CPU flat.
* `HttpClientWithProgressIntegrationTest` gained `TestRequestTimeoutOnStalledServer`: a
  real `TcpListener` that accepts from the kernel backlog and never answers. Red with
  the bound disabled ("Request to a server that never answers did not return"), green
  with it. The simulation helpers replace the transport, so only a real socket covers
  this.
* `TestFastaImport` 52 s -> 11 s, identical with internet on and off, in en and fr.
* `UniquePeptides2PerfTest` 4 consecutive passes (104/111/77/96 s) against live UniProt
  vs TeamCity's 2244 s hang. Confirms the change does not break the live-web path; it
  does not prove the hang is cured, since UniProt was responsive throughout.
* CodeInspection and full ReSharper solution inspection: zero warnings.

## Not touched

* Uploads (`UploadFromStreamInternal`) still have no bound and can block forever; once
  the body is written `ProgressStream.Read` stops being called, so even Cancel cannot
  break out. A bound there must not cut off a legitimately slow large transfer, so it
  is a separate design question. Own issue.
* `TestFastaImportWeb` fails on NCBI eutils 429, unchanged before and after. Separate,
  and internet-gated so it did not break the nightly.
* `RECORDED_API_DEPLOYMENT_DATE` is stale (29-July-2026 vs 10-July-2026 recorded).
* Nothing enforces the no-internet flag; tests are trusted to honor it, which is why
  this went unnoticed from 2025-11-23 to 2026-08-21. A guard in `HttpClientWithProgress`
  refusing non-allowlisted hosts when `AccessInternet` is false would catch the next one.

## Progress Log

### 2026-09-01 - Merged

PR #4607 merged as commit `27affed1c2`. Shipped as written: the response-header wait and
the error-status body read are both bounded, and `TestFastaImport`'s negative pass no
longer reaches the live web. `RequestTimeout` stays the no-op it was - honoring it was
tried and reverted, and that reasoning is now carried in the squash commit body so it
survives in `git log` rather than only here.

One fix was added during review. `SendWithResponseTimeout` was missing the
`CancellationToken.ThrowIfCancellationRequested()` guard that `ReadChunk` applies after
its `Task.WaitAny`. Because the delay shares the caller's token, cancelling completed it
and the wait ended exactly as on a timeout, so a user who clicked Cancel was told the
request timed out, and `WebEnabledFastaImporter` - which catches `NetworkRequestException`
before `OperationCanceledException` - recorded the whole batch as timed out rather than
cancelled. A regression against the pre-diff `.Result`, which threw
`AggregateException(TaskCanceledException)` and mapped correctly. Fixed in `c641bdadba`.

Four Copilot threads were reviewed and all declined with reasons recorded on the PR: the
abandoned request outliving its wait (deliberate, and the late response is disposed by the
continuation), the undisposed error response (pre-existing on that path, marginally
worsened), and the foreground thread in the new test (real mechanism, but `listener.Stop()`
in the `finally` resets the backlog connection and unblocks the worker).

Merged with `--admin` during a TeamCity outage. The last full 19/19 green predates
`c641bdadba` and the final master merge; Brendan and Matt judged the change level
acceptable. The cancellation fix was verified locally instead - clean build plus
`TestHttpClientWithProgressIntegration`, `TestFastaImport`, `TestBasicFastaImport`,
`TestSkyp`, `TestPublishToPanorama` and `TestRInstaller`, all green in en and fr.

Everything under "Not touched" remains deferred; no follow-up issues were filed.
