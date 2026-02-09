# Phase 3: Repository Setup

**Goal**: Clone LabKey and MacCoss Lab repositories in correct structure.

## Prerequisites
- GitHub SSH configured and tested
- `labkey_root` set in state.json (Phase 0)

## Step 3.1: Prepare Working Directory

Read `labkey_root` from state.json (set in Phase 0). Create the directory
and navigate to it:
```bash
mkdir -p "<labkey_root>"
cd "<labkey_root>"
```

## Step 3.2: Clone LabKey Server

Read `labkey_version` from state.json (set in Phase 0) and construct the
candidate branch names:
- **SNAPSHOT**: `release<labkey_version>-SNAPSHOT`
- **Stable**: `release<labkey_version>`

Present the user with a branch choice. **Include `develop` only if
`labkey_version` matches the latest release** (currently 26.x per the cached
requirements in Phase 0).

**For non-latest releases (e.g. 25.7, 25.11):**
```
Which branch would you like to clone?

1. SNAPSHOT (release<version>-SNAPSHOT) — receives changes ahead of stable;
   preferred for active development
2. Stable (release<version>) — fully tested, production-ready
3. A different branch (you will type the name)

Enter 1, 2, or 3:
```

**For the latest release (currently 26.x):**
```
Which branch would you like to clone?

1. SNAPSHOT (release<version>-SNAPSHOT) — receives changes ahead of stable;
   preferred for active development
2. Stable (release<version>) — fully tested, production-ready
3. develop — leading edge; may include unreleased features
4. A different branch (you will type the name)

Enter 1, 2, 3, or 4:
```

**Store the chosen branch in state.json** for reuse in Steps 3.3 and 3.4:
```json
{"clone_branch": "<chosen-branch-name>"}
```

**Clone and checkout**:
```bash
git clone git@github.com:LabKey/server.git .
git checkout <clone_branch>
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
git checkout <clone_branch>  # From state.json (Step 3.2)
cd ..
```

**commonAssays** (required):
```bash
git clone git@github.com:LabKey/commonAssays.git
cd commonAssays
git checkout <clone_branch>  # From state.json (Step 3.2)
cd ..
```

**targetedms** (MacCoss Lab):
```bash
git clone git@github.com:LabKey/targetedms.git
cd targetedms
git checkout <clone_branch>  # From state.json (Step 3.2)
cd ..
```

**MacCossLabModules**:
```bash
git clone git@github.com:LabKey/MacCossLabModules.git
cd MacCossLabModules
git checkout <clone_branch>  # From state.json (Step 3.2)
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
cd "<labkey_root>/server"
git clone git@github.com:LabKey/testAutomation.git
cd testAutomation
git checkout <clone_branch>  # From state.json (Step 3.2)
cd ..
```

> **Note:** testAutomation must be cloned directly under `server/`, not under `server/modules/`. Placing it in `server/modules/` will cause a Gradle build failure.

**Expected final structure**:
```
<labkey_root>\
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
