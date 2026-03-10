# Private Data Reminder Pipeline Job — Detailed Flow

**Module:** panoramapublic
**Primary file:** `src/org/labkey/panoramapublic/pipeline/PrivateDataReminderJob.java`
**Date:** 2026-03-04

---

## Overview

The `PrivateDataReminderJob` is a pipeline job that iterates over all private datasets on Panorama Public and:
1. Decides whether a reminder is due for each dataset
2. Optionally searches for associated publications via NCBI
3. Posts a reminder message (with or without publication info) to the support thread
4. Updates the `DatasetStatus` record to track what was sent and found

The publication search and the reminder are **independent decisions**. A reminder can be posted without any publication info, and a dismissed publication does not suppress the reminder itself.

---

## Entry Points

### Scheduled (automatic)
`PrivateDataMessageScheduler` triggers the job at the configured reminder time daily.

### Manual
Admin navigates to Private Data Reminder Settings, selects a Panorama Public folder, selects datasets, and clicks "Post Reminders". The `_forcePublicationCheck` flag can override the global publication search setting for this run.

---

## Job Execution Flow

### 1. `run()` → `postMessage()` → `processExperiments()`

Iterates over all specified experiment annotation IDs with one DB transaction per experiment.

### 2. `processExperiment()` — Per-dataset processing

```
For each experiment:
│
├── Lookup ExperimentAnnotations → skip if not found
│
├── getReminderDecision() → should we send a reminder?
│   ├── Data is already public → skip
│   ├── Not the current version → skip
│   ├── Pending re-submission → skip
│   ├── Deletion requested → skip
│   ├── Extension is still valid → skip
│   ├── Recent reminder already sent → skip
│   └── First reminder not due yet → skip
│   (Otherwise: proceed)
│
├── Lookup JournalSubmission, Announcement, Submitter → skip if any missing
│
├── searchForPublication() → returns @Nullable PublicationMatch
│
├── If NOT test mode:
│   ├── postReminderMessage(..., publicationResult)
│   └── updateDatasetStatus(expAnnotations, publicationResult)
│
└── Record as processed
```

**Key point:** `searchForPublication()` returning null does NOT prevent the reminder from being posted. The reminder message simply omits the publication section.

---

## Publication Search Logic (`searchForPublication`)

### Method Signature
```java
private PublicationMatch searchForPublication(
    @NotNull ExperimentAnnotations expAnnotations,
    @NotNull PrivateDataReminderSettings settings,
    boolean forceCheck,
    @NotNull User user,
    boolean testMode,
    @NotNull Logger log)
```

The `User` parameter is needed for saving DatasetStatus updates when resetting a dismissal date after a deferred search. The `testMode` parameter prevents DB writes (dismissal date resets are logged but not persisted).

### Decision Tree

```
Is publication search enabled (or forced)?
├── No → return null
│
└── Yes → Lookup DatasetStatus for experiment
    │
    ├── No DatasetStatus exists
    │   → Search NCBI
    │   → return match (or null)
    │
    └── DatasetStatus exists
        │
        ├── userDismissedPublication is non-null (user dismissed)?
        │   │
        │   ├── isPublicationDismissalRecent() → true (within search frequency)?
        │   │   → LOG "Publication search deferred (N months)"
        │   │   → return null (no search performed)
        │   │
        │   └── Deferral expired
        │       → LOG "Search deferral expired; re-searching NCBI"
        │       → Search NCBI
        │       │
        │       ├── Different publication found (new ID ≠ cached ID)
        │       │   → LOG "New publication found"
        │       │   → return new match
        │       │
        │       └── Same publication found, or nothing found
        │           → Reset userDismissedPublication to now
        │           → Save DatasetStatus to DB
        │           → return null
        │
        ├── potentialPublicationId is non-blank (cached, not dismissed)?
        │   → LOG "Using cached publication"
        │   → return PublicationMatch.fromDatasetStatus(datasetStatus)
        │
        └── No cached publication, not dismissed
            → Search NCBI
            → return match (or null)
```

### Search Deferral

When a user dismisses a publication, `userDismissedPublication` is set to the current timestamp. The system uses the configurable "Publication search frequency" setting (default: 3 months) to determine when to re-search:

- `isPublicationDismissalRecent()` checks if `dismissedDate + searchFrequency` is still in the future
- If the deferral has expired, the system re-searches NCBI
- If the same (or no) publication is found, the dismissal date is reset to now, restarting the deferral period
- If a different publication is found, it is returned to the caller, which clears the dismissal

---

## DatasetStatus Update Logic (`updateDatasetStatus`)

Called after the reminder message is posted. Fetches a fresh `DatasetStatus` from the DB (important because `searchForPublication` may have already modified it).

### New DatasetStatus (first reminder for this experiment)

Creates a new record with:
- `experimentAnnotationsId` = experiment ID
- `lastReminderDate` = now
- If `publicationResult` is non-null: saves `potentialPublicationId`, `publicationType`, `publicationMatchInfo`, `citation`

### Existing DatasetStatus

Updates:
- `lastReminderDate` = now (always)
- If `publicationResult` is non-null AND the publication ID differs from the cached one:
  - `potentialPublicationId` = new publication ID
  - `publicationType` = new type
  - `publicationMatchInfo` = new match info
  - `citation` = new citation
  - `userDismissedPublication` = null (clears dismissal for the new publication)

---

## Scenarios with DatasetStatus Field Changes

### Scenario 1: No prior publication — first search finds one

**Context:** Publication search enabled, no DatasetStatus exists yet (or exists without publication info).

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | null / old date | now |
| `potentialPublicationId` | null | PMID or PMC ID |
| `publicationType` | null | "PubMed" or "PMC" |
| `publicationMatchInfo` | null | e.g. "ProteomeXchange ID, Author, Title" |
| `citation` | null | NLM citation string |
| `userDismissedPublication` | null | null (unchanged) |

**Reminder message:** Includes publication citation and link.

---

### Scenario 2: Cached publication exists, not dismissed

**Context:** A publication was previously found and cached. User has not dismissed it.

`searchForPublication` returns the cached match from `PublicationMatch.fromDatasetStatus()` without calling NCBI.

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | old date | now |
| `potentialPublicationId` | PMID-123 | PMID-123 (unchanged) |
| `publicationType` | "PubMed" | "PubMed" (unchanged) |
| `publicationMatchInfo` | "PX ID, Author" | "PX ID, Author" (unchanged) |
| `userDismissedPublication` | null | null (unchanged) |

**Reminder message:** Includes the cached publication citation and link.

---

### Scenario 3: Publication dismissed, deferral is recent

**Context:** User dismissed the publication suggestion within the configured search frequency period.

`searchForPublication` returns null without calling NCBI.

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | old date | now |
| `potentialPublicationId` | PMID-123 | PMID-123 (unchanged) |
| `publicationType` | "PubMed" | "PubMed" (unchanged) |
| `publicationMatchInfo` | "PX ID, Author" | "PX ID, Author" (unchanged) |
| `userDismissedPublication` | 2026-01-15 | 2026-01-15 (unchanged) |

**Reminder message:** No publication info. Standard "please make your data public" reminder.

---

### Scenario 4a: Publication dismissed, deferral expired — different publication found

**Context:** The deferral period has passed. NCBI search finds a new, different publication.

`searchForPublication` returns the new match. `updateDatasetStatus` detects the ID differs and updates all publication fields.

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | old date | now |
| `potentialPublicationId` | PMID-123 | **PMID-456** (new) |
| `publicationType` | "PubMed" | "PubMed" (or new type) |
| `publicationMatchInfo` | "PX ID, Author" | **new match info** |
| `citation` | old citation | **new citation** |
| `userDismissedPublication` | 2025-10-01 | **null** (cleared) |

**Reminder message:** Includes the new publication citation and link. Submitter sees a fresh publication notification.

---

### Scenario 4b: Publication dismissed, deferral expired — same publication found

**Context:** The deferral period has passed. NCBI search finds the same publication the user already dismissed.

`searchForPublication` resets the dismissal date to now (inside the method, saved to DB) and returns null. `updateDatasetStatus` then only updates `lastReminderDate`.

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | old date | now |
| `potentialPublicationId` | PMID-123 | PMID-123 (unchanged) |
| `publicationType` | "PubMed" | "PubMed" (unchanged) |
| `publicationMatchInfo` | "PX ID, Author" | "PX ID, Author" (unchanged) |
| `userDismissedPublication` | 2025-10-01 | **now** (deferral restarts) |

**Reminder message:** No publication info. Standard reminder.

**Note:** DatasetStatus is saved twice in this scenario — once inside `searchForPublication` (to reset the dismissal date) and once in `updateDatasetStatus` (to update `lastReminderDate`). This works correctly because `updateDatasetStatus` fetches a fresh copy from the DB.

---

### Scenario 4c: Publication dismissed, deferral expired — nothing found

**Context:** The deferral period has passed. NCBI search returns no results.

Identical to Scenario 4b. The dismissal date is reset to restart the deferral period.

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | old date | now |
| `potentialPublicationId` | PMID-123 | PMID-123 (unchanged) |
| `publicationType` | "PubMed" | "PubMed" (unchanged) |
| `publicationMatchInfo` | "PX ID, Author" | "PX ID, Author" (unchanged) |
| `userDismissedPublication` | 2025-10-01 | **now** (deferral restarts) |

**Reminder message:** No publication info. Standard reminder.

---

### Scenario 5: Publication search disabled

`searchForPublication` returns null immediately without checking DatasetStatus or calling NCBI.

| Field | Before | After |
|---|---|---|
| `lastReminderDate` | old date | now |
| All publication fields | (unchanged) | (unchanged) |

**Reminder message:** No publication info. Standard reminder.

---

## User-Initiated Actions (Controller)

These are separate from the pipeline job but affect the same DatasetStatus fields. For complete action details, see [SPEC.md](SPEC.md#controller-actions).

### DismissPublicationSuggestionAction

User clicks the dismissal link in a reminder email.

| Field | Before | After |
|---|---|---|
| `userDismissedPublication` | null | **now** |
| All other fields | (unchanged) | (unchanged) |

### NotifySubmitterOfPublicationAction

Admin manually notifies a submitter about a selected publication (from the Search Publications page).

| Field | Before | After |
|---|---|---|
| `potentialPublicationId` | any | selected publication ID |
| `publicationType` | any | selected type |
| `publicationMatchInfo` | any | selected match info |
| `citation` | any | selected citation |
| `userDismissedPublication` | any | **null** (cleared) |
| `lastReminderDate` | old date | now |

---

## Configurable Settings

All settings are in `PrivateDataReminderSettings` and configurable via Admin Console > Panorama Public > Private Data Reminder Settings.

Key settings that affect publication search behavior:
- **Enable publication search** (default: false) — Whether to search NCBI for publications
- **Publication search frequency** (default: 3 months) — How long to wait after a dismissal before re-searching

For a complete list of all reminder settings and their defaults, see [../private-data-reminders-overview.md](../private-data-reminders-overview.md#settings).

---

## Complete Lifecycle Example

For a detailed month-by-month walkthrough showing how publication search, dismissal, deferral, and re-search interact over time, see the **Example Timeline** section in [../private-data-reminders-overview.md](../private-data-reminders-overview.md#example-timeline).
