# Phase 4: Gradle Configuration

**Goal**: Configure Gradle properties for PostgreSQL and LabKey deployment.

## Prerequisites
- Repositories cloned
- PostgreSQL running with labkey database

## Step 4.1: About Gradle Wrapper

LabKey uses the Gradle wrapper (`gradlew.bat` on Windows) which automatically downloads the correct Gradle version. **Do not install Gradle separately.**

Verify the wrapper exists:
```powershell
Test-Path $enlistmentPath\gradlew.bat  # Should be True
```

> **PowerShell vs Command Prompt:** The LabKey documentation shows `gradlew deployApp`, which works in Command Prompt (cmd). In PowerShell, you must prefix with `.\` to run executables in the current directory:
>
> | Shell | Command |
> |-------|---------|
> | Command Prompt (cmd) | `gradlew deployApp` |
> | PowerShell | `.\gradlew deployApp` |
```

**Update state.json**:
```json
{"completed": ["phase-4-step-4.1"]}
```

## Step 4.2: Create Global Gradle Properties

**First, check if gradle.properties already exists:**

```powershell
Test-Path "$env:USERPROFILE\.gradle\gradle.properties"
```

- If `True` → Skip to "Verify Artifactory properties" below
- If `False` → Continue with creating the file

**Create the global Gradle properties file from the template:**

```powershell
# Check and create .gradle directory if needed
if (-not (Test-Path "$env:USERPROFILE\.gradle")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.gradle" -Force
}

# Copy template (if it exists)
$templatePath = "$enlistmentPath\gradle\global_gradle.properties_template"
$targetPath = "$env:USERPROFILE\.gradle\gradle.properties"

if (Test-Path $templatePath) {
    Copy-Item $templatePath $targetPath
    Write-Host "Copied template to $targetPath"
} else {
    Write-Host "Template not found at $templatePath - creating minimal file"
}
```

**Verify the file was copied:**
```powershell
Test-Path "$env:USERPROFILE\.gradle\gradle.properties"  # Should be True
```

**Update state.json**:
```json
{"completed": ["phase-4-step-4.2"]}
```

## Step 4.3: Verify Artifactory properties

**Important:** After copying the template, uncomment and set the Artifactory properties (even if empty):

```powershell
notepad "$env:USERPROFILE\.gradle\gradle.properties"
```

Find these lines and uncomment them:
```properties
artifactory_user=
artifactory_password=
```

> **Why?** The Gradle build requires these properties to be *defined*, even if empty. Empty values work for public modules (anonymous Artifactory access). Valid credentials are only needed for premium/private modules or publishing artifacts.

Edit `~/.gradle/gradle.properties` and configure:
- Set `systemProp.labkey.server=<build directory>` if you want builds outside the enlistment
- Configure any proxy settings if behind a corporate firewall

**Update state.json**:
```json
{"completed": ["phase-4-step-4.3"]}
```

## Completion

Gradle properties configured. Database connection will be configured in Phase 5 after verifying Java environment.

**Next**: Phase 5 - Initial Build (includes terminal restart and database configuration)
