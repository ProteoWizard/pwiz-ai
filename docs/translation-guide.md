# Translation Guide

Guide for updating localized RESX files and preparing translation tables for Japanese (ja) and Chinese Simplified (zh-CHS) translations.

## Overview

Skyline maintains translations in two languages:
- **Japanese (ja)** - `.ja.resx` files
- **Chinese Simplified (zh-CHS)** - `.zh-CHS.resx` files

The translation workflow involves:
1. Syncing localized RESX files with English (copying non-text properties)
2. Generating CSV files with strings needing translation
3. Sending CSVs to translators
4. Importing translated CSVs back into RESX files

## Tools

### ResourcesOrganizer

Location: `pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer/`

A .NET 8 tool that:
- Reads RESX files into a SQLite database
- Compares current resources against `LastReleaseResources.db`
- Generates localization CSV files for translators
- Imports translated CSVs back into RESX files

### LastReleaseResources.db

Location: `pwiz_tools/Skyline/Translation/LastReleaseResources.db`

SQLite database containing resources from the last major release. Used to:
- Identify which strings are new or changed
- Preserve existing translations for unchanged strings

## Boost Build Targets

### IncrementalUpdateResxFiles

**When to use**: During development cycle when UI changes occur.

**What it does**:
- Updates `.ja.resx` and `.zh-CHS.resx` files
- Syncs non-text properties (layout, size, location) from English RESX files
- Reverts to English any strings NOT found in `LastReleaseResources.db`
- Does NOT add "NeedsReview:" comments

**How to run**:
```cmd
cd C:\proj\pwiz
quickbuild.bat address-model=64 pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer//IncrementalUpdateResxFiles
```

### FinalizeResxFiles

**When to use**: After visual freeze (FEATURE COMPLETE), before sending to translators.

**What it does**:
- Everything `IncrementalUpdateResxFiles` does, PLUS
- Adds "NeedsReview:" comments to strings that changed since last release
- These comments mark strings that need translator review

**How to run**:
```cmd
cd C:\proj\pwiz
quickbuild.bat address-model=64 pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer//FinalizeResxFiles
```

## Post-Processing: Revert Whitespace-Only Changes

After running the Boost Build targets, some files may have whitespace-only changes (e.g., tab-to-space conversion in XML comments). These should be reverted to keep the diff clean.

**Script**: `ai/scripts/revert-whitespace-only-files.ps1`

```powershell
# Preview which files would be reverted
pwsh -Command "& './ai/scripts/revert-whitespace-only-files.ps1' -WhatIf"

# Revert whitespace-only changes
pwsh -Command "& './ai/scripts/revert-whitespace-only-files.ps1'"
```

## Generating Translation CSVs

After running `FinalizeResxFiles`, generate CSV files for translators:

```cmd
cd C:\proj\pwiz
pwiz_tools\Skyline\Executables\DevTools\ResourcesOrganizer\scripts\GenerateLocalizationCsvFiles.bat
```

**Output files** (in `pwiz_tools/Skyline/Translation/Scratch/`):
- `localization.ja.csv` - Japanese translation table
- `localization.zh-CHS.csv` - Chinese Simplified translation table

These CSVs contain only strings with "NeedsReview:" comments.

## Validation Before Sending CSVs

After running `FinalizeResxFiles` and generating CSVs, validate that all CSV entries exist in the localized RESX files. This catches bugs where the RESX sync process failed to add entries.

**Script**: `ai/scripts/Skyline/scripts/Validate-TranslationCsvSync.ps1`

```powershell
# Validate Japanese - every CSV entry should exist in .ja.resx files
pwsh -Command "& './ai/scripts/Skyline/scripts/Validate-TranslationCsvSync.ps1' -CsvPath 'pwiz_tools/Skyline/Translation/Scratch/localization.ja.csv' -Language ja"

# Validate Chinese - every CSV entry should exist in .zh-CHS.resx files
pwsh -Command "& './ai/scripts/Skyline/scripts/Validate-TranslationCsvSync.ps1' -CsvPath 'pwiz_tools/Skyline/Translation/Scratch/localization.zh-CHS.csv' -Language zh-CHS"
```

**Expected result**: SUCCESS with 0 missing entries. If entries are missing, there's a bug in `FinalizeResxFiles` or the export process (e.g., missing `--overrideAll` flag).

**Do not send CSVs to translators until validation passes.**

### Understand the CSV Issue Types

The generated CSVs contain an `Issue` column indicating why each string needs review:

| Issue Type | Meaning | Translator Action |
|------------|---------|-------------------|
| `New resource` | String is new since last release | Translate from scratch |
| `English text changed` | English changed, translation may be stale | Review and update translation |
| `Missing translation` | No translation exists | Translate from scratch |
| `Inconsistent translation` | Same English has different translations elsewhere | Review for consistency |

## Importing Translated CSVs

After receiving translated CSVs back from translators:

```cmd
cd C:\proj\pwiz\pwiz_tools\Skyline\Translation\Scratch

# Import the CSV files into the database
..\Executables\DevTools\ResourcesOrganizer\scripts\exe\ResourcesOrganizer.exe importLocalizationCsv

# Export updated RESX files
..\Executables\DevTools\ResourcesOrganizer\scripts\exe\ResourcesOrganizer.exe exportResx resxFiles.zip

# Extract to project root
cd C:\proj\pwiz
libraries\7za.exe x -y pwiz_tools\Skyline\Translation\Scratch\resxFiles.zip
```

### Understanding "Needs Review" Comment Behavior

When translations are imported, the `Issue` column in the CSV controls whether "Needs Review:" comments remain:

| CSV Issue Column | Result in RESX |
|------------------|----------------|
| Empty/cleared | Comment removed (translation accepted) |
| `English text changed` | Comment kept (reviewer should verify) |
| `Inconsistent translation` | Comment kept (reviewer should verify) |

**This is intentional**: Some comments persist to flag entries that still need human review even after translation. If translators clear the Issue column, they're indicating the translation is final.

### What to Expect in the PR

When reviewing a translation import PR, expect:

- **Mostly additions** if many "New resource" strings existed in the CSV
- **Replacements** where English text was replaced with translated text
- **Persistent "Needs Review:" comments** for `English text changed` and `Inconsistent translation` entries

If you see an unexpectedly large number of **additions** (new entries added to localized RESX files rather than replacements), this may indicate:
1. Many new strings were added since the last release (normal)
2. A bug in the RESX sync process where localized files weren't updated (investigate)

### Troubleshooting: Localized files missing entries

If localized RESX files are missing entries that exist in English files:

1. Check that `FinalizeResxFiles` (or `IncrementalUpdateResxFiles`) ran successfully
2. Verify the batch scripts are passing correct flags (e.g., `--overrideAll` for final exports)
3. Compare entry counts between English and localized files

**Historical note (PR #3804)**: A bug in `UpdateResxFiles.bat` failed to pass `--overrideAll` to the export step, causing new entries to be missing from localized files until translations were imported. This was fixed in January 2026.

## Workflow Summary

### During Development (Incremental Update)

1. Create a working branch from master
2. Run `IncrementalUpdateResxFiles`
3. Run `revert-whitespace-only-files.ps1` to clean up whitespace-only changes
4. Review changes and commit
5. Create PR

### At Feature Complete

1. Run `FinalizeResxFiles` - adds "NeedsReview:" comments
2. Run `revert-whitespace-only-files.ps1` to clean up
3. Run `GenerateLocalizationCsvFiles.bat` - creates CSV files
4. **Run `Validate-TranslationCsvSync.ps1`** - verify all CSV entries exist in RESX files
5. Send CSV files to translators (only if validation passes)
6. Wait for translations

### After Receiving Translations

1. Place translated CSVs in `Translation/Scratch/`
2. Run `importLocalizationCsv`
3. Run `exportResx`
4. Extract ZIP to project root
5. Build and test

## File Locations

| File/Folder | Purpose |
|-------------|---------|
| `pwiz_tools/Skyline/Translation/` | Translation working directory |
| `Translation/LastReleaseResources.db` | Baseline from last major release |
| `Translation/Scratch/` | Working directory for CSV and DB files |
| `Executables/DevTools/ResourcesOrganizer/scripts/` | Batch scripts |
| `Executables/DevTools/ResourcesOrganizer/Jamfile.jam` | Boost Build targets |
| `ai/scripts/revert-whitespace-only-files.ps1` | Clean up whitespace-only changes |
| `ai/scripts/Skyline/scripts/Validate-TranslationCsvSync.ps1` | Validate CSV entries exist in RESX files |

## Related Documentation

- **ai/docs/release-guide.md** - Release management overview
- **ai/docs/screenshot-update-workflow.md** - Screenshots and RESX sync notes
- **pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer/README.md** - Tool documentation
