# UniProt /stream error body hangs protein metadata lookup

**Branch**: `Skyline/work/20260709_uniprot_stream_error_body`
**Started**: 2026-07-09
**Status**: Completed
**PR**: [#4407](https://github.com/ProteoWizard/pwiz/pull/4407) (merged 2026-07-10 as 6419202d)

## Problem

All four `UniquePeptides*PerfTest` hit the 360s `WaitForConditionUI` timeout in the
2026-07-09 nightlies, on master and on the release branch. The release branch ran an
identical commit (02239a0a3) clean on 07-08 and failed on 07-09, so nothing in our code
changed.

`https://rest.uniprot.org/uniprotkb/stream` answers some queries with HTTP 200, a valid TSV
header, two blank lines, and then the plain text `Error encountered when streaming data.
Please try again later.` It responds in ~0.5s, so nothing times out. One such term empties
the entire OR-batch, so good accessions in the batch return nothing either.

In `QueryUniprot`, the blank line indexed `fields[colLength]` on a one-element array and
threw `IndexOutOfRangeException`, which the generic catch mapped to `retry_later`. The pass
aborted, proteins stayed `NeedsSearch`, and the background loader rescheduled forever.
Because no `timed_out` outcome ever occurred, the give-up seam added in #4340 never fired.

## Work done

* `ConstructUniprotURL` uses `/uniprotkb/search` with `size=500` and modern `fields=`
  (`columns=` is silently ignored by the current REST API).
* `QueryUniprot` skips blank lines, bounds-checks columns, raises
  `UnusableWebResponseException` on a non-TSV row, and drops withdrawn "deleted" tombstone
  rows that `/search` returns and `/stream` did not.
* New `unusable_response` outcome / `invalid_response` reason, bounded by the give-up seam
  alongside `timed_out`. Seam renamed to `GiveUpOnUnresponsiveWebService`.
* Regression check `TestUniprotErrorBody()`, called from `TestFastaImport`.
* Refreshed `FastaImporterTestWebData.json` / `FastaImporterTestExpected.json`;
  `failOnSearch` 8 -> 10.

## Gotchas found

* Never append to the UniProt query. `(P10636-2)` is an exact isoform lookup; adding
  `AND (active:true)` makes UniProt read the hyphenated accession as free text and return
  dozens of unrelated proteins. That ruled out the obvious tombstone filter.
* Three expected-metadata changes (CGI_10000780, NP_458827, NP_710065) are genuine UniProt
  withdrawals, verified returning zero rows on both endpoints live.

## Also shipped (beyond the original plan)

* A **second** recorded fixture, `Test/Proteome/ProteomeDbTestWebData.json`, also keyed by
  URL, broke on the endpoint switch (`TestOlderProteomeDb`); refreshed it too. There are two
  such fixtures — grep `uniprotkb/` across `*.json` before changing any web URL.
* `QueryUniprot` also refuses a response whose header lacks the accession column, so an
  error-message-as-header is not mistaken for an empty "no match" (which would drop metadata).
* `TestUtil/UniprotApiVersionCheck.cs`: a console-only WARNING (never a test failure) from the
  web-going tests when UniProt's undocumented `X-API-Deployment-Date` header moves off the
  pinned date. Watches the API deploy only, not the frequent data release. On its first live
  run it caught a real UniProt deploy (12-June -> 10-July-2026); verified benign and re-pinned.
* Tombstones come back as both `deleted` and `demerged`; the filter keys on empty Length, not
  the name.

## Gates

* All four `UniquePeptides*PerfTest` pass live in ~60s (were 360s timeouts). `TestFastaImport`,
  `TestOlderProteomeDb`, `ProteinMetadataFunctionalTests`, `CodeInspectionTest`, and full
  ReSharper inspection all green. Fresh-context self-review (several rounds) and Copilot both
  clean; the one Copilot thread addressed and resolved.

## Follow-up (out of scope, not filed)

* `QueryEntrez` fires summary+full back-to-back inside one `ENTREZ_RATELIMIT` (333ms)
  interval, so NCBI sees bursts above its 3/sec limit and returns 429. This blocks a full
  `IsRecordMode` re-record and can bite real users importing Entrez accessions. Surfaced live
  during this work (TestFastaImportWeb failed on NCBI 429, unrelated to UniProt).
* Not cherry-picked to release automatically. Brian hand-backported to `Skyline/skyline_26_1`
  in `C:\Dev\Backport` mid-stream; given how much landed after, re-deriving that from the
  merged branch is cleaner than continuing to cherry-pick.

## Progress Log

### 2026-07-10 - Merged

PR #4407 merged (squash) as commit 6419202d, "Updates to deal with UniProt API change". Shipped
the endpoint switch to `/uniprotkb/search`, the `QueryUniprot` hardening (blank lines, bounds
checks, unusable-response and headerless-header detection, tombstone filter), the broadened
give-up seam, both refreshed recordings + expectations, the regression test, and the
API-version-drift console warning. Twelve commits on the branch, all AI-review gates green.
Deferred: the NCBI Entrez burst-rate-limit fix (out of scope) and reconciling the hand-made
release backport (better re-derived than cherry-picked).
