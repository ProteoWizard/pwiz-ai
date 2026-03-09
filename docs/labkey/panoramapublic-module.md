# panoramapublic Module Architecture

The `panoramapublic` module provides the data publishing infrastructure for Panorama Public, enabling researchers to share Skyline targeted mass spectrometry data with the scientific community. It handles experiment submissions, ProteomeXchange integration, DOI assignment, data validation, and catalog management.

## Git Repository Structure

The `MacCossLabModules` repository is a **separate Git repository** nested inside the LabKey enlistment (not a submodule):

```
labkeyEnlistment/                              ← Main repo (LabKey/server.git)
└── server/modules/
    └── MacCossLabModules/                     ← Separate repo (LabKey/MacCossLabModules.git)
        └── panoramapublic/                    ← This module
```

### Branch Naming Convention

**LabKey requires branches to follow this naming scheme:**
```
{version}_fb_{feature-name}
```

Examples:
- `25.11_fb_panoramapublic-bluesky` - Feature branch for 25.11 release
- `26.3_fb_datacite-updates` - Feature branch for 26.3 release

**Common mistake:** Using `feature/...` naming will be rejected by LabKey CI.

### Build and Deploy

```bash
# From labkeyEnlistment directory
./gradlew :server:modules:MacCossLabModules:panoramapublic:deployModule

# Full rebuild with Tomcat restart
./gradlew stopTomcat
./gradlew :server:modules:MacCossLabModules:panoramapublic:deployModule
./gradlew startTomcat
```

**Note:** JSP changes in included files require a full module rebuild, not just a Tomcat restart, because static includes are compiled into the parent JSPs.

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

## Controller Actions

### Publishing Workflow

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `PublishExperimentAction` | PanoramaPublicSubmitter | Form | Submit experiment to journal |
| `CopyExperimentAction` | CopyTargetedMSExperiment | Form | Copy experiment to public folder |
| `SubmitPxValidationJobAction` | PanoramaPublicSubmitter | Mutating | Start PX data validation |
| `PxValidationStatusAction` | Read | View | View PX validation status |
| `DataValidationCheckAction` | PanoramaPublicSubmitter | Form | Check data validation status |
| `UpdateSubmissionAction` | PanoramaPublicSubmitter | Form | Update existing submission |
| `ResubmitExperimentAction` | PanoramaPublicSubmitter | Form | Resubmit experiment |
| `DeleteSubmissionAction` | Admin | Mutating | Delete a submission |

### ProteomeXchange Actions

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `GetPxActionsAction` | Read | View | View PX submission actions |
| `ExportPxXmlAction` | Read | Stream | Download PX XML |
| `PxXmlSummaryAction` | Read | View | View PX XML summary |
| `UpdatePxDetailsAction` | PanoramaPublicSubmitter | Form | Update PX submission details |

### DOI Management

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `DoiOptionsAction` | Read | View | View DOI options |
| `AssignDoiAction` | Admin | Mutating | Assign DOI via DataCite |
| `DeleteDoiAction` | SiteAdmin | Mutating | Delete DOI |

### Journal Administration

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `PanoramaPublicAdminViewAction` | SiteAdmin | View | Manage journals |
| `CreateJournalGroupAction` | SiteAdmin | Form | Create new journal |
| `DeleteJournalGroupAction` | SiteAdmin | Mutating | Delete journal |
| `JournalGroupDetailsAction` | Read | View | View journal details |
| `ChangeJournalSupportContainerAction` | SiteAdmin | Form | Change support container |
| `AddPublicDataUserAction` | SiteAdmin | Form | Add public data user |

### Catalog Management

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `GetCatalogEntryAction` | Read | API | Get catalog entry |
| `UpdateCatalogEntryAction` | Admin | Mutating | Update catalog entry |
| `ApproveCatalogEntryAction` | Admin | Mutating | Approve catalog entry |

### Search and Autocomplete

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `CompleteInstrumentAction` | Read | API | Autocomplete instrument names |
| `CompleteOrganismAction` | Read | API | Autocomplete organism names |

### Bluesky Integration

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `DownloadPanoramaLogoForBlueskyAction` | Read | Download | Download Panorama logo |
| `DeletePanoramaLogoForBlueskyAction` | Admin | Mutating | Delete Panorama logo |

## Publishing Workflow

The panoramapublic module implements a multi-step workflow for publishing Skyline targeted MS data:

### 1. Experiment Annotation

Users annotate their experiments with metadata:
- Title, abstract, citation, publication link
- Organism, instrument, sample description
- Keywords, lab head, submitter information

### 2. Data Validation

Before submission, data is validated:
- **Skyline Document Validation**: Checks document structure, sample files
- **Spectral Library Validation**: Validates library files and source files
- **Modification Validation**: Maps modifications to Unimod IDs
- **File Validation**: Ensures all referenced files exist

Validation is run as a pipeline job (`PxDataValidationTask`).

### 3. Submission to Journal

Users submit to a configured journal (e.g., "Panorama Public"):
- Choose whether to request a ProteomeXchange (PX) ID
- Optionally keep data private (embargo period)
- Select data license (CC0, CC-BY 4.0)
- Provide lab head information

### 4. Data Copy

A pipeline job (`CopyExperimentPipelineJob`) copies the experiment:
- Copies Skyline documents and raw files
- Copies spectral libraries and source files
- Creates symlinks for large files (if configured)
- Sets appropriate permissions for public access

### 5. ProteomeXchange Submission (Optional)

If PX ID requested:
- Generates PX XML with experiment metadata
- Includes modifications mapped to Unimod
- Lists all data files with checksums
- Submits to ProteomeXchange via API
- Receives PX ID (e.g., PXD012345)

### 6. DOI Assignment (Optional)

Administrators can assign DOIs via DataCite:
- Creates DOI metadata from experiment annotations
- Registers DOI with DataCite
- Links DOI to Panorama Public URL

### 7. Publication

Published experiments:
- Get permanent short URLs (e.g., panoramaweb.org/abc123)
- Appear in journal project folder
- Become searchable on Panorama Public
- Can be featured in the catalog

## ProteomeXchange Integration

The module integrates with ProteomeXchange for data repository registration:

### Unimod Matching

Skyline modifications must be mapped to Unimod IDs for PX submission:
- Automatic matching based on modification mass and residues
- Manual override for ambiguous cases
- Combination modifications mapped to multiple Unimod IDs
- Stored in `ModificationValidation` table

### PX XML Generation

The `PxXmlWriter` generates ProteomeXchange XML including:
- Dataset metadata (title, description, keywords)
- Contact information (submitter, lab head)
- Publication references
- Instrument information
- Modifications with Unimod IDs
- File list with checksums and types
- Dataset identifiers (PX ID, DOI, short URL)

### PX Validation

The `PxDataValidationTask` validates:
- All sample files are present
- Spectral libraries are accessible
- Modifications have Unimod mappings
- Required metadata is complete

Results stored in `DataValidation` and related tables.

## DataCite DOI Management

Digital Object Identifiers (DOIs) are managed via DataCite:

### DOI Creation
- Generates DOI metadata from `ExperimentAnnotations`
- Includes creators, title, publication year, publisher
- Resource type: Dataset
- Submits to DataCite API

### DOI Updates
- Can update metadata when experiment is re-published
- Updates stored in `PxXml.updatelog`

### DOI Deletion
- Site admin only
- Removes DOI from DataCite
- Clears DOI from experiment annotations

## Spectral Library Management

Spectral libraries can be dependencies or part of published data:

### Library Types
- BiblioSpec (.blib)
- EncyclopeDIA (.elib, .dlib)
- SpectraST (.sptxt)
- NIST (.msp)

### Dependency Types
- **None**: Library is part of the submission
- **PanoramaPublic**: Library is published on Panorama Public
- **ProteomeXchange**: Library is in ProteomeXchange repository
- **Skyline**: Library is a Skyline-provided library

### Library State Export

For BiblioSpec libraries, chromatogram library state can be exported:
- Exported to SQLite database
- Includes chromatogram data for precursors
- Allows Skyline to import pre-calculated library data
- Managed by `ChromLibStateManager`

## Catalog System

The catalog showcases featured datasets on Panorama Public:

### Catalog Entry
- Linked to a published experiment via short URL
- Image attachment (screenshot or figure)
- Description text
- Requires approval by administrator

### Catalog Types
- **Dataset**: Individual published experiment
- **Collection**: Group of related experiments
- **Tutorial**: Educational content

## Private Data Reminders

Tracks and reminds users about private (embargoed) data:

### Reminder Schedule
- Configurable reminder interval (e.g., every 90 days)
- Tracks last reminder date in `DatasetStatus`
- Sends email to experiment submitter and lab head

### Extension Requests
- Users can request extension of embargo period
- Tracked in `DatasetStatus.extensionrequesteddate`

### Deletion Requests
- Users can request data deletion
- Tracked in `DatasetStatus.deletionrequesteddate`

## Bluesky Integration

Announces new publications on Bluesky social network:

### Settings
- Bluesky handle (e.g., panoramapublic.bsky.social)
- App password for authentication
- Optional Panorama logo attachment

### Announcement Posts
- Auto-posts when experiment is published
- Includes experiment title and link
- Tracks post ID in `BlueskyLinks` table
- Managed by `BlueskyLinksManager`

## Web Parts

| Web Part | Description |
|----------|-------------|
| **Targeted MS Experiments** | List of all published experiments in folder |
| **Targeted MS Experiment** | Single experiment details |
| **Protein Search** | Search for proteins across published data |
| **Peptide Search** | Search for peptides across published data |
| **Small Molecule Search** | Search for small molecules |
| **Download Data** | Instructions for downloading public data |
| **Spectral Libraries** | List of spectral libraries in experiment |
| **Structural Modifications** | List of structural modifications |
| **Isotope Modifications** | List of isotope modifications |
| **Panorama Public Search** | General search across Panorama Public |

## Permissions and Roles

### Custom Permissions
- **PanoramaPublicSubmitterPermission**: Submit data to Panorama Public

### Custom Roles
- **PanoramaPublicSubmitterRole**: Can submit experiments
- **CopyTargetedMSExperimentRole**: Can copy experiments to public folders

### Typical Setup
- **Private folder**: PanoramaPublicSubmitterRole for researchers
- **Journal project**: Reader access for public, Admin for journal managers

## Common Workflows

### Publishing a Dataset

1. User uploads Skyline document to private folder
2. User fills in `ExperimentAnnotations` metadata
3. User submits to journal via `PublishExperimentAction`
4. System runs `PxDataValidationTask` if PX ID requested
5. System runs `CopyExperimentPipelineJob` to copy to public folder
6. System creates short URLs for access and copying
7. If configured, posts announcement to Bluesky
8. Administrator can assign DOI via `AssignDoiAction`

### Updating a Published Dataset

1. User makes changes in private folder
2. User re-uploads Skyline document
3. User clicks "Update" on published experiment
4. System re-validates data
5. System updates copy in public folder
6. System updates PX XML with change log
7. System increments data version

### Creating a Catalog Entry

1. Administrator navigates to published experiment
2. Clicks "Add to Catalog"
3. Uploads image and adds description
4. Approves catalog entry
5. Entry appears on Panorama Public home page

## Testing

The module includes comprehensive unit and integration tests:

### Unit Tests
- `PanoramaPublicController.TestCase`: Controller actions
- `SkylineVersion.TestCase`: Version parsing
- `SpecLibKey.TestCase`: Library key generation
- `SkylineDocValidator.TestCase`: Document validation
- `SpecLibValidator.TestCase`: Library validation
- `Formula.TestCase`: Chemical formula parsing
- `BlueskyApiClient.TestCase`: Bluesky API
- `UnimodUtil.TestCase`: Unimod matching

### Integration Tests
- `ExperimentModificationGetter.TestCase`: Modification extraction
- Full publishing workflow tests

## Configuration

### Site Admin Settings

Accessible via Admin Console > "panorama public":
- Manage journals
- Configure public data user
- Set ProteomeXchange credentials
- Set DataCite credentials
- Configure Bluesky settings
- Configure private data reminder schedule

### Module Properties

Defined in `module.properties`:
- Module class: `PanoramaPublicModule`
- Label: "Panorama Public Module"
- Schema version: 25.003 (as of latest)

## Pipeline Jobs

| Job | Description | Provider |
|-----|-------------|----------|
| `CopyExperimentPipelineJob` | Copy experiment to public folder | CopyExperimentPipelineProvider |
| `PxDataValidationPipelineJob` | Validate data for PX submission | PxValidationPipelineProvider |
| `PostPanoramaPublicMessageJob` | Post announcement to Bluesky | (Background job) |
| `PrivateDataReminderJob` | Send private data reminders | (Scheduled job) |

## Dependencies

The panoramapublic module depends on:
- **targetedms**: Skyline document schema and services
- **pipeline**: Pipeline job framework
- **announcements**: Announcement/message board
- **core**: Container, security, data APIs

External integrations:
- **ProteomeXchange**: Data repository submission
- **DataCite**: DOI registration
- **Unimod**: Modification database
- **Bluesky**: Social media announcements

## Schema Version

Current schema version: **25.003**

Schema upgrades are managed via SQL scripts in:
```
resources/schemas/dbscripts/postgresql/panoramapublic-{version}.sql
```

Major schema changes:
- **19.21**: Initial schema
- **20.000**: Added spectral library support
- **21.000**: Added catalog entries
- **22.000**: Added Bluesky integration
- **25.000**: Added private data reminders and dataset status
