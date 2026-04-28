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

## Phase 6: PR Review Follow-ups

PR review surfaced several items beyond the original Spring-binding scope. Done in this
branch as a follow-up to the original refactor.

### Copilot review comments (automated)

- [x] **#1** Parse PostAction response as JSON instead of substring match (TestResultsTest)
- [x] **#2** Datepicker navigation: start at the test date via URL, then use prev/next day links
- [x] **#3** SelectRowsCommand container path — verified both forms work; dismissed
- [x] **#4** TrainRunAction: validate `train` param is `true`/`false`/`force` instead of accepting any string
- [x] **#5** `toLowerCase(Locale.ROOT)` — dismissed (US-locale server, ASCII table names)

### Josh Eckels review comments

- [x] **J1** Extract `"Success"` to `KEY_SUCCESS` constant
- [x] **J2** `SendEmailNotificationAction` was `@RequiresNoPermission` (open relay) — locked down to
      `@RequiresPermission(AdminOperationsPermission.class)`. Possible dead code; dead-code review
      tracked in `TODO-LK-20260403_testresults-bugs.md`.
- [x] **J3** `FlagRunAction`: replaced `getArray()[0]` with `getObject()` + null check
- [ ] **J4** Schema tables without container column → split into separate PR (branch
      `26.3_fb_testresults-container-filter`, commit `b2b2d82`). Not included in this PR.
- [x] **J5** `ShowUserAction`: pass form values via bean so `user.jsp` doesn't read from request

### Container filtering for child tables (J4)

Split into a separate PR — branch `26.3_fb_testresults-container-filter` (commit
`b2b2d82`), based on the tip of this branch. Different review concern than the
Spring-binding refactor. Covers schema-level filter overrides on `TestResultsSchema`
plus a fix to `TestResultsController.getUsers()` so the User-tab dropdown and Training
Data tab list only users with runs in the current folder. Full design notes in
`TODO-LK-20260403_testresults-bugs.md`.

### Misc cleanup made in this branch

- [x] **NavTree breadcrumbs**: extracted `addModuleNavTrail()` helper so all actions
      share a single "TestResults" breadcrumb. Tabs identify the page; breadcrumb just
      anchors back to the module home.
- [x] **WebPartView frame**: replaced ad-hoc `view.setTitle(...)` calls with
      `view.setFrame(WebPartView.FrameType.PORTAL)` so views render with the standard
      LabKey portal frame.

## Phase 7: Post-Deploy on Production (skyline.ms "Nightly x64" folder)

`TestResultsSchema` is now registered via code (`DefaultSchema.registerProvider()`), which
shadows the manually created External Schema that has existed since 2018. The code-level
registration takes precedence, so all saved queries and custom views continue to work.

Shadow-test verification done on a dev-machine mirror restored from a production DB dump —
**passed** (see `TODO-LK-20260425_testresults-schema-shadow-test.md`). All 13 read-only
MCP nightly tools produced byte-identical output across all three states (External schema-only,
External+UserSchema coexist, UserSchema-only). Both write tools (`deactivate_computer`,
`reactivate_computer`) work post-refactor after MCP-side fixes (see "Companion MCP-side
fixes" below).

### Deployment steps

- [ ] Deploy the updated `testresults` module to skyline.ms.
- [ ] Verify `testresults` schema and tables are accessible in `/home/development/Nightly x64`
      (Query UI, any custom queries) after deploy. The 14 saved queries should resolve
      via the now-active UserSchema.
- [ ] **Enable the `TestResults` module in `/home/development`** (parent container)
      *before* deleting the External Schema there. Reasoning: the saved queries are
      stored in `query.querydef` with `container = /home/development`, and sub-folders
      see them via parent-chain inheritance. With the External Schema gone, the parent
      container has no `testresults` schema unless the module is enabled there. Read
      paths (e.g., the MCP) continue to work because LabKey resolves the schema in the
      leaf-folder context where the module is enabled, but the Schema Browser's
      Jump-to-Definition / saved-query editing UI shows "Missing Schema" from
      sub-folders. Discovered in shadow-test Phase 3.
- [ ] Delete the External Schema via **Admin → Schema Administration → testresults → DELETE**.
      **Important:** the External Schema is registered in **7 containers** on prod —
      `/home/development` plus the 6 test sub-folders (`Nightly x64`, `Release Branch`,
      `Release Branch Performance Tests`, `Performance Tests`, `Integration`,
      `Integration with Perf Tests`). Delete must be repeated per container — it does
      not propagate from the parent.

### Companion MCP-side fixes

Three MCP-side regressions caused by this refactor's contract changes were caught
by the shadow test. **Production deployment of the testresults module is not safe
for MCP consumers until they land alongside.**

- Tracked in `TODO-20260428_labkey_mcp_shadow-fixes.md`. Covers:
  `runid` → `runId` URL params, JSON-body + Message-check on `SetUserActive`,
  and `exception`-over-`error` non-200 extraction.
- Sibling PR `TODO-20260428_labkey_mcp_dev-target.md` adds env-var dev-target
  switching to the MCP. Not blocking for the testresults deployment, but
  provides the mechanism that caught these regressions.

## Known Bugs (out of scope)

See `TODO-LK-20260403_testresults-bugs.md` for known bugs discovered during test development.
