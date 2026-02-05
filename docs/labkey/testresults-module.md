# testresults Module Architecture

The `testresults` module provides the nightly test results dashboard on skyline.ms, including run tracking, training data for anomaly detection, and email notifications.

## Git Repository Structure

The `MacCossLabModules` repository is a **separate Git repository** nested inside the LabKey enlistment (not a submodule):

```
labkeyEnlistment/                              ← Main repo (LabKey/server.git)
└── server/modules/
    └── MacCossLabModules/                     ← Separate repo (LabKey/MacCossLabModules.git)
        └── testresults/                       ← This module
```

### Branch Naming Convention

**LabKey requires branches to follow this naming scheme:**
```
{version}_fb_{feature-name}
```

Examples:
- `25.11_fb_testresults-retrain-all` - Feature branch for 25.11 release
- `26.3_fb_menu-improvements` - Feature branch for 26.3 release

**Common mistake:** Using `feature/...` naming will be rejected by LabKey CI.

### Build and Deploy

```bash
# From labkeyEnlistment directory
./gradlew :server:modules:MacCossLabModules:testresults:deployModule

# Full rebuild with Tomcat restart
./gradlew stopTomcat
./gradlew :server:modules:MacCossLabModules:testresults:deployModule
./gradlew startTomcat
```

**Note:** JSP changes in included files (like `menu.jsp`) require a full module rebuild, not just a Tomcat restart, because static includes are compiled into the parent JSPs.

## Source Location

```
labkeyEnlistment/server/modules/MacCossLabModules/testresults/
  src/org/labkey/testresults/
    TestResultsController.java    # All HTTP actions
    TestResultsSchema.java        # DB schema access (table references)
    TestResultsModule.java        # Module registration
    SendTestResultsEmail.java     # Daily email job
    model/
      RunDetail.java              # Test run data
      User.java                   # Computer/user identity
      TestFailDetail.java         # Test failure records
      TestPassDetail.java         # Test pass records
      TestLeakDetail.java         # Base leak class
      TestMemoryLeakDetail.java   # Memory leak records
      TestHandleLeakDetail.java   # Handle leak records
      TestHangDetail.java         # Hang records
      GlobalSettings.java         # Warning/error boundaries
      BackgroundColor.java        # UI color constants
    view/
      trainingdata.jsp            # Training data management page
      rundown.jsp                 # Main dashboard (landing page)
      runDetail.jsp               # Single run detail view
      user.jsp                    # Per-computer run history
      longTerm.jsp                # Long-term trend view
      failureDetail.jsp           # Failure detail view
      multiFailureDetail.jsp      # Multi-failure view
      flagged.jsp                 # Flagged runs view
      errorFiles.jsp              # Error file management
      menu.jsp                    # Navigation menu (included by other JSPs)
```

## Database Tables (PostgreSQL)

All tables are in the `testresults` schema. Access via `TestResultsSchema.getTableInfo*()` methods.

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `testruns` | Test run records | id, userid, container, duration, posttime, passedtests, failedtests, leakedtests, averagemem, flagged |
| `user` | Computer identities | id, username |
| `userdata` | Per-computer training stats | userid, container, meantestsrun, meanmemory, stddevtestsrun, stddevmemory, active |
| `trainruns` | Training run associations | id, runid (FK to testruns) |
| `hangs` | Hang records | id, testrunid (FK to testruns), testname |
| `memoryleaks` | Memory leak records | id, testrunid, testname, bytes |
| `handleleaks` | Handle leak records | id, testrunid, testname, handles |
| `testpasses` | Individual test pass records | id, testrunid, testname, duration, managed memory, total memory |
| `testfails` | Individual test failure records | id, testrunid, testname, stacktrace |
| `globalsettings` | Warning/error boundary settings | warningb, errorb |

## Controller Actions

| Action | Permission | Type | Description |
|--------|-----------|------|-------------|
| `BeginAction` | Read | View | Landing page (rundown.jsp) |
| `TrainingDataViewAction` | Read | View | Training data page |
| `TrainRunAction` | Admin | Mutating | Add/remove single training run |
| `RetrainAllAction` | SiteAdmin | Mutating | Rebuild all training data from clean runs |
| `SetUserActive` | SiteAdmin | Mutating | Activate/deactivate computer |
| `ShowUserAction` | Read | View | Per-computer run history |
| `ShowRunAction` | Read | View | Single run detail |
| `LongTermAction` | Read | View | Long-term trends |
| `ShowFailures` | Read | View | Failure details |
| `DeleteRunAction` | Admin | Mutating | Delete a run |
| `FlagRunAction` | Admin | Mutating | Flag/unflag a run |
| `PostAction` | None | Mutating | Receive XML results from SkylineNightly |
| `SetEmailCronAction` | SiteAdmin | Mutating | Manage daily email job |
| `ChangeBoundaries` | SiteAdmin | Mutating | Update warning/error thresholds |

## Training Data System

Training data is used to calculate baseline statistics (mean and stddev for tests run and memory) per computer. These baselines feed into the daily nightly test email for anomaly detection.

### Clean Run Criteria

A run qualifies as a training run when all are true:
- `failedtests = 0` (no test failures)
- `leakedtests = 0` (no leaks)
- `passedtests > 0` (not empty/uncached)
- `flagged = false` (not manually flagged)
- `duration >= expectedDuration` (540 min for standard, 720 min for Perf containers)
- No row in `hangs` table for that run

### Container Duration Rules

The expected duration is determined by the container path:
- Path contains "Perf" (case-insensitive) -> 720 minutes
- All other containers -> 540 minutes
