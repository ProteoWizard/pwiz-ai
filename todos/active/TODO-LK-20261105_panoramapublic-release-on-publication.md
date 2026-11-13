# TODO-LK-20261105_panoramapublic-release-on-publication.md

## Branch Information
- **Branch**: `26.7_fb_panoramapublic-release-on-publication`
- **Checkout**: `C:\Users\vsharma\WORK\labkey\release-branch\server\modules\MacCossLabModules`
- **Base**: created off `26.7_fb_panoramapublic-search-newer-data` (PR #689). At 2f91fc59, the tip of PR #689,
  with no commits of its own. Rebase onto `release26.7-SNAPSHOT` after PR #689 merges
- **Created**: 2026-11-05
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `panoramapublic`
- **PR**: (pending)

## Objective

Notify the submitter and lab head when a published paper cites their private data, and make the data public 30
days later. A Panorama Public admin releases the data, or the job releases it when automatic release is turned on.

## Task Checklist

All of the code goes into one PR (decision 10). The groups are in implementation order.

### Completed
- [x] Decisions 1-11
- [x] Draft text for the release notice, weekly reminder, submission checkbox, confirmation note and
      policy-change announcement

### In Progress
- (none)

### Remaining

**Release notice**
- [ ] Treat a match on the permanent URL, DOI or ProteomeXchange ID as a qualifying match. A title or
      author match only notifies the submitter, as it does today
- [ ] On a qualifying match, notify the submitter and lab head that the data will be made public in
      30 days, and save the notice date and the release date
- [ ] No option to keep the data private, and no Request Extension or Request Deletion link

**Weekly reminders during the 30 days**
- [ ] Add the "Reminder frequency when a publication is found (days)" setting, default 7
- [ ] While a qualifying match is pending and not dismissed, post a reminder that names the paper and the
      release date at that frequency, instead of the monthly reminder
- [ ] Skip the first-reminder delay and the stop limit for these reminders. Do not add them to
      `ReminderCount`
- [ ] A dismissed paper returns the dataset to the monthly reminders
- [ ] Tests for the weekly frequency, the skipped delay and stop limit, and the return to monthly after
      a dismissal

**Release by an admin or automatically**
- [ ] Add a view of `DatasetStatus` listing the datasets with a release date, linked from the settings page.
      For each dataset it shows
  - dataset title, Panorama Public permanent URL, ProteomeXchange ID and DOI
  - the publication citation, PMID or PMCID, link, and the identifiers that matched
  - `ReleaseNoticeDate`, `ReleaseDate` and the days remaining
  - submitter and lab head names and email addresses
  - the corresponding author from the publication record, where available
  - a "Release Data" link
- [ ] Move the steps in `MakePublicAction.handlePost` into a helper that `MakePublicAction`, "Release Data"
      and `ReleaseDataJob` all call
- [ ] Add a "Release Data" admin-only action. It makes the data public with the publication details from the
      saved paper filled in, and the "data is public" message goes to the submitter and lab head. It works
      for any private dataset with a saved paper, without waiting for the release date
- [ ] Add the "Make data public automatically on the release date" setting, default off
- [ ] Add `ReleaseDataJob`, queued by `PrivateDataMessageSchedulerJob` after `PrivateDataReminderJob` when
      release notices and automatic release are both on (decision 11)
- [ ] Tests for the qualifying-match rule, the grid, "Release Data", and `ReleaseDataJob`, including a
      dataset that fails to release

**Submission**
- [ ] Add a required agreement checkbox to the submission form when a reviewer account is requested
- [ ] Store the agreement (who agreed, when) with the submission
- [ ] Add the release-on-publication note to the submission confirmation page
- [ ] Add the same note to the message sent when the data is copied to Panorama Public

**Before deployment**
- [ ] Brendan and Mike approve the wording (decision 9)
- [ ] Count query for the datasets that get a release notice on the first run (decision 8)

## Current state

- The publication search (`NcbiPublicationSearchServiceImpl`, `PrivateDataReminderJob`) searches
  PubMed and PubMed Central for private datasets. `PublicationMatch` records which identifiers
  matched - `matchesPanoramaUrl`, `matchesDoi`, `matchesProteomeXchangeId`, `matchesTitle`,
  `matchesAuthor`. `matchesDataIdentifier()` is true for a URL, DOI or ProteomeXchange ID match.
- `NotifySubmitterOfPublicationAction` sends the submitter a request to make the data public.
- `MakePublicAction` is allowed for `AdminPermission` or `PanoramaPublicSubmitterPermission` in the
  Panorama Public copy. It makes the folder public, publishes the DOI, saves the publication details and
  posts a message in the submission thread. It does not announce the data on ProteomeXchange.
  `handlePost` has no transaction. The folder is made public before the DOI is published. If publishing
  the DOI fails, the data is still public, and `notifyDataPublished` reports the DOI error in the message.
- `PrivateDataMessageSchedulerJob` queues `PrivateDataReminderJob` once a day, as the Panorama Public admin
  user.
- LabKey can post messages only to users with accounts on the server. The submitter and lab head have
  accounts. The paper's corresponding author usually does not, so an admin emails that person directly.

From PR #689, which this branch builds on
- Reminders for a dataset with a saved paper the submitter has not dismissed skip the first-reminder
  delay and a current extension. Request Extension is refused while the paper is not dismissed
- A "Publication Found" message for a new paper sets `LastReminderDate` and does not change
  `ReminderCount`
- Reminders stop when `ReminderCount` reaches "Stop reminders after". An extension request or a dismissal
  resets `ReminderCount` to 0
- `PrivateDataReminderJob.postAndRecordMessage` posts the message first and updates `DatasetStatus` only
  after the post returns

## Decisions

Brendan MacLean and Mike MacCoss agreed on the direction. Panorama Public is not expected to keep data
private after the paper is published, and journals and reviewers expect the data to be public at that point.
Submitters of private data agree to this when they submit.

1. **Qualifying match** - a match on the permanent URL, DOI or ProteomeXchange ID starts the release
   notice. A title or author match gets the "Publication Found" message and stays on the monthly
   reminders, which name the paper.
2. **Release notice and release date** - the notice goes to the submitter and lab head through LabKey. The
   admin emails the paper's corresponding author when needed, using the details in the release grid.
   - The release date is the notice date plus "Days until data is released after a paper is found"
     (default 30), stored when the notice is posted. A change to the setting applies only to later
     notices, so a submitter is never released before the date they were given. Its help text says the
     value must match the policy page
   - The messages show the release date, not the words "30 days"
   - The job posts the notice to the dataset's support thread first, then saves `ReleaseNoticeDate` and
     `ReleaseDate`. A dataset has a release date only if the notice is in the support thread
     - If the post fails, no dates are saved, and the next run posts the notice again
     - If saving the dates fails, the notice stays in the support thread, and the next run posts a second
       notice with a later release date
     - The announcements module sends the email to the submitter and lab head from a background thread
       after the post. An email failure does not stop the dates from being saved
3. **Weekly reminders** - while a release notice is pending, a reminder that names the paper and the
   release date replaces the monthly reminder, at "Reminder frequency when a publication is found (days)"
   (default 7). Weekly reminders start when the paper is found, skip the first-reminder delay and the stop
   limit, and do not add to `ReminderCount`. They stop on the release date, with no final reminder.
4. **Dismissal** - a dismissed paper clears the release notice. The dataset returns to the monthly
   reminders and the stop limit. A different qualifying paper found later starts a new notice.
5. **No keep-private option** - the paper is published, so the data is released. The release notice and
   the weekly reminders have no Request Extension or Request Deletion link. A submitter who replies is
   handled by an admin, who decides whether to click "Release Data".
6. **Extensions and deletion requests** - an extension does not pause the notice, the weekly reminders or
   the release, because an extension is for a paper that is not out yet. A deletion request stops
   everything, including the publication search and the release.
7. **After the release date** - nothing more is posted in the submitter's thread except the "data is
   public" message posted when the data is released. Nothing is posted to the admins either.
   - With automatic release off, an admin finds the dataset in the release grid and clicks "Release Data".
     An admin who agrees to more time waits before clicking "Release Data"
   - With automatic release on, `ReleaseDataJob` releases the dataset (decision 11)
   - This PR has no admin action to edit a pending release date
8. **Which datasets** - all private datasets, including those submitted before the agreement checkbox
   existed. "Release data when a paper citing it is found", off by default, turns the release notices on.
   While it is off, the job behaves as in PR #689. Vagisha turns it on after the policy-change
   announcement. A dataset with a saved, undismissed qualifying match and no release notice gets the
   notice on the next run. "Make data public automatically on the release date", also off by default,
   turns on `ReleaseDataJob`. Vagisha turns it on once admins have released the datasets from the first
   notices.
9. **Wording** - Brendan and Mike approve it. Once the code works and the PR is open, they review an
   outline of the plan, the release notice, the text displayed in the UI, and the messages posted to the
   dataset's support thread.
10. **Scope** - one PR, including the weekly reminders, because the release ends them. The 9 datasets
    still private after reminders and direct emails are handled outside this TODO, using "Release Data"
    once it exists. An admin still announces released data on ProteomeXchange. Automating that is a later
    PR.
11. **Automatic release** - a separate pipeline job, `ReleaseDataJob`, not more work in
    `PrivateDataReminderJob`.
    - `PrivateDataMessageSchedulerJob` queues it after `PrivateDataReminderJob` when both settings are on
    - It selects its own datasets from `DatasetStatus` - `ReleaseDate` has passed, the data is still
      private, and there is no deletion request. The two jobs do not depend on their order, because the
      release date is at least 30 days after the notice
    - It releases each dataset through the same helper as "Release Data", with the link and citation from
      the saved paper's PubMed ID
    - A DOI error does not stop the release, as in `MakePublicAction`. The job logs it as a warning, and the
      "data is public" message reports it
    - Any other failure is logged as an error. The job moves on to the next dataset and ends in ERROR. The
      dataset stays private and in the release grid, and the next day's run tries it again

## Design

**Schema** - a new upgrade script `panoramapublic-25.006-25.007.sql` adds two nullable timestamp columns
to `panoramapublic.DatasetStatus`, with the schema version bumped in `PanoramaPublicModule` and both
fields added to `model/DatasetStatus.java`
- `ReleaseNoticeDate` - when the release notice was posted
- `ReleaseDate` - `ReleaseNoticeDate` plus the "days until release" setting at that time (decision 2)

**Settings** - in `PrivateDataReminderSettings` and `privateDataRemindersSettingsForm.jsp`
- "Release data when a paper citing it is found", default off (decision 8)
- "Reminder frequency when a publication is found (days)", default 7 (decision 3)
- "Days until data is released after a paper is found", default 30 (decision 2)
- "Make data public automatically on the release date", default off (decisions 8, 11)

**Job** - in `PrivateDataReminderJob`, only when the checkbox is on
- A qualifying match is `PublicationMatch.matchesDataIdentifier()`. An author or title match keeps the
  "Publication Found" message
- A new `MessageType.RELEASE_NOTICE` is posted when a qualifying match is found, the submitter has not
  dismissed that paper, and `ReleaseNoticeDate` is null. This includes a saved qualifying match from
  before the checkbox was turned on (decision 8), and a saved author or title match found again on an
  identifier
- The notice sets `ReleaseNoticeDate`, `ReleaseDate` and `LastReminderDate`. `ReminderCount` does not change
- While `ReleaseDate` is in the future, a weekly reminder replaces the monthly one, timed from
  `LastReminderDate`. No first-reminder delay, no stop limit, not counted in `ReminderCount`
- `getReminderDecision` checks for a weekly reminder before the extension check (decision 6). A deletion
  request still excludes the dataset (decision 6)
- On and after `ReleaseDate`, nothing more is posted to the submitter (decisions 3, 7)

**Dismiss** - `DismissPublicationSuggestionAction` also clears `ReleaseNoticeDate` and `ReleaseDate`. A
different qualifying paper found later starts a new notice.

**Release** (decisions 7, 11)
- A `DatasetStatus` view of the datasets with a release date, with a "Release Data" link
- A helper with the steps now in `MakePublicAction.handlePost`, called by `MakePublicAction`, the new
  admin-only "Release Data" action and `ReleaseDataJob`
- `ReleaseDataJob` in the `pipeline` package, queued by `PrivateDataMessageSchedulerJob`

**Messages** - in `PanoramaPublicNotification`, next to `postPrivateDataReminderMessage`. The text is under
"Draft text". The "Cited as" line comes from the saved match info.

**Implementation order**
1. Schema, model and settings
2. Job logic and Dismiss, with unit tests for the decision logic written first
3. Messages
4. The release grid, the shared release helper and "Release Data"
5. `ReleaseDataJob` and the automatic release setting
6. Selenium - extend `PrivateDataReminderTest` with the mock NCBI service, the checkbox on and "days
   until release" set to 0, with automatic release off and on

## Draft text (Brendan and Mike to approve)

### Confirmation note (submission page and copy message)

Data on Panorama Public is expected to become public when the associated paper is published. Journals and
reviewers expect the same. While your data is private, we will periodically search PubMed and PubMed
Central for a paper that cites the Panorama Public permanent URL, the DOI, or the ProteomeXchange ID
assigned to your data. If we find one, we will notify you and make your data public 30 days later.

### Submission checkbox

I understand that this data will be made public when a paper citing it is published.

### Release notice

Square brackets are values the code fills in.

Title: Action Required: Your Data on Panorama Public Will Be Made Public on [release date]

> Dear [submitter],
>
> We found a paper that cites your private data on Panorama Public ([short URL]).
>
> **Title:** [dataset title]
> **Publication Found:** [citation, linked]
> **Cited as:** [the identifiers that matched, for example ProteomeXchange ID PXD012345]
>
> Congratulations on your publication! Data on Panorama Public is made public when the associated paper
> is published, so the research community can access it alongside your paper. **Your data will be made
> public on [release date].**
>
> You do not need to wait until then. You can make your data public now by clicking the "Make Public"
> button in your data folder or by clicking this link: **Make Data Public**. [Please enter [PMID] in the
> PubMed ID field.]
>
> If this paper is not associated with your data, please let us know by clicking **Dismiss Publication
> Suggestion**, and your data will stay private.
>
> [the existing closing - questions link, thank you, Best regards]

No Request Extension link (decision 5) and no Request Deletion link. A submitter who wants either
replies to the message. Once the policy page is updated, the "made public when the associated paper is
published" sentence links to it.

### Weekly reminder

Title: Reminder: Your Data on Panorama Public Will Be Made Public on [release date]

> Dear [submitter],
>
> This is a reminder that your private data on Panorama Public ([short URL]) will be made public on
> **[release date]**, because a paper that cites it has been published.
>
> [the Title, Publication Found and Cited as lines, the Make Data Public paragraph, the Dismiss paragraph
> and the closing, the same as in the release notice]

### Policy-change announcement

We are updating the Panorama Public data release policy. Starting [date], when we find a published paper
that cites the Panorama Public permanent URL, DOI, or ProteomeXchange ID of a private dataset, we will
notify the submitter and lab head and make the data public 30 days later. This matches what journals and
reviewers expect once a paper is published. If you have questions, contact us at panorama@proteinms.net.

## Deployment on PanoramaWeb

1. Update the Panorama Public data release policy page.
2. Send the policy-change announcement to every submitter with private data.
3. After the announcement date, run the count query for the datasets that get a release notice on the
   first run (decision 8).
4. Check "Release data when a paper citing it is found" on the Private Data Reminder Settings page. From
   then on the process applies to all private datasets, not only new ones (decision 8).
5. Leave "Make data public automatically on the release date" unchecked. Admins release data from the
   release grid. Check it once the datasets from the first notices are public (decision 8).

## Known limitations, accepted
- With automatic release on, there is no way to hold back one dataset past its release date
- A dataset that fails to release automatically is tried again on every daily run until an admin fixes it

## Progress Log

### 2026-11-05 to 2026-11-12
- Decided the policy and the design (decisions 1-11) and wrote the draft text. No code yet
- Created the branch off PR #689, now at 2f91fc59
