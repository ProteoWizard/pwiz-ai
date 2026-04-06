# TODO-20260326_testresults-migrate-actions.md

## Branch Information
- **Branch**: `26.3_fb_testresults-refactor` (MacCossLabModules repo)
- **Base**: `release26.3-SNAPSHOT`
- **Created**: 2026-03-26
- **Status**: In Progress
- **PR**: [#622](https://github.com/LabKey/MacCossLabModules/pull/622)

## Objective

Migrate `TestResultsController` actions to use Spring automatic parameter binding instead
of manual `request.getParameter()` parsing. Create Selenium tests as a safety net — run
before and after the refactor to verify no UI regressions.

## Key Files

- `testresults/src/org/labkey/testresults/TestResultsController.java` — all actions
- `testresults/test/src/org/labkey/test/tests/testresults/TestResultsTest.java` — Selenium test class ✓
- `testresults/test/sampledata/testresults/*.xml` — sample XML files ✓

## Phase 1: Test Infrastructure ✓

- [x] Create `testresults/test/` directory structure (no `test/build.gradle` needed — auto-discovered)
- [x] Create `TestResultsTest.java` base test class extending `BaseWebDriverTest implements PostgresOnlyTest`
  - `@BeforeClass` posts 3 sample XML runs via `PostAction` (multipart HTTP), queries run IDs via `SelectRowsCommand`
  - Tests: `testRundownPage`, `testShowRunPage`, `testShowUserPage`, `testLongTermPage`, `testShowFailuresPage`, `testShowFlaggedPage`, `testTrainingDataPage`
  - `doCleanup()` deletes test container
- [x] Create sample XML sample XML files:
  - `test/sampledata/testresults/clean-run.xml` — 5 passes, no failures/leaks (qualifies as training run)
  - `test/sampledata/testresults/run-with-failures.xml` — TestFailOne, TestFailTwo
  - `test/sampledata/testresults/run-with-leaks.xml` — TestWithMemoryLeak (managed), TestWithHandleLeak (handle)

## Phase 2: Selenium Tests ✓ (run before refactor to establish baseline)

All tests use UI-based navigation (clicking links, filling forms, selecting options) — no `beginAt()` URL construction.

- [x] `testBeginPage` — BeginAction
  - Navigate via datepicker to sample data dates (01/16, 01/17, 01/18)
  - Verify "Top Failures" / "Top Leaks" sections and test names at each date
  - Test `viewType` selector (day/wk/mo)
- [x] `testShowRunPage` — ShowRunAction + ShowUserAction
  - Navigate to user page via date range, click "run details" links for each sample run
  - Verify run detail fields (passes, failures, leaks)
  - Test sort links (Duration, Managed Memory, Total Memory) with scoped text assertions
- [x] `testRunLookup` — ShowRunAction via Run tab form
  - Enter each sample run ID in the Run tab form, submit, verify run details
- [x] `testLongTermPage` — LongTermAction
  - Test `viewType` selector (wk/mo/yr)
- [x] `testShowFailuresPage` — ShowFailures
  - Navigate to run via Run tab, click failure link, test `viewType` selector
- [x] `testShowFlaggedPage` — FlagRunAction + ShowFlaggedAction
  - Verify empty state ("no flagged runs") → flag run → verify displayed → unflag → verify empty again
- [x] `testTrainingDataPage` — TrainRunAction + TrainingDataViewAction
  - Verify empty state ("No Training Data") → add to training set → verify displayed → remove → verify empty again
- [x] `testViewLog` — ViewLogAction
- [x] `testViewXml` — ViewXmlAction
- [x] `testChangeBoundaries` — ChangeBoundariesAction
- [x] `testSetUserActive` — SetUserActiveAction
- [x] `testDeleteRun` — DeleteRunAction

### Sample Data Enhancements

- [x] Expanded TEST-PC-1 XML files to 150 tests with realistic timestamps and memory profiles
      to support trend chart rendering and avoid false hang detection
- [x] Added TEST-PC-2 sample data (4 runs: clean, disposable, failures, leaks) for
      multi-computer problems matrix and top failures/leaks table verification

## Phase 3: Spring Binding Refactor ✓

### Form Classes Created

| Form Class | Used By | Parameters |
|---|---|---|
| `RunDownForm` | `BeginAction` | `end` (String), `viewType` (String) |
| `ShowUserForm` | `ShowUserAction` | `start` (String), `end` (String), `username` (String), `datainclude` (String) |
| `ShowRunForm` | `ShowRunAction` | `runId` (Integer), `filter` (String) |
| `LongTermForm` | `LongTermAction` | `viewType` (String) |
| `ShowFailuresForm` | `ShowFailures` | `end` (String), `failedTest` (String), `viewType` (String) |
| `RunIdForm` | `DeleteRunAction`, `ViewLogAction`, `ViewXmlAction` | `runId` (Integer) |
| `TrainRunForm` | `TrainRunAction` | `runId` (Integer), `train` (String) |
| `FlagRunForm` | `FlagRunAction` | `runId` (Integer), `flag` (Boolean) |
| `BoundariesForm` | `ChangeBoundaries` | `warningb` (Integer), `errorb` (Integer) |
| `SendEmailForm` | `SendEmailNotificationAction` | `to` (String), `subject` (String), `message` (String) |
| `EmailCronForm` | `SetEmailCronAction` | `action` (String), `emailF` (String), `emailT` (String), `generatedate` (String) |
| `SetUserActiveForm` | `SetUserActive` | `active` (Boolean), `userId` (Integer) |

Date params (`end`, `start`) stay as `String` in forms with `getEndDate()`/`getStartDate()`
convenience methods that call `parseDate()` and throw `ParseException`.

### Additional Improvements Made

- [x] Refactored `getRunDownBean(User, Container, ViewContext)` to accept params directly
- [x] Used `Integer`/`Boolean` instead of primitives for optional params (null = missing)
- [x] Added null guards with descriptive error messages for required params
- [x] Normalized `"Success"` → `"success"` in API responses; added `"cause"` to error responses
- [x] Updated JSP callers (`data.success`, cause-aware alert messages)
- [x] Added `ParseException` handling with `SimpleErrorView` in `BeginAction`, `ShowUserAction`, `ShowFailures`
- [x] Normalized `runid` → `runId` in JSP callers for `ViewLogAction`/`ViewXmlAction`
- [x] Replaced deprecated `javax.management.modelmbean.XMLParseException` with `IllegalArgumentException`
- [x] Replaced `org.springframework.util.StringUtils` with `org.apache.commons.lang3.StringUtils`
- [x] Renamed `ShowUserForm.user` → `username` (and URL param in all JSPs) — `user` is in
      LabKey's `HasAllowBindParameter` disallowed list, so Spring binding silently ignored it
- [x] Fixed pre-existing bug: `ParseAndStoreXML` used `Element.toString()` which returns
      `"[nightly: null]"` instead of serialized XML. Replaced with `Transformer` serialization.

### Actions Already Correct (no change needed)

- `TrainingDataViewAction`, `ShowFlaggedAction`, `ErrorFilesAction`, `PostErrorFilesAction` — no params
- `RetrainAllAction` — already uses `RetrainAllForm` correctly
- `PostAction` — multipart file upload, no form needed

## Phase 4: Run Tests Again ✓

- [x] Run full Selenium test suite against refactored code
- [x] All tests pass (no regressions)

## Phase 5: Build and Commit ✓

- [x] `./gradlew :server:modules:MacCossLabModules:testresults:deployModule` — clean build
- [x] Commit following team conventions

## Phase 6: Post-Deploy on Production (skyline.ms "Nightly x64" folder)

`TestResultsSchema` is now registered via code (`DefaultSchema.registerProvider()`), which
shadows the manually created External Schema that has existed since 2018. The code-level
registration takes precedence, so all saved queries and custom views continue to work.

- [ ] Verify `testresults` schema and tables are accessible in the "Nightly x64" folder
      (Query UI, any custom queries) after deploying the updated module
- [ ] Delete the External Schema via **Admin → Schema Administration → testresults → DELETE**
      to remove the now-dead manual registration

## Known Bugs (out of scope)

See `TODO-LK-20260403_testresults-bugs.md` for known bugs discovered during test development.
