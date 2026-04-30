# TODO-LK-20260403_testresults-bugs.md

## Branch Information
- **Branch**: TBD
- **Base**: `release26.3-SNAPSHOT`
- **Created**: 2026-04-03
- **Status**: Not Started

## Objective

Known bugs in the `testresults` module discovered during Selenium test development.

---

## ~~Bug: `ViewXmlAction` stores and returns `"[nightly: null]"` instead of actual XML~~ — FIXED

**Fixed in PR [#622](https://github.com/LabKey/MacCossLabModules/pull/622)** (2026-04-06).
Replaced `docElement.toString()` with `Transformer` serialization in `ParseAndStoreXML`.
Note: existing rows in `testresults.testruns.xml` on skyline.ms still contain
`"[nightly: null]"` — new posts will store correct XML going forward.

---

## Bug: CSP `img-src` violation on `showUser.view`

The browser reports a CSP `img-src` violation where the blocked URI is the `showUser.view`
page URL itself, e.g.:
```
img-src: http://localhost:8080/<container>/testresults-showUser.view?user=TESTPC-AUTOMATION
```
A blocked URI equal to the document URI means an `<img src="">` (empty `src`) exists on
the page — the browser resolves empty `src` as the current page URL, which is then
blocked by the `img-src` CSP policy.

**Most likely cause**: the jQuery UI datepicker widget (loaded via `user.jsp` line 37–38)
generates `<img>` navigation arrows. When `buttonImage: ""` (the jQuery UI default) and
a datepicker instance is created, jQuery UI may emit `<img class="ui-datepicker-trigger"
src="">` for the calendar trigger. The `initDatePicker()` call in `user.jsp` line 240
triggers this via `$('#jrange div').datepicker({...})`.

**Fix options**:
1. Replace the jQuery UI datepicker with a CSP-compliant alternative (no `<img>` arrows)
2. Add explicit `buttonImage` / navigation text options to suppress `<img>` generation
3. Host jQuery UI locally (eliminates external CDN) and audit for empty `src` generation

**Status**: Not yet confirmed — discovered during test development, needs verification.

---

## Bug: Client-side JS errors on `showFailures.view`

`checkErrors()` reports client-side JavaScript errors after loading `failureDetail.jsp`.

**Most likely cause**: The c3 bar chart in `failureDetail.jsp` is initialized with
`axis.x.min` / `axis.x.max` set from `problemData.graphData.dates[0]` and
`dates[dates.length - 1]`. When the sample XML data (posted January 2026) fall outside the
active date range (e.g., `viewType=mo` with today = April 2026), `dates` may be empty,
making both values `undefined`. c3/D3 may throw on `undefined` date axis bounds.

Additionally, the `tablesorter` `headers` option uses `"#col-problem"` (an element ID
string) as a key:
```javascript
headers : { "#col-problem": { sorter: false } },
```
Tablesorter expects numeric column indices as keys. The string key is silently ignored,
but certain tablesorter versions throw on non-numeric keys.

**Fix**: Guard the c3 axis config against empty dates:
```javascript
axis: {
    x: {
        min: dates.length > 0 ? dates[0] : undefined,
        max: dates.length > 0 ? dates[dates.length - 1] : undefined,
        ...
    }
}
```
Also change `headers: { "#col-problem": ... }` → `headers: { 5: { sorter: false } }`
(column index 5, the last column).

**Status**: Not yet confirmed — discovered during test development, needs verification.

---

## Bug: `MDYFormat` (date parsing) is lenient — invalid dates roll over silently

`parseDate` in `TestResultsController.java:169` uses `MDYFormat` which is a
`SimpleDateFormat("MM/dd/yyyy")`. `SimpleDateFormat` is **lenient by default**,
so out-of-range values are silently rolled over instead of throwing
`ParseException`. For example, `13/45/2026` parses to `02/14/2027` (month 13 →
+1 year, day 45 of January → +44 days into February).

Effect: a user typing a wrong date in the date picker (or hitting a URL with a
typo'd date) sees runs from a completely unrelated time period instead of an
"invalid date" error. The error-handling code in `BeginAction`,
`ShowUserAction`, and `ShowFailures` that catches `ParseException` and rejects
with `"Invalid date format: ..."` only fires for *unparseable* strings like
`"garbage"`, not for nonsense dates.

**Fix**: call `MDYFormat.setLenient(false)` once on the static formatter (and
make sure it's not shared in a thread-unsafe way — `SimpleDateFormat` is not
thread-safe; consider using `DateTimeFormatter` from `java.time` instead).

**Status**: Confirmed via `TestResultsTest.testInvalidDateParameters`. The
test originally tried `13/45/2026` and it parsed successfully, exposing the
leniency issue. The test now uses a clearly-unparseable string.

---

## Bug: `TrainRunAction` leaves stale `UserData` row when removing user's last training run

When a user removes the last run from their training set via `TrainRunAction`
(`train=false`), the user's `UserData` row is left untouched with its previous
(now stale) `meanmemory` / `meantestsrun` values. The user keeps appearing in
`<table id="trainingdata">` on the Training Data page even though they have no
training runs, because `trainingdata.jsp:158` decides which users go into the
"No Training Data --" list by checking `user.getMeanmemory() == 0d &&
user.getMeantestsrun() == 0d`.

**Root cause** — the recompute query in `TrainRunAction` (`TestResultsController.java:533`):

```sql
INSERT INTO UserData (userid, container, meantestsrun, meanmemory, stddevtestsrun, stddevmemory)
SELECT ?, ?, avg(passedtests), avg(averagemem), stddev_pop(passedtests), stddev_pop(averagemem)
FROM TestRuns
JOIN Train ON TestRuns.id = Train.runid
WHERE userid = ? AND container = ?
GROUP BY userid, container
ON CONFLICT(userid, container) DO UPDATE SET ...
```

After the `DELETE FROM Train` step removes the user's last training row, the
`TestRuns JOIN Train` produces zero rows. With `GROUP BY userid, container`,
aggregates over an empty input produce **zero output rows** (not one NULL row).
The INSERT inserts nothing, `ON CONFLICT` never fires, and the existing
`UserData` row is left in place with its old values.

`RetrainAllAction` in **reset mode** does not have this bug because it calls
`mgr.deleteUserDataForContainer(c)` upstream, wiping the table before
rebuilding. **Incremental mode** of `RetrainAllAction` does have a similar
issue — if a user's `finalRunIds` ends up below `minRuns`, the `continue`
leaves their stale `UserData` row in place — but that's a narrower edge case.

**Fix options** (in order of cleanliness):
1. **Best**: in `TrainRunAction`, after the Train delete, check whether any
   Train rows remain for `(userid, container)`. If not, run
   `DELETE FROM UserData WHERE userid = ? AND container = ?` instead of the
   recompute query. This matches the JSP's contract: no training data → user
   appears under "No Training Data --".
2. Drop `GROUP BY` from the recompute query so an empty join produces one NULL
   row, which would let `ON CONFLICT DO UPDATE` fire and write NULLs. Less
   clean: leaves a junk row whose `getMeanmemory()` value depends on how the
   bean handles NULL columns.
3. Apply the same delete/clear logic to `RetrainAllAction`'s incremental path
   for the `continue` cases.

**Status**: Confirmed via test development. Test
`TestResultsTest.testTrainingDataPage` works around it by not asserting empty
state after removing the last training run.

---

## Bug: `DeleteRunAction` fails with foreign key constraint violation

Deleting a run that has associated leak records fails with:
```
error: SqlExecutor.execute(); ERROR: update or delete on table "testruns" violates
foreign key constraint "fk_memoryleaks_testruns" on table "handleleaks"
  Detail: Key (id)=(94) is still referenced from table "handleleaks".
```

`DeleteRunAction` deletes from `testruns` without first deleting child rows in `handleleaks` (and likely `memoryleaks`, `failures`, `passes`). The fix is to delete from child tables before deleting the parent `testruns` row, or add `ON DELETE CASCADE` to the foreign key constraints.

---

## Review: `SendEmailNotificationAction` may be dead code

`SendEmailNotificationAction` (`TestResultsController.java:1211`) is a generic endpoint
that sends arbitrary email (with caller-supplied `to`, `subject`, `message`) as
`skyline@proteinms.net`. It was previously annotated `@RequiresNoPermission`, making it
an open email relay. Changed to `@RequiresPermission(AdminOperationsPermission.class)` in
PR [#622](https://github.com/LabKey/MacCossLabModules/pull/622).

Nothing in the module calls this action — no JSP, JS, or Java reference exists. The daily
8am summary email uses `SendTestResultsEmail` (a Quartz job) which sends directly via
`EmailService`, completely independent of this action.

**Action**: Review whether any external script or service calls
`testresults-sendEmailNotification.api`. If not, remove it as dead code.

**Status**: Permission lockdown done (PR #622). Dead code review pending.

---

## Issue: Schema tables missing container column — query browser shows unfiltered rows — FIX PENDING

Several `testresults` schema tables (`handleleaks`, `memoryleaks`, `testfails`,
`testpasses`, `hangs`, `trainruns`, `user`) do not have a `container` column. In
`TestResultsSchema.createTable()` they were wrapped in a plain `FilteredTable`, so the
default container filter had no column to bind to and silently did nothing — the query
browser showed all rows across all containers.

Visible on skyline.ms and dev machines: skyline.ms has several containers with the
TestResults module active, so the schema browser was effectively cross-container before
this fix.

**Fixed on branch `26.3_fb_testresults-container-filter`** (commit `b2b2d82`, PR TBD) by
overriding `applyContainerFilter()` on a per-table `FilteredTable` subclass. Split out
of PR [#622](https://github.com/LabKey/MacCossLabModules/pull/622) into a separate PR so
the schema-level fix can be reviewed independently from the Spring-binding refactor.

- Run-child tables (`handleleaks`, `memoryleaks`, `testfails`, `testpasses`, `hangs`,
  `trainruns`): add a `WHERE fk_col IN (SELECT id FROM testruns WHERE <container filter>)`
  predicate, where `fk_col` is `testrunid` or (for `trainruns`) `runid`. Also override
  `getContainerFieldKey()` to return the path through the FK so LabKey's introspection
  knows where the container "lives".
- `user`: filter to user rows referenced by at least one testrun in an allowed container,
  via `WHERE id IN (SELECT userid FROM testruns WHERE <container filter>)`. (No `DISTINCT`
  — `IN` already has semi-join semantics, and adding it would force an extra dedup step.)
  No `getContainerFieldKey()` since the FK direction is reversed (testruns → user).
- `testruns` and `userdata` already have a `container` column, so the default filter
  works for them — they continue to use the plain `FilteredTable`.
- `globalsettings` is intentionally global (no container scoping needed).

### Why `applyContainerFilter()` and not `getFromSQL()`

Two patterns are common in LabKey for this:
- **Pattern A — override `applyContainerFilter()`**: adds an `IN` / `EXISTS` `WHERE`
  predicate on top of the underlying DB table. Used by `CommentsTable` in the issues
  module (filter comments by their parent issue's container).
- **Pattern B — override `getFromSQL()`**: wraps the table in a `SELECT ... JOIN parent
  ... WHERE <container filter>` subquery in the FROM clause. Used by `PanoramaPublicTable`,
  `ExpRunGroupMapTableImpl`, `DatasetColumnsTable`.

Both call `filter.getSQLFragment(...)` to produce the actual container SQL, so both
support `CurrentAndSubfolders` equally well. The differences:

| Concern | Pattern A | Pattern B |
|---|---|---|
| Code complexity | Light — a single SQL fragment | Heavier — reconstruct full SELECT with column aliasing |
| Multi-level FK chains | Awkward (nested IN subqueries) | Clean (explicit JOIN chain) |
| Synthetic columns from parent | Not supported | Supported |
| FK navigation in schema browser | Use `getContainerFieldKey()` to expose the path | Implicit — filter lives in the FROM |

Chose **Pattern A** because the testresults child tables have a single, simple FK to
`testruns` and we don't need to expose synthetic columns from the parent. `CommentsTable`
is the closest analogue in the platform code and uses the same approach.

**When to revisit**: switch to Pattern B if we add child tables with multi-level FK
chains (e.g., something that joins through two parent tables to reach a container) or if
the schema browser starts misbehaving on FK navigation.

**Test coverage**: `TestResultsTest.testContainerFiltering` creates a subfolder, posts
one run into it, and verifies that `testpasses`, `testfails`, `trainruns`, and `user`
queries from each container only return rows scoped to that container.

### Related fix: `User` dropdown and Training Data tab listed users from all containers

The same branch also fixes `TestResultsController.getUsers(Container, String)`, which
ignored the container parameter when building the user list. The User-tab dropdown
(`user.jsp`) and the Training Data tab now list only users with at least one testrun in
the current folder. `PostAction`'s find-or-create-by-name lookup continues to use the
`(null, username)` overload and stays global — exactly what's needed for that path.
