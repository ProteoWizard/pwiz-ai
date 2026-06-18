# Code Review Feedback Catalog — targetedms & MacCossLabModules

<!--
generated: 2026-06-18
sources: ~820 human code-review comments + Copilot/CodeQL findings across ALL PRs
         (repo-wide, regardless of author) in LabKey/targetedms and
         LabKey/MacCossLabModules, fetched via `gh api`.
regenerate: scripts in C:\Users\vsharma\WORK\ClaudeSessions\LabKeyReviewCatalog\
            (refresh_review_catalog.ps1 orchestrates fetch -> digest -> claude -p
            synthesis). Bump `generated:` above.
-->

A checklist of issues reviewers repeatedly flag in these two repos. Each entry is
the recurring problem and the LabKey-idiomatic fix. Apply to the diff under
review; flag matches with the category name.

## Product code

### Security
- **IDOR / container + permission.** Every action that takes an object/row ID
  must verify the object's container and the user's permission on it
  (`ensureCorrectContainer(...)`, or pass `Container`/`User` into the manager).
  Tables without a container column are not auto-filtered — join to one that has
  it. (Auto-incrementing IDs make guessing trivial.)
- **HTML output encoding.** Encode everything rendered to HTML, including
  Excel/TSV/API export paths (`getValue()`), not just the grid. Use `HtmlString`,
  `PageFlowUtil.filter()`, the `DOM` builder, or JS `LABKEY.Utils.encodeHtml()`.
  Do not double-encode (`innerText`/`text()` already encode).
- **SQL / JS literal escaping.** Never hand-concatenate values into SQL or JS.
  Parameterize SQL; use `SQLFragment.appendStringLiteral()` for literals and
  `PageFlowUtil.jsString()` for JS strings.
- **URL encoding.** URL-encode query parameters even when they look constant.
- **No password echo.** Never write a stored credential back into a form; require
  re-entry or an explicit "change credentials" control.
- **Misc.** `rel="noopener noreferrer"` on `target="_blank"`; don't expose an
  unauthenticated email-sending action (open relay).

### Null-safety and types
- Annotate `@Nullable`/`@NotNull` on new params/returns.
- Return `int` not `Integer` when a value is non-null; question every dereference
  of a nullable DB value; put the constant on the left in `equals()`.

### Return types
- No `Object[]` tuples or stringly-typed maps as return values — use a small typed
  holder or `Pair<>`. Name methods for what they return (`hasX` -> boolean).

### Constants
- Repeated string/format literals become named constants — especially
  table/column names shared between a `TableInfo` and its schema class.

### LabKey platform idioms (use the framework, don't reinvent)
- Query/Table API: `TableSelector.setMaxRows()/setOffset()`; `colInfo.getFieldKey()`
  (not the alias); include the `FieldKey` parent so it survives custom
  queries/lookups; override `isSortable()`/`isFilterable()` (return false when
  sorting on a value different from what's rendered); `TargetedMSManager.getSchema()`
  instead of constructing a `UserSchema`; `supportsContainerFilter()`.
- Utilities: `DateUtil.parseDate()`/`getDateOnly()` (not manual/ExtJS parsing);
  `Map.computeIfAbsent()`; `Throttle` for repetitive logging; `LoginUrls` and
  `AuthenticationManager.isRegistrationEnabled()`; `ResponseHelper.setContentDisposition()`;
  `DOM`/`LinkBuilder`/`link()`; `Collections.unmodifiableList()`; `equals()`/`hashCode()`
  so a `Set<DomainObject>` replaces `Set<Integer>`; enhanced `switch`.

### Resource handling
- Close `Results`/`ResultSet`/`Connection`/`TabLoader`/`PrintWriter` with
  try-with-resources — never an explicit `close()` in `finally`.

### Error handling and logging
- Never swallow exceptions (especially in importers — it reports failure as
  success); rethrow or wrap.
- Use a `Logger`; no `System.out.println()` / `e.printStackTrace()`.
- Pick log levels deliberately (`debug` is invisible in prod; use `warn` for
  admin-actionable problems).
- For user/data errors use `BadRequestException` or something implementing
  `SkipMothershipLogging` rather than letting it report to mothership.
- Don't double-log (no `ExceptionUtil` log when already logged locally).

### Transactions
- Wrap multi-statement writes in a transaction; ensure early returns/exceptions
  don't skip `commit()`.

### Dead code
- Remove commented-out code, `console.log`, dead methods/params, emptied
  functions, no-op string concatenations, and unnecessary defensive copies.

### Comments and naming
- Name methods/vars for behavior; document map-value semantics and any subtle or
  negated boolean logic; explain *why* when deviating from the standard approach.

### DB / schema scripts
- Index foreign keys.
- Match column type/length to sibling tables (`VARCHAR(255)`, `NVARCHAR` on SQL
  Server).
- Put the container FK on parent tables, not children (join to the parent).
- Clear orphaned references before adding a FK; year-based script versioning;
  restate `NOT NULL` after `ALTER`; declare deps in `build.gradle`; flag the
  module Postgres-only when SQL Server isn't needed.

### User-facing wording
- Say "folder", not "container". Make messages concrete and match what the user
  actually did.

### Defensive validation / fail-fast
- Validate inputs and throw a real exception (e.g. `IllegalArgumentException`) on
  broken invariants. Do not use bare `assert` (no message on dev, NPE on prod).

### Typos
- Spell-check identifiers, comments, and user-facing strings.

## Test code (Selenium / integration)

### Synchronization
- Synchronize on state change, not time. No bare `sleep` (explain or remove every
  one). Use `clickAndWait`/`waitAndClickAndWait` for navigations; wait for
  data-region staleness after an update. `get*` methods must not mutate page
  state.

### Assertion quality
- Use descriptive AssertJ assertions with `.as(...)` messages, not bare
  `assertTrue`/`assertFalse`. Derive expected counts from named constants, not
  magic numbers.

### Error-path helper
- Model expected-error flows with a paired `*ExpectingError` helper that waits for
  and returns the error message (don't dismiss the dialog first); don't signal
  errors with a boolean flag.

## Module architecture
- Modernize legacy modules: replace manual `request.getParameter()` parsing with a
  Form bean + `FormViewAction`/`MutatingApiAction<Form>` (auto-bound); move SQL
  out of controllers/JSPs into the Manager class.

## Additional checks (from automated reviewers)
- **Fail-open error paths:** a security/perf gate must not fall through to the
  expensive/unsafe path when its guard (e.g. `Files.size()`) throws.
- **API response-shape consistency:** set `status`/`Success` on every error path,
  not just the happy path.
- **Test time/environment assumptions:** no logic that breaks as dates pass or
  across environments; parse JSON instead of substring-matching; use full
  container paths.
- **Accessibility:** no `<button>` nested in `<a>`; `alt=""` for decorative icons.
- **JDK compatibility:** match the build's Java level (e.g. `List.getFirst()` is
  Java 21+).
- **Repeated I/O in loops:** hoist per-iteration filesystem/DB calls out of loops.
- **Stored XSS for uploads:** user-uploaded HTML served same-origin needs a CSP
  sandbox / isolation.
- **Log injection:** parameterized logging (`_log.warn("... {}", x)`), not string
  concatenation of untrusted input.
- **Locale-safe casing:** `toLowerCase(Locale.ROOT)`.
- **Enum-like input validation:** reject unexpected values explicitly instead of
  treating them as a default branch.
- **XXE (CodeQL):** guard XML parsing against external entity expansion.
