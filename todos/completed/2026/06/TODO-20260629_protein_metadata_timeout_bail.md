# TODO: Web service timeout handling for protein metadata lookup

**Status:** Completed
**Branch:** `Skyline/work/20260629_protein_metadata_timeout_bail`
**PR:** [#4340](https://github.com/ProteoWizard/pwiz/pull/4340) (merged 2026-07-07 as c36791a)

## Objective

Stop `WebEnabledFastaImporter` from hanging the background-proteome metadata load
when a web service (UniProt) is reachable but slow. A request timeout returned
`retry_later`, which aborted the pass and left proteins pending; the background
loader then rescheduled without limit and never reached a terminal "done" state.
Surfaced by intermittent `PerfUniquePeptidesTest` hangs (parks ~75-79% at
"Accessing web services…" then fails the 360s WaitForConditionUI). UniProt was up
— the issue is slow `/uniprotkb/stream` responses for a ~163-protein unresolved
tail racing the test timeout.

## Design (final — test-only seam)

Permanently giving up on a timeout would drop metadata for a transient slowdown
and could apply gene/species uniqueness on incomplete data (a UX regression). The
foreground "Resolving Protein Details" dialog is already cancelable, so production
does not need to auto-give-up — only automated tests need deterministic
termination. So:

* `WebEnabledFastaImporter.GiveUpOnRepeatedTimeout` (default false) — the seam.
* Seam OFF (normal use): a `timed_out` outcome is treated as retry-eligible
  (`abort` the pass; proteins stay `NeedsSearch`), so the loader reschedules and
  the cancelable dialog is not force-completed.
* Seam ON (tests): bounded batch-shrink give-up (`MAX_CONSECUTIVE_WEBSERVICE_TIMEOUTS`,
  per-search-type) marks the remaining proteins timeout-failed +
  `SetWebSearchCompleted` so the load terminates.

## Done

* `timed_out` outcome distinct from `retry_later`; inner retry loop propagates it.
* Seam property + gate; production falls through to the retry-eligible `abort` path.
* FastaImporterTest: `timeout` (seam on → bail) and `timeout_retry` (seam off →
  retry-eligible: proteins stay needs-search, timeout reason recorded, none
  permanently failed). Verified red → green.
* PerfUniquePeptidesTest opts into the seam (fail fast, not hang).
* Copilot review (all threads resolved) + two fresh-context self-reviews — clean.
* CodeInspection + ReSharper full-solution — 0/0. Not cherry-picked to 26.1.

## Remaining / follow-ups

* Optional: gentle inter-pass backoff in the base `BackgroundLoader` so seam-off
  retry doesn't hammer a persistently slow service (per-pass hammering is already
  just one timed-out request; higher blast radius since it's the shared loader).
* Step 2 (separate): curate the `PerfUniquePeptidesTest` protDB tail to ~10-20
  archetype-covering proteins (reviewed accession, unreviewed/TrEMBL, SGD-id
  yeast). protDBs live in PerfUniquePeptidesTest_v2.zip on PanoramaWeb, not the
  repo — all 163 are resolvable locally from the fully-resolved human_and_yeast.protdb
  (no UniProt hits needed), but the exact uniqueness-count assertions are coupled to
  which proteins resolve.
* Parked, NOT fixed by #4340: Philip Remes' 2025 "never dispatches / protein groups"
  infinite re-iteration — same syndrome (load never reaches done) but a different
  trigger (no requests sent); likely a completion-detection bug in the
  ProteinMetadataManager / BackgroundProteomeManager handshake.

## Progress Log

### 2026-07-07 - Merged

PR #4340 merged as commit c36791a. Shipped the `timed_out` outcome plus a
**test-only** give-up seam (`WebEnabledFastaImporter.GiveUpOnRepeatedTimeout`,
default false): normal Skyline use now treats a web-service timeout as
retry-eligible (loader reschedules; cancelable foreground dialog not
force-completed), so a transient slowdown never drops metadata or applies a
uniqueness filter on incomplete data; automated tests opt in to terminate
deterministically (PerfUniquePeptidesTest fails fast instead of hanging).
Verified red→green (FastaImporterTest `timeout` / `timeout_retry`), Copilot +
two fresh-context self-reviews clean, CodeInspection + ReSharper 0/0. Deferred:
optional base-loader inter-pass backoff, and protDB tail curation (step 2). Not
cherry-picked to 26.1 (per Brian). Philip's protein-group no-dispatch bug remains
a separate, unfixed follow-up.
