# Retrain All Training Data + LabKey Development Skill

## Branch Information
- **Branch**: `LabKey/work/20260204_retrain_all_training_data`
- **Base**: `develop`
- **Created**: 2026-02-04
- **Status**: Planning
- **Module**: MacCossLabModules/testresults

## Objective

Add a "Retrain All" button to the Training Data page (`trainingdata.jsp`) that performs a clean-slate rebuild of training data for all active computers in the current container. Also create a `labkey-development` skill and `ai/docs/labkey/` documentation directory as the foundation for LabKey Server development knowledge.

## Background

The Training Data page shows per-computer baseline statistics used for anomaly detection in the nightly test email. Currently, training runs must be added/removed one at a time. The data is stale (last trained ~6 months ago) and includes inactive computers (e.g., SKYLINE-DEV0 trained in December 2021).

### Key Tables
- `testresults.trainruns` - Links run IDs to training set (id + runid FK to testruns)
- `testresults.userdata` - Per-computer/container stats (userid, container, meantestsrun, meanmemory, stddevtestsrun, stddevmemory, active)
- `testresults.testruns` - Run data (userid, container, duration, passedtests, failedtests, leakedtests, averagemem, posttime, flagged)
- `testresults.hangs` - Hang records (testrunid FK to testruns)
- `testresults.user` - Computer names (id, username)

### Key Code
- Controller: `testresults/src/org/labkey/testresults/TestResultsController.java`
  - `TrainRunAction` (line 368) - existing single-run train/untrain endpoint
  - `SetUserActive` (line 1003) - activate/deactivate computer
  - `TrainingDataViewAction` (line 339) - page action
- JSP: `testresults/src/org/labkey/testresults/view/trainingdata.jsp`
- Schema: `testresults/src/org/labkey/testresults/TestResultsSchema.java`
- User model: `testresults/src/org/labkey/testresults/model/User.java`

## Tasks

### Part 1: Retrain All Feature
- [x] Add `RetrainAllAction` to `TestResultsController.java`
- [x] Add "Retrain All" button + JS handler to `trainingdata.jsp`
- [x] Build and deploy testresults module
- [ ] Test on local LabKey server

### Part 2: LabKey Development Skill + Docs
- [x] Create `ai/docs/labkey/` directory
- [x] Create `ai/docs/labkey/testresults-module.md` with module architecture
- [x] Create `.claude/skills/labkey-development/SKILL.md`

## Plan

### RetrainAllAction Design

**Location:** After `SetUserActive` (~line 1038) in TestResultsController.java
**Annotation:** `@RequiresSiteAdmin`
**Returns:** `ApiSimpleResponse` with `success`, `usersRetrained`, `totalTrainRuns`

**Algorithm (single transaction):**

1. **Determine expected duration** from container path:
   - Contains "Perf" (case-insensitive) -> 720 min
   - Otherwise -> 540 min

2. **Snapshot active user IDs:**
   ```sql
   SELECT userid FROM testresults.userdata
   WHERE container = ? AND active = true
   ```

3. **Delete all trainruns for this container:**
   ```sql
   DELETE FROM testresults.trainruns
   WHERE runid IN (SELECT id FROM testresults.testruns WHERE container = ?)
   ```

4. **Delete all userdata for this container:**
   ```sql
   DELETE FROM testresults.userdata WHERE container = ?
   ```

5. **For each active userId**, find up to 20 most recent clean runs:
   ```sql
   SELECT tr.id FROM testresults.testruns tr
   WHERE tr.userid = ? AND tr.container = ?
     AND tr.failedtests = 0 AND tr.leakedtests = 0
     AND tr.passedtests > 0 AND tr.flagged = false
     AND tr.duration >= ?
     AND NOT EXISTS (SELECT 1 FROM testresults.hangs h WHERE h.testrunid = tr.id)
   ORDER BY tr.posttime DESC LIMIT 20
   ```

6. **Insert runs** into `trainruns`

7. **Calculate stats** and insert into `userdata` with `active = true`:
   ```sql
   INSERT INTO testresults.userdata
     (userid, container, meantestsrun, meanmemory, stddevtestsrun, stddevmemory, active)
   SELECT ?, ?, avg(passedtests), avg(averagemem),
          stddev_pop(passedtests), stddev_pop(averagemem), true
   FROM testresults.testruns WHERE id = ANY(?)
   ```

### Clean Run Criteria

All must be true:
- `failedtests = 0` (no test failures)
- `leakedtests = 0` (no memory/handle leaks)
- `passedtests > 0` (not uncached/empty)
- `flagged = false` (not flagged)
- `duration >= expectedDuration` (540 or 720 min, full run)
- No row in `hangs` table for that run
- Belongs to current container

### JSP Changes

- Button HTML before `<table id="trainingdata">` (~line 116)
- JS handler: confirm dialog, disable button, POST to RetrainAllAction with CSRF, show result, reload page

### Edge Cases

- **No active users**: Succeeds, deletes all, inserts nothing
- **Active user with no clean runs**: Skipped, appears in "No Training Data"
- **Transaction safety**: Single transaction, auto-rollback on failure

### Future: Incremental Mode

A separate `IncrementalTrainAction` could be added later that keeps existing trainruns and adds new clean runs, recalculating stats with the combined set.

## Verification

1. Build: `gradlew :server:modules:MacCossLabModules:testresults:deployModule`
2. Navigate to Training Data page, confirm button appears
3. Click Retrain All on `/home/development/Nightly x64` container
4. Verify page reloads with only active computers and recent clean runs
5. Verify inactive computers (SKYLINE-DEV0 etc.) are gone
6. Verify MCP `list_computer_status` still works correctly
