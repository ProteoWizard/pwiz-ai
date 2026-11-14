# TODO-LK-20260831_panoramapublic-search-newer-data.md

## Branch Information
- **Branch**: `26.11_fb_panoramapublic-search-newer-data`, renamed from `26.7_fb_panoramapublic-search-newer-data`.
  Deleted after the merge
- **Checkout**: `C:\Users\vsharma\WORK\labkey\release-branch\server\modules\MacCossLabModules`
- **Base**: `release26.11-SNAPSHOT`
- **Created**: 2026-08-31
- **Status**: Merged into `release26.11-SNAPSHOT` as 047c6dca on 2026-11-13. Testing on PWeb-DR is next
- **GitHub Issue**: (none)
- **Module**: `panoramapublic`
- **PR**: [#692](https://github.com/LabKey/MacCossLabModules/pull/692). Replaces
  [#689](https://github.com/LabKey/MacCossLabModules/pull/689), which targeted 26.7 and has Josh Eckels'
  review and the replies
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
- [x] Josh Eckels' review. Labels added for the form inputs, and his other two comments answered
- [x] Moved to 26.11 as PR #692
- [x] Josh Eckels approved PR #692, and it was squash-merged into `release26.11-SNAPSHOT` as 047c6dca

### Remaining
- [ ] Test on PWeb-DR for a week, then deploy on PanoramaWeb, following "Deployment on PanoramaWeb"

## Work done

Commits on PR #692, squash-merged as 047c6dca. All but the last two were also on #689
- bd0409c9 - the feature
- 46b0888e - code review fixes
- abec0b1d - Copilot fixes
- 521bf311 - message posted before `DatasetStatus` is updated
- 986fab47 - reminder job and submitter action updates to `DatasetStatus` no longer overwrite each other
- 5b3137aa - `processExperiment` refactored, and the saved paper named in reminders
- 8bc6015b - page title on the error page of the dataset status actions
- acc48264 - reminders and extensions for a dataset with a saved paper
- 2f91fc59 - Selenium test for a publication found for a dataset at the reminder limit
- c1c5eda7 - labels for the inputs on the settings and Send Reminders pages
- 6ff7c966 - merge of `release26.11-SNAPSHOT`, which TeamCity needed to start the tests

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

Run these steps on PWeb-DR first, after its data is synced from PanoramaWeb, and test there for a week
before deploying on PanoramaWeb. The changes ship in 26.11.

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
6. Set the first publication search dates. Every private dataset has an empty `LastPublicationSearchDate`
   after the upgrade, so the first run would search all of them, 80 on 2026-11-13. Save the script below
   to a file and run it with `frequency_months` set to the value from step 5, and `user_id` set to a site
   admin's user ID.
   ```
   psql -d <database> -v frequency_months=1 -v user_id=<site admin user id> -f <script file>
   ```
   - A row with a `LastReminderDate` in the past month gets that date, because the job searched when it
     posted that reminder. The reminders for the datasets submitted in 2020 to 2025 were posted one year
     per day in November 2026
   - Any other dataset, including one with no `DatasetStatus` row, gets a random date that makes its first
     search due on one of the next 30 days
   - It ends with ROLLBACK. Check the number of datasets due each day, then change it to COMMIT and run
     it again
   ```sql
   \set ON_ERROR_STOP on

   BEGIN;

   -- The current version of each private dataset in the Panorama Public project, with no deletion request.
   CREATE TEMP TABLE targets ON COMMIT DROP AS
   WITH RECURSIVE pp_folders AS (
       SELECT j.Project AS EntityId FROM panoramapublic.Journal j WHERE j.Name = 'Panorama Public'
       UNION ALL
       SELECT c.EntityId FROM core.Containers c JOIN pp_folders p ON c.Parent = p.EntityId
   )
   SELECT ea.Id AS ExperimentAnnotationsId,
          ds.Id AS DatasetStatusId,
          CASE WHEN ds.LastReminderDate > now() - make_interval(months => :frequency_months)
               THEN ds.LastReminderDate
               ELSE now() - make_interval(months => :frequency_months)
                    + make_interval(days => floor(random() * 30)::int)
          END AS SearchDate
   FROM panoramapublic.ExperimentAnnotations ea
   JOIN pp_folders f ON f.EntityId = ea.Container
   LEFT JOIN panoramapublic.DatasetStatus ds ON ds.ExperimentAnnotationsId = ea.Id
   WHERE ea.DataVersion = (SELECT MAX(v.DataVersion) FROM panoramapublic.ExperimentAnnotations v
                           WHERE v.SourceExperimentId = ea.SourceExperimentId)
     AND NOT EXISTS (SELECT 1 FROM core.RoleAssignments ra
                     WHERE ra.ResourceId = ea.Container
                       AND ra.UserId = -3 -- Guests
                       AND ra.Role = 'org.labkey.api.security.roles.ReaderRole')
     AND ds.DeletionRequestedDate IS NULL
     AND ds.LastPublicationSearchDate IS NULL;

   UPDATE panoramapublic.DatasetStatus ds
   SET LastPublicationSearchDate = t.SearchDate, Modified = now(), ModifiedBy = :user_id
   FROM targets t
   WHERE ds.Id = t.DatasetStatusId;

   INSERT INTO panoramapublic.DatasetStatus
       (ExperimentAnnotationsId, LastPublicationSearchDate, Created, CreatedBy, Modified, ModifiedBy)
   SELECT ExperimentAnnotationsId, SearchDate, now(), :user_id, now(), :user_id
   FROM targets
   WHERE DatasetStatusId IS NULL;

   -- Datasets due for their first search on each day.
   SELECT (SearchDate + make_interval(months => :frequency_months))::date AS first_search_due,
          count(*) AS datasets
   FROM targets
   GROUP BY 1
   ORDER BY 1;

   ROLLBACK;
   ```
7. Count the private datasets that get a reminder naming their saved paper on the first run, because the
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
8. Turn the daily reminder schedule back on.

If a reminder job runs before step 3, each of the 18 datasets gets one more reminder, and the backfill
still stops them. Datasets whose extension has expired start at 0 and get a few more reminders before
stopping.

## Known limitations, accepted
- A submitter who replies in the thread without using Make Public, Request Extension or Request
  Deletion is not detected, and reminders stop after the limit. Replies are rare, and an admin answers
  and usually asks the submitter to request an extension or deletion
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
  private
- Committed and pushed 2f91fc59, the Selenium test for a dataset at the reminder limit
- PR #689 marked ready for review
- The TeamCity build for 2f91fc59 passed

### 2026-11-13
- Josh Eckels approved PR #689 with three comments. Committed and pushed c1c5eda7, the input labels.
  `PrivateDataReminderTest`, `PublicationSearchTest` and `NcbiApiKeyTest` pass
- Moved to 26.11 so it can be tested on PWeb-DR first. Renamed the branch to
  `26.11_fb_panoramapublic-search-newer-data`, which closed #689, and opened PR #692
- Merged `release26.11-SNAPSHOT` into the branch in 6ff7c966, so the TeamCity tests would start. They
  passed
- Josh Eckels approved PR #692. Squash-merged into `release26.11-SNAPSHOT` as 047c6dca and deleted the branch
