# Phase 6: IntelliJ Setup

**Goal**: Configure IntelliJ IDEA for LabKey development.

## Prerequisites
- IntelliJ installed (Community or Ultimate)
- Initial build completed

## Step 6.1: Install IntelliJ

**Skip if**: Environment check showed [OK]

**Install**:
If not found, ask the user which edition they want:

```
Which IntelliJ IDEA edition do you want to install?

1. Community Edition (free, sufficient for LabKey development)
2. Ultimate Edition (paid, additional features for web/enterprise development)

Enter 1 or 2:
```

Install the selected edition:
```bash
# For Community Edition (option 1):
pwsh -Command "winget install JetBrains.IntelliJIDEA.Community --source winget --accept-source-agreements --accept-package-agreements"

# For Ultimate Edition (option 2):
pwsh -Command "winget install JetBrains.IntelliJIDEA.Ultimate --source winget --accept-source-agreements --accept-package-agreements"

**User launches** IntelliJ after installation.

## 6.2 Run IntelliJ Configuration Tasks

Before opening in IntelliJ, run the setup tasks:

```bash
pwsh -Command "cd $enlistmentPath; .\\gradlew ijWorkspaceSetup"
```

```bash
pwsh -Command "cd $enlistmentPath; .\\gradlew ijConfigure"
```

## Step 6.3: Open Project

**User instructions**:
1. Launch IntelliJ IDEA
2. On the Welcome screen, click **Open** (or if already in a project: File > Open)
3. Navigate to `<labkey_root>`
4. Select the `<labkey_root>` directory
5. On the "Trust and Open Project..." dialog click "Trust Project"
5. Click "OK"
6. Wait for IntelliJ to finish indexing (progress bar in the status bar at bottom). This can take several minutes

**While indexing, ignore these messages:**
- "Invalid Gradle JDK configuration found" in the console - we'll configure the JDK next
- "NODE_PATH undefined" pop-up - not needed for LabKey development
- "Configure Kotlin language settings" - dismiss or ignore

**Wait for user to confirm indexing is complete before proceeding to Step 6.4.**

## Step 6.4: Configure Project SDK

**User instructions**:
1. **File > Project Structure** (Ctrl+Alt+Shift+S)
2. Select **SDKs** in the left panel
3. Click **+** → **Add JDK**
4. Browse to your JDK (e.g., `C:\Program Files\Eclipse Adoptium\jdk-17...`)
5. **Rename it to "labkey"** (click the name to edit)
6. Click **Apply**
7. Now select **Project** in the left panel
8. Set the **SDK** dropdown to **"labkey"**
9. Click **OK**

> **Important:** You must both create the SDK named "labkey" AND assign it as the Project SDK. The run configuration won't find it otherwise.

**Wait for user to confirm SDK is configured before proceeding to Step 6.5.**

## Step 6.5: Refresh Gradle Project

After setting the Project SDK, refresh the Gradle project to sync the run configurations:

1. Open the Gradle tool window (View > Tool Windows > Gradle)
2. Click the refresh button (circular arrow icon)
3. Wait for Gradle sync to complete

> **Note:** The run configuration ("LabKey Embedded Tomcat Dev") should automatically configure correctly after the Gradle refresh. Manual configuration is typically not needed.

**Wait for user to confirm Gradle sync is complete before proceeding.**

## Step 6.5 (optional)
You may also want to increase the number of open tabs IntelliJ will support. 
The default is 10, and depending on your working process, you may see tabs disappear unexpectedly. 
**User instructions**
1. Select Window > Editor Tabs > Configure Editor Tabs.
2. Scroll down to the "Closing Policy" section to increase the number of tabs you can have open in IntelliJ at one time.
  
 
**Update state.json**:
```json
{"completed": ["phase-6"]}
```

## Completion

IntelliJ configured for LabKey development.

**Next**: Phase 7 - Running LabKey Server
