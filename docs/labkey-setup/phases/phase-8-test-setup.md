# Phase 8: Test Setup

**Goal**: Configure environment for running UI tests (optional but recommended).
If the user cloned `testAutomation` in Phase 3, configure the test environment.

## Prerequisites
- LabKey Server running

## 8.1 Configure Test Credentials

**Important**: This command requires interactive input, so have the user run it themselves.

The user will be prompted to enter:
- **Username**: The admin username they created in the **LabKey initial setup wizard** (Step 7.2)
- **Password**: The admin password they created in the **LabKey initial setup wizard** (Step 7.2)

**Instruct user to run**:
```powershell
# In a new PowerShell terminal at <labkey_root> directory
.\gradlew :server:test:setPassword
```

When prompted, enter the admin credentials you created during LabKey's initial setup.

## 8.2 Browser Setup

LabKey tests use Selenium with Firefox or Chrome. **Ask the user which browser they prefer.**

**Option A: Firefox ESR (recommended by LabKey to avoid bugs or incompatibilities)**
```bash
powershell.exe -Command 'winget install Mozilla.Firefox.ESR --source winget --accept-source-agreements --accept-package-agreements'
```
The default `test.properties` is already configured for Firefox (`selenium.browser=firefox`).

**Option B: Chrome**

If the user prefers Chrome
**Check if installed**:
```bash
powershell.exe -Command 'Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue'
```

**If missing**:
```bash
powershell.exe -Command 'winget install Google.Chrome --source winget'
```

**Update the test properties file** to change the browser setting:

Read `<labkey_root>\server\testAutomation\test.properties` using the Read tool.

Use the Edit tool to change:
```properties
selenium.browser=firefox
```
to:
```properties
selenium.browser=chrome
```

## Step 8.3: Install ChromeDriver

**Skip if**: Firefox was chosen in Step 8.2.

**Automatic** (Gradle downloads matching version):
ChromeDriver is downloaded automatically when running tests.

**Manual** (if automatic fails):
1. Check Chrome version: chrome://settings/help
2. Download matching ChromeDriver: https://chromedriver.chromium.org/
3. Extract to: `<labkey_root>/server/build/chromedriver/`


## Step 8.4: Verify Test Setup with BasicTest

**REQUIRED**: Before completing this phase, verify that the test environment is working by running the BasicTest.

**Instruct user to run** (in PowerShell at <labkey_root>):
```powershell
.\gradlew :server:test:uiTests "-Ptest=BasicTest"
```

**Wait for the test to complete.** This may take a few minutes.

Expected output on success:
```
INFO  Runner : =============== Completed BasicTest (1 of 1) =================
INFO  Runner : ======================= Time Report ========================
INFO  Runner : BasicTest                                 passed - 0:16 100%
INFO  Runner : ------------------------------------------------------------
INFO  Runner : Total duration:                                         0:16
```

**If the test fails:**
- Check that the LabKey server is running at http://localhost:8080/
- Verify test credentials were set correctly in Step 8.1
- Ensure the browser (Chrome/Firefox) is installed correctly
- Check the error message for specific issues

**Do not proceed to Phase 9 until BasicTest passes successfully.**

**After BasicTest passes**, update state.json:
```json
{"completed": ["phase-8"]}
```

## Additional Test Information

After BasicTest succeeds, you can run other tests as needed:

**Display test runner GUI:**
```powershell
.\gradlew :server:test:uiTests
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
```powershell
# TargetedMS / Panorama tests
.\gradlew :server:test:uiTests "-Psuite=targetedms"

# Panorama Public tests
.\gradlew :server:test:uiTests "-Psuite=panoramapublic"
```

## Completion

Test environment configured and verified with BasicTest.

**Next**: Phase 9 - Developer Tools (optional)
