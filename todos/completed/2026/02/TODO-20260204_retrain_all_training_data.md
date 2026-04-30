# Retrain All Training Data + Menu Styling

## Branch Information
- **Repository**: MacCossLabModules (nested in labkeyEnlistment)
- **Branch**: `25.11_fb_testresults-retrain-all-and-menu-styling`
- **Base**: `release25.11-SNAPSHOT`
- **PR**: https://github.com/LabKey/MacCossLabModules/pull/599
- **Created**: 2026-02-04
- **Status**: Completed
- **Module**: MacCossLabModules/testresults

## Objective

Add a "Retrain All" feature to the Training Data page with two modes:
1. **Reset mode** - Clean-slate rebuild of training data for all computers
2. **Incremental mode** - Rolling window to replace oldest runs with newer ones

Also improve menu styling with active tab highlighting.

## Tasks

### Part 1: Retrain All Feature
- [x] Add `RetrainAllAction` to `TestResultsController.java`
- [x] Add "Retrain" option to Actions dropdown in `trainingdata.jsp`
- [x] Add retrain form with Reset/Incremental radio buttons
- [x] Add Max runs input field (default 20)
- [x] Add Min runs input field (default 5)
- [x] Implement 1.5x lookback period to filter out ancient data
- [x] Implement Reset mode - rebuild from recent clean runs
- [x] Implement Incremental mode - rolling window replacement
- [x] Test Reset mode on Performance Tests container
- [x] Verify lookback period filters correctly
- [x] Verify partial data computers appear (>= minRuns but < maxRuns)

### Part 2: Menu Styling
- [x] Add active tab highlighting with rounded corners
- [x] Add gold hover color (#B8A506) matching UW branding
- [x] Set activeTab request attribute in all parent JSPs
- [x] Use CSS classes instead of inline styles
- [x] Verify menu works on all pages

### Part 3: Documentation
- [x] Create `ai/docs/labkey/testresults-module.md` with module architecture
- [x] Document LabKey branch naming convention: `{version}_fb_{feature-name}`
- [x] Document build/deploy commands
- [x] Create `.claude/skills/labkey-development/SKILL.md`

## Implementation Details

### Files Modified (11 files, +428/-44 lines)

1. **TestResultsController.java** - Added `RetrainAllAction`
   - `@RequiresSiteAdmin`, `MutatingApiAction`
   - Parameters: `mode` (reset/incremental), `maxRuns` (1-100, default 20), `minRuns` (1-maxRuns, default 5)
   - Lookback period: `1.5 * maxRuns` days (30 days for default)
   - Returns: `{success, usersRetrained, totalTrainRuns, mode}`

2. **trainingdata.jsp** - UI changes
   - Added "Retrain" option to Actions dropdown
   - Added form with Mode radio buttons, Max/Min runs fields
   - JavaScript handler for AJAX POST

3. **menu.jsp** - Navigation styling
   - Added CSS for active tab highlighting (rounded corners, semi-transparent)
   - Gold hover color matching original UW branding
   - Reads `activeTab` request attribute

4. **All other JSPs** (rundown, user, runDetail, longTerm, flagged, errorFiles, failureDetail, multiFailureDetail)
   - Each sets `activeTab` request attribute before including menu.jsp

### Clean Run Criteria

All must be true:
- `failedtests = 0` (no test failures)
- `leakedtests = 0` (no memory/handle leaks)
- `passedtests > 0` (not uncached/empty)
- `flagged = false` (not flagged)
- `duration >= expectedDuration` (540 min standard, 720 min for Perf)
- No row in `hangs` table for that run
- `posttime >= cutoffDate` (within lookback period)

### Reset vs Incremental Mode

**Reset Mode:**
1. Delete all trainruns and userdata for container
2. Query all unique users from recent testruns (within lookback period)
3. For each user, find up to `maxRuns` most recent clean runs
4. Skip users with fewer than `minRuns` clean runs
5. Create trainruns and userdata (active only if runs >= maxRuns)

**Incremental Mode (Rolling Window):**
1. Get existing trainruns for each user
2. Find all clean runs within lookback period
3. Combine both sets, sort by posttime descending
4. Keep only the most recent `maxRuns`
5. Remove trainruns that got "pushed out", add new ones
6. Recalculate stats based on final set

## Progress Log

### 2026-02-04 - Session 1
- Created initial `RetrainAllAction` with reset-only functionality
- Added standalone "Retrain All" button to JSP
- Created labkey-development skill and testresults-module.md docs
- Restored production database (135GB) to local PostgreSQL for testing

### 2026-02-04 - Session 2 (UI Refinement)
- Moved Retrain to Actions dropdown
- Added Reset/Incremental mode radio buttons
- Added configurable target runs field

### 2026-02-05 - Session 3 (Feature Complete)
- Fixed form padding/alignment issues across all forms
- Added menu active tab highlighting with rounded corners and gold hover
- Updated all JSPs to set activeTab attribute
- Discovered JSP static includes require module rebuild (not just Tomcat restart)
- Created rebuild script: `ai/.tmp/rebuild-testresults.ps1`
- Tested on Performance Tests container - found issues:
  - Query only looked at userdata table (missed new computers)
  - No time limit caused ancient data from 2018 to appear
- Fixed: Query all users from testruns, added 1.5x lookback period
- Added Min runs parameter (default 5) for partial training data
- Implemented rolling window for Incremental mode
- Created PR #599 to release25.11-SNAPSHOT
- Documented LabKey branch naming convention

### 2026-02-06 - Merged

PR [#599](https://github.com/LabKey/MacCossLabModules/pull/599) merged 2026-02-06.

## LabKey Branch Naming Convention

**Required format:** `{version}_fb_{feature-name}`

Examples:
- `25.11_fb_testresults-retrain-all` ✓
- `feature/testresults-retrain-all` ✗ (rejected by CI)
