# Phase 0: Getting Started

**Goal**: Determine target LabKey version and assess current environment.

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

**Update state.json** with version choices:
```json
{
  "labkey_version": "25",
  "java_version": 17,
  "postgres_version": 17
}
```

## Step 0.2: Run Environment Check

Locate `Verify-LabKeyEnvironment.ps1` and run it:

```bash
# For LabKey 25.x:
powershell.exe -ExecutionPolicy Bypass -File "Verify-LabKeyEnvironment.ps1" -LabKeyVersion 25

# For LabKey 26.x:
powershell.exe -ExecutionPolicy Bypass -File "Verify-LabKeyEnvironment.ps1" -LabKeyVersion 26
```

**Parse the output:**
- **[OK]** - Installed, skip in later phases
- **[UPDATE]** - Installed but newer available, offer update
- **[MISSING]** - Not installed, will install
- **[WRONG]** - Wrong version, will install correct version

**Update state.json** with findings:
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

## Completion

Mark phase complete in state.json and show progress tracker.

**Next**: Phase 1 - Core Setup
