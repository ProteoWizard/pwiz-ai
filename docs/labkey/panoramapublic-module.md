# panoramapublic Module Architecture

The `panoramapublic` module provides the data publishing infrastructure for Panorama Public, enabling researchers to share Skyline targeted mass spectrometry data with the scientific community. It handles experiment submissions, ProteomeXchange integration, DOI assignment, data validation, and catalog management.

### The "Journal" Concept

The code is built around the concept of a **Journal** — an independent data repository with its own project on PanoramaWeb, managed by journal editors. The original design anticipated multiple journals. In practice, only one journal exists: **Panorama Public**. The `Journal` abstraction remains in the code and is useful for Selenium tests, which can target a journal project with any name without depending on the production "Panorama Public" project.

## Git Repository Structure

The `MacCossLabModules` repository is a **separate Git repository** nested inside the LabKey enlistment (not a submodule):

```
labkeyEnlistment/                              ← Main repo (LabKey/server.git)
└── server/modules/
    └── MacCossLabModules/                     ← Separate repo (LabKey/MacCossLabModules.git)
        └── panoramapublic/                    ← This module
```

### Branch Naming Convention

See [labkey-feature-branch-workflow.md](labkey-feature-branch-workflow.md) for naming rules and merge process. Module-specific examples:
- `25.11_fb_panoramapublic-private-data-notification`
- `26.3_fb_panoramapublic-updates`

### Build and Deploy

```bash
# From labkeyEnlistment directory
./gradlew :server:modules:MacCossLabModules:panoramapublic:deployModule

```

## Workflow

### Submitting a Dataset

1. User uploads Skyline documents and optional files (raw data, supplementary files) to a private folder in their own project
2. User fills in `ExperimentAnnotations` metadata
3. User creates a short URL for the dataset (initially points to their private folder)
4. User submits to Panorama Public via `PublishExperimentAction`; this starts a message thread in the journal's support container to notify administrators
5. System runs `PxDataValidationTask` if a PX ID was requested
6. Administrator copies the experiment to Panorama Public via `CopyExperimentPipelineJob`; the short URL is updated to point to the Panorama Public copy
7. If a PX ID was requested, the copy job requests a ProteomeXchange ID and assigns it to the data; A DOI is also assigned.
8. Data remains private until the submitter explicitly makes it public


### Resubmitting a Dataset

1. User makes changes in their private folder, including uploading new Skyline documents
2. User clicks "Resubmit"; this posts another message to the existing support thread
3. Administrator re-runs the copy job to create a new Panorama Public copy and deletes the old copy
4. If the data is already public and metadata or publication info changes (e.g., a PubMed ID is added), PX XML is updated and resubmitted to ProteomeXchange


### Making Data Public

By default, copied data is kept private (accessible readable by the submitter and the reviewer account created for the data). When the submitter is ready to make the data public:

1. Submitter clicks "Make Public" button in their private folder. They an associate a PubMed ID or publication with the dataset.
2. Panorama Public folder permissions are updated to grant read access to all users
3. DOI assigned to the data is made public
3. Admin submits a PX XML to "announce" that data on ProteomeXchange (if a PX ID was requested
4. A Bluesky announcement is posted (if configured)

If the submitter associates a PubMed ID or publication with the dataset after making it public, an updated PX XML is submitted to ProteomeXchange.


### Creating a Catalog Entry

1. Submitter makes their data public
2. Submitter navigates to the published experiment and adds a catalog entry (`AddCatalogEntryAction`): uploads an image and adds a description
3. Administrator approves the entry via `ChangeCatalogEntryStateAction`
4. Approved entry appears on the PanoramaWeb home page


## Dependencies

The panoramapublic module depends on:
- **targetedms**: Skyline document schema and services
- **pipeline**: Pipeline job framework
- **announcements**: Announcement/message board
- **core**: Container, security, data APIs

## External integrations:
- **ProteomeXchange**: Data repository submission
- **DataCite**: DOI registration
- **NCBI (PubMed/PMC)**: Publication search for private data reminders
- **Unimod**: Modification database
- **Bluesky**: Social media announcements


## Configuration

### Site Admin Settings

Accessible via Admin Console > "panorama public":
- Manage journals
- Configure public data user
- Set ProteomeXchange credentials
- Set DataCite credentials
- Configure Bluesky settings
- Configure private data reminder schedule



## Database Tables (PostgreSQL)

All tables are in the `panoramapublic` schema. Access via `PanoramaPublicManager.getTableInfo*()` methods.

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `ExperimentAnnotations` | Experiment metadata for published data | id, container, title, organism, instrument, citation, pubmedid, pxid, doi |
| `Journal` | Journal/repository configurations | id, name, labkeygroupid, project, supportcontainer |
| `JournalExperiment` | Published experiments in a journal | id, journalid, experimentannotationsid, shortaccessurl, shortcopyurl, reviewer |
| `Submission` | Submission details and workflow | id, journalexperimentid, copiedexperimentid, copied, pxidrequested, keepprivate, datalicense |
| `PxXml` | ProteomeXchange XML submissions | id, journalexperimentid, xml, version, updatelog |
| `SpecLibInfo` | Spectral library metadata | id, librarytype, name, experimentannotationsid, sourcetype, sourceurl, dependencytype |
| `DataValidation` | Data validation jobs | id, experimentannotationsid, jobid, status |
| `SkylineDocValidation` | Skyline document validation | id, validationid, name, runid |
| `SkylineDocSampleFile` | Sample file validation | id, skylinedocvalidationid, samplefileid, name, path |
| `ModificationValidation` | Modification Unimod matching | id, validationid, skylinemodname, dbmodid, unimodid, unimodname |
| `SkylineDocModification` | Doc-to-modification mapping | id, skylinedocvalidationid, modificationvalidationid |
| `SpecLibValidation` | Spectral library validation | id, validationid, libname, filename, size, libtype, speclibinfoid |
| `SpecLibSourceFile` | Spectral library source files | id, speclibvalidationid, name, path, sourcetype |
| `SkylineDocSpecLib` | Doc-to-library mapping | id, skylinedocvalidationid, speclibvalidationid, included, spectrumlibraryid |
| `ExperimentStructuralModInfo` | Structural modification Unimod mapping | id, experimentannotationsid, modid, unimodid, unimodname |
| `ExperimentIsotopeModInfo` | Isotope modification Unimod mapping | id, experimentannotationsid, modid, unimodid, unimodname |
| `IsotopeUnimodInfo` | Additional isotope Unimod IDs | id, modinfoid, unimodid, unimodname |
| `CatalogEntry` | Catalog entries for featured data | id, shorturl, imagefilename, description, approved |
| `DatasetStatus` | Dataset status tracking | id, experimentannotationsid, lastreminderdate, extensionrequesteddate, deletionrequesteddate |

---

## Controller Actions

### Publishing Workflow

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `PublishExperimentAction` | AdminPermission | FormViewAction | Submit experiment to Panorama Public |
| `CopyExperimentAction` | RequiresLogin | FormViewAction | Copy experiment to Panorama Public |
| `SubmitPxValidationJobAction` | AdminPermission | FormHandlerAction | Start PX data validation |
| `PxValidationStatusAction` | AdminPermission | SimpleViewAction | View full PX validation details |
| `DataValidationCheckAction` | AdminPermission | FormViewAction | Check data validation status |
| `UpdateSubmissionAction` | AdminPermission | FormViewAction | Update existing submission |
| `ResubmitExperimentAction` | AdminPermission | FormViewAction | Resubmit experiment |
| `DeleteSubmissionAction` | AdminPermission | ConfirmAction | Delete a submission |

### Journal Administration

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `PanoramaPublicAdminViewAction` | AdminOperationsPermission | SimpleViewAction | Manage journals |
| `CreateJournalGroupAction` | AdminOperationsPermission | FormViewAction | Create new journal |
| `DeleteJournalGroupAction` | AdminOperationsPermission | ConfirmAction | Delete journal |
| `JournalGroupDetailsAction` | AdminOperationsPermission | SimpleViewAction | View journal details |
| `ChangeJournalSupportContainerAction` | AdminOperationsPermission | FormViewAction | Change support container |
| `AddPublicDataUserAction` | AdminOperationsPermission | FormViewAction | Add public data user |

### ProteomeXchange Actions

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `GetPxActionsAction` | AdminOperationsPermission | FormViewAction | View PX submission actions |
| `ExportPxXmlAction` | AdminOperationsPermission | SimpleStreamAction | Download PX XML |
| `PxXmlSummaryAction` | AdminPermission | SimpleViewAction | View PX XML summary |
| `UpdatePxDetailsAction` | AdminOperationsPermission | FormViewAction | Update PX submission details |

### DOI Management

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `DoiOptionsAction` | AdminOperationsPermission | SimpleViewAction | View DOI options |
| `AssignDoiAction` | AdminOperationsPermission | ConfirmAction | Assign DOI via DataCite |
| `DeleteDoiAction` | AdminOperationsPermission | ConfirmAction | Delete DOI |

### Catalog Entry Management

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `AddCatalogEntryAction` | AdminPermission or PanoramaPublicSubmitterPermission | FormViewAction | Add catalog entry |
| `EditCatalogEntryAction` | AdminPermission or PanoramaPublicSubmitterPermission | FormViewAction | Edit catalog entry |
| `ViewCatalogEntryAction` | AdminPermission or PanoramaPublicSubmitterPermission | SimpleViewAction | View catalog entry |
| `DeleteCatalogEntryAction` | AdminPermission or PanoramaPublicSubmitterPermission | FormHandlerAction | Delete catalog entry |
| `ChangeCatalogEntryStateAction` | AdminOperationsPermission | FormHandlerAction | Approve/reject catalog entry |
| `ManageCatalogEntrySettings` | AdminOperationsPermission | FormViewAction | Manage catalog settings |

### Search and Autocomplete

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `CompleteInstrumentAction` | ReadPermission | ReadOnlyApiAction | Autocomplete instrument names |
| `CompleteOrganismAction` | ReadPermission | ReadOnlyApiAction | Autocomplete organism names |


---
 
## Private Data Reminders

Tracks and reminds users about private data, optionally searching NCBI for associated publications.

For detailed documentation, see the [`panoramapublic/`](panoramapublic/) subfolder:
- [`panoramapublic-coding-patterns.md`](panoramapublic/panoramapublic-coding-patterns.md) — Module coding patterns
- [`private-data-reminders-overview.md`](panoramapublic/private-data-reminders-overview.md) — Feature overview (read when working on this system)
- [`spec-private-data-publication-search/`](panoramapublic/spec-private-data-publication-search/) — Implementation spec (read for deep debugging or extensions)


## Web Parts

| Web Part | Description |
|----------|-------------|
| **Targeted MS Experiments** | List of all published experiments in folder |
| **Targeted MS Experiment** | Single experiment details |
| **Panorama Public Search** | General search across Panorama Public |
| **Protein Search** | Search for proteins across published data |
| **Peptide Search** | Search for peptides across published data |
| **Small Molecule Search** | Search for small molecules |
| **Download Data** | Instructions for downloading public data |
| **Spectral Libraries** | List of spectral libraries in experiment |
| **Structural Modifications** | List of structural modifications |
| **Isotope Modifications** | List of isotope modifications |


## Permissions and Roles

### Custom Permissions
- **PanoramaPublicSubmitterPermission**: Submit data to Panorama Public

### Custom Roles
- **PanoramaPublicSubmitterRole**: Can submit experiments
- **CopyTargetedMSExperimentRole**: Can copy experiments to Panorama Public

### Typical Permissions Setup
- **Private folder**: Submitter has Administrator permissions.
- **Journal folder**: Admin role for journal managers; Reader role for all admins of the source folder.  PanoramaPublicSubmitterRole for submitter and lab head users.



## Pipeline Jobs

| Job | Description | Provider |
|-----|-------------|----------|
| `CopyExperimentPipelineJob` | Copy experiment to public folder | CopyExperimentPipelineProvider |
| `PxDataValidationPipelineJob` | Validate data for PX submission | PxValidationPipelineProvider |
| `PostPanoramaPublicMessageJob` | Post message to Panorama Public support threads of selected experiments | (Background job) |
| `PrivateDataReminderJob` | Send private data reminders | (Scheduled job) |


## Source Location

```
labkeyEnlistment/server/modules/MacCossLabModules/panoramapublic/
  src/org/labkey/panoramapublic/
    PanoramaPublicController.java      # All HTTP actions (publishing, validation, DOI, etc.)
    PanoramaPublicSchema.java          # DB schema access
    PanoramaPublicModule.java          # Module registration
    PanoramaPublicManager.java         # Core manager class with table accessors
    PanoramaPublicListener.java        # Event listeners (experiments, containers, imports)
    PanoramaPublicNotification.java    # Email notification system
    PanoramaPublicSymlinkManager.java  # File symlink management

    bluesky/                           # Bluesky social media integration
      BlueskyApiClient.java            # Bluesky API client
      BlueskySettingsManager.java      # Bluesky credentials management
      BlueskyLinksManager.java         # Manage announcement posts
      PanoramaPublicLogoManager.java   # Logo attachment handling

    catalog/                           # Catalog entry management
      CatalogEntrySettings.java        # Catalog entry configuration
      CatalogImageAttachmentType.java  # Image attachment handling

    chromlib/                          # Chromatogram library state management
      ChromLibStateManager.java        # Library state import/export
      ChromLibStateImporter.java       # Import library state
      ChromLibStateExporter.java       # Export library state
      LibPrecursor.java                # Precursor models

    datacite/                          # DOI management via DataCite
      DataCiteService.java             # DataCite API client
      Doi.java                         # DOI model
      DoiMetadata.java                 # DOI metadata
      DataCiteException.java           # DataCite errors

    message/                           # Private data reminder system
      PrivateDataMessageScheduler.java # Scheduled reminder jobs
      PrivateDataReminderSettings.java # Reminder configuration

    model/                             # Data models
      ExperimentAnnotations.java       # Experiment metadata
      Journal.java                     # Journal/repository
      JournalExperiment.java           # Published experiment
      JournalSubmission.java           # Submission wrapper
      Submission.java                  # Submission details
      CatalogEntry.java                # Catalog entry
      DataLicense.java                 # Data license enum
      DatasetStatus.java               # Dataset status tracking
      PxXml.java                       # ProteomeXchange XML
      speclib/                         # Spectral library models
        SpectralLibrary.java           # Library info
        SpecLibInfo.java               # Library metadata
        SpecLibKey.java                # Library identifier
      validation/                      # Validation models
        DataValidation.java            # Validation job
        SkylineDoc.java                # Skyline document
        SkylineDocSampleFile.java      # Sample file validation
        SpecLib.java                   # Spectral library validation
        Modification.java              # Modification validation

    pipeline/                          # Pipeline jobs
      CopyExperimentPipelineProvider.java  # Copy experiment pipeline
      CopyLibraryStateTask.java            # Copy library state
      PxValidationPipelineProvider.java    # PX validation pipeline
      PxDataValidationTask.java            # PX validation task
      FilesMetadataImporter.java           # Files metadata import
      FilesMetadataWriter.java             # Files metadata export

    proteomexchange/                   # ProteomeXchange integration
      PxXmlWriter.java                 # Generate PX XML
      PxHtmlWriter.java                # Generate PX HTML
      UnimodUtil.java                  # Unimod utilities
      UnimodParser.java                # Parse Unimod XML
      ExperimentModificationGetter.java # Extract modifications
      validator/                       # PX data validators
        DataValidator.java             # Base validator
        SkylineDocValidator.java       # Skyline document validator
        SpecLibValidator.java          # Spectral library validator

    query/                             # Query and manager classes
      ExperimentAnnotationsManager.java   # Experiment CRUD
      JournalManager.java                 # Journal CRUD
      CatalogEntryManager.java            # Catalog CRUD
      DataValidationManager.java          # Validation CRUD
      DatasetStatusManager.java           # Dataset status CRUD
      ModificationInfoManager.java        # Modification metadata
      modification/                       # Modification views
        ModificationsView.java            # Modification web parts
      speclib/                            # Spectral library views
        SpecLibView.java                  # Spectral library web part

    security/                          # Security roles and permissions
      PanoramaPublicSubmitterRole.java       # Submitter role
      PanoramaPublicSubmitterPermission.java # Submitter permission
      CopyTargetedMSExperimentRole.java      # Copy experiment role

    view/                              # JSP views
      publish/                         # Publishing workflow
        publishExperimentForm.jsp      # Publish experiment form
        confirmSubmit.jsp              # Confirm submission
        confirmPublish.jsp             # Confirm publish
        copyExperimentForm.jsp         # Copy experiment form
        pxValidationStatus.jsp         # PX validation status
        pxActions.jsp                  # PX submission actions
        catalogEntryForm.jsp           # Catalog entry form
        publicationDetails.jsp         # Publication details
      expannotations/                  # Experiment annotations
        TargetedMSExperimentWebPart.java    # Single experiment web part
        TargetedMSExperimentsWebPart.java   # Experiment list web part
      search/                          # Search views
        panoramaWebSearch.jsp          # Panorama Public search
        panoramaPublicProteinSearch.jsp     # Protein search
        panoramaPublicPeptideSearch.jsp     # Peptide search
```

## Testing

LabKey has three levels of tests:

- **Unit tests** — Static inner `TestCase` classes (extending JUnit `Assert`) embedded in the production class. They run in-process with no server or database, testing pure logic (parsing, formatting, matching).
- **Integration tests** — Also `TestCase` inner classes, but they run against a live LabKey server and database. They can query tables and exercise server-side logic end-to-end without a browser.
- **Selenium tests** — Browser-driven tests using the WebDriver API. They live in the separate `test/` source tree and exercise full user-facing workflows through the UI.

### Unit Tests
- `PanoramaPublicController.TestCase`: Controller logic
- `PanoramaPublicNotification.TestCase`: Notification formatting
- `PrivateDataReminderSettings.TestCase`: Extension/reminder date logic
- `NcbiPublicationSearchServiceImpl.TestCase`: Citation parsing, preprint detection, author/title matching, date parsing, priority filtering
- `BlueskyApiClient.TestCase`: Bluesky API
- `SkylineVersion.TestCase`: Version parsing
- `SpecLibKey.TestCase`: Spec lib key logic
- `SkylineDocValidator.TestCase`: Document validation
- `SpecLibValidator.TestCase`: Spec lib validation
- `ContainerJoin.TestCase`: Container join SQL
- `Formula.TestCase`: Chemical formula parsing
- `CatalogEntryManager.TestCase`: Catalog entries
- `UnimodUtil.TestCase`: Unimod matching

### Integration Tests
- `ExperimentModificationGetter.TestCase`: Modification extraction from a live experiment

### Selenium Tests

All Selenium tests live in `test/src/org/labkey/test/tests/panoramapublic/` and extend `PanoramaPublicBaseTest`.

| Test Class | Description |
|---|---|
| `PanoramaPublicTest` | Core end-to-end workflow: submit, copy, version management |
| `PanoramaPublicMakePublicTest` | Making data public and adding catalog entries |
| `PanoramaPublicModificationsTest` | Structural and isotope modification matching with Unimod |
| `PanoramaPublicChromLibTest` | Chromatogram library copying and integrity |
| `PanoramaPublicValidationTest` | Data validation: sample files, raw files, spectral libraries, PX readiness |
| `PanoramaPublicSymlinkTest` | File symlink vs. copy behavior during experiment copy |
| `PanoramaPublicMoveSkyDocTest` | Experiment copy when Skyline documents have been moved to different folders |
| `PanoramaPublicMyDataViewTest` | "My Data" view for submitters and catalog entry management |
| `PanoramaWebPublicSearchTest` | Search for experiments, proteins, peptides, and small molecules |
| `PrivateDataReminderTest` | Private data reminders, extension requests, and deletion requests |
| `PublicationSearchTest` | Publication search via PubMed/PMC and submitter notification |






