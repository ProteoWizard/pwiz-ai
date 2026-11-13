# Private Data Reminders — Overview

**Module:** panoramapublic

---

## Purpose

When researchers submit data to Panorama Public, the data is initially kept private. The Private Data Reminder
system periodically reminds submitters to make their data public, and searches PubMed and PubMed Central for a paper
associated with the data.

The behavior described here is from the `26.7_fb_panoramapublic-search-newer-data` branch. The planned release of
private data when a paper cites it is in `ai/todos/active/TODO-LK-20261105_panoramapublic-release-on-publication.md`.

---

## Messages

The job posts two kinds of message to the dataset's support thread, told apart by their title.

| Message | Title | Links |
|---|---|---|
| Private data reminder | Action Required: Status Update for Your Private Data on Panorama Public | Make Data Public, Request Extension, Request Deletion |
| "Publication Found" message | Action Required: Publication Found for Your Data on Panorama Public | Make Data Public, Dismiss Publication Suggestion |

A "Publication Found" message names a paper and is posted in two cases.
- **For a new paper.** The search found a paper that is new for the dataset, and no reminder is due. It does not
  change `ReminderCount` (`MessageType.PUBLICATION_FOUND`)
- **As a reminder.** A reminder is due and the dataset has a paper, newly found or saved and not dismissed. It adds 1
  to `ReminderCount` (`MessageType.REMINDER`)

In this document "a reminder" means a private data reminder or a "Publication Found" reminder.

---

## How It Works

`PrivateDataMessageScheduler` runs `PrivateDataReminderJob` daily at the configured time. An admin can also run it
for selected datasets from the Send Reminders page. The job processes each private dataset in turn
(`processExperiment`).

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. CHECK (getTarget). The dataset is skipped, with no NCBI search       │
│    and no message, when                                                 │
│    • the data is public                                                 │
│    • it is not the current version of the experiment                    │
│    • a re-submission is pending                                         │
│    • the submitter requested deletion                                   │
│    • it has no submission, support thread, submitter or short URL       │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. PUBLICATION SEARCH (searchForPublication), if enabled and due.       │
│    Runs whether or not a reminder is due. See "Publication              │
│    Search" below                                                        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. READ AGAIN. The experiment and DatasetStatus are read again          │
│    and the checks for public data, version, re-submission and           │
│    deletion are made again                                              │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. MESSAGE                                                              │
│    • PAPER (getPaper). A new paper from the search, otherwise the       │
│      saved paper unless the submitter dismissed it                      │
│    • Paper, reminder due         → "Publication Found" reminder         │
│    • Paper new, reminder not due → "Publication Found" for a new paper  │
│    • No paper, reminder due      → private data reminder                │
│    • Otherwise                   → nothing                              │
└─────────────────────────────────────────────────────────────────────────┘
```

A reminder is due when `getReminderDecision` finds none of the following.
- an extension is current
- reminders have stopped (`ReminderCount` at or above the stop setting)
- a message was posted within the reminder frequency
- the first-reminder delay since the copy has not passed

For a dataset with a saved paper the submitter has not dismissed, the extension and first-reminder delay checks are
skipped. A paper is saved when the first "Publication Found" message naming it is posted, so "Publication Found"
reminders follow that message at the reminder frequency, even during an extension granted before the paper was
found. An extension cannot be requested while the dataset has a saved paper the submitter has not dismissed. A
paper found 2 months after the copy gets a "Publication Found" message for a new paper at month 2 and a "Publication
Found" reminder at month 3.

With publication search disabled, reminders are still posted when due. A dataset with a saved paper the submitter
has not dismissed gets "Publication Found" reminders, and any other dataset gets private data reminders. No
"Publication Found" message for a new paper is posted, because no new paper is found.

Both kinds of reminder add 1 to `ReminderCount`, and a "Publication Found" message for a new paper does not. All of
them set `LastReminderDate`. A completed search sets `LastPublicationSearchDate`, saved with the message if one is
posted.

If the job is cancelled, it stops before the next dataset.

The message is posted first, with no transaction open, and `DatasetStatus` is updated only after the post returns
(`PrivateDataReminderJob.postAndRecordMessage`). Posting sends email right away, and with no transaction open the
message is saved before the email is sent. If the post throws, `DatasetStatus` is not created or updated, so
`LastReminderDate`, `ReminderCount`, a newly found paper and `LastPublicationSearchDate` keep their earlier values.
The next run posts the message again. The submitter gets the message a second time if the post saved it before
throwing, or if the `DatasetStatus` update fails after the post.

---

## Reminder Count and Stopping Reminders

`DatasetStatus.ReminderCount` counts the reminders posted since the submitter last responded.

| Event | `ReminderCount` | `LastReminderDate` |
|---|---|---|
| Private data reminder posted by the job (scheduled or Send Reminders page) | +1 | set |
| "Publication Found" reminder posted by the job, naming a saved or newly found paper | +1 | set |
| "Publication Found" message for a new paper posted by the job | unchanged | set |
| Notify Submitter on the admin Search Publications page | unchanged | set |
| Extension request | reset to 0 | unchanged |
| Dismiss publication | reset to 0 | unchanged |

A "Publication Found" message for a new paper sets `LastReminderDate`. The next reminder is posted one reminder
frequency later, one month by default, unless reminders have stopped. A current extension does not hold it back.

When `ReminderCount` reaches "Stop reminders after (number of reminders)" (default 6), reminders stop. An empty
setting means reminders never stop. The publication search continues for a dataset at the reminder limit, and a
newly found paper gets a "Publication Found" message for a new paper, the same as for any other dataset.

The job log lists the datasets at the reminder limit at WARN. The summary at the end of the log gives their number
in a separate line, split into skipped and sent a "Publication Found" message for a new paper. They are also
counted in the processed and skipped totals.

The "Stopped Reminders" link on the Private Data Reminder Settings page opens the `PrivateDataNoResponse` query
filtered to `ReminderCount` at or above the setting. The query lists only the current version of each dataset.

The "Ignore Reminder Limit" checkbox on the Send Reminders page posts a reminder to a dataset at the reminder
limit. The reminder adds 1 to the count. The extension and reminder frequency checks still apply, and the
first-reminder delay applies as described under "How It Works".

---

## What Submitters Can Do

The links in each message are listed under "Messages".

| Action | What happens |
|---|---|
| **Make data public** | Data becomes publicly accessible |
| **Request extension** | Private status extended by N months (configurable, default 6). Resets `ReminderCount`. Refused while the dataset has a saved paper the submitter has not dismissed (`DatasetStatus.hasPublicationSuggestion`) |
| **Request deletion** | Flags the dataset for removal. Reminders and searches stop |
| **Dismiss publication** | If a wrong paper was suggested, marks it as dismissed. Resets `ReminderCount` |

---

## Publication Search

`PublicationMatch` records what the paper matched on. A match on the ProteomeXchange ID, Panorama Public URL or DOI
is an identifier match (`PublicationMatch.matchesDataIdentifier`). A match on author or title only is weaker.

| Saved on `DatasetStatus` | What the job does |
|---|---|
| No paper | Searches once every publication search frequency (default 1 month) |
| Author or title match | Searches at the same frequency. An identifier match replaces the saved paper and gets a "Publication Found" message, including the same paper newly matched on an identifier. Otherwise the saved paper is kept |
| Identifier match | Uses the saved paper. No further search |
| Dismissed paper | Searches again one search frequency after the dismissal, then once every search frequency. A different paper clears the dismissal and gets a "Publication Found" message. `UserDismissedPublication` keeps the date of the dismissal |

Other rules

- A dataset with no submission request, support message thread, submitter or short URL is reported on every run and
  not searched. The Search Publications page linked from the settings page searches any private dataset by hand.
- `LastPublicationSearchDate` is set only when a search completes. A search that fails is retried on the next run.
  An unexpected error during a search is counted as a failed search. A reminder that is due after a failed search
  is a "Publication Found" reminder naming the saved paper, unless the submitter dismissed it.
- A run from the Send Reminders page with "Search for Publications" checked ignores the last search date.
- The job stops searching for the rest of a run when NCBI fails for several datasets in a row, and reports the
  datasets it skipped.

---

## Example Timeline

Consider a dataset submitted to Panorama Public with PXD ID `PXD012345`, with the default settings.

```
Month 0     Dataset copied to Panorama Public (private)
  │         No DatasetStatus record exists yet.
  │
Month 0     FIRST SCHEDULED RUN AFTER THE COPY
  │         ├─ No reminder (12-month delay)
  │         ├─ Publication search: nothing found
  │         └─ Creates DatasetStatus with LastPublicationSearchDate = Month 0
  │
  │         ... searched once a month, nothing found ...
  │
Month 4     SEARCH FINDS PMID 12345678, matched on author and title
  │         ├─ Updates DatasetStatus:
  │         │    potentialPublicationId  = 12345678
  │         │    publicationMatchInfo    = "Author, Title"
  │         │    lastReminderDate        = Month 4
  │         │    reminderCount           = 0
  │         └─ Posts a "Publication Found" message for a new paper
  │
Month 5     USER DISMISSES PUBLICATION, before a reminder naming the paper is due
  │         └─ userDismissedPublication = Month 5. The first-reminder delay applies again
  │
Month 6     SEARCH AGAIN (1 month after the dismissal)
  │         └─ Finds the same paper. LastPublicationSearchDate = Month 6
  │
  │         ... searched once a month, same paper ...
  │
Month 12    FIRST REMINDER DUE
  │         ├─ reminderCount = 1, lastReminderDate = Month 12
  │         └─ Posts a private data reminder (paper was dismissed)
  │
Month 13-17 MONTHLY PRIVATE DATA REMINDERS. reminderCount reaches 6 at Month 17
  │
Month 18    REMINDERS STOPPED
  │         ├─ No reminder. The job log lists the dataset at WARN
  │         └─ The search continues once a month
  │
Month 20    SEARCH FINDS PMID 99999999, matched on "ProteomeXchange ID"
  │         ├─ Clears the dismissal, saves the new paper
  │         └─ Posts a "Publication Found" message for a new paper. reminderCount stays 6
  │
Month 21    USER MAKES DATA PUBLIC
            └─ Data is now public. No more reminders or searches.
```

---

## Settings

On the Private Data Reminder Settings page in the admin console.

| Setting | Default | Effect |
|---|---|---|
| Enable private data reminder | off | Schedules the daily job |
| Reminder time | 8:00 AM | When the daily job runs |
| Delay until first reminder (months) | 12 | No reminder until the data has been private this long. The search does not wait. A dataset with a saved paper the submitter has not dismissed does not wait |
| Reminder frequency (months) | 1 | Minimum time between messages to one dataset, including a "Publication Found" message for a new paper |
| Extension duration (months) | 6 | No reminders while an extension is current. The search still runs. A dataset with a saved paper the submitter has not dismissed still gets "Publication Found" reminders |
| Stop reminders after (number of reminders) | 6 | Reminders without a response before they stop. Empty means never |
| Enable publication search | off | Searches PubMed Central and PubMed for each private dataset |
| Publication search frequency (months) | 1 | Time between searches for one dataset, including after a dismissal |
| NCBI API key | none | Raises the NCBI request rate limit. Stored encrypted |

---

## Key Design Points

1. **The search does not depend on the reminder decision.** A paper published before the first reminder, during an
   extension or after reminders stop is still found.

2. **Reminders stop by count, not by date.** The count goes up only when a reminder is posted, so a period when the
   job did not run cannot stop reminders early. An extension request or a dismissal starts the count again.

3. **One message per dataset per run.** A reminder that is due is a "Publication Found" reminder when the dataset has
   a paper. A "Publication Found" message for a new paper sets `LastReminderDate`, and the next reminder is posted
   one reminder frequency later.

4. **An author or title match does not end the search.** Only an identifier match is final.

5. **All state lives in `DatasetStatus`.** One record per experiment, tracking the last reminder date, reminder
   count, extension and deletion requests, the saved publication, the dismissal date and the last search date.
   A search that posts no message still creates the record, with only `LastPublicationSearchDate` set, so most
   private datasets have one. To find datasets that were sent a reminder, filter on `ReminderCount` or
   `LastReminderDate`, not on whether a record exists.

6. **Only one publication is saved per dataset.** The pipeline job and admin notification flow save a single best
   match to `DatasetStatus`. Multiple matches (up to 5) are only displayed on the admin Search Publications page for
   manual selection. They are not stored.

---
## Example Messages

### "Publication Found" message, for a new paper or as a reminder

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

### Private data reminder, when the dataset has no paper or the paper was dismissed

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
