# Private Data Reminders — Overview

**Module:** panoramapublic

---

## Purpose

When researchers submit data to Panorama Public, the data is initially kept private. The Private Data Reminder system periodically nudges submitters to make their data public, especially once an associated publication is detected.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PrivateDataMessageScheduler                      │
│               (runs daily at configured time, e.g. 8 AM)            │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      PrivateDataReminderJob                         │
│                                                                     │
│  For each private dataset on Panorama Public:                       │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ 1. SHOULD WE SEND A REMINDER?                                 │  │
│  │    • Data already public?                    → skip           │  │
│  │    • Pending re-submission request?          → skip           |  |
│  │    • Deletion requested?                     → skip           │  │
│  │    • Extension still valid?                  → skip           │  │
│  │    • Recent reminder already sent?           → skip           │  │
│  │    • First reminder not due yet?             → skip           │  │
│  │    • Otherwise                               → proceed        │  │
│  └──────────────────────────────┬────────────────────────────────┘  │
│                                 │                                   │
│                                 ▼                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ 2. SEARCH FOR PUBLICATION (if enabled)                        │  │
│  │    • Searches PubMed Central and PubMed for papers            │  │
│  │      using this dataset's PXD ID, Panorama URL, and DOI       │  │
│  │      as search terms                                          │  │
│  │    • Returns a PublicationMatch or null                       │  │
│  └──────────────────────────────┬────────────────────────────────┘  │
│                                 │                                   │
│                                 ▼                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ 3. POST REMINDER MESSAGE                                      │  │
│  │    • Posted to the dataset's support message thread           │  │
│  │    • Two message variants:                                    │  │
│  │                                                               │  │
│  │    With publication:                                          │  │
│  │      "Action Required: Publication Found for Your Data on     │  │
│  │       Panorama Public" — includes citation link, options      │  │
│  │       to make data public or dismiss the suggestion.          │  │
│  │                                                               │  │
│  │    Without publication:                                       │  │
│  │      "Action Required: Status Update for Your Private Data    │  │
│  │       on Panorama Public" — asks if paper is published,       │  │
│  │       offers make public / extension / deletion options.      │  │
│  └──────────────────────────────┬────────────────────────────────┘  │
│                                 │                                   │
│                                 ▼                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ 4. UPDATE DatasetStatus                                       │  │
│  │    • Record when the reminder was sent                        │  │
│  │    • Cache any publication found                              │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## What Submitters Can Do

When a submitter receives a reminder, the message includes links to:

| Action | What happens |
|---|---|
| **Make data public** | Data becomes publicly accessible |
| **Request extension** | Private status extended by N months (configurable, default 6) |
| **Request deletion** | Flags the dataset for removal |
| **Dismiss publication** | If a wrong paper was suggested, marks it as dismissed |

---

## Publication Search & Dismissal Cycle

```
    ┌──────────────┐
    │ Search NCBI  │
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐     nothing found     ┌──────────────────────┐
    │ Publication  ├─────────────────────→ │ Send reminder        │
    │ found?       │                       │ (no publication info)│
    └──────┬───────┘                       └──────────────────────┘
           │ yes
           ▼
    ┌──────────────────────┐
    │ Cache publication    │
    │ in DatasetStatus     │
    │ Send reminder with   │
    │ publication citation │
    └──────────┬───────────┘
               │
               ▼
    ┌──────────────────────┐
    │ Submitter receives   │
    │ reminder with paper  │
    └──────────┬───────────┘
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
  ┌───────────┐  ┌────────────────┐
  │ Makes     │  │ Dismisses      │
  │ data      │  │ publication    │
  │ public    │  │ (wrong paper)  │
  └───────────┘  └───────┬────────┘
                         │
                         ▼
                  ┌────────────────┐
                  │ Deferral period│ (configurable, default 3 months)
                  │ No searches    │
                  │ Reminders sent │
                  │ without pub    │
                  └───────┬────────┘
                          │ deferral expires
                          ▼
                  ┌────────────────┐
                  │ Re-search NCBI │
                  └───────┬────────┘
                          │
                   ┌──────┴──────┐
                   │             │
                   ▼             ▼
            ┌────────────┐  ┌─────────────────┐
            │ Same or no │  │ Different       │
            │ publication│  │ publication     │
            │ found      │  │ found           │
            └─────┬──────┘  └────────┬────────┘
                  │                  │
                  ▼                  ▼
            ┌────────────┐  ┌─────────────────┐
            │ Reset      │  │ Clear dismissal │
            │ deferral   │  │ Cache new pub   │
            │ (wait      │  │ Notify submitter│
            │ another    │  │ about new paper │
            │ 3 months)  │  └─────────────────┘
            └────────────┘
```

---

## Example Timeline

Consider a dataset submitted to Panorama Public with PXD ID `PXD012345`.

### Settings
- First reminder delay: **12 months**
- Reminder frequency: **1 month**
- Extension duration: **6 months**
- Publication search: **enabled**
- Publication search frequency: **3 months**

### Timeline

```
Month 0     Dataset copied to Panorama Public (private)
  │         No DatasetStatus record exists yet.
  │
  │         ... no reminders sent (12-month delay) ...
  │
Month 12    FIRST REMINDER DUE
  │         ├─ Publication search: searches NCBI → finds PMID 12345678
  │         ├─ Creates DatasetStatus:
  │         │    lastReminderDate        = Month 12
  │         │    potentialPublicationId  = 12345678
  │         │    publicationType         = PMID
  │         │    userDismissedPublication = null
  │         └─ Sends reminder: "Action Required: Publication Found..."
  │
Month 13    REMINDER DUE (1 month since last)
  │         ├─ Publication search: returns cached PMID 12345678 (no NCBI call)
  │         ├─ Updates DatasetStatus:
  │         │    lastReminderDate = Month 13 (only field changed)
  │         └─ Sends reminder with same publication citation
  │
Month 13    USER DISMISSES PUBLICATION
  │         (clicks "Dismiss Publication Suggestion")
  │         ├─ Updates DatasetStatus:
  │         │    userDismissedPublication = Month 13
  │         └─ Posts dismissal notice to support thread
  │
Month 14    REMINDER DUE
  │         ├─ Publication search: dismissal is recent (1 month < 3 months)
  │         │    → search deferred, returns null
  │         ├─ Updates DatasetStatus:
  │         │    lastReminderDate = Month 14 (only field changed)
  │         └─ Sends reminder WITHOUT publication info:
  │            "Action Required: Please update the status..."
  │
Month 15    REMINDER DUE
  │         ├─ Publication search: still deferred (2 months < 3 months)
  │         ├─ Updates lastReminderDate
  │         └─ Sends reminder without publication info
  │
Month 16    REMINDER DUE — DEFERRAL EXPIRED
  │         ├─ Publication search: 3 months since dismissal → re-searches NCBI
  │         ├─ Finds same PMID 12345678 (no new paper yet)
  │         ├─ Updates DatasetStatus:
  │         │    userDismissedPublication = Month 16 (reset, deferral restarts)
  │         │    lastReminderDate        = Month 16
  │         └─ Sends reminder without publication info
  │
Month 16    USER REQUESTS 6-MONTH EXTENSION
  │         ├─ Updates DatasetStatus:
  │         │    extensionRequestedDate = Month 16
  │         └─ No reminders sent while extension is valid
  │
  │         ... months 17–21: extension is valid, reminders skipped ...
  │
Month 22    EXTENSION EXPIRED, REMINDER DUE
  │         ├─ Publication search: deferral expired (6 months since Month 16)
  │         │    → re-searches NCBI
  │         │    → finds NEW paper: PMID 99999999
  │         ├─ Updates DatasetStatus:
  │         │    lastReminderDate        = Month 22
  │         │    potentialPublicationId  = 99999999 (new!)
  │         │    publicationType         = PMID
  │         │    publicationMatchInfo    = "ProteomeXchange ID, Author"
  │         │    userDismissedPublication = null (cleared!)
  │         └─ Sends reminder: "Action Required: Publication Found..."
  │            with the NEW publication citation
  │
Month 23    USER MAKES DATA PUBLIC
            └─ Data is now public. No more reminders.
```

---

## Key Design Points

1. **Reminders and publication search are independent.** A dismissed publication does not suppress the reminder — it only suppresses the publication citation in the message.

2. **Publication results are cached.** Once found, a publication is reused from `DatasetStatus` without querying NCBI again. A fresh NCBI search only happens when:
   - No publication has been cached yet
   - A dismissed publication's deferral period has expired

3. **Dismissal is not permanent.** After the configurable deferral period, the system re-searches. This handles the case where a different publication is later associated with the dataset.

4. **All state lives in `DatasetStatus`.** One record per experiment, tracking: last reminder date, extension/deletion requests, cached publication info, and dismissal timestamp.

5. **Only one publication is persisted per dataset.** The pipeline job and admin notification flow save a single best match to `DatasetStatus`. Multiple matches (up to 5) are only displayed on the admin Search Publications page for manual selection — they are not stored.

---
## Example Messages

### When a publication is found

**Subject:** Action Required: Publication Found for Your Data on Panorama Public

> Dear Jane,
>
> We found a paper that appears to be associated with your private data on Panorama Public (https://panoramaweb.org/abc123.url).
>
> **Title:** Quantitative proteomics analysis of tumor samples
>
> **Publication Found:** [Smith J, et al. J Proteome Res. 2025](https://pubmed.ncbi.nlm.nih.gov/12345678)
>
> If this is indeed your paper, congratulations! We encourage you to make your data public so the research community can access it alongside your paper. You can do this by clicking the "Make Public" button in your data folder or by clicking this link: **[Make Data Public](...)**. Please enter 12345678 in the PubMed ID field.
>
> If this paper is not associated with your data please let us know by clicking **[Dismiss Publication Suggestion](...)**.
>
> If you have any questions or need further assistance, please do not hesitate to respond to this message by **[clicking here](...)**.
>
> Thank you for sharing your research on Panorama Public. We appreciate your commitment to open science and your contributions to the research community.
>
> Best regards,
> Panorama Admin

*Note:* The "Please enter ... in the PubMed ID field" line only appears when the publication is from PubMed (not PMC).

### When no publication is found (or publication was dismissed)

**Subject:** Action Required: Status Update for Your Private Data on Panorama Public

> Dear Jane,
>
> We are reaching out regarding your data on Panorama Public (https://panoramaweb.org/abc123.url), which has been private since January 15, 2025.
>
> **Title:** Quantitative proteomics analysis of tumor samples
>
> **Is the paper associated with this work already published?**
> - If yes: Please make your data public by clicking the "Make Public" button in your folder or by clicking this link: **[Make Data Public](...)**. This helps ensure that your valuable research is easily accessible to the community.
> - If not: You have a couple of options:
>   - **Request an Extension** - If your paper is still under review, or you need additional time, please let us know by clicking **[Request Extension](...)**.
>   - **Delete from Panorama Public** - If you no longer wish to host your data on Panorama Public, please click **[Request Deletion](...)**. We will remove your data from Panorama Public. However, your source folder ([/home/Jane/project](...)) will remain intact, allowing you to resubmit your data in the future if you wish.
>
> If you have any questions or need further assistance, please do not hesitate to respond to this message by **[clicking here](...)**.
>
> Thank you for sharing your research on Panorama Public. We appreciate your commitment to open science and your contributions to the research community.
>
> Best regards,
> Panorama Admin

*Note:* The source folder sentence only appears if the source experiment folder can be located.

### When a user dismisses a publication

**Subject:** Publication Suggestion Dismissed - https://panoramaweb.org/abc123.url

> Dear Jane,
>
> Thank you for letting us know that the suggested paper is not associated with your data on Panorama Public.
>
> **Dismissed Publication:** PubMed ID 12345678
> Smith J, et al. J Proteome Res. 2025
>
> We will no longer suggest this paper for your dataset. If you would like to make your data public, you can do so at any time by clicking the "Make Public" button in your data folder, or by clicking this link: **[Make Data Public](...)**.
>
> Best regards,
> Panorama Admin

### When a user requests an extension

**Subject:** Private Status Extended - https://panoramaweb.org/abc123.url

> Dear Jane,
>
> Thank you for your request to extend the private status of your data on Panorama Public. Your data has been granted a 6 month extension. You will receive another reminder when this period ends. If you'd like to make your data public sooner, you can do so at any time by clicking the "Make Public" button in your data folder, or by clicking this link: **[Make Data Public](...)**.
>
> Best regards,
> Panorama Admin

### When a user requests deletion

**Subject:** Data Deletion Requested - https://panoramaweb.org/abc123.url

> Dear Jane,
>
> Thank you for your request to delete your data on Panorama Public. We will remove your data from Panorama Public. Your source folder [/home/Jane/project](...) will remain intact, allowing you to resubmit the data in the future if you wish.
>
> Best regards,
> Panorama Admin

*Note:* If the source experiment folder cannot be located, the message instead says: "We were unable to locate the source folder for this data in your project. The folder at the path [path] may have been deleted."

---