# Panorama Public Module — Coding Patterns

Quick reference for panoramapublic-specific patterns. For general LabKey module patterns (actions, forms, DOM builder, unit tests, Selenium tests), see [labkey-modules-coding-patterns.md](../labkey-modules-coding-patterns.md).

For architecture and table layout see `panoramapublic-module.md`.

## Form Class Hierarchy

```
ViewForm                      — base (see general patterns doc)
  └─ IdForm                   — adds int id getter/setter (defined in PanoramaPublicController)
       └─ ExperimentIdForm    — adds lookupExperiment() → ExperimentAnnotations
```

- `IdForm` binds `?id=123` or a hidden `<input name="id">` automatically.
- `ExperimentIdForm.lookupExperiment()` calls `ExperimentAnnotationsManager.get(getId())`.

## Experiment Lookup Helpers

```java
// Inside an action — validates experiment exists and is in the right container
ExperimentAnnotations expt = getValidExperiment(form, getContainer(), getViewContext(), errors);

// Direct lookup by ID (no container check)
ExperimentAnnotations expt = ExperimentAnnotationsManager.get(form.getId());
```

### `ensureCorrectContainer()`

`getValidExperiment()` calls `ensureCorrectContainer()` — a method in `PanoramaPublicController` that verifies the request's container matches the experiment's container. This ensures permission checks are performed against the correct container. If the containers don't match, it throws a `RedirectException` to redirect the browser to the correct container URL.

This works fine for `SimpleViewAction` and `FormViewAction` (the browser follows the redirect), but for `ReadOnlyApiAction` and `MutatingApiAction` the framework catches the `RedirectException` and serializes it as a JSON error response instead of issuing a 302 redirect. **Use `form.lookupExperiment()` in API actions** to avoid this issue.

## ExperimentAnnotations Key Accessors

| Method | Returns | Notes |
|---|---|---|
| `getTitle()` | String | Experiment title |
| `getCreated()` | Date | Creation date |
| `getSubmitter()` | Integer | User ID |
| `getSubmitterUser()` | User | User object (may be null) |
| `getSubmitterName()` | String | Display name (may be null) |
| `getLabHeadUser()` | User | Lab head user (may be null) |
| `getShortUrl()` | ShortURLRecord | Short URL record (may be null) |
| `getPxid()` | String | ProteomeXchange ID |
| `hasPxid()` | boolean | |
| `getDoi()` | String | DOI string |
| `hasDoi()` | boolean | |
| `getContainer()` | Container | Owning container |

### ShortURLRecord

`getShortUrl().renderShortURL()` returns a **full URL** (e.g., `https://panoramaweb.org/abc123.url`), not just the slug.

### ProteomeCentral link

```
"https://proteomecentral.proteomexchange.org/cgi/GetDataset?ID=" + PageFlowUtil.encode(pxid)
```

## Common Model Lookup Chains

### Get journal submission context for an experiment

```java
JournalSubmission submission = SubmissionManager.getSubmissionForExperiment(exptAnnotations);
Journal journal = JournalManager.getJournal(submission.getJournalId());
Container supportContainer = journal.getSupportContainer();
Announcement announcement = submission.getAnnouncement(
        AnnouncementService.get(), supportContainer, getUser());
```

## DOM Builder Helpers

The controller defines static `row()` helpers for building `lk-fields-table` layouts:

```java
private static DOM.Renderable row(String title, String value)   { return TR(TD(cl("labkey-form-label"), title), TD(value)); }
private static DOM.Renderable row(String title, DOM.Renderable) { return TR(TD(cl("labkey-form-label"), title), TD(value)); }
```

## Existing Unit TestCase Classes

| Class | Tests |
|---|---|
| `PanoramaPublicController.TestCase` | Controller logic |
| `PanoramaPublicNotification.TestCase` | Notification formatting |
| `PrivateDataReminderSettings.TestCase` | Extension/reminder date logic |
| `NcbiPublicationSearchServiceImpl.TestCase` | Citation parsing, preprint detection, author/title matching, date parsing, priority filtering |
| `BlueskyApiClient.TestCase` | Bluesky API |
| `SkylineVersion.TestCase` | Version parsing |
| `SpecLibKey.TestCase` | Spec lib key logic |
| `SkylineDocValidator.TestCase` | Document validation |
| `SpecLibValidator.TestCase` | Spec lib validation |
| `ContainerJoin.TestCase` | Container join SQL |
| `Formula.TestCase` | Chemical formula parsing |
| `CatalogEntryManager.TestCase` | Catalog entries |

## Selenium Tests

Selenium-based tests live in `test/src/org/labkey/test/tests/panoramapublic/`. They extend `PanoramaPublicBaseTest` (which extends `TargetedMSTest`).

### Key base class helpers

| Method | Description |
|---|---|
| `setupFolderSubmitAndCopy(project, folder, targetFolder, title, submitter, submitterName, admin, skyFile)` | Creates a source folder, imports a Skyline doc, submits to Panorama Public, copies to target. Returns the short access URL. |
| `goToExperimentDetailsPage()` | Navigates to the experiment details page in the current folder. |
| `makeDataPublic(unpublishedData)` | Makes the dataset public via the experiment webpart. |
| `createExperimentCompleteMetadata(title)` | Creates experiment with full metadata. Returns `TargetedMsExperimentWebPart`. |
| `submitWithoutPXId()` | Submits without a PX ID. Returns the short access URL. |
| `makeCopy(shortUrl, title, targetFolder, keepPrivate, cancel)` | Copies submitted experiment to Panorama Public. |
| `verifyIsPublicColumn(project, title, isPublic)` | Verifies the "Is Public" column in the experiment list. |

### DataFolderInfo pattern

Tests that manage multiple folders often use an inner class to track folder info:

```java
private static class DataFolderInfo
{
    private final String _sourceFolder;
    private final String _targetFolder;
    private final String _shortUrl;
    private final String _experimentTitle;
    private final int _experimentAnnotationsId;
    private final String _submitter;
    // constructor, getters...
}
```


## Adding Nav Menu Items (TargetedMSExperimentWebPart)

Admin menu items are added around line ~88 in `TargetedMSExperimentWebPart.java`, inside the `AdminOperationsPermission` check:

```java
navTree.addChild("Menu Label",
    new ActionURL(MyAction.class, container).addParameter("id", expAnnotations.getId()));
```

## Private Data Reminders System

For the private data reminders and publication notification system, see:
- [`private-data-reminders-overview.md`](private-data-reminders-overview.md) — How the system works, example messages, example timeline
