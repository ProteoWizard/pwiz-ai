# Phase 3: Repository Setup

**Goal**: Clone LabKey and MacCoss Lab repositories in correct structure.

## Prerequisites
- GitHub SSH configured and tested
- Working directory decided (default: `C:\labkey`)

## Step 3.1: Choose Working Directory

**Ask user**:
```
Where should LabKey repositories be cloned?
Default: C:\labkey
Enter path or press Enter for default:
```

**Create directory**:
```bash
mkdir -p /c/labkey  # Adjust path based on user input
cd /c/labkey
```

**Update state.json**:
```json
{"labkey_root": "C:\\labkey"}
```

## Step 3.2: Clone LabKey Server

**Note about branches**: For production LabKey development, use the appropriate release branch (e.g., `release25.11-SNAPSHOT`, `release25.7-SNAPSHOT`, `release26.3-SNAPSHOT`). Ask user which branch or use `develop` for latest.
SNAPSHOT branches (e.g., `release25.11-SNAPSHOT`) are used for faster feature deployment before changes are merged to the stable release branch (e.g., `release25.11`).

**Clone**:
```bash
git clone git@github.com:LabKey/server.git .
git checkout <branch-name>  # If not using develop
```

**Verify**:
```bash
ls -la
```

Should see gradle files, server directory, etc.

**Update state.json**:
```json
{"completed": ["phase-3-step-3.2"]}
```

## Step 3.3: Clone Required Modules

**Navigate to modules directory**:
```bash
cd server/modules
```

**Clone core required modules**:

**platform** (required):
```bash
git clone git@github.com:LabKey/platform.git
cd platform
git checkout <branch-name>  # Match server branch
cd ..
```

**commonAssays** (required):
```bash
git clone git@github.com:LabKey/commonAssays.git
cd commonAssays
git checkout <branch-name>  # Match server branch
cd ..
```

**targetedms** (MacCoss Lab):
```bash
git clone git@github.com:LabKey/targetedms.git
cd targetedms
git checkout <branch-name>  # Match server branch
cd ..
```

**MacCossLabModules**:
```bash
git clone git@github.com:LabKey/MacCossLabModules.git
cd MacCossLabModules
git checkout <branch-name>  # Match server branch
cd ..
```

**Verify structure**:
```bash
ls -la
```

Should show: `platform/`, `commonAssays/`, `targetedms/`, `MacCossLabModules/`

## Step 3.4: Clone testAutomation (optional)

**Ask user**: Do you want to run automated tests? (yes/no)

**If yes**, navigate to `server/` (NOT `server/modules/`) and clone testAutomation there:
```bash
cd <labkey_root>/server
git clone git@github.com:LabKey/testAutomation.git
cd testAutomation
git checkout <branch-name>  # Match server branch
cd ..
```

> **Note:** testAutomation must be cloned directly under `server/`, not under `server/modules/`. Placing it in `server/modules/` will cause a Gradle build failure.

**Expected final structure**:
```
C:\labkey\release25.11\    (or chosen directory)
├── build.gradle
├── gradlew.bat
└── server\
    ├── testAutomation\      (optional, if user wants to run tests)
    └── modules\
        ├── platform\          (core required)
        ├── commonAssays\      (core required)
        ├── targetedms\        (Panorama module)
        └── MacCossLabModules\
            ├── SkylineToolsStore\
            ├── panoramapublic\
            ├── pwebdashboard\
            └── (other modules)
```

**Update state.json**:
```json
{"completed": ["phase-3-step-3.3"]}
```

## Completion

All repositories cloned in correct structure.

**Next**: Phase 4 - Gradle Configuration
