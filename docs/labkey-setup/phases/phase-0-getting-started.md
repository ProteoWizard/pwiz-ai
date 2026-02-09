# Phase 0: Getting Started

**Goal**: Determine target LabKey version and assess current environment.

## Step 0.0: Determine setup_root

Extract `setup_root` from the path the user provided to README.md — it is the
directory containing README.md (absolute path). This is needed for resume
checkpoints so the user knows where to `cd` before running `claude --resume`.

**Note:** Do not create state.json yet - wait until after the environment check in Step 0.3.

## Step 0.1: Determine Target Version

Ask user which LabKey version they're developing for:

```
Which LabKey version will you be developing for?

1. LabKey 25.7.x and lower → Java 17 + PostgreSQL 17
2. LabKey 25.11.x → Java 17 + PostgreSQL 17 or 18
3. LabKey 26.x → Java 25 + PostgreSQL 18
4. Other version (fetch from labkey.org)

Enter 1, 2, 3, or 4:
```

**For options 1-3**: Use cached requirements below.

**For option 4**: 
1. Ask specific version (e.g., "27.1")
2. Fetch from https://www.labkey.org/Documentation/wiki-page.view?name=supported
3. Extract Java and PostgreSQL requirements
4. Proceed with those requirements

**Cached Requirements** (retrieved 2026-01-30):

| LabKey Version | Java Required | PostgreSQL Support |
|----------------|---------------|--------------------|
| 25.7.x and lower | Java 17 (Temurin) | PostgreSQL 17 only |
| 25.11.x | Java 17 (Temurin) | PostgreSQL 17 or 18 |
| 26.x | Java 25 (Temurin) | PostgreSQL 18 |

**Remember these values** for state.json creation in Step 0.3. If the selected LabKey version supports
multiple PostgreSQL versions (e.g. 25.11.x supports 17 or 18), leave postgres_version
as null -- it will be set in Phase 2 after asking the user.

## Step 0.2: Determine Clone Directory

Ask the user where they want the LabKey repositories cloned. This is the
enlistment root — it will contain `build.gradle`, `gradlew.bat`, and `server/`.

**Ask user**: "Where should the LabKey repositories be cloned?"

**Remember this value** for state.json creation in Step 0.3.

## Step 0.3: Run Environment Check

**IMPORTANT:** Run the environment check script BEFORE creating or updating state.json.

Run the environment check script located at `<setup_root>/scripts/Verify-LabKeyEnvironment.ps1`:

```bash
# For LabKey 25.x:
powershell.exe -ExecutionPolicy Bypass -File "<setup_root>\scripts\Verify-LabKeyEnvironment.ps1" -LabKeyVersion 25

# For LabKey 26.x:
powershell.exe -ExecutionPolicy Bypass -File "<setup_root>\scripts\Verify-LabKeyEnvironment.ps1" -LabKeyVersion 26
```

**Parse the output:**
- **[OK]** - Installed, skip in later phases
- **[UPDATE]** - Installed but newer available, offer update
- **[MISSING]** - Not installed, will install
- **[WRONG]** - Wrong version, will install correct version

**Now create state.json** with all collected information (setup_root, versions from steps 0.0-0.2, and environment check results):
```json
{
  "environment_check": {
    "completed": true,
    "missing_required": ["Java 17", "PostgreSQL"],
    "missing_optional": ["GitHub CLI"],
    "needs_update": ["Git"]
  }
}
```

## Step 0.4: Show Results Table to User

**Before displaying the table:**
1. Output message to user: "Let me update the state file..."
2. Complete ALL state.json writes:
   - Create state.json with all collected data from steps 0.0-0.3
   - Mark phase 0 as complete (update current_phase, current_step, and completed)

After all state.json writes are done, display a summary table to the user
showing every component, its status, and what will happen next. Example:

```
| Component        | Status  | Required | Action            |
|------------------|---------|----------|-------------------|
| Git              | OK      | Yes      | Skip              |
| Git autocrlf     | OK      | Yes      | Skip              |
| SSH Key          | MISSING | Yes      | Will generate     |
| GitHub SSH       | MISSING | Yes      | Will configure    |
| Java 17          | MISSING | Yes      | Will install      |
| JAVA_HOME        | MISSING | Yes      | Will set          |
| PostgreSQL       | MISSING | Yes      | Will install      |
| IntelliJ IDEA    | MISSING | Yes      | Will install      |
| GitHub CLI       | MISSING | No       | Ask later         |
| Claude Code      | OK      | No       | Skip              |
| Notepad++        | MISSING | No       | Ask later         |
| WinMerge         | MISSING | No       | Ask later         |
| TortoiseGit      | MISSING | No       | Ask later         |
```

Map statuses to actions:
- OK / UPDATE → "Skip" (or "Update available" for UPDATE)
- MISSING / WRONG (required) → "Will install" / "Will generate" / "Will set"
- MISSING / WRONG (optional) → "Ask later"

## Completion

Show progress tracker after the summary table.

**Next**: Phase 1 - Core Setup
