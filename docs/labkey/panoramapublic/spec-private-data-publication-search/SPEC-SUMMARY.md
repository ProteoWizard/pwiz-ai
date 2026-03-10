# NCBI Publication Detection — Summary

**Module:** panoramapublic
**Schema Version:** 25.004

---

## What It Does

Automatically detects publications associated with private datasets on Panorama Public by searching PubMed Central and PubMed. When a publication is found, the submitter receives a reminder with the publication citation and a link to make their data public. When no publication is found, a generic reminder is sent instead.

---

## Search Strategy

1. **PMC first** — search by PXD ID, Panorama URL, and DOI (exact phrase matching)
2. **Verify** — filter preprints, check author match (LastName FirstInitial with word boundary check and diacritics stripping), check title match (exact or keyword-based, with HTML tag stripping and diacritics stripping)
3. **Priority filter** — prefer articles found by multiple data IDs, then by both author and title, then sort by publication date proximity to dataset creation
4. **PubMed fallback** — only if PMC finds nothing; searches by author + title

---

## Database Changes

Five columns added to `DatasetStatus`:

| Column | Type | Purpose |
|---|---|---|
| `PotentialPublicationId` | VARCHAR(255) | Cached publication ID (PMID or PMC ID) |
| `PublicationType` | VARCHAR(50) | `PubMed` or `PMC` |
| `PublicationMatchInfo` | TEXT | What matched (e.g. "ProteomeXchange ID, Author") |
| `UserDismissedPublication` | TIMESTAMP | When the user dismissed the suggestion (null = not dismissed) |
| `Citation` | TEXT | Cached NLM citation string for the potential publication |

---

## Publication Caching and Dismissal

- **Cached:** Once found, a publication (including its NLM citation) is reused from `DatasetStatus` without re-querying NCBI.
- **Dismissed:** When a user dismisses a publication, the dismissal timestamp is stored. During the configurable deferral period (default 3 months), no NCBI searches are performed.
- **Re-search after deferral:** When the deferral expires, the system re-searches NCBI:
  - **Different publication found** → clear dismissal, cache new publication, notify submitter
  - **Same or no publication found** → reset dismissal date (restart deferral), send reminder without publication info
- **`isPublicationDismissed(publicationId)`** — convenience method on `DatasetStatus` that checks both the dismissal date and whether the given publication ID matches the cached one.
- **Only one publication is persisted per dataset.** The pipeline job and admin notification flow save a single best match to `DatasetStatus`. Multiple matches (up to 5) are only displayed on the admin Search Publications page for manual selection — they are not stored.

---

## Key Components

| Component | File | Purpose |
|---|---|---|
| `NcbiPublicationSearchService` | `ncbi/NcbiPublicationSearchService.java` | Interface for publication search |
| `NcbiPublicationSearchServiceImpl` | `ncbi/NcbiPublicationSearchServiceImpl.java` | Real implementation (HTTP calls to NCBI). Instance held as `volatile static` for test swapping. |
| `MockNcbiPublicationSearchService` | `ncbi/MockNcbiPublicationSearchService.java` | Extends real impl, overrides only `getString()` with canned data |
| `PublicationMatch` | `ncbi/PublicationMatch.java` | Matched publication with ID, type, match flags, date, citation |
| `PrivateDataReminderJob` | `pipeline/PrivateDataReminderJob.java` | Pipeline job — processes each experiment in its own transaction |
| `PrivateDataReminderSettings` | `message/PrivateDataReminderSettings.java` | Configurable settings including publication search frequency |
| `DatasetStatus` | `model/DatasetStatus.java` | Per-experiment state for reminders and publication tracking |

---

## Controller Actions

| Action | Purpose |
|---|---|
| `SearchPublicationsForDatasetAction` | Manual search for a single dataset — displays up to 5 matches |
| `SearchPublicationsAction` | Admin bulk search page with DataRegion grid |
| `SearchPublicationsForDatasetApiAction` | API endpoint used by bulk search JavaScript |
| `NotifySubmitterOfPublicationAction` | Admin notifies submitter about a selected publication; clears dismissal |
| `DismissPublicationSuggestionAction` | User dismisses a wrong publication; stores dismissal timestamp. Citation fetched lazily via `fetchCitation()` (not during validation). |
| `SetupMockNcbiServiceAction` | Test support — install mock service |
| `RegisterMockPublicationAction` | Test support — register mock article |
| `RestoreNcbiServiceAction` | Test support — restore real service |

---

## Pipeline Job Flow

```
For each experiment (one transaction per experiment):
  1. Should we send a reminder? (skip if public, extension valid, recent reminder, etc.)
  2. Search for publication (if enabled):
     - Dismissed + deferral active → skip search
     - Dismissed + deferral expired → re-search NCBI (handle same/different/none)
     - Cached (not dismissed) → return cached
     - Not cached → search NCBI
  3. If not test mode: post reminder message + update DatasetStatus
```

See [PIPELINE-JOB-FLOW.md](PIPELINE-JOB-FLOW.md) for the complete decision tree and DatasetStatus field changes per scenario.

---

## Reminder Messages

| Scenario | Subject |
|---|---|
| Publication found | "Action Required: Publication Found for Your Data on Panorama Public" |
| No publication | "Action Required: Status Update for Your Private Data on Panorama Public" |
| User dismisses publication | "Publication Suggestion Dismissed - {url}" |
| User requests extension | "Private Status Extended - {url}" |
| User requests deletion | "Data Deletion Requested - {url}" |

See [../private-data-reminders-overview.md](../private-data-reminders-overview.md) for example message content and a timeline walkthrough.

---

## Settings

Configurable via Admin Console > Panorama Public > Private Data Reminder Settings:

| Setting | Default | Description |
|---|---|---|
| Enable publication search | false | Whether to search NCBI for publications |
| Publication search frequency | 3 months | How long to wait after a dismissal before re-searching |

---

## API Rate Limiting

- 400ms delay between NCBI ESearch calls (stays under 3 req/sec limit)
- `tool=PanoramaPublic` and `email=panorama@proteinms.net` included per NCBI guidelines
- ~2-4 seconds per dataset

---

## Testing

- **Unit tests:** `NcbiPublicationSearchServiceImpl.TestCase` (registered in `PanoramaPublicModule`)
- **Selenium test:** `PublicationSearchTest` — end-to-end flow with mock NCBI service covering search, notification, dismissal, and re-notification
- Mock exercises real search/verification code paths; only HTTP calls are stubbed

---

## Related Documents

- [SPEC.md](SPEC.md) — Full specification with API details, code structure, and error handling
- [PIPELINE-JOB-FLOW.md](PIPELINE-JOB-FLOW.md) — Detailed pipeline job decision tree with DatasetStatus field changes per scenario
- [../private-data-reminders-overview.md](../private-data-reminders-overview.md) — High-level overview with schematics, example timeline, and example messages
