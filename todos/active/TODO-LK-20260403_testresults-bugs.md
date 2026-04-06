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

## Bug: `DeleteRunAction` fails with foreign key constraint violation

Deleting a run that has associated leak records fails with:
```
error: SqlExecutor.execute(); ERROR: update or delete on table "testruns" violates
foreign key constraint "fk_memoryleaks_testruns" on table "handleleaks"
  Detail: Key (id)=(94) is still referenced from table "handleleaks".
```

`DeleteRunAction` deletes from `testruns` without first deleting child rows in `handleleaks` (and likely `memoryleaks`, `failures`, `passes`). The fix is to delete from child tables before deleting the parent `testruns` row, or add `ON DELETE CASCADE` to the foreign key constraints.
