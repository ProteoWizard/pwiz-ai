# Phase 5: Initial Build

**Goal**: Complete first LabKey build with all modules.

## Prerequisites
- Gradle properties configured
- PostgreSQL running
- Repositories cloned

## Step 5.0: Verify Environment and Restart Terminal

**Check if JAVA_HOME is set:**
```bash
pwsh -Command '$env:JAVA_HOME'
```

**If output is empty or shows an error:**
1. You need to restart your terminal for Java and PowerShell PATH updates to take effect
2. Close your current terminal
3. Open a new terminal
4. Run `claude --resume` to continue from this step

**If JAVA_HOME is set correctly (shows Java installation path):**
- Continue to next step

**Update state.json**:
```json
{"completed": ["phase-5-step-5.0"]}
```

## Step 5.1: Configure Database Connection

**Update pg.properties with PostgreSQL password:**

Read the existing `pg.properties` file:
```bash
cat server/configs/pg.properties
```

The file should contain these settings. Update `jdbcPassword` with the postgres user password you set during installation:
```properties
jdbcURL=jdbc:postgresql://${jdbcHost}:${jdbcPort}/${jdbcDatabase}${jdbcURLParameters}
jdbcUser=postgres
jdbcPassword=<your-postgres-password>
```

Use the Edit tool to update the `jdbcPassword` line with the actual password.

**Run pickPg** to copy settings to application.properties:
```bash
cd <labkey_root>
./gradlew pickPg
```

Expected output: Should complete successfully and show "BUILD SUCCESSFUL"

> **Note:** The `gradlew` file is at the enlistment root (where you cloned the server repository).

> **Note:** MacCossLabModules only support PostgreSQL, not MSSQL.

**Update state.json**:
```json
{"completed": ["phase-5-step-5.1"]}
```

## Step 5.2: Clean Start

**Ensure clean state**:
```bash
cd <labkey_root>
./gradlew --stop
```

**Update state.json**:
```json
{"completed": ["phase-5-step-5.2"]}
```

## Step 5.3: Run Initial Build

**Important**: This is a LONG-RUNNING task (15-30 minutes). User should run in separate terminal to see progress.

**Instruct user to run**:
```powershell
# In a new PowerShell terminal at server directory
.\gradlew deployApp
```

**What happens**:
- Downloads Gradle dependencies
- Compiles all modules
- Builds web application
- Deploys to tomcat directory

**Expected output** (at end):
```
BUILD SUCCESSFUL in XXm XXs
```

**If build fails**:
1. Check error message
2. Verify Java version: `java -version`
3. Verify JAVA_HOME: `echo $env:JAVA_HOME`
4. Try: `.\gradlew --stop` then retry
5. Check reference/troubleshooting.md

**After successful build, verify**:
```bash
ls build/deploy
```

Should see: `labkeywebapp/`, `embedded/`, etc.

**Update state.json**:
```json
{
  "completed": ["phase-5"],
  "current_step": "5.3",
  "first_build_completed": true
}
```

## Completion

LabKey successfully built. Ready for IntelliJ setup.

**Next**: Phase 6 - IntelliJ Setup
