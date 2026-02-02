# Phase 8: Test Setup

**Goal**: Configure environment for running UI tests (optional but recommended).
If the user cloned `testAutomation` in Phase 3, configure the test environment.

## Prerequisites
- LabKey Server running

## 8.1 Configure Test Credentials
**Important**: This command requires interactive input, so have the user run it themselves. User will be required to enter the username and password
they created during the initial LabKey setup

**Instruct user to run**:
```powershell
# In a new PowerShell terminal at <labkey_root> directory
.\gradlew :server:test:setPassword
```

## 8.2 Browser Setup

LabKey tests use Selenium with Firefox or Chrome. **Ask the user which browser they prefer.**

**Option A: Firefox ESR (recommended by LabKey to avoid bugs or incompatibilities)**
```bash
pwsh -Command "winget install Mozilla.Firefox.ESR --source winget --accept-source-agreements --accept-package-agreements"
```
The default `test.properties` is already configured for Firefox (`selenium.browser=firefox`).

**Option B: Chrome**

If the user prefers Chrome
**Check if installed**:
```bash
powershell.exe -Command "Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction SilentlyContinue"
```

**If missing**:
```bash
powershell.exe -Command "winget install Google.Chrome --source winget"
```

Then edit the test properties file to change the browser setting:
```powershell
notepad $enlistmentPath\server\testAutomation\test.properties
```
Find and change:
```properties
selenium.browser=chrome


## Step 8.3: Install ChromeDriver

**Automatic** (Gradle downloads matching version):
ChromeDriver is downloaded automatically when running tests.

**Manual** (if automatic fails):
1. Check Chrome version: chrome://settings/help
2. Download matching ChromeDriver: https://chromedriver.chromium.org/
3. Extract to: `<labkey_root>/server/build/chromedriver/`


## Step 8.4: Runing Tests

**Display test runner GUI:**
```powershell
.\gradlew :server:test:uiTests
```

**Run specific test class:**
```powershell
.\gradlew :server:test:uiTests "-Ptest=BasicTest"
```

Expected output on success:
```
INFO  Runner : =============== Completed BasicTest (1 of 1) =================
INFO  Runner : ======================= Time Report ========================
INFO  Runner : BasicTest                                 passed - 0:16 100%
INFO  Runner : ------------------------------------------------------------
INFO  Runner : Total duration:                                         0:16
```

**Run test suite (e.g., DRT - Daily Regression Tests):**
```powershell
.\gradlew :server:test:uiTests "-Psuite=DRT"
```

**Run module-specific tests:**
```powershell
.\gradlew -PenableUiTests :server:modules:targetedms:moduleUiTests
```

**Run module test suites:**

Many modules define a test suite that can be run using the suite parameter:
```powershell
# TargetedMS / Panorama tests
.\gradlew :server:test:uiTests "-Psuite=targetedms"

# Panorama Public tests
.\gradlew :server:test:uiTests "-Psuite=panoramapublic"

**Update state.json**:
```json
{"completed": ["phase-8"]}
```

## Completion

Test environment configured.

**Next**: Phase 9 - Developer Tools (optional)
