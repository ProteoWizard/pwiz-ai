# NCBI Publication Detection for Private Dataset Reminders - Specification

**Module:** panoramapublic
**Schema Version:** 25.004
**Date:** 2026-02-13

---

## Overview

Enhance the existing Private Data Reminder system to automatically detect publications associated with private datasets by searching PubMed Central (PMC) and PubMed. When publications are found, send differently-worded reminders encouraging submitters to make their data public.

### Key Features
1. **Automatic publication detection** when reminders are sent
2. **PMC-first search strategy** with PubMed fallback
3. **Verification** using author and title matching; ignoring known "preprint" journals
4. **Different reminder messages** based on whether publications are found
5. **User dismissal** of incorrect publication suggestions
6. **Result caching** to avoid repeated API calls
7. **Manual controls** for administrators

---

## Design Decisions

### Integration Approach
- **Integrated with existing PrivateDataReminderJob** - No separate scheduler required
- **Timing:** Publication checks happen when reminders are sent
- **Respects user dismissals with re-search** - After a configurable deferral period, re-searches for new publications
- **Caches results** - Stores found publication IDs to avoid repeated API calls
- **One publication per dataset** - Only the single best match is persisted in `DatasetStatus`. Multiple matches (up to 5) are only displayed on the admin Search Publications page for manual selection — they come from a live NCBI search and are not stored.

### Publication Types (`NcbiConstants.DB` enum)
- **PubMed** - PubMed ID (preferred; "resolved up" from PMC when possible)
- **PMC** - PubMed Central ID (used when no PMID is available for a PMC article)

### Search Strategy: PMC-First

**Why PMC First?**
- PubMed Central contains full-text articles with better dataset citation tracking
- More likely to contain direct references to ProteomeXchange IDs, DOIs, and Panorama URLs
- Better metadata for verification

**Search Flow:**
1. **PMC Search** (3 strategies)
   - Search by PX ID: `"PXD012345"`
   - Search by Panorama URL: `"https://panoramaweb.org/abc123.url"`
   - Search by DOI URL: `"https://doi.org/10.1234/xyz"`

2. **Verification & Filtering**
   - Fetch metadata for all found PMC IDs
   - Filter out preprints (bioRxiv, medRxiv, arXiv, etc.)
   - Verify author match (LastName + FirstInitial format)
   - Verify title match (exact or keyword-based)
   - Extract PMID from PMC metadata (prefer PMID over PMC ID)
   - Track which strategies matched each article

3. **Priority Filtering** (when multiple results found)
   - Priority 1: Articles found by multiple data IDs (most reliable)
   - Priority 2: Articles matching both Author AND Title
   - **Date-proximity sorting:** After filtering, remaining articles are sorted by how close their publication date is to the experiment's creation date (`ExperimentAnnotations.getCreated()`). Articles without a parseable publication date are sorted to the end.

4. **PubMed Fallback** (only if PMC finds nothing)
   - Query: `"LastName FirstName[Author] AND Title NOT preprint[Publication Type]"`
   - Require BOTH author AND title match
   - Filter preprints

### PubMed vs PMC API Differences

The NCBI ESearch and ESummary APIs use the same endpoints for both databases (`db=pubmed` vs `db=pmc`), but the behavior differs significantly. These differences shaped our search and verification strategy.

#### Field Tags Behave Differently

| Feature | PubMed | PMC | Our Solution |
|---------|--------|-----|--------------|
| `[Title]` tag | Only applies to last word in query | Returns 0 results | Don't use; verify title in metadata |
| `[Author]` tag | Expands to `(surname, first[Author] OR surname first[Author])` | Translates to `[Full Author Name]` | Use `[Author]` tag (works in both, interpreted differently) |
| `[Publication Type]` | Works correctly (`NOT preprint[Publication Type]`) | Not recognized; falls back to all-field search | PubMed: query filter; PMC: metadata check |

**Example — `[Title]` tag pitfall:**
Query: `word1 word2 word3[Title]`
- PubMed interprets as: `word1[All Fields] AND word2[All Fields] AND word3[Title]` (only last word gets the tag)
- PMC: Returns 0 results

**Example — `[Publication Type]` pitfall:**
Query: `... NOT preprint[Publication Type]`
- PubMed: Correctly filters preprints
- PMC query translation: `... AND preprint[All Fields]` — searches "preprint" as text, not as a type filter

#### Different Metadata Fields (ESummary)

**Common fields:**
- `source` — journal abbreviation
- `title` — article title
- `authors` — array of author objects

**PubMed-specific:**
- `sorttitle` — normalized lowercase title without punctuation (ideal for matching)
- `fulljournalname` — full journal name

**PMC-specific:**
- `articleids` — array containing PMID, PMC ID, DOI, etc. (used to "resolve up" to PMID)

#### Best Practices Adopted

1. **Exact phrase matching:** Use quotes, e.g. `"PXD058658"` — works reliably in both databases
2. **Author search:** Use `[Author]` field tag (works in both, though interpreted differently)
3. **Title search:** Do NOT use `[Title]` tag — search all fields, then verify title match in metadata
4. **Preprint filtering:**
   - PubMed: Use `NOT preprint[Publication Type]` in the query
   - PMC: Fetch metadata and check `source` / `fulljournalname` fields for preprint indicators
5. **Title verification:** Use `sorttitle` from metadata when available (exact match), otherwise normalize and compare
6. **Author verification:** Check `authors` array in metadata (works the same in both)

**Key insight:** Don't rely on field tags working the same way in both databases. Use simple queries with exact phrases, then verify matches using metadata.

---

## Database Schema Changes

### Migration File
**File:** `resources/schemas/dbscripts/postgresql/panoramapublic-25.003-25.004.sql`

```sql
-- Add columns to DatasetStatus table for publication tracking
ALTER TABLE panoramapublic.DatasetStatus ADD COLUMN PotentialPublicationId VARCHAR(255);
ALTER TABLE panoramapublic.DatasetStatus ADD COLUMN PublicationType VARCHAR(50);
ALTER TABLE panoramapublic.DatasetStatus ADD COLUMN PublicationMatchInfo TEXT;
ALTER TABLE panoramapublic.DatasetStatus ADD COLUMN Citation TEXT;
ALTER TABLE panoramapublic.DatasetStatus ADD COLUMN UserDismissedPublication TIMESTAMP;
```

### Schema XML
**File:** `resources/schemas/panoramapublic.xml`

Added column definitions:
- `PotentialPublicationId` - Cached publication ID (PMID or PMC ID)
- `PublicationType` - Type of publication ID: `PubMed` or `PMC`
- `PublicationMatchInfo` - Comma-separated list of what matched (e.g. "ProteomeXchange ID, Author, Title")
- `UserDismissedPublication` - Timestamp when the user dismissed the publication suggestion (null = not dismissed)
- `Citation` - Cached NLM citation string for the potential publication

---

## Implementation Components

### 1. PublicationMatch

**File:** `src/org/labkey/panoramapublic/ncbi/PublicationMatch.java`

Top-level class representing a matched publication article.

#### Match Info Constants
```java
public static final String MATCH_PX_ID       = "ProteomeXchange ID";
public static final String MATCH_PANORAMA_URL = "Panorama URL";
public static final String MATCH_DOI          = "DOI";
public static final String MATCH_AUTHOR       = "Author";
public static final String MATCH_TITLE        = "Title";
```

#### Key Methods
```java
public String getMatchInfo()          // e.g. "ProteomeXchange ID, Author, Title"
public String getPublicationUrl()     // Full NCBI URL based on type
public String getPublicationIdLabel() // e.g. "PubMed ID 12345678"
public JSONObject toJson()            // Returns JSON with publicationId, publicationType, publicationLabel, publicationUrl, matchInfo

public static PublicationMatch fromMatchInfo(String publicationId, PublicationType type, String matchInfo)
public static @Nullable PublicationMatch fromDatasetStatus(DatasetStatus)  // Delegates to fromMatchInfo()
```

`fromMatchInfo()` parses a match info string back into boolean flags using the match info constants. `fromDatasetStatus()` extracts the publication ID and type from `DatasetStatus`, delegates to `fromMatchInfo()`, and populates the citation from the cached `DatasetStatus.getCitation()` value.

---

### 2. Publication Search Service

Refactored into an **interface + implementation + mock** pattern for testability.

#### Interface

**File:** `src/org/labkey/panoramapublic/ncbi/NcbiPublicationSearchService.java`

```java
public interface NcbiPublicationSearchService
{
    int MAX_RESULTS = 5;

    static NcbiPublicationSearchService get() { return NcbiPublicationSearchServiceImpl.getInstance(); }

    @Nullable String getCitation(String publicationId, DB database);
    @Nullable Pair<String, String> getPubMedLinkAndCitation(String pubmedId);
    @Nullable PublicationMatch searchForPublication(@NotNull ExperimentAnnotations expAnnotations, @Nullable Logger logger);
    List<PublicationMatch> searchForPublication(@NotNull ExperimentAnnotations expAnnotations, int maxResults, @Nullable Logger logger, boolean getCitations);
}
```

All call sites use `NcbiPublicationSearchService.get().method(...)`.

#### Real Implementation

**File:** `src/org/labkey/panoramapublic/ncbi/NcbiPublicationSearchServiceImpl.java`

Real implementation uses Apache HttpClient 5; `getString(String url)` is `protected` so the mock can override it.

Static holder pattern:
```java
private static volatile NcbiPublicationSearchService _instance = new NcbiPublicationSearchServiceImpl();
public static NcbiPublicationSearchService getInstance() { return _instance; }
public static void setInstance(NcbiPublicationSearchService impl) { _instance = impl; }
```

#### Mock Implementation

**File:** `src/org/labkey/panoramapublic/ncbi/MockNcbiPublicationSearchService.java`

Extends impl, overrides only `getString()`, uses registry maps for ESearch/ESummary/citation data. All search logic, filtering, author/title verification, and citation parsing run through the real implementation code.

---

### 3. Settings Integration

**File:** `src/org/labkey/panoramapublic/message/PrivateDataReminderSettings.java`

```java
public static final String PROP_ENABLE_PUBLICATION_SEARCH = "Enable publication search";
public static final String PROP_PUBLICATION_SEARCH_FREQUENCY = "Publication search frequency (months)";

private static final boolean DEFAULT_ENABLE_PUBLICATION_SEARCH = false;
private static final int DEFAULT_PUBLICATION_SEARCH_FREQUENCY = 3;

public boolean isEnablePublicationSearch()
public void setEnablePublicationSearch(boolean)
public int getPublicationSearchFrequency()
public void setPublicationSearchFrequency(int)

// Checks if a dismissed publication's deferral period is still active
public boolean isPublicationDismissalRecent(@NotNull DatasetStatus status)
```

---

### 4. Job Integration

**File:** `src/org/labkey/panoramapublic/pipeline/PrivateDataReminderJob.java`

#### Publication Search Method

```java
private PublicationMatch searchForPublication(
    @NotNull ExperimentAnnotations expAnnotations,
    @NotNull PrivateDataReminderSettings settings,
    boolean forceCheck,
    @NotNull User user,
    boolean testMode,
    @NotNull Logger log)
```

Logic:
1. Check if enabled (globally or forced for this run)
2. Check user dismissals with deferral logic (re-search after configurable period)
3. When deferral expired: re-search NCBI. If same/nothing found, reset dismissal date (skipped in test mode). If different publication found, return the new match.
4. Use cached results if available (via `PublicationMatch.fromDatasetStatus()`)
5. Otherwise call `NcbiPublicationSearchService.searchForPublication(expAnnotations, log)`

The `testMode` parameter prevents DB writes when resetting dismissal dates during deferred search re-evaluation.

See [PIPELINE-JOB-FLOW.md](PIPELINE-JOB-FLOW.md) for the complete decision tree.

#### Integration in processExperiment()

```java
PublicationMatch publicationResult = searchForPublication(expAnnotations, context.getSettings(),
    _forcePublicationCheck, getUser(), context.isTestMode(), processingResults._log);

if (!context.isTestMode())
{
    postReminderMessage(..., publicationResult, ...);
    updateDatasetStatus(expAnnotations, publicationResult);
}
```

Each experiment is processed in its own DB transaction (`ensureTransaction()` per experiment in `processExperiments()`), so a failure in one experiment does not roll back others.

---

### 5. Notification Messages

**File:** `src/org/labkey/panoramapublic/PanoramaPublicNotification.java`

#### Method Signatures

```java
public static void postPrivateDataReminderMessage(
    @NotNull Journal journal, @NotNull JournalSubmission js,
    @NotNull ExperimentAnnotations expAnnotations,
    @NotNull User submitter, @NotNull User messagePoster,
    List<User> notifyUsers, @NotNull Announcement announcement,
    @NotNull Container announcementsContainer, @NotNull User journalAdmin,
    @Nullable PublicationMatch articleMatch)

public static String getDataStatusReminderMessage(
    @NotNull ExperimentAnnotations exptAnnotations, @NotNull User submitter,
    @NotNull JournalSubmission js, @NotNull Announcement announcement,
    @NotNull Container announcementContainer, @NotNull User journalAdmin,
    @Nullable PublicationMatch articleMatch)
```

#### Subject Lines

| Scenario | Subject |
|---|---|
| Publication found | "Action Required: Publication Found for Your Data on Panorama Public" |
| No publication | "Action Required: Status Update for Your Private Data on Panorama Public" |
| User dismisses publication | "Publication Suggestion Dismissed - {url}" |
| User requests extension | "Private Status Extended - {url}" |
| User requests deletion | "Data Deletion Requested - {url}" |

---

### 6. Controller Actions

**File:** `src/org/labkey/panoramapublic/PanoramaPublicController.java`

| Action | Purpose |
|---|---|
| `SearchPublicationsForDatasetAction` | Manual search for a single dataset — displays up to 5 matches |
| `SearchPublicationsAction` | Admin bulk search page with DataRegion grid |
| `SearchPublicationsForDatasetApiAction` | API endpoint used by bulk search JavaScript |
| `NotifySubmitterOfPublicationAction` | Admin notifies submitter about a selected publication; clears dismissal |
| `DismissPublicationSuggestionAction` | User dismisses a wrong publication; stores dismissal timestamp |
| `SetupMockNcbiServiceAction` | Test support — install mock service |
| `RegisterMockPublicationAction` | Test support — register mock article |
| `RestoreNcbiServiceAction` | Test support — restore real service |

**`DismissPublicationSuggestionAction` citation fetching note:** Uses a `fetchCitation()` helper that lazily fetches the citation from NCBI when needed (in `getConfirmViewMessage()` and `postNotification()`). If NCBI is unavailable, falls back to the publication ID label. The citation is NOT fetched during validation. This is a non-obvious design choice — citation fetch is deferred to avoid blocking form validation.

---

### 7. Experiment WebPart Integration

**File:** `src/org/labkey/panoramapublic/view/expannotations/TargetedMSExperimentWebPart.java`

A "Find Publications" link is added to the admin dropdown menu (nav tree) on the experiment details web part. The link is only shown when:
- The user has `AdminOperationsPermission`
- The experiment has a short URL (i.e., has been submitted to a journal)

Links to `SearchPublicationsForDatasetAction` with the experiment annotations `id` parameter.

---

### 8. Admin Settings UI

**File:** `src/org/labkey/panoramapublic/view/privateDataRemindersSettingsForm.jsp`

- Checkbox for enabling/disabling publication search
- Text input for publication search frequency (months) — how long to wait after a user dismisses a publication before re-searching

Links at the bottom (after selecting a Panorama Public folder):
- "Send Reminders Now" — navigates to `SendPrivateDataRemindersAction`
- "Search Publications" — navigates to `SearchPublicationsAction`

Both links use JavaScript to read the selected folder and build the URL via `LABKEY.ActionURL.buildURL()`.

**File:** `src/org/labkey/panoramapublic/view/sendPrivateDataRemindersForm.jsp`

Checkbox to control publication checking for manual reminder sends (defaults to global setting, can be overridden per run).

---

## Data Flow

> For pipeline job execution, publication search decision tree, and DatasetStatus field changes, see [PIPELINE-JOB-FLOW.md](PIPELINE-JOB-FLOW.md).

---

## Error Handling

### API Failures
- **Network/I/O errors (`IOException`):** Caught in `executeSearch` / `fetchMetadata`, logged to provided `Logger`, return empty list / map
- **Non-2xx response (`HttpResponseException`):** Thrown by `getJson()` with status code and reason phrase; caught as `IOException` by callers
- **Malformed JSON (`JSONException`):** Caught alongside `IOException` by callers, logged, return empty list / map
- **Empty results:** Return gracefully
- **Rate limit errors:** Already prevented by 400ms delay

### Missing Data
- **No submitter:** Skip author verification, rely only on title
- **No title:** Skip title verification, rely only on author
- **No PX ID/DOI/URL:** Skip those search strategies
- **Missing both author and title for PubMed fallback:** Return empty list

### Database Errors
- **DatasetStatus save fails:** Log error but continue (reminder still sent)
- **Null experiment:** Skip processing for this dataset

### Job Failures
- **Individual dataset errors:** Log and continue to next dataset
- **Critical failures:** Job fails but logs detailed error information

---

## File Summary

### New Files
- `src/org/labkey/panoramapublic/ncbi/NcbiPublicationSearchService.java` — Interface
- `src/org/labkey/panoramapublic/ncbi/NcbiPublicationSearchServiceImpl.java` — Real implementation
- `src/org/labkey/panoramapublic/ncbi/MockNcbiPublicationSearchService.java` — Mock for Selenium tests (extends impl)
- `src/org/labkey/panoramapublic/ncbi/NcbiConstants.java` — DB enum, URL builders, ID patterns
- `src/org/labkey/panoramapublic/ncbi/PublicationMatch.java` — Matched publication result
- `src/org/labkey/panoramapublic/view/searchPublicationsForm.jsp`
- `src/org/labkey/panoramapublic/view/searchPublicationsForDataset.jsp`
- `resources/schemas/dbscripts/postgresql/panoramapublic-25.003-25.004.sql`
- `test/src/org/labkey/test/tests/panoramapublic/PublicationSearchTest.java` — Selenium test

### Modified Files
- `resources/schemas/panoramapublic.xml`
- `src/org/labkey/panoramapublic/model/DatasetStatus.java`
- `src/org/labkey/panoramapublic/PanoramaPublicModule.java` — Unit test registration: `NcbiPublicationSearchServiceImpl.TestCase`
- `src/org/labkey/panoramapublic/message/PrivateDataReminderSettings.java`
- `src/org/labkey/panoramapublic/pipeline/PrivateDataReminderJob.java`
- `src/org/labkey/panoramapublic/PanoramaPublicNotification.java`
- `src/org/labkey/panoramapublic/PanoramaPublicController.java` — Call sites use `NcbiPublicationSearchService.get().*`; test support actions added
- `src/org/labkey/panoramapublic/view/privateDataRemindersSettingsForm.jsp`
- `src/org/labkey/panoramapublic/view/sendPrivateDataRemindersForm.jsp`
- `src/org/labkey/panoramapublic/view/expannotations/TargetedMSExperimentWebPart.java`
- `test/src/org/labkey/test/tests/panoramapublic/PanoramaPublicBaseTest.java` — Added `getPrivateDataReminderSettings()`

---

## Selenium Test: PublicationSearchTest

**File:** `test/src/org/labkey/test/tests/panoramapublic/PublicationSearchTest.java`

Tests the end-to-end publication search, notification, and dismissal flows using two datasets.

### Test Datasets

| | Dataset 1 | Dataset 2 |
|---|---|---|
| **Folder** | System Suitability Study | Carafe |
| **Title** | Design, implementation and multisite evaluation... | Carafe: a tool for in silico spectral library... |
| **PXD** | PXD010535 | PXD056793 |
| **PMID** | 23689285 | 41198693 |
| **PMC ID** | — | 12592563 |
| **Search path** | PubMed fallback (author+title) | PMC search by PXD (2 results: Nature + bioRxiv preprint) |
| **Submitter** | submitter1 | submitter2 |

### Test Steps

1. Setup two folders, submit and copy to Panorama Public
2. Set PXD IDs on copied experiments using the `UpdatePxDetails` web page (navigated via `beginAt()`). Note: Cannot use `UpdateRowsCommand` because the `ExperimentAnnotations` table is not updatable via the HTTP-based APIs.
3. Enable publication search in settings
4. Run publication search pipeline job
5. Verify pipeline job found publications and posted messages for both datasets
6. Verify message content for each dataset
7. Test dismissal flow: dismiss publication → verify error on re-dismiss → verify dismissal message posted
8. Test re-notification after dismissal

---

**End of Specification**
