# Switching LabKey Versions

Use this guide when you want to move an existing development environment to a
different (typically newer) LabKey version.

## Version Requirements

| LabKey Version   | Java Required     | PostgreSQL Support     |
|------------------|-------------------|------------------------|
| 25.7.x and lower | Java 17 (Temurin) | PostgreSQL 17 only     |
| 25.11.x          | Java 17 (Temurin) | PostgreSQL 17 or 18    |
| 26.x             | Java 25 (Temurin) | PostgreSQL 18          |

For versions not listed, check https://www.labkey.org/Documentation/wiki-page.view?name=supported

## Recommended Claude Prompt

Start a new Claude Code session from `C:\Users\vsharma\WORK` and use this prompt:

```
I want to switch my LabKey development environment from version <current> to
<target> (e.g. release26.3-SNAPSHOT). My repos are checked out in
<path-to-enlistment-root>. Please read the dev machine setup docs in
pwiz-ai/docs/labkey-setup and guide me through the version switch.
```

Replace `<current>` and `<target>` with actual version strings (e.g. `25.11` and `26.3`),
and `<path-to-enlistment-root>` with the directory containing `build.gradle` and `gradlew.bat`
(e.g. `labkey/release-branch`).

## Steps

### 1. Switch all repos to the new branch

**Claude performs this step** — do not ask the user to run these commands manually.

The enlistment has 6 repos. For each repo, Claude must:

1. **Check for uncommitted changes** using `git status --short`. If any repo has
   uncommitted changes, report them to the user and **stop**. Ask the user whether
   to stash, commit, or discard before proceeding. Do not switch any repo until
   the user has resolved all dirty repos.

2. **Present a confirmation summary** listing all 6 repos and the target branch,
   and ask the user to confirm before switching anything.

3. **Switch each repo** one at a time, reporting success or failure after each:

```bash
ROOT=<labkey_root>            # the enlistment root provided by the user
TARGET_BRANCH=release26.3-SNAPSHOT   # change as needed

# Check all repos for uncommitted changes first:
for REPO in "$ROOT" \
            "$ROOT/server/modules/platform" \
            "$ROOT/server/modules/commonAssays" \
            "$ROOT/server/modules/targetedms" \
            "$ROOT/server/modules/MacCossLabModules" \
            "$ROOT/server/testAutomation"; do
    echo "=== $REPO ===" && git -C "$REPO" status --short
done

# Then switch each repo after user confirms:
git -C "$ROOT"                                        fetch origin && git -C "$ROOT"                                        checkout $TARGET_BRANCH
git -C "$ROOT/server/modules/platform"                fetch origin && git -C "$ROOT/server/modules/platform"                checkout $TARGET_BRANCH
git -C "$ROOT/server/modules/commonAssays"            fetch origin && git -C "$ROOT/server/modules/commonAssays"            checkout $TARGET_BRANCH
git -C "$ROOT/server/modules/targetedms"              fetch origin && git -C "$ROOT/server/modules/targetedms"              checkout $TARGET_BRANCH
git -C "$ROOT/server/modules/MacCossLabModules"       fetch origin && git -C "$ROOT/server/modules/MacCossLabModules"       checkout $TARGET_BRANCH
git -C "$ROOT/server/testAutomation"                  fetch origin && git -C "$ROOT/server/testAutomation"                  checkout $TARGET_BRANCH
```

> If a module has no matching branch, check whether it uses a different branch
> naming convention or stays on `develop`. Report this to the user before skipping.

### 2. Upgrade Java (if required)

**Claude performs this step.**

Check the current Java version:
```bash
java -version
```

Compare against the requirements table above. If the current version already
satisfies the target LabKey version, skip this step.

LabKey requires **Eclipse Temurin** specifically. Try winget first:

```bash
# Check if the required Temurin version is available in winget, e.g. for Java 25:
winget search EclipseAdoptium.Temurin.25.JDK
```

**If found in winget:**

Before launching the installer, tell the user:

> The Java installer will open a GUI. Here's what to watch for:
>
> 1. **UAC prompt** — Click **Yes** to allow changes
> 2. **Custom Setup screen** — Click the icon next to each of these features
>    and select **"Will be installed on local hard drive"**:
>    - **Set or override JAVA_HOME variable** — required for LabKey's Gradle build
>    - **Modify PATH variable** — required so `java` works from the command line
> 3. Leave all other options at their defaults
> 4. Click **Next** through remaining screens, then **Install**
>
> Ready to launch the installer?

Wait for user confirmation, then install:
```bash
powershell.exe -Command 'winget install EclipseAdoptium.Temurin.<N>.JDK --source winget --interactive'
# Replace <N> with the required Java version number (e.g. 25)
```

**If NOT found in winget:**

Tell the user:

> Temurin <N> is not yet available in winget. Please download it manually:
>
> 1. Go to https://adoptium.net
> 2. Select **JDK <N>** and **Windows x64** — download the **.msi** installer
> 3. Let me know when the download is complete and I'll guide you through installation

When the user confirms the download is ready, give the same Custom Setup
instructions as above, then ask the user to run the installer:
```bash
msiexec /i "%USERPROFILE%\Downloads\<filename>.msi"
```

**After installation (both paths):**

Instruct the user to **restart their terminal** so the new `JAVA_HOME` and PATH
take effect, then resume the Claude session:

```
To resume: cd "<working-directory>" && claude --resume
```

After restart, verify:
```bash
java -version
powershell.exe -Command '[System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")'
```

Both should reflect the newly installed version. If `JAVA_HOME` is empty, set
it manually:
```bash
powershell.exe -Command '[System.Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Eclipse Adoptium\jdk-<version>-hotspot", "Machine")'
```

### 3. Upgrade PostgreSQL (if required)

**Claude performs this check.**

Check the installed PostgreSQL version:
```bash
pwsh -Command "Get-Service -Name 'postgresql*' | Select-Object Name, Status"
```

Compare against the requirements table above. If the current version satisfies
the target LabKey version, skip this step.

If an upgrade is needed, see phase-2-postgresql.md for installation steps.

> **Important:** PostgreSQL upgrades require migrating your existing databases.
> Back up your data before upgrading.

### 4. Clean build

Old build artifacts from the previous version are incompatible and must be removed.
Run from the enlistment root (`<labkey_root>`):

```powershell
.\gradlew --stop
.\gradlew clean deployApp
```

This takes 15–30 minutes.

### 5. Update IntelliJ

After the build completes:

**Run Gradle configuration tasks** (before opening IntelliJ):
```powershell
.\gradlew ijWorkspaceSetup
.\gradlew ijConfigure
```

**Update the Project SDK** in IntelliJ:
1. File > Project Structure (Ctrl+Alt+Shift+S)
2. SDKs > **+** > Add JDK > browse to the new JDK installation
3. Rename the SDK to **"labkey"**
4. Select Project > set SDK to **"labkey"** > OK

**Refresh Gradle**:
1. View > Tool Windows > Gradle
2. Click the refresh (circular arrow) button
3. Wait for sync to complete
