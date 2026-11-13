# TODO-LK-20260831_panoramapublic-search-newer-data.md

## Branch Information
- **Branch**: `26.7_fb_panoramapublic-search-newer-data`
- **Checkout**: `C:\Users\vsharma\WORK\labkey\release-branch\server\modules\MacCossLabModules`
- **Base**: `release26.7-SNAPSHOT`
- **Created**: 2026-08-31
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `panoramapublic`
- **PR**: [#689](https://github.com/LabKey/MacCossLabModules/pull/689) (ready for review)
- **Related**: builds on the publication search in PR #606 and the failure reporting in PR #675. Comes
  before `TODO-LK-20261105_panoramapublic-release-on-publication.md`, which needs the search to run for
  every private dataset.

## Objective

Search every private dataset for a publication on its own schedule, and stop reminders after a set number
with no response.

## Task Checklist

### Completed
- [x] Search every private dataset at the publication search frequency, whether or not a reminder is due
- [x] Reminder limit, with `ReminderCount`, the Stopped Reminders grid and Ignore Reminder Limit
- [x] Reminders for a saved paper skip the first-reminder delay and a current extension. Request
      Extension is refused while the paper is not dismissed
- [x] Post each message before `DatasetStatus` is updated
- [x] `/code-review` and `lk-review` findings, and the Copilot review, which has no open issues
- [x] PR #689 ready for review
- [x] TeamCity build for 2f91fc59 passes

### Remaining
- [ ] Human review, and merge into `release26.7-SNAPSHOT`
- [ ] Deploy on PanoramaWeb, following "Deployment on PanoramaWeb"

## Work done

Commits on PR #689
- bd0409c9 - the feature
- 46b0888e - code review fixes
- abec0b1d - Copilot fixes
- 521bf311 - message posted before `DatasetStatus` is updated
- 986fab47 - reminder job and submitter action updates to `DatasetStatus` no longer overwrite each other
- 5b3137aa - `processExperiment` refactored, and the saved paper named in reminders
- 8bc6015b - page title on the error page of the dataset status actions
- acc48264 - reminders and extensions for a dataset with a saved paper
- 2f91fc59 - Selenium test for a publication found for a dataset at the reminder limit

- **Search split from the reminder decision.** `PrivateDataReminderJob.processExperiment` searches
  every dataset that is not excluded (public, old version, pending resubmission, deletion request) and
  can be sent a message, whether or not a reminder is due. `getPaper` picks the paper a message names.
  `postPublicationNotification` posts a "Publication Found" message naming the paper if a reminder is
  due or the paper is new, and `postPrivateDataReminder` posts a reminder with no paper if one is due.
  Every private dataset that is the current version is searched at most once per
  `publicationSearchFrequency`, default changed from 3 to 1 month.
- **Saved paper named with search disabled.** A due reminder names a saved paper the submitter has not
  dismissed, even when publication search is disabled.
- **Schema** `panoramapublic-25.005-25.006.sql` adds `DatasetStatus.LastPublicationSearchDate`, set only
  when a search completes, and `ReminderCount`.
- **Paper found before a reminder is due** posts the existing "Publication Found" message. It sets
  `LastReminderDate` and does not change `ReminderCount`.
- **Reminder limit.** "Stop reminders after (number of reminders)", default 6, empty means never.
  Datasets at the reminder limit are listed at WARN in the job log and in the "Stopped Reminders" grid
  (`PrivateDataNoResponse` query) linked from the settings page. "Ignore Reminder Limit" on the Send
  Reminders page overrides it.
- **Author or title matches** are searched again at the search frequency and replaced by an identifier
  match, including the same paper newly matched on an identifier.
- **Dismissed paper.** A match on the paper the submitter dismissed is not posted again.
  `processExperiment` reads `DatasetStatus` again after the search to choose the message type.
- **Message posted before `DatasetStatus` is updated** (`PrivateDataReminderJob.postAndRecordMessage`),
  with no transaction open. A failed post saves nothing to `DatasetStatus`, so the next run posts the message
  again. The reasoning is in `ai/docs/labkey/panoramapublic/private-data-reminders-overview.md`.
- **Unexpected states.** A dataset with no submission, submitter or short URL is reported as an error on
  every run. A missing support thread is a warning.
- **Saved paper.** Reminders for a dataset with a saved paper the submitter has not dismissed skip the
  first-reminder delay and a current extension. Request Extension is refused for such a dataset, and the
  page shows the paper with a Dismiss Publication Suggestion link.
- **Page title** on the error page of Request Extension, Request Deletion and Dismiss Publication
  Suggestion (`UpdateDatasetStatusAction.getFailView`).
- **Tests.** 72 PanoramaPublic unit tests, `PublicationSearchTest`, `PrivateDataReminderTest` and
  `NcbiApiKeyTest` pass. `PrivateDataReminderTest` uses the mock NCBI service to check that a dataset at
  the reminder limit still gets "Publication Found" messages. The mock NCBI helpers are in
  `PanoramaPublicBaseTest`.

## Decisions

- **`ReminderCount`, not a first-reminder date** - a date rule counts months even when the job did not
  run. The count changes only as follows.
  - A reminder posted by the job adds 1, from the scheduled run or the Send Reminders page
  - An extension request or a dismissed publication resets it to 0
  - A "Publication Found" notice and Notify Submitter do not change it
  - A due reminder that also names a newly found paper counts as a reminder. One message per dataset
    per run
- **Datasets at the reminder limit are still searched**, and get a "Publication Found" notice for a newly found
  paper.
- **A saved identifier match is final** and is not searched again.
- **No first-reminder delay or extension for a saved paper.** A dataset with a saved paper the submitter
  has not dismissed gets reminders at the reminder frequency after the "Publication Found" notice, even
  while an extension granted before the paper was found is current. The stop limit still applies.
  Request Extension is refused while the saved paper is not dismissed. A paper found
  2 months after the copy gets the notice at month 2 and a reminder at month 3. A paper found for the
  first time still gets the notice, which does not add to `ReminderCount`. A dismissal brings the delay
  back. The release-on-publication branch replaces these with weekly reminders for a URL, DOI or
  ProteomeXchange ID match while release notices are turned on
- **Override** - "Ignore Reminder Limit" adds 1 to the count. The frequency, extension and first-reminder
  delay checks still apply.
- **Backfill by hand on PanoramaWeb**, not in the upgrade script, because the cutoff comes from
  PanoramaWeb's reminder history. `ReminderCount = 6` for rows with `LastReminderDate`, no extension or
  deletion request and `Created` before 2026-05-05. This stops the 18 private datasets reminded since
  2025-09-28.

## Deployment on PanoramaWeb

1. Before deploying, check that the daily reminder schedule is off on the Private Data Reminder
   Settings page.
2. After the upgrade, and before any reminder job runs, check the rows the backfill will change.
   On the 2026-11-05 and 2026-11-12 exports this returns 68 rows. 18 are for private datasets. The other 50
   are for datasets made public after a reminder, and the job and the Stopped Reminders grid ignore them.
   ```sql
   SELECT COUNT(*) FROM panoramapublic.DatasetStatus
       WHERE LastReminderDate IS NOT NULL
         AND ExtensionRequestedDate IS NULL
         AND DeletionRequestedDate IS NULL
         AND Created < '2026-05-05';
   ```
3. Run the backfill.
   ```sql
   UPDATE panoramapublic.DatasetStatus SET ReminderCount = 6
       WHERE LastReminderDate IS NOT NULL
         AND ExtensionRequestedDate IS NULL
         AND DeletionRequestedDate IS NULL
         AND Created < '2026-05-05';
   ```
4. Open the Stopped Reminders grid and check that it lists the 18 datasets.
5. On the Private Data Reminder Settings page, change "Publication search frequency (months)" from 3
   to 1. PanoramaWeb has 3 saved, so the new default does not apply there.
6. Count the private datasets that get a reminder naming their saved paper on the first run, because the
   first-reminder delay and a current extension no longer apply to them. A paper saved with Notify on the
   Search Publications page can be on a dataset in either period. Set the two intervals to "Delay until
   first reminder" and "Extension duration", and the limit to "Stop reminders after", from the settings
   page. A dataset is private when site guests have no Reader role on its folder. On the 2026-11-12 export
   this returns 0.
   ```sql
   SELECT COUNT(*) FROM panoramapublic.DatasetStatus ds
       JOIN panoramapublic.ExperimentAnnotations ea ON ea.Id = ds.ExperimentAnnotationsId
       WHERE ds.PotentialPublicationId IS NOT NULL
         AND ds.UserDismissedPublication IS NULL
         AND ds.DeletionRequestedDate IS NULL
         AND ds.ReminderCount < 6
         AND NOT EXISTS (SELECT 1 FROM core.RoleAssignments ra
                         WHERE ra.ResourceId = ea.Container
                           AND ra.UserId = -3
                           AND ra.Role = 'org.labkey.api.security.roles.ReaderRole')
         AND (ea.Created > NOW() - INTERVAL '12 months'
              OR ds.ExtensionRequestedDate > NOW() - INTERVAL '6 months');
   ```
7. Turn the daily reminder schedule back on.

If a reminder job runs before step 3, each of the 18 datasets gets one more reminder, and the backfill
still stops them. Datasets whose extension has expired start at 0 and get a few more reminders before
stopping. Repeat steps 2 to 4 on any staging copy of PanoramaWeb.

## Known limitations, accepted
- A submitter who replies in the thread without using Make Public, Request Extension or Request
  Deletion is not detected, and reminders stop after the limit
- A failed `DatasetStatus` update after a successful post sends the message a second time on the next
  run. An update that fails on every run sends it on every run, because `LastReminderDate` and
  `ReminderCount` never change. The job ends in ERROR each time
- A failed post also leaves `LastPublicationSearchDate` unset, so the next run searches NCBI again for
  that dataset. Saving the search date before the post would lose a newly found paper, which is saved
  only with the message

## Progress Log

### 2026-11-05 to 2026-11-07
- Implemented the search split, the two `DatasetStatus` columns and the reminder limit. Committed
  bd0409c9 and the code review fixes in 46b0888e

### 2026-11-09
- Opened draft PR #689. Fixed two Copilot comments in abec0b1d

### 2026-11-10 to 2026-11-11
- Committed 521bf311, 986fab47, 5b3137aa, 8bc6015b and acc48264, and pushed them. The Copilot re-review
  reported no open issues. Updated the PR description

### 2026-11-12
- The TeamCity build for acc48264 passed
- Checked the deployment steps against a PanoramaWeb export. The backfill matches 68 rows, 18 of them
  private. Removed the step that spread the first publication searches, because a search of the 49
  private datasets submitted in 2026 found one paper. Fixed the join in the saved-paper count query
- Committed and pushed 2f91fc59, the Selenium test for a dataset at the reminder limit
- PR #689 marked ready for review
- The TeamCity build for 2f91fc59 passed
