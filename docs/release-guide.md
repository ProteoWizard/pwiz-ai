# Release Guide

Guide to Skyline release management, including version numbering, release types, workflows, and automation.

## Wiki Page Locations

Release documentation wiki pages are in two locations on skyline.ms:

| Container | Access | Pages |
|-----------|--------|-------|
| `/home/software/Skyline` | Public | Install pages, tutorials, Release Notes |
| `/home/software/Skyline/daily` | Semi-public (signup required) | Skyline-daily release announcements |
| `/home/software/Skyline/releases` | Public | Major release announcement archive |
| `/home/development` | Authenticated | `release-prep`, `DeployToDockerHub`, dev tools |

See `ai/docs/mcp/wiki.md` for full wiki container documentation.

## Release Types

Skyline has four distinct release types, each with a different workflow:

| Release Type | Version Format | Branch | Purpose |
|--------------|----------------|--------|---------|
| **Skyline-daily (beta)** | `YY.N.1.DDD` | `master` | Ongoing development builds |
| **Skyline-daily (FEATURE COMPLETE)** | `YY.N.9.DDD` | `Skyline/skyline_YY_N` | Pre-release stabilization |
| **Skyline (release)** | `YY.N.0.DDD` | `Skyline/skyline_YY_N` | Official stable release |
| **Skyline (patch)** | `YY.N.0.DDD` | `Skyline/skyline_YY_N` | Bug fixes to stable release |

## Version Numbering

### Format: `YY.N.B.DDD`

| Component | Name | Values | Description |
|-----------|------|--------|-------------|
| `YY` | Year | 24, 25, 26... | Year of release (also base year for day calculation) |
| `N` | Ordinal | 0, 1, 2... | Release number within year (0 = first/unreleased, 1 = first official) |
| `B` | Branch | 0, 1, 9 | Build type: 0=release, 1=daily, 9=feature complete |
| `DDD` | Day | 001-365 | Zero-padded day of year from git commit date |

### Jamfile.jam Constants

```jam
constant SKYLINE_YEAR : 26 ;      # YY component, also base year for day calculation
constant SKYLINE_ORDINAL : 1 ;    # N component
constant SKYLINE_BRANCH : 1 ;     # B component: 0=release, 1=daily, 9=feature complete
```

### Day-of-Year Calculation (Reproducible Builds)

**Key change (2026-01-04)**: Day-of-year is now calculated from the **git commit date**, not the build machine date. This enables reproducible builds from any release tag.

```jam
# Uses git commit date (not JAMDATE) for reproducible versioning
local git_date = [ SHELL "git log -1 --format=%cs HEAD" ] ;
```

**Day calculation formula**:
```
DDD = (year_2digit - SKYLINE_YEAR) * 365 + day_of_year(commit_date)
```

This means:
- Rebuilding from a release tag produces the same version number
- Cherry-pick commits `2b169349f3` + `cee2c514d0` to any old release tag for reproducible builds
- Zero-padding (`004` not `4`) ensures chronological sorting in file listings

### Version Examples

| Version | Meaning |
|---------|---------|
| `26.1.1.004` | 2026, release 1, daily build, day 4 (Jan 4) |
| `26.0.9.004` | 2026, release 0, feature complete, day 4 |
| `26.1.0.045` | 2026, release 1, official release, day 45 (Feb 14) |
| `25.1.1.369` | 2025, release 1, daily, day 369 (crosses into 2026 = 365 + day 4) |

## Version-Format-Schema Dependency

**CRITICAL**: Version numbers, document format, and schema files must stay synchronized.

### The Constraint

When Skyline version changes to a new `YY.N` (e.g., 25.1 → 26.1), three things must be updated together:

1. **`DocumentFormat.CURRENT`** in `Model/Serialization/DocumentFormat.cs`
2. **XSD schema file** `TestUtil/Schemas/Skyline_YY.N.xsd`
3. **`SkylineVersion.SupportedForSharing()`** must include the new version

### Why This Matters

Two automated tests enforce this constraint on daily builds (Build=1) and release builds (Build=0):

```csharp
// TestDocumentFormatCurrent - enforces version/format match
if (Install.Build > 1) return; // Skip for FEATURE COMPLETE (Build=9)
Assert.AreEqual(expectedVersion, DocumentFormat.CURRENT.AsDouble(), 0.099);

// TestMostRecentReleaseFormatIsSupportedForSharing
if (Install.Build > 1) return; // Skip for FEATURE COMPLETE (Build=9)
Assert.Fail("SupportedForSharing needs to include {0}.{1}", MajorVersion, MinorVersion);
```

These tests **skip** for FEATURE COMPLETE builds (Build=9) but **run** for daily builds (Build=1).

### Implication for Release Workflow

- **FEATURE COMPLETE (26.0.9)**: Tests skip, so no format/schema changes needed yet
- **Master during FEATURE COMPLETE**: Cannot update to 26.x because tests would run and fail
- **MAJOR release (26.1.0)**: Must update format, schema, and SupportedForSharing together
- **After MAJOR**: Master can update to 26.1.1, tests will pass

### Files to Update for MAJOR Release

These updates happen in two phases. See the "Skyline (release)" workflow for the full sequence.

**Phase 1 — Cherry-pick to both branches** (format/schema/sharing):

| File | Change |
|------|--------|
| `Model/Serialization/DocumentFormat.cs` | Add format constant for 26.1, update `CURRENT` |
| `TestUtil/Schemas/Skyline_26.1.xsd` | Copy from latest schema (e.g., `Skyline_25.11.xsd`) |
| `Model/SkylineVersion.cs` | Add `V26_1` to `SupportedForSharing()` list |
| `Alerts/AboutDlg.resx` | Update copyright year (e.g., "2008-2025" → "2008-2026") |
| `Alerts/AboutDlg.ja.resx` | Update copyright year (Japanese) |
| `Alerts/AboutDlg.zh-CHS.resx` | Update copyright year (Chinese) |
| All `.resx` files | Find-replace "Skyline-daily" → "Skyline" (saves localization work) |
| `Jamfile.jam` (master cherry-pick only) | Bump `SKYLINE_YEAR` to match new release (e.g., 25→26) |

**Phase 2 — Release branch only** (NOT cherry-picked to master):

| File | Change |
|------|--------|
| `Jamfile.jam` | Set `SKYLINE_ORDINAL : 1`, `SKYLINE_BRANCH : 0` |
| `Skyline.csproj` | Product name "Skyline-daily" → "Skyline", update `ApplicationVersion` |
| `Executables/Installer/FileList64-template.txt` | "Skyline-daily" → "Skyline" |
| Other project files | Find-in-Files `*.*` for remaining "Skyline-daily" (skip items marked keep) |
| `Skyline.ico` | Overwrite with `Skyline_Release.ico` (release icon) |
| `Resources/Skyline.bmp` | Overwrite with `Resources/Skyline_Release.bmp` (About box image) |

## Release Folder Setup

Each major release uses a dedicated folder (e.g., `skyline_26_1` in your project root). This keeps release work separate from ongoing master development and maintains isolated build configurations.

**Folder naming convention**: `skyline_YY_N` (e.g., `skyline_26_1`, `skyline_25_1`) as a sibling to `pwiz/` and `ai/`

### Why Separate Folders?

- **Master stays development-ready**: Your `pwiz` checkout remains on master for ongoing work
- **Isolated build artifacts**: Each release has its own intermediate files
- **Preserved configuration**: Signing files, publish settings persist per-release
- **Historical reference**: Keep 1-2 previous release folders for debugging old versions

### Setup Steps for New Release Folder

**1. Clone the release branch:**
```bash
cd <your project root>
git clone --branch Skyline/skyline_YY_N https://github.com/ProteoWizard/pwiz.git skyline_YY_N
```

**2. Create build batch files** (required - contains vendor license agreement):
```bash
# b.bat - base build command
echo 'pwiz_tools\build-apps.bat 64 --i-agree-to-the-vendor-licenses toolset=msvc-14.3 %*' > b.bat

# bs.bat - build Skyline only
echo 'b.bat pwiz_tools\Skyline//Skyline.exe' > bs.bat

# bso.bat - official release build (Skyline + Installer + version check)
cat > bso.bat << 'EOF'
call b.bat pwiz_tools\Skyline//Skyline.exe --official
call b.bat pwiz_tools/Skyline/Executables/Installer//setup.exe --official
pwiz_tools\Skyline\bin\x64\Release\SkylineCmd --version
EOF
```

Note: These files cannot be in the repo because `--i-agree-to-the-vendor-licenses` is a legal acknowledgment each developer must make.

**3. Copy signing files** from previous release folder:
```bash
cp ../skyline_25_1/pwiz_tools/Skyline/SignAfterPublishKey.bat \
   ../skyline_25_1/pwiz_tools/Skyline/SignSimple.bat \
   "../skyline_25_1/pwiz_tools/Skyline/University of Washington (MacCoss Lab).crt" \
   pwiz_tools/Skyline/
```

**4. Copy and edit publish settings** (`.csproj.user`):
```bash
cp ../skyline_25_1/pwiz_tools/Skyline/Skyline.csproj.user pwiz_tools/Skyline/
```

Then edit `PublishUrlHistory` to update the ZIP path version:
- Change: `Skyline-daily-64_25_1_1_xxx` → `Skyline-daily-64_26_0_9_004`
- The ClickOnce path (T: drive) stays the same

Note: The third position matches the version branch type (1=daily, 9=feature complete, 0=release).

This is faster than navigating the VS Publish UI to create the folder.

**5. First build** to populate intermediate files:
```bash
clean.bat && bso.bat
```

### Transitioning from Previous Release

When starting FEATURE COMPLETE, set up the new release folder **before** making version changes:

1. Create `skyline_YY_N` in your project root as described above
2. Do all release work from the new folder
3. Keep `pwiz` on master for development

This way, your `pwiz` checkout is always ready for the next daily release after the major release.

## Release Workflows

### Skyline-daily (beta)

Regular daily builds from master branch. No special workflow - automated nightly builds.

**Version settings on master**:
```jam
constant SKYLINE_YEAR : 25 ;
constant SKYLINE_ORDINAL : 1 ;
constant SKYLINE_BRANCH : 1 ;  # daily
```

### Skyline-daily (FEATURE COMPLETE)

Pre-release stabilization period before official release.

**Key concepts:**
- **Release branch** (`Skyline/skyline_YY_N`): All FEATURE COMPLETE releases come from here
- **Master is release-frozen**: No Skyline-daily releases from master during this period
- **Master is development-open**: PRs merge freely, new features accumulate for next cycle
- **Version stays at 25.x on master**: Cannot update to 26.x until MAJOR release (see "Version-Format-Schema Dependency" below)

**Strategic goal**: By major release day, master has exciting new work. Release 26.1.0 (major) and 26.1.1 (daily) on the same day so Skyline-daily users see 26.1.1 as an upgrade with new features and stay on the daily track, rather than switching to nearly-identical 26.1.0.

**Pre-branch preparation**: FEATURE COMPLETE also means **UI Freeze**. In the days before creating the release branch:

- **Finalize tutorial screenshots**: Run automated screenshot capture and verify all screenshots look presentable with the final UI. This is a critical reality check before branching.
- **Finalize localized .resx files**: Run `FinalizeResxFiles` target to update .ja and .zh-CHS .resx files, adding comments for strings added since last release:
  ```cmd
  quickbuild pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer//FinalizeResxFiles
  ```
  This uses `Translation/LastReleaseResources.db` as the baseline. Commit the updated .resx files to master before branching.
- **Hold back non-release PRs**: Developers should hold back PRs not triaged for this release (prevents exclusion work after branch creation)
- **Set up release folder**: See "Release Folder Setup" section above

**Workflow**:

1. **Create release branch** from master: `Skyline/skyline_YY_N`

2. **Copy tutorials for the new version** (can do immediately after branch creation):
   ```cmd
   xcopy /E /I <release folder>\pwiz_tools\Skyline\Documentation\Tutorials T:\www\site\skyline.ms\html\tutorials\26-0-9
   ```

   This copies the tutorial HTML to a versioned directory on the web server (same T: drive used for ClickOnce publishing).
   The `tutorial.js` update to show the `[html 26.0.9]` link happens later (step 15).

3. **Generate translation CSV files** and send to translators (time-sensitive):
   ```cmd
   cd <release folder>
   b.bat pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer//GenerateLocalizationCsvFiles
   ```

   This creates `localization.ja.csv` and `localization.zh-CHS.csv` in `pwiz_tools\Skyline\Translation\Scratch\` containing strings needing translation. The CSV files include:
   - **Name**: Resource key (empty for consolidated entries shared across files)
   - **English**: The English text to translate
   - **Translation**: Empty column for translators to fill in
   - **Issue**: Any localization issues (e.g., "English text changed", "Inconsistent translation")
   - **FileCount/File**: Source .resx file(s) for context

   Send these to Japanese and Chinese translators immediately - translation time often determines release schedule.

   **When translations come back**, import them on the release branch:
   ```cmd
   cd <release folder>
   # Place translated CSVs in pwiz_tools\Skyline\Translation\Scratch\
   # (keeping same filenames: localization.ja.csv, localization.zh-CHS.csv)
   b.bat pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer//ImportLocalizationCsvFiles
   ```

   This imports translations into the .resx files and extracts the updated files. Verify the import succeeded by checking:
   - Build log shows "changed X/Y matching records in resx files"
   - Build ends with "SUCCESS"

   Commit the updated .resx files to the release branch, then merge to master (translations are one of the things that flow from release branch back to master, unlike release-only changes like renaming Skyline-daily to Skyline).

   See `pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer/README.md` for detailed ResourcesOrganizer documentation.

4. **Update cherry-pick workflow** in `.github/workflows/cherrypick-pr-to-release.yml`:
   - Change `pr_branch: 'Skyline/skyline_YY_N'` to the new branch name
   - Commit to master so the "Cherry pick to release" label works for the new branch

5. **Immediately notify dev team** (don't wait until end of release):

   > I have made and pushed the Skyline/skyline_YY_N release branch. Everyone needs to
   > consider whether a merge to master needs to be cherry-picked to the release branch
   > starting now. Use the "Cherry pick to release" label on PRs to automate this.
   > Also, master is now open for YY.N+1 development.
   >
   > Congratulations on reaching feature complete!

   This is time-sensitive: developers merging to master need to know immediately so they
   can use the cherry-pick label. Delayed notification causes manual cherry-pick work.

6. **Update TeamCity** to point to new release branch (do this immediately so commits trigger builds):
   - Go to: [ProteoWizard Project Parameters](https://teamcity.labkey.org/admin/editProject.html?projectId=ProteoWizard&tab=projectParams)
   - Update the release branch parameter to the new branch name (e.g., `skyline_26_1`)
   - This single parameter controls all release branch build configurations including Docker

   **Verify** all build configurations have transitioned to the new branch:
   - Core Windows x86_64 (Skyline release branch)
   - Skyline Release Branch x86_64
   - Skyline Release Branch Code Inspection
   - Skyline Release Perf and Tutorial tests
   - Skyline release TestConnected tests
   - ProteoWizard and Skyline (release branch) Docker container (Wine x86_64) - **Docker image build**

   Note: These configs appear in 3 separate alphabetical sections (Core..., ProteoWizard..., Skyline...)
   so they don't cluster together when scrolling through TeamCity.

   Check that each configuration shows a queued or running build for the new branch.

7. **Calculate the version** for today's commit date:
   ```
   DDD = (year - SKYLINE_YEAR) * 365 + day_of_year
   Example: Jan 4, 2026 with SKYLINE_YEAR=26 → DDD = (26-26)*365 + 4 = 004
   ```

8. **Set version on release branch** in both files (single commit):

   **Jamfile.jam**:
   ```jam
   constant SKYLINE_YEAR : 26 ;
   constant SKYLINE_ORDINAL : 0 ;   # Not yet released
   constant SKYLINE_BRANCH : 9 ;    # Feature complete
   ```

   **Skyline.csproj**:
   ```xml
   <ApplicationRevision>4</ApplicationRevision>
   <ApplicationVersion>26.0.9.004</ApplicationVersion>
   ```

   **WARNING**: Never commit `<SignManifests>true</SignManifests>`. This requires
   special certificate configuration and would break builds on other machines.
   Always revert this line before committing.

9. **DO NOT update master version yet**:

   Master stays at its current version (e.g., 25.1.1) during FEATURE COMPLETE.
   The version cannot be updated to 26.x until the MAJOR release because:
   - `DocumentFormat.CURRENT` must match the version (see "Version-Format-Schema Dependency")
   - Format updates require creating a new XSD schema file
   - Tests enforce this constraint and will fail if version/format mismatch

   Master version is updated during the MAJOR release workflow, not here.

10. **Build and test** from release branch (`clean.bat` + `bso.bat`)

   **IMPORTANT**: Verify you are building a **Release** build, not Debug. Developers often
   work with Debug builds. Double-check this before running tests - you want tests running
   against the Release build that will be published.

   **Troubleshooting**: If build fails with file lock errors on DLLs, check for leftover
   Docker Desktop containers from testing. Stop any remaining containers manually before
   rebuilding. (Most containers exit automatically, but occasionally some hold file locks.)

11. **Tag release commit**: `Skyline-daily-26.0.9.004`

12. **Publish installers** (5 steps):

   a. **ClickOnce to website** (Visual Studio Project Properties):

      **Publish tab**:
      - Publishing Folder Location: `T:\www\site\skyline.ms\html\software\Skyline-daily13-64\`
        (T: is mapped to the skyline.ms server through an internal Samba share)
      - Installation Folder URL: `https://skyline.gs.washington.edu/software/Skyline-daily13-64/`
      - Install Mode: "The application is available offline as well (launchable from Start menu)"
      - Publish Version: Set to match build (e.g., 26.0.9.004)
      - "Automatically increment revision with each publish" - **unchecked**

      **Updates button** (Application Updates dialog):
      - "The application should check for updates" - **unchecked**
      - Update location: `https://skyline.gs.washington.edu/software/Skyline-daily13-64/`

      **Signing tab**:
      - "Sign the ClickOnce manifests" - **checked**
      - Certificate: University of Washington (DigiCert, expires 2/28/2027)
      - "Sign the assembly" - **unchecked**

      Click **Publish Now**

   b. **ZIP to nexus server** (disk publish for disconnected install):

      Change VS Publish settings for disk (no URLs):
      - Publishing Folder Location: `M:\home\brendanx\tools\Skyline-daily\Skyline-daily-64_26_0_9_004\`
        (M: is mapped to the nexus server through an internal Samba share)
      - Installation Folder URL: **empty**
      - Updates > Update location: **empty**

      Click **Publish Now**, then create the ZIP:
      ```powershell
      # From M:\home\brendanx\tools\Skyline-daily\
      Compress-Archive -Path 'Skyline-daily-64_26_0_9_004' -DestinationPath 'Skyline-daily-64_26_0_9_004.zip'
      ```

      **IMPORTANT**: The ZIP must contain the folder as the root entry (not just contents).
      Verify by extracting - should create `Skyline-daily-64_26_0_9_004/` containing `setup.exe`.

   c. **MSI preparation**:
      - Copy `bin\x64\Skyline-daily-26.0.9.004-x86_64.msi` to `M:\home\brendanx\tools\Skyline-daily\`
      - Rename to `Skyline-Daily-Installer-64_26_0_9_004.msi` (historical naming convention)

   d. **Upload to FileContent** (automated via MCP):
      ```python
      # Upload ZIP
      upload_file(
          local_file_path="M:/home/brendanx/tools/Skyline-daily/Skyline-daily-64_26_0_9_004.zip",
          container_path="/home/software/Skyline/daily"
      )

      # Upload MSI
      upload_file(
          local_file_path="M:/home/brendanx/tools/Skyline-daily/Skyline-Daily-Installer-64_26_0_9_004.msi",
          container_path="/home/software/Skyline/daily"
      )
      ```

      Verify uploads with `list_files(container_path="/home/software/Skyline/daily")`.

   e. **Update wiki download pages** (automated via MCP):

      Fetch current pages, update the download URL version, then update:
      ```python
      # Get current page content
      get_wiki_page("install-disconnected-64", container_path="/home/software/Skyline/daily")
      get_wiki_page("install-administrator-64", container_path="/home/software/Skyline/daily")

      # Update pages with new version (change _004 to _021 etc. in download URLs)
      update_wiki_page("install-disconnected-64", container_path="/home/software/Skyline/daily", body_file="ai/.tmp/wiki-page-updated.html")
      update_wiki_page("install-administrator-64", container_path="/home/software/Skyline/daily", body_file="ai/.tmp/wiki-page-updated.html")
      ```

   f. **VERIFY downloads before proceeding**:

      **This step is critical** - verify the uploads and wiki updates worked correctly:

      1. Open both wiki pages in a web browser:
         - https://skyline.ms/home/software/Skyline/daily/wiki-page.view?name=install-disconnected-64
         - https://skyline.ms/home/software/Skyline/daily/wiki-page.view?name=install-administrator-64

      2. Click "I Agree" and then "Download" on each page

      3. Verify both files download successfully and are the correct size

      Only proceed to Docker deployment after confirming downloads work.

13. **Publish Docker image** to DockerHub (see `/home/development/DeployToDockerHub` wiki):
   - For FEATURE COMPLETE (release candidates): [Skyline-release-daily](https://teamcity.labkey.org/buildConfiguration/ProteoWizard_ProteoWizardPublishDockerImageSkylineReleaseDaily)
   - For final release: [Skyline Release Branch](https://teamcity.labkey.org/viewType.html?buildTypeId=ProteoWizard_ProteoWizardPublishDockerAndSingularityImagesSkylineReleaseBranch)

   **Before clicking Deploy**: Check Settings > Dependencies to verify dependency builds:
   - ProteoWizard and Skyline (release branch) Docker container (Wine x86_64) - **the actual Docker image**

   This config depends on:
   - Core Windows x86_64 (Skyline release branch)
   - Skyline Release Branch x86_64

   This is a double-check of work already verified in step 6. The Deploy button publishes
   from the Docker container build, not from a new build.

   **Claude can also verify** using the TeamCity MCP (see [mcp/team-city.md](mcp/team-city.md)):
   ```
   search_builds(build_type_id="ProteoWizard_ProteoWizardAndSkylineReleaseBranchDockerContainerWineX8664", count=3)
   ```

   - Verify at [DockerHub Tags](https://hub.docker.com/r/proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses/tags) after deployment

   **Verify via API** (Claude can do this automatically):
   ```bash
   curl -s "https://hub.docker.com/v2/repositories/proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses/tags?page_size=5"
   ```
   Look for tag matching `skyline_daily_26.0.9.021-722d843` with recent `last_updated` timestamp.

   **Optional: Test Docker image locally** (requires Docker Desktop in Linux container mode):
   ```bash
   # Pull the new image
   docker pull proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:skyline_daily_26.0.9.004-7b2495b

   # Verify SkylineCmd works (use MSYS_NO_PATHCONV on Windows Git Bash)
   MSYS_NO_PATHCONV=1 docker run --rm --entrypoint /bin/bash \
     proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:skyline_daily_26.0.9.004-7b2495b \
     -c "WINEPREFIX=/wineprefix64 wine /wineprefix64/drive_c/pwiz/skyline/SkylineCmd.exe --version"

   # Expected output:
   # Skyline-daily (64-bit : automated build) 26.0.9.004 (7b2495b)
   #     ProteoWizard MSData 3.0.26004
   ```

   Notes:
   - Docker Desktop must be in **Linux container mode** (right-click tray icon to switch)
   - The `MSYS_NO_PATHCONV=1` prefix prevents Git Bash from mangling Linux paths
   - Replace the tag with your actual release version

14. **Post release notes**:

   Two destinations — skyline.ms announcement (automated) and MailChimp email (manual):

   **a. Post to skyline.ms** (automated via MCP):

   After the developer approves the draft release notes (see "Writing Release Notes" below),
   post directly using `post_announcement`:

   ```python
   # Skyline-daily and FEATURE COMPLETE — post to /daily container
   post_announcement(
       title="Skyline-daily 26.0.9.021",
       body_file="ai/.tmp/release-notes-26.0.9.021.md",
       container_path="/home/software/Skyline/daily",
   )
   ```

   Note: Major releases use a different container — see the "Skyline (release)" workflow.

   This posts through LabKey's announcement controller, which sends email notifications
   to subscribers of the container. The body should use Markdown format matching the
   release notes templates below.

   **b. Email via MailChimp** (manual — not yet automated):

   **Email list scope** (both are open signup, opt-in):
   - Major releases → entire active Skyline list (~23,500 users)
   - Skyline-daily releases → beta signup list only (~5,000 users)

   See `/home/development/User Signups` for signup analytics dashboard.

   **MailChimp workflow**:
   - Copy previous release email as template (preserves formatting and font sizes)
   - Replace version numbers in subject and body
   - Replace bullet list with new release notes
   - **Gotcha**: When copying from previous email, carefully remove ALL old content.
     Keeping one bullet to preserve font size can leave stale features at the end.
   - **Send test email to Claude** for review before sending to list. Claude can
     access the test email via Gmail MCP and verify: correct version numbers,
     no leftover content from previous releases, proper attributions, etc.
   - Query previous releases with `query_support_threads(container_path="/home/software/Skyline/daily")`
     to check if features were already announced

15. **Update tutorial.js to show version link** (after first release is published):

   Edit `pwiz_tools/Skyline/Documentation/tutorial.js` on the release branch:
   ```javascript
   var altVersion = '26-0-9';  // Update to match the release version
   ```

   This makes tutorial wiki pages show an `[html 26.0.9]` link to the versioned tutorials
   copied in step 2. Commit and push to the release branch.

16. Continue stabilization on release branch, daily development on master

**Why version calculation works**: Since versioning is now based on git commit date (not build time), we can calculate the exact version before committing. The tagged commit accurately represents the build.

### Skyline (release)

Official stable release. This transforms the FEATURE COMPLETE release branch into the
official Skyline product (not Skyline-daily). The product name, icon, and install paths
all change. The release goes to the full Skyline user base (~23,500 users).

See also the `release-prep` wiki page in `/home/development` on skyline.ms.

**Key concepts:**
- **Release branch continues**: No new branch — work on the existing `Skyline/skyline_YY_N`
- **Two commit phases**: Some changes cherry-pick to master, others stay release-only
- **Same-day daily release**: After the major release, update master and release 26.1.1 so
  Skyline-daily users see new features accumulated during FEATURE COMPLETE
- **Release branch becomes patch-only**: After the major release, the bar for cherry-picks
  to the release branch goes up — only bug fixes for patch releases

**Workflow**:

#### Phase 1: Pre-release code changes (cherry-pick to both branches)

These changes are needed on **both** the release branch and master. Commit to the release
branch via PR, then cherry-pick to master.

1. **Update DocumentFormat, SkylineVersion, and XSD schema**:

   - `Model/Serialization/DocumentFormat.cs`: Add a new format constant for 26.1, update `CURRENT`
   - `Model/SkylineVersion.cs`: Add `V26_1` to `SupportedForSharing()` list
   - `TestUtil/Schemas/`: Copy the latest schema (e.g., `Skyline_25.11.xsd`) to `Skyline_26.1.xsd`

   See "Version-Format-Schema Dependency" above for why these must stay synchronized.

2. **Update copyright year** in the About box:

   - `Alerts/AboutDlg.resx`: Update "Copyright (c) 2008-20XX" to current year
   - `Alerts/AboutDlg.ja.resx`: Same update for Japanese localization
   - `Alerts/AboutDlg.zh-CHS.resx`: Same update for Chinese localization

3. **Replace "Skyline-daily" assembly references in all RESX files** with "Skyline":

   ```bash
   pwsh -Command "& 'ai/scripts/Skyline/Replace-SkylineDailyResx.ps1' -SkylineDir 'pwiz_tools/Skyline'"
   ```

   This replaces `Skyline-daily, Version=XX.X.X.XXX,` with `Skyline, Version=1.0.0.0,`
   in all `.resx` files (excluding `Executables/AutoQC` and `Executables/SharedBatch` which
   have intentional user-facing "Skyline-daily" references). Use `-DryRun` to preview.
   This prevents sending "Skyline-daily" strings to translators. Cherry-picking to master
   means both branches have clean strings.

4. **Commit to release branch via PR**, then cherry-pick to master.

5. **Bump `SKYLINE_YEAR` on the master cherry-pick branch** in Jamfile.jam:

   When Phase 1 sets `DocumentFormat.CURRENT` to the new release version (e.g., 26.1),
   master's Jamfile must also advance so `TestDocumentFormatCurrent` passes. This test
   asserts that `DocumentFormat.CURRENT` matches the Skyline version derived from the
   Jamfile. On master, change only `SKYLINE_YEAR` — leave `ORDINAL` and `BRANCH` as-is:
   ```jam
   constant SKYLINE_YEAR : 26 ;      # Was 25 — advance to match DocumentFormat 26.1
   constant SKYLINE_ORDINAL : 1 ;    # Keep existing value
   constant SKYLINE_BRANCH : 1 ;     # Keep as daily
   ```
   This produces version 26.1.1.DDD on master, which is within 0.1 of DocumentFormat 26.1.

   > **Note**: This effectively moves the Phase 8 Jamfile update forward. Phase 8 no longer
   > needs a separate Jamfile change — it just confirms the daily release is working.

#### Phase 2: Release-only changes (release branch only — NOT cherry-picked to master)

These changes transform the product from Skyline-daily to Skyline. They stay on the
release branch permanently — master continues as Skyline-daily.

6. **Set version on release branch** in Jamfile.jam:
   ```jam
   constant SKYLINE_YEAR : 26 ;
   constant SKYLINE_ORDINAL : 1 ;   # First official release
   constant SKYLINE_BRANCH : 0 ;    # Release
   ```

7. **Product rename — Find-in-Files "Skyline-daily" → "Skyline"** across the project tree:

   Key files to check:
   - `Skyline.csproj` — product name, assembly name
   - `Executables/Installer/FileList64-template.txt`
   - Any other occurrences found by searching `*.*` (use Notepad++ for thorough sweep)
   - **Skip** items intentionally marked as "keep" (references to the daily product concept)

8. **Swap the application icon and About box image**:
   - Copy `Skyline_Release.ico` over `Skyline.ico` (taskbar/window icon)
   - Copy `Resources/Skyline_Release.bmp` over `Resources/Skyline.bmp` (Help > About image)

   Both `Skyline.ico` and `Resources/Skyline.bmp` are normally identical to their
   `_Daily` variants (red "daily" banner and white arrow on red background). For
   release, they get replaced with the `_Release` variants (clean skyline image).

9. **Update version in Skyline.csproj**:
   ```xml
   <ApplicationRevision>DDD</ApplicationRevision>
   <ApplicationVersion>26.1.0.DDD</ApplicationVersion>
   ```

   Calculate DDD from the planned commit date:
   ```
   DDD = (year_2digit - SKYLINE_YEAR) * 365 + day_of_year
   ```

   **WARNING**: Never commit `<SignManifests>true</SignManifests>`. Always revert this line.

10. **Update publish settings** in `Skyline.csproj.user`:
   - ClickOnce path: `T:\www\site\skyline.ms\html\software\Skyline-release-64_26_1\`
   - Installation URL: `https://skyline.gs.washington.edu/software/Skyline-release-64_26_1/`

#### Phase 3: Build, test, verify

11. **Build**: `clean.bat && bso.bat` from the release folder (e.g., `skyline_26_1`)

    **IMPORTANT**: Verify this is a **Release** build, not Debug.

    Verify version: `pwiz_tools\Skyline\bin\x64\Release\SkylineCmd --version`
    should show `Skyline (64-bit) 26.1.0.DDD` (note: "Skyline" not "Skyline-daily").

12. **Test installation with upgrade from previous version**:
    - Install the previous release (e.g., Skyline 25.1)
    - Upgrade to the new 26.1 build
    - Verify the upgrade completes successfully
    - **Test Koina connection** — make sure it connects after upgrade

13. **Commit** all release-only changes to the release branch via PR.
    **DO NOT cherry-pick to master.** These changes (product rename, icon, version) are
    release-branch-specific.

14. **Tag the release**:
    ```bash
    git tag Skyline-26.1.0.DDD
    git push origin Skyline-26.1.0.DDD
    ```
    Note: Official releases use `Skyline-` prefix (no "daily").

#### Phase 4: Publish installers

Major release installers use **different paths** than Skyline-daily:
- ClickOnce goes to `Skyline-release-64_YY_N` (not `Skyline-daily13-64`)
- ZIP/MSI go to `M:\home\brendanx\tools\Skyline\` (not `Skyline-daily\`)
- Uploads go to `/home/software/Skyline` container (not `/home/software/Skyline/daily`)
- File names use `Skyline-64_` prefix (not `Skyline-daily-64_`)

15. **ClickOnce to website** (Visual Studio Project Properties):

    **Publish tab**:
    - Publishing Folder Location: `T:\www\site\skyline.ms\html\software\Skyline-release-64_26_1\`
      (this directory must be created — it's a new folder for each major version)
    - Installation Folder URL: `https://skyline.gs.washington.edu/software/Skyline-release-64_26_1/`
    - Install Mode: "The application is available offline as well (launchable from Start menu)"
    - Publish Version: Set to match build (e.g., 26.1.0.DDD)
    - "Automatically increment revision with each publish" — **unchecked**

    **Updates button** (Application Updates dialog):
    - "The application should check for updates" — **unchecked**
    - Update location: `https://skyline.gs.washington.edu/software/Skyline-release-64_26_1/`

    **Signing tab**:
    - "Sign the ClickOnce manifests" — **checked**
    - Certificate: University of Washington (DigiCert, expires 2/28/2027)
    - "Sign the assembly" — **unchecked**

    Click **Publish Now**

16. **ZIP to nexus server** (disk publish for disconnected install):

    Change VS Publish settings for disk (no URLs):
    - Publishing Folder Location: `M:\home\brendanx\tools\Skyline\Skyline-64_26_1_0_DDD\`
    - Installation Folder URL: **empty**
    - Updates > Update location: **empty**

    Click **Publish Now**, then create the ZIP:
    ```powershell
    # From M:\home\brendanx\tools\Skyline\
    Compress-Archive -Path 'Skyline-64_26_1_0_DDD' -DestinationPath 'Skyline-64_26_1_0_DDD.zip'
    ```

    **IMPORTANT**: The ZIP must contain the folder as the root entry (not just contents).

17. **MSI preparation**:
    - Copy `bin\x64\Skyline-26.1.0.DDD-x86_64.msi` to `M:\home\brendanx\tools\Skyline\`
    - Rename to `Skyline-Installer-64_26_1_0_DDD.msi`

18. **Upload to FileContent** (automated via MCP):
    ```python
    # Upload ZIP — note: /home/software/Skyline (not /daily)
    upload_file(
        local_file_path="M:/home/brendanx/tools/Skyline/Skyline-64_26_1_0_DDD.zip",
        container_path="/home/software/Skyline",
        subfolder="installers"
    )

    # Upload MSI
    upload_file(
        local_file_path="M:/home/brendanx/tools/Skyline/Skyline-Installer-64_26_1_0_DDD.msi",
        container_path="/home/software/Skyline",
        subfolder="installers"
    )
    ```

    Verify uploads with `list_files(container_path="/home/software/Skyline", subfolder="installers")`.

19. **Update wiki download pages** in `/home/software/Skyline` (automated via MCP):

    Two pages need updating:
    ```python
    # ZIP download page
    get_wiki_page("install-64-disconnected", container_path="/home/software/Skyline")
    # Update: title to "Skyline 26.1", download URL to new ZIP, add 25.1 to archive list
    update_wiki_page("install-64-disconnected", container_path="/home/software/Skyline", body_file="ai/.tmp/wiki-page-updated.html")

    # MSI download page
    get_wiki_page("install-administator-64", container_path="/home/software/Skyline")
    # Update: title to "Skyline 26.1", download URL to new MSI
    update_wiki_page("install-administator-64", container_path="/home/software/Skyline", body_file="ai/.tmp/wiki-page-updated.html")
    ```

20. **VERIFY downloads** before proceeding:

    1. Open both wiki pages in a browser
    2. Click "I Agree" and then "Download"
    3. Verify both files download successfully and are the correct size

#### Phase 5: Docker

21. **Deploy Docker image** via TeamCity:
    - Use [Skyline Release Branch publish](https://teamcity.labkey.org/viewType.html?buildTypeId=ProteoWizard_ProteoWizardPublishDockerAndSingularityImagesSkylineReleaseBranch) (not the daily one)
    - First verify the release branch Docker container build succeeded (in TeamCity UI or via MCP):
      ```
      search_builds(build_type_id="ProteoWizard_ProteoWizardAndSkylineReleaseBranchDockerContainerWineX8664", count=3)
      ```
    - Verify at [DockerHub Tags](https://hub.docker.com/r/proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses/tags)

#### Phase 6: Website and wiki updates

22. **Create new install page** `SkylineInstall_64_26-1`:
    - Copy content from the previous version's page (`SkylineInstall_64_25-1`)
    - Update all version references (25.1 → 26.1)
    - Update the ClickOnce install URL to the new `Skyline-release-64_26_1` path

    **GOTCHA — Infinite refresh loop**: The install page contains JavaScript that
    redirects to itself (e.g., `SkylineInstall_64_26-1&submit=false`). If you rename
    the page but don't update the JavaScript self-references, the page enters an
    infinite refresh loop. Search for ALL occurrences of the old version in the page
    body — there are typically 5 references: 3 `SkylineInstall_64_` links and
    2 `Skyline-release-64_` ClickOnce paths.

23. **Update the `default` (homepage) wiki page** in `/home/software/Skyline`:
    - Change install button link from `SkylineInstall_64_25-1` to `SkylineInstall_64_26-1`
    - Change button text (e.g., "Skyline 25.1 - 64 bit" → "Skyline 26.1")

24. **Update short URL redirects**:
    - `skyline64.url` must redirect to the new install page (`SkylineInstall_64_26-1`)
    - Check for any other short URLs containing old version numbers

25. **Tutorial versioning**:
    - Copy tutorials to release directory on the web server:
      ```cmd
      xcopy /E /I <release folder>\pwiz_tools\Skyline\Documentation\Tutorials T:\www\site\skyline.ms\html\tutorials\26-1
      ```
    - Update `pwiz_tools/Skyline/Documentation/tutorial.js` on the release branch:
      ```javascript
      var tutorialVersion = '26-1';         // New stable release
      var tutorialAltVersion = '';           // Clear pre-release (no more 26-0-9)
      ```

26. **Update Release Notes wiki page** (`Release Notes` in `/home/software/Skyline`):
    - Add "Skyline v26.1" section at the top with the full feature list

#### Phase 7: Announcements (before first post-release daily)

The release email goes out **before** updating master for the first post-release
Skyline-daily. This ensures the major release announcement is the first thing users see.

27. **Generate major release notes** — see "Generating Major Release Notes" below.
    This aggregates all Skyline-daily announcements since the last major release,
    removes attribution and cycle-internal fixes, and reorganizes by importance.

28. **Post to skyline.ms** (automated via MCP):
    ```python
    # Major releases go to /releases container (NOT /daily)
    post_announcement(
        title="Skyline 26.1 Release",
        body_file="ai/.tmp/release-notes-26.1.0.057.md",
        container_path="/home/software/Skyline/releases",
    )
    ```

29. **Update Release Notes wiki page** (`Release Notes` in `/home/software/Skyline`):
    Add a "Skyline v26.1 Released on MM/DD/YYYY" section at the top.

30. **MailChimp email** to the full Skyline list (~23,500 users):
    - Major releases go to the **entire** Skyline list (not just the beta list)
    - Copy previous major release email as template
    - See MailChimp workflow in the Release Notes section below
    - See "Release Notes Templates" for the major release template

#### Phase 8: Master branch update and first Skyline-daily

31. **Verify master Jamfile is already at 26.1.1**: The Phase 1 cherry-pick to master
    included bumping `SKYLINE_YEAR` (see Phase 1 step 5), so master should already be
    producing version 26.1.1.DDD. Confirm with `gh pr checks` that the cherry-pick PR
    passed all CI checks.

32. **First Skyline-daily 26.1.1.DDD** releases from master via the normal nightly build
    process. This should happen on the same day as the major release so Skyline-daily users
    see 26.1.1 as an upgrade containing new features accumulated during FEATURE COMPLETE,
    rather than switching to the nearly-identical 26.1.0.

    After this point:
    - **Master** continues as the Skyline-daily development branch (26.1.1.DDD)
    - **Release branch** is used only for patch releases (26.1.0.DDD with new day numbers)
    - The bar for cherry-picks to the release branch goes up — critical bug fixes only

### Skyline (patch)

Bug fixes to an existing stable release. Patches are published from the same release
branch using the same install paths as the major release.

**Key concepts:**
- **Same branch, same paths**: Patches use the existing `Skyline/skyline_YY_N` branch and
  publish to the same ClickOnce/ZIP/MSI locations as the major release
- **Higher bar**: Only critical bug fixes that affect released users — not new features
- **Cherry-pick from master**: Fixes are typically developed on master first, then
  cherry-picked to the release branch
- **Version stays at BRANCH=0**: Same `SKYLINE_ORDINAL` and `SKYLINE_BRANCH` as the
  major release — only the day number (DDD) changes

**Workflow**:

1. **Cherry-pick or commit fixes** to the release branch
2. **Calculate new version**: Same formula, new day number (e.g., `26.1.0.090`)
3. **Update version** in `Skyline.csproj`:
   ```xml
   <ApplicationRevision>DDD</ApplicationRevision>
   <ApplicationVersion>26.1.0.DDD</ApplicationVersion>
   ```
4. **Build and test**: `clean.bat && bso.bat`
   - Test upgrade from the previous patch (or initial release if first patch)
   - Test Koina connection
5. **Commit and tag**: `Skyline-26.1.0.DDD` (new day number)
6. **Publish installers**: Same paths as the major release (steps 15-20 above)
   - ClickOnce to `T:\...\Skyline-release-64_26_1\` (same folder, overwrites)
   - ZIP/MSI to `M:\...\Skyline\` with new version number
   - Upload to `/home/software/Skyline` container
   - Update `install-64-disconnected` and `install-administator-64` wiki pages
7. **Deploy Docker image** via TeamCity (same config as major release — see Phase 5 above)
8. **Post release notes**: Smaller announcement — typically just the bug fixes
   - Post to `/home/software/Skyline/daily` (and optionally `/releases`)
   - Update the Release Notes wiki page
   - MailChimp email to full Skyline list for significant patches

## Publish Paths Reference

Skyline-daily and Skyline (release) use **different** publish paths, naming conventions,
and skyline.ms containers. This table is the quick reference for which paths to use.

### ClickOnce (T: drive → skyline.gs.washington.edu)

| Release Type | Folder on T: drive | Installation URL |
|--------------|-------------------|------------------|
| Skyline-daily | `Skyline-daily13-64\` | `https://skyline.gs.washington.edu/software/Skyline-daily13-64/` |
| Skyline (release) | `Skyline-release-64_26_1\` | `https://skyline.gs.washington.edu/software/Skyline-release-64_26_1/` |

Note: Skyline-daily uses a fixed folder name (`Skyline-daily13-64`), while major releases
get a new folder per version (`Skyline-release-64_YY_N`).

### ZIP/MSI (M: drive → nexus server → skyline.ms upload)

| Release Type | Local folder (M:) | Upload container | File prefix |
|--------------|-------------------|-----------------|-------------|
| Skyline-daily | `Skyline-daily\` | `/home/software/Skyline/daily` | `Skyline-daily-64_` / `Skyline-Daily-Installer-64_` |
| Skyline (release) | `Skyline\` | `/home/software/Skyline` (subfolder `installers/`) | `Skyline-64_` / `Skyline-Installer-64_` |

### Wiki download pages

| Release Type | Container | ZIP page | MSI page |
|--------------|-----------|----------|----------|
| Skyline-daily | `/home/software/Skyline/daily` | `install-disconnected-64` | `install-administrator-64` |
| Skyline (release) | `/home/software/Skyline` | `install-64-disconnected` | `install-administator-64` |

Note: The page names differ slightly between daily and release (different word order,
different spelling of "administrator").

## Build Commands

### Full Release Build

```bash
# Clean build environment
pwiz_tools\Skyline\clean.bat

# Build 64-bit Skyline with all installers
pwiz_tools\Skyline\bso64.bat
```

### Quick Test Build

```bash
# Quick build to verify version
quickbuild.bat -j12 --abbreviate-paths pwiz_tools\Skyline//Skyline.exe --official
```

## Git Tags

### Tag Format

| Release Type | Tag Format | Example |
|--------------|------------|---------|
| Daily (beta) | `Skyline-daily-YY.N.1.DDD` | `Skyline-daily-25.1.1.147` |
| Feature Complete | `Skyline-daily-YY.N.9.DDD` | `Skyline-daily-26.0.9.004` |
| Official Release | `Skyline-YY.N.0.DDD` | `Skyline-26.1.0.045` |

### Creating Tags

```bash
# Create tag
git tag Skyline-daily-26.0.9.004

# Push tag
git push origin Skyline-daily-26.0.9.004
```

### Finding Tags

```bash
git fetch --tags origin
git tag -l "Skyline-daily-26*"
git show Skyline-daily-26.0.9.004 --no-patch
```

## Release Notes

### Locations

| Type | Location |
|------|----------|
| Major release | skyline.ms wiki: `/home/software/Skyline` → `Release%20Notes` |
| Skyline-daily | skyline.ms announcements: `/home/software/Skyline/daily` |

### Generating Skyline-daily Release Notes

**Step 1: Find commits since last release**

```bash
# Find last Skyline-daily tag
git fetch --tags origin
git tag -l "Skyline-daily-*" --sort=-version:refname | head -1

# Get commits since that tag
git log Skyline-daily-25.1.1.271..HEAD --oneline
```

**Step 2: Convert to user-facing summaries**

Transform developer commit messages into brief (single line) past tense summaries from a **user perspective**.

**Include:**
- Added features ("Added support for X")
- Updated functionality ("Updated method export for Thermo instruments")
- Fixed bugs ("Fixed crash when importing large files")
- Performance improvements (visible to users)

**Exclude:**
- Refactoring (internal code changes)
- Test changes
- Infrastructure/build improvements
- Anything invisible to users

**Step 3: Format each item**

- **Past tense, subjectless sentences** ending with period
- **Categories**: "Added...", "Updated...", "Fixed..."
- **New features**: Prefix with `**New!**` - use sparingly for major user-facing features only
- **Developer attribution**: `(thanks to Nick)` - not needed for Brendan (he sends the email)
- **Requester/reporter attribution**: `(requested by Philip)`, `(reported by Lillian)`
- **First names only** for all attributions
- **Look in commit body** for requester/reporter info (not in title)
- **Link to tutorials/webinars** when a feature has associated documentation (e.g., `https://skyline.ms/webinar27.url`)
- **Cherry-picked commits**: Look up the original PR to find the author:
  ```bash
  # Cherry-pick PR title shows original PR number
  gh pr view 3841 --repo ProteoWizard/pwiz --json author,title
  # If it's "Automatic cherry pick of #XXXX", look up the original:
  gh pr view XXXX --repo ProteoWizard/pwiz --json author,title
  ```

### GitHub ID to Name Mapping

| GitHub ID | First Name |
|-----------|------------|
| brendanx67, Brendan MacLean | Brendan (omit - sends email) |
| nickshulman | Nick |
| Brian Pratt | Brian |
| Matt Chambers | Matt |
| Rita Chupalov | Rita |
| vagisha | Vagisha |
| Eddie O'Neil | Eddie |
| eduardo-proteinms | Eduardo |
| danjasuw | Dan |

**Examples:**
```
- **New!** Peak boundary imputation for DIA (https://skyline.ms/webinar27.url). (thanks to Nick)
- Added support for NCE optimization for Thermo instruments. (requested by Philip)
- Fixed MS Fragger download. (thanks to Matt)
- Fixed case where library m/z tolerance got multiplied improperly.
```

### Generating Major Release Notes

Major release notes are **not** built from git commits. They are aggregated from all
Skyline-daily release announcements posted during the development cycle.

**Step 1: Collect all Skyline-daily announcements since the last major release**

```python
# List all announcements since the last major release
query_support_threads(container_path="/home/software/Skyline/daily", days=365)

# Read each announcement to extract bullet points
get_support_thread(thread_id=..., container_path="/home/software/Skyline/daily")
```

Gather every bullet point from every Skyline-daily and FEATURE COMPLETE release
announcement since the previous major release (e.g., since Skyline 25.1).

**Step 2: Remove items that don't belong in a major release announcement**

1. **Remove all attribution** — no "(thanks to Nick)", "(reported by Philip)", etc.
   The major release represents the whole team's work, not individual contributions.

2. **Remove cycle-internal fixes** — fixes to new features being developed during
   this cycle, or regressions introduced and fixed within the same cycle. These were
   never in a released product, so users don't need to know about them.

3. **Remove fixes already mentioned in patch releases** — check the `Release Notes`
   wiki page in `/home/software/Skyline` for any patch release entries (e.g.,
   "Skyline v25.1 Updated on 8/25/2025"). Those fixes were already communicated to
   users and don't need repeating.

**Step 3: Sort and organize**

The order is different from Skyline-daily notes (which are roughly chronological):

1. **`**New!**` items first** (2-5 items) — the most important new features that
   headline the release. These should be the items most likely to excite users.
2. **Other additions and improvements** — sorted by functional area (not chronologically).
   Group related items together (e.g., all DIA improvements, all small molecule changes).
3. **Fixes last** — bug fixes that survived from the previous major release.

**Step 4: Review against the Release Notes wiki page**

Check the existing `Release Notes` page to match the style and depth of previous
major releases. The 25.1 entry is a good reference for scope and formatting.

### Release Notes Templates

**FEATURE COMPLETE:**
```
Dear Skyline-daily Users,

I have just released Skyline-daily 26.0.9.DDD, our FEATURE COMPLETE release for
our next major release Skyline 26.1. This release also contains the following
improvements over the last release:

- [bullet points]

Skyline-daily should ask to update automatically when you next restart or use
Help > Check for Updates.

Thanks for using Skyline-daily and reporting the issues you find as we make
Skyline even better.

--Brendan
```

**Regular Skyline-daily:**
```
Dear Skyline-daily Users,

I have just released Skyline-daily 26.1.1.DDD. This release contains the
following improvements over the last release:

- [bullet points]

Skyline-daily should ask to update automatically when you next restart or use
Help > Check for Updates.

Thanks for using Skyline-daily and reporting the issues you find as we make
Skyline even better.

--Brendan
```

**Major release:**
```
Dear Skyline Users,

I am pleased to announce Skyline 26.1, the latest release of our free and open
source Windows application for building targeted mass spectrometry methods and
processing the resulting quantitative data.

This release contains the following improvements over Skyline 25.1:

- [comprehensive bullet points covering all features since last major release]

Skyline should ask to update automatically when you next restart or use
Help > Check for Updates. You can also download it from our website at
https://skyline.ms

Thanks for using Skyline!

--Brendan
```

**Patch release:**
```
Dear Skyline Users,

I have just released a patch to Skyline 26.1 with the following fixes:

- [bullet points]

Skyline should ask to update automatically when you next restart or use
Help > Check for Updates.

--Brendan
```

**First post-release daily:**
```
Dear Skyline-daily Users,

I have just released Skyline-daily 26.1.1.DDD, our first since the Skyline 26.1
release. This release contains the following improvements over Skyline 26.1:

- [bullet points]

...
```

### Writing and Posting Release Notes

The workflow is the same for all release types: draft to a temp file, get developer
approval, then post to the appropriate destinations.

**Step 1: Draft to temp file** for developer review:

```python
# Skyline-daily / FEATURE COMPLETE
Write("ai/.tmp/release-notes-26.0.9.021.md", content)

# Major release
Write("ai/.tmp/release-notes-26.1.0.055.md", content)
```

The developer can then:
1. Open the file in a text editor
2. Make edits (reorder items, adjust wording)
3. Save and tell Claude to read it back

**Step 2: Post announcement to skyline.ms** after developer approval:

These are separate channels — Skyline-daily and major releases do **not** cross-post.

```python
# Skyline-daily and FEATURE COMPLETE — daily container
post_announcement(
    title="Skyline-daily 26.0.9.021",
    body_file="ai/.tmp/release-notes-26.0.9.021.md",
    container_path="/home/software/Skyline/daily",
)

# Major release and patches — releases container
post_announcement(
    title="Skyline 26.1 Release",
    body_file="ai/.tmp/release-notes-26.1.0.057.md",
    container_path="/home/software/Skyline/releases",
)
```

**Step 3: Update the Release Notes wiki page** (major releases and patches only):

```python
# Fetch current page
get_wiki_page("Release Notes", container_path="/home/software/Skyline")

# Add new section at the top with the release date:
#   <h2><a name="skyline_26_1"></a>Skyline v26.1 Released on MM/DD/YYYY</h2>
#   <ul>
#   <li>...</li>
#   </ul>
# Then update the page
update_wiki_page("Release Notes", container_path="/home/software/Skyline", body_file="ai/.tmp/wiki-page-updated.html")
```

The heading format follows previous entries (e.g., "Skyline v25.1 Released on 5/22/2025").
Patch updates use "Skyline v25.1 Updated on 8/25/2025" with the patch items appended
above the original release items.

**Step 4: MailChimp email** — developer uses the same content manually in MailChimp (not yet automated).

### Querying Past Release Notes

```python
# List recent releases
query_support_threads(container_path="/home/software/Skyline/daily", days=365)

# Get specific release notes
get_support_thread(thread_id=69437, container_path="/home/software/Skyline/daily")
```

## Wiki Documentation

### Developer wiki (`/home/development`)

| Page | Purpose |
|------|---------|
| `release-prep` | Major release checklist (canonical source for release steps) |
| `installers` | General installer overview |
| `ClickOnce-installers` | ClickOnce deployment |
| `WIX-installers` | WiX-based MSI installers |
| `DeployToDockerHub` | Docker image deployment instructions |
| `test-upgrade` | Upgrade testing procedures |
| `renew-code-sign` | Certificate renewal |

### Public Skyline wiki (`/home/software/Skyline`)

These pages need updating for each major release and patch:

| Page | Purpose | Update for Major Release |
|------|---------|--------------------------|
| `SkylineInstall_64_YY-N` | Main install page (ClickOnce) | Create new page for each major version |
| `default` | Homepage with install button | Update button link and text |
| `install-64-disconnected` | ZIP download page | Update download URL, add old version to archive |
| `install-administator-64` | MSI download page | Update download URL |
| `Release Notes` | Cumulative release notes | Add new version section at top |

**Short URL redirects** that reference version numbers:
- `skyline64.url` → Points to current `SkylineInstall_64_YY-N` page

### Skyline-daily wiki (`/home/software/Skyline/daily`)

| Page | Purpose |
|------|---------|
| `install-disconnected-64` | Skyline-daily ZIP download |
| `install-administrator-64` | Skyline-daily MSI download |

## Tutorial Versioning System

Tutorial cover images on wiki pages are versioned to match Skyline releases. A centralized JavaScript system manages version numbers so they only need to be updated in one place.

### How It Works

Wiki pages use **placeholder version numbers** in image URLs that get rewritten by JavaScript:

| Placeholder | Rewrites To | Purpose |
|-------------|-------------|---------|
| `/tutorials/0-0/` | `/tutorials/25-1/` | Current stable release |
| `/tutorials/0-9/` | `/tutorials/26-0-9/` | Pre-release only (new tutorials) |

The `0-0` and `0-9` placeholders are obviously invalid versions, making it clear to anyone reading the HTML source that they will be rewritten.

### Configuration File

**Location**: `pwiz_tools/Skyline/Documentation/tutorial.js` (served as `/tutorials/tutorial.js`)

```javascript
var tutorialVersion = '25-1';       // Current stable release
var tutorialAltVersion = '26-0-9';  // Pre-release version (empty string if none)
```

The `rewriteTutorialUrls()` function transforms placeholder URLs to actual version paths when pages load.

### Wiki Pages Using This System

| Page | Language | Placeholders |
|------|----------|--------------|
| `tutorials` | English | 0-0, 0-9 |
| `tutorials_ja` | Japanese | 0-0 |
| `tutorials_zh` | Chinese | 0-0 |
| `default` | English (homepage slideshow) | 0-0, 0-9 |

Each page includes the script and calls `rewriteTutorialUrls()` at the end:
```html
<script src="/tutorials/tutorial.js"></script>
<script>rewriteTutorialUrls();</script>
```

### Release Updates

**FEATURE COMPLETE** (step 15 in workflow):
1. Copy tutorials to versioned directory (e.g., `/tutorials/26-0-9/`)
2. Update `tutorialAltVersion` in tutorial.js to show `[html 26.0.9]` link

**MAJOR release**:
1. Copy tutorials to release directory (e.g., `/tutorials/26-1/`)
2. Update `tutorialVersion` to the new release (e.g., `'26-1'`)
3. Clear `tutorialAltVersion` to empty string (no pre-release)

### Adding New Tutorials

For tutorials that only exist in pre-release (not yet in stable):
1. Use `0-9` placeholder in the image URL
2. Call `renderPagePreRelease()` instead of `renderPageRelease()` in the tutorial wiki page

When the tutorial is included in a stable release, change the placeholder to `0-0` and the render function to `renderPageRelease()`.

### Version Override Parameter

Tutorial wiki pages support `ver=` and `show=html` URL parameters:
```
https://skyline.ms/home/software/Skyline/wiki-page.view?name=tutorial_method_edit&show=html&ver=24-1
```

- `show=html` - Jump directly to tutorial content (with TOC and screenshots) instead of summary page
- `ver=24-1` - Override the default version to show tutorials from a specific release folder

Note: The short `.url` redirects (e.g., `/tutorial_method_edit.url`) don't preserve query parameters, so the full wiki URL is required for version-specific links.

### Future: Version-Locked Tutorial Links in Skyline

**Current state**: Tutorial links in `Skyline\Controls\Startup\TutorialLinkResources.resx` point to generic short URLs (e.g., `/tutorial_method_edit.url`), which always show the latest tutorial version.

**Potential enhancement**: Major releases could use full wiki URLs with version parameters:
```
/home/software/Skyline/wiki-page.view?name=tutorial_method_edit&show=html&ver=25-1
```

This would ensure users on Skyline 25.1 always see tutorials matching their UI, even after newer tutorials are published. The `ver=` parameter already works - only the .resx URLs would need updating per release.

## Future Automation: `/pw-release` Command

**Vision**: A guided slash command that walks through release workflows step-by-step.

| Type | Purpose | Documentation Status |
|------|---------|---------------------|
| `complete` | FEATURE COMPLETE release - create branch, publish, announce | **Fully documented** |
| `major` | Official stable release (e.g., 26.1.0) | **Fully documented** |
| `patch` | Bug fix to existing release | **Fully documented** |
| `rc` | Release candidate (repeat of complete workflow on existing branch) | Placeholder - expand when performed |

**Note**: `daily` builds are automated nightly from master and don't need a command.

**`rc`** (release candidate):
- Similar to `complete` but on existing branch
- Incremental testing cycle
- May have multiple RCs before major release

## Related Documentation

- **ai/docs/version-control-guide.md** - Git conventions
- **ai/docs/build-and-test-guide.md** - Building and testing
- **Jamroot.jam** - ProteoWizard version (MAKE_BUILD_TIMESTAMP)
- **pwiz_tools/Skyline/Jamfile.jam** - Skyline version constants
