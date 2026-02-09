# Phase 4: Gradle Configuration

**Goal**: Configure Gradle properties for PostgreSQL and LabKey deployment.

## Prerequisites
- Repositories cloned

## Step 4.1: About Gradle Wrapper

LabKey uses the Gradle wrapper (`gradlew.bat` on Windows) which automatically downloads the correct Gradle version. **Do not install Gradle separately.**

Verify the wrapper exists:
```bash
powershell.exe -Command 'Test-Path "<labkey_root>\gradlew.bat"'  # Should output True
```

> **PowerShell vs Command Prompt:** The LabKey documentation shows `gradlew deployApp`, which works in Command Prompt (cmd). In PowerShell, you must prefix with `.\` to run executables in the current directory:
>
> | Shell | Command |
> |-------|---------|
> | Command Prompt (cmd) | `gradlew deployApp` |
> | PowerShell | `.\gradlew deployApp` |

**Update state.json**:
```json
{"completed": ["phase-4-step-4.1"]}
```

## Step 4.2: Create Global Gradle Properties

**First, check if gradle.properties already exists:**

```bash
powershell.exe -Command 'Test-Path "$env:USERPROFILE\.gradle\gradle.properties"'
```

- If `True` → Skip to "Verify Artifactory properties" below
- If `False` → Continue with creating the file

**Create the global Gradle properties file from the template:**

> **Note:** Single quotes around the PowerShell command are required — they prevent Git Bash from
> stripping `$env:USERPROFILE` before PowerShell sees it.

```bash
powershell.exe -Command '
if (-not (Test-Path "$env:USERPROFILE\.gradle")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.gradle" -Force
}
$templatePath = "<labkey_root>\gradle\global_gradle.properties_template"
$targetPath = "$env:USERPROFILE\.gradle\gradle.properties"
if (Test-Path $templatePath) {
    Copy-Item $templatePath $targetPath
    Write-Host "Copied template to $targetPath"
} else {
    Write-Host "Template not found at $templatePath - creating minimal file"
}
'
```

**Verify the file was copied:**
```bash
powershell.exe -Command 'Test-Path "$env:USERPROFILE\.gradle\gradle.properties"'  # Should output True
```

**Update state.json**:
```json
{"completed": ["phase-4-step-4.2"]}
```

## Step 4.3: Verify Artifactory properties

**Important:** After copying the template, uncomment and set the Artifactory properties (even if empty).

**Read the gradle.properties file** using the Read tool on `$env:USERPROFILE\.gradle\gradle.properties`.

**Update the file** using the Edit tool to uncomment these lines (remove the `#`):
```properties
artifactory_user=
artifactory_password=
```

Leave them empty (empty values work for public modules with anonymous Artifactory access).

> **Why?** The Gradle build requires these properties to be *defined*, even if empty. Empty values work for public modules (anonymous Artifactory access). Valid credentials are only needed for premium/private modules or publishing artifacts.


**Update state.json**:
```json
{"completed": ["phase-4-step-4.3"]}
```

## Completion

Gradle properties configured. Database connection will be configured in Phase 5 after verifying Java environment.

**Next**: Phase 5 - Initial Build (includes terminal restart and database configuration)
