# TODO-LK-20260407_panoramapublic-ncbi_doctype_parsing.md

## Branch Information

| Repo | Branch | PR | Base |
|---|---|---|---|
| `MacCossLabModules` | `26.3_fb_panoramapublic-ncbi-doctype-parsing` | [#623](https://github.com/LabKey/MacCossLabModules/pull/623) | `release26.3-SNAPSHOT` |
| `platform` | `26.3_fb_panoramapublic-ncbi-doctype-parsing` | [#7561](https://github.com/LabKey/platform/pull/7561) | `release26.3-SNAPSHOT` |

- **Created**: 2026-04-07
- **Last updated**: 2026-04-28
- **Completed**: 2026-04-09
- **Status**: **DONE**. Both PRs merged on 2026-04-09 — platform
  [#7561](https://github.com/LabKey/platform/pull/7561) at 03:48 UTC
  (merge commit `a5c73221`), MacCossLabModules
  [#623](https://github.com/LabKey/MacCossLabModules/pull/623) at 16:59 UTC
  (merge commit `c21db755`). Platform-first ordering preserved. CodeQL
  `java/xxe` alert resolved (no remaining alerts blocking this work).
- **Cross-repo workflow**: per
  [`labkey-feature-branch-workflow.md`](../../docs/labkey/labkey-feature-branch-workflow.md)
  — both branches share the same name so TeamCity matches them. **The platform
  PR must merge first** (or simultaneously), since `NcbiUtils.getDocumentBuilder()`
  references the new `DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE` constant.

### Build issues (resolved 2026-04-08)

TeamCity initially failed with `"Snapshot dependency failed"` and a downstream
compile error in `platform/api/.../McpService.java` referencing a missing
`org.springaicommunity.mcp.provider.resource` package. Root cause: the platform
feature branch was 9 commits behind `origin/release26.3-SNAPSHOT`, missing the
"MCP Server MVP" commit
([#7548](https://github.com/LabKey/platform/pull/7548)) which added both
`McpService.java` and the corresponding gradle dependency. The branch had this
state because the local `release26.3-SNAPSHOT` had not been pulled immediately
before branching off. Fixed by rebasing the platform feature branch onto
current upstream and force-pushing. (MacCossLabModules branch did not need an
update — its build was only failing because its snapshot dependency on the
platform branch was failing.)

## Bug

`NcbiUtils.getScientificNames` throws `PxException` when generating
ProteomeXchange XML, caused by:

```
SAXParseException: DOCTYPE is disallowed when the feature
"http://apache.org/xml/features/disallow-doctype-decl" set to true
```

NCBI's `esummary.fcgi` taxonomy response begins with
`<!DOCTYPE eSummaryResult PUBLIC ... esummary-v1.dtd>`, which the hardened
parser rejects.

**Affected surfaces** (all three funnel through `NcbiUtils.getScientificNames`,
so one fix repairs all):

1. "Validate PX XML" button — `GetPxActionsAction` → `PxXmlWriter.writeSpeciesList`
2. "PX XML Summary" view — `PxXmlSummaryAction` → `PxHtmlWriter`
3. `PxWriter.getScientificNames` (base method called by both writers above)

**Not affected**: PX data validation pipeline (no NCBI calls), and the
experiment metadata form's organism autocomplete (`NcbiUtils.getCompletions`
uses regex on a JS-array text response — no XML parsing).

## Root Cause

[LabKey/MacCossLabModules#605](https://github.com/LabKey/MacCossLabModules/pull/605)
*"Ensure consistent XML parser config"* (merge commit
[`f1977199`](https://github.com/LabKey/MacCossLabModules/commit/f1977199a973e09cf0735ef49a3822f2ac2578ed))
replaced a local `DocumentBuilderFactory.newInstance()` with the shared
`XmlBeansUtil.DOCUMENT_BUILDER_FACTORY`, which sets `disallow-doctype-decl=true`
for XXE protection. The other parsers touched by #605 (`PsiInstrumentParser`,
`UnimodParser`, `FilesMetadataImporter`) all parse local files without
DOCTYPE declarations — `NcbiUtils` is the only regression.

### About XXE

XML eXternal Entity injection: a vulnerable parser resolves
`<!ENTITY xxe SYSTEM "file:///etc/passwd">` when it sees `&xxe;`, exposing
local files / SSRF / billion-laughs DoS. The fix keeps every external-entity
defense from #605 (no external entities, no external DTD load, secure
processing on, no entity expansion) and only relaxes the strict
`disallow-doctype-decl` flag for this one caller.

## Fix

Mirror the existing `XmlBeansUtil.SAX_PARSER_FACTORY_ALLOWING_DOCTYPE` pattern
by adding a new `public static final DocumentBuilderFactory
DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE` constant to `XmlBeansUtil` (platform
repo), plus a private `documentBuilderFactory(boolean allowDocType)` helper.
The existing `DOCUMENT_BUILDER_FACTORY` is also routed through the helper so
both DOM factories are configured in one place — the only difference between
them is the `disallow-doctype-decl` flag.

`NcbiUtils.getDocumentBuilder()` (panoramapublic) consumes the new constant.
The DOM walk in `parseScientificNames` is unchanged.

### Considered and rejected

- **SAX-only, single repo.** Rewrite `parseScientificNames` to use
  `SAX_PARSER_FACTORY_ALLOWING_DOCTYPE` with a small `DefaultHandler`. Avoids
  the cross-repo coordination but converts that one call site away from DOM
  and doesn't make a hardened DOCTYPE-allowing DOM factory available to
  future callers. The platform-constant route was preferred for symmetry with
  the existing SAX constant.
- **Mutate `XmlBeansUtil.DOCUMENT_BUILDER_FACTORY` in place**
  (`factory.setFeature("...disallow-doctype-decl", false)`). Rejected: that
  singleton is `public static final` shared across the JVM. The first call
  would permanently flip `disallow-doctype-decl=false` for every other parser
  in the server, silently defeating the XXE hardening intent of
  [#605](https://github.com/LabKey/MacCossLabModules/pull/605).

## Test Plan

TeamCity has no outbound network access, so use a canned-response unit test.
Both tests live in the `NcbiUtils.TestCase` inner class:

- `testParseScientificNamesAllowsDoctype` — parses a real captured NCBI
  payload (taxids 9606/Homo sapiens, 10090/Mus musculus, 4932/S. cerevisiae)
  with the `<!DOCTYPE>` line preserved verbatim. Would have failed pre-fix.
- `testParseScientificNamesBlocksXxe` — declares
  `<!ENTITY xxe SYSTEM "file:///etc/passwd">` and asserts the entity is not
  resolved (or the parser rejects the payload outright).

`TestCase` registered in `PanoramaPublicModule.getUnitTests()`.

## Tasks

- [x] Diagnose root cause and identify regression source (#605, commit
      [`f1977199`](https://github.com/LabKey/MacCossLabModules/commit/f1977199a973e09cf0735ef49a3822f2ac2578ed)).
- [x] Audit other parsers touched by #605 (`PsiInstrumentParser`,
      `UnimodParser`, `FilesMetadataImporter`) — all parse local files
      without DOCTYPE, unaffected.
- [x] Rule out PX data validation pipeline and metadata-form organism
      autocomplete as affected surfaces.
- [x] Extract `parseScientificNames(InputStream)` seam in `NcbiUtils`.
- [x] Add `NcbiUtils.TestCase` with DOCTYPE-allows + XXE-blocks tests, using
      a real captured NCBI payload.
- [x] Register `NcbiUtils.TestCase` in `PanoramaPublicModule.getUnitTests()`.
- [x] Draft both fix approaches (SAX-only and platform constant).
- [x] Email Josh Eckels for preference between approaches.
- [x] Decision: go with the platform-constant approach.
- [x] Add `DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE` constant + private
      `documentBuilderFactory(boolean)` helper to `XmlBeansUtil` (platform
      branch).
- [x] Wire `NcbiUtils.getDocumentBuilder()` to consume the new constant.
- [x] Commit panoramapublic changes to local branch.
- [x] Commit platform changes to fork.
- [x] Open both PRs (platform [#7561](https://github.com/LabKey/platform/pull/7561),
      MacCossLabModules [#623](https://github.com/LabKey/MacCossLabModules/pull/623)).
- [x] Fix TeamCity "Snapshot dependency failed" by rebasing platform branch
      onto current `release26.3-SNAPSHOT` (was 9 commits behind, missing the
      MCP Server MVP commit and its gradle dependency).
- [x] CodeQL `java/xxe` alert resolved — no remaining alerts blocking this
      work. Pre-existing alert #13 on `develop` auto-closed (`fixed`) once the
      old `parse(conn.getInputStream())` line vanished post-merge, as
      anticipated in the dismissal plan.
- [x] Confirm TeamCity build clears for both PRs after the rebase + push —
      both PRs merged successfully on 2026-04-09.
- [x] Reproduce original failure on `release-branch` head (pre-fix).
- [x] Run unit tests locally; both pass.
- [x] Sanity check: temporarily revert the fix and confirm the regression test
      fails (proves the test guards the bug).
- [x] Confirm `getPxActions.view` "Validate PX XML" and `pxXmlSummary.view`
      "PX XML Summary" both succeed end-to-end on the Seoul National
      University dataset.
- [x] Merge platform PR first — platform #7561 merged 03:48 UTC,
      MacCossLabModules #623 merged 16:59 UTC same day.

## CodeQL `java/xxe` alert

GitHub Code Scanning flags `parseScientificNames` with rule `java/xxe`
("Resolving XML external entity in user-controlled data") at the
`getDocumentBuilder().parse(in)` call site. This is a **false positive** but
needs to be dismissed because CodeQL cannot verify the factory configuration.

### Why it fires

CodeQL traces taint from `HttpURLConnection.getInputStream()` (in
`getScientificNames`) through the `parseScientificNames(InputStream in)`
helper into `parse(in)`. The factory comes from
`XmlBeansUtil.DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE`, which lives in the
platform JAR. CodeQL with default setup analyzes the panoramapublic source
only — the `XmlBeansUtil` class is a binary dependency, so CodeQL has no
visibility into how the factory was configured. From CodeQL's perspective the
factory is opaque, the input is tainted, and there is no visible sanitizer.

### Why it is in fact safe

`DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE` (added in this work, in
`XmlBeansUtil.documentBuilderFactory(true)` on the platform branch) sets every
XXE mitigation:

- `external-general-entities = false`
- `external-parameter-entities = false`
- `nonvalidating/load-external-dtd = false`
- `FEATURE_SECURE_PROCESSING = true`
- `setXIncludeAware(false)`
- `setExpandEntityReferences(false)`

Only `disallow-doctype-decl` is relaxed (left at the default `false`), so the
NCBI `<!DOCTYPE eSummaryResult PUBLIC ... esummary-v1.dtd>` line is parsed
but the external DTD URL is never fetched, and any `&entity;` references are
never expanded. `NcbiUtils.TestCase.testParseScientificNamesBlocksXxe`
provides regression coverage: it declares
`<!ENTITY xxe SYSTEM "file:///etc/passwd">` and asserts the entity is not
resolved into the parsed output (or the parser rejects the payload outright).

### Why it didn't appear before the refactor

Pre-refactor, `NcbiUtils.getScientificNames` had
`builder.parse(conn.getInputStream())` inline. CodeQL was *already* flagging
that line — it appears as alert
[#13](https://github.com/LabKey/MacCossLabModules/security/code-scanning/13)
on the `develop` branch ("Resolving XML external entity in user-controlled
data", `Open`, `panoramapublic/.../NcbiUtils.java:134`). It just never blocked
a PR because GitHub Code Scanning only surfaces alerts whose location overlaps
with the PR diff. The refactor moved `parse()` onto a brand-new line in a
brand-new method (`parseScientificNames`), which now overlaps the diff and is
reported as a "new" PR alert. **It is the same finding as #13, just at a
different line.**

### Dismissal plan

1. On the panoramapublic PR's CodeQL alert: click "Dismiss alert" → **"Won't
   fix"**, and paste the justification below.
2. On `develop`-branch alert
   [#13](https://github.com/LabKey/MacCossLabModules/security/code-scanning/13):
   dismiss with the same reason and the same justification — otherwise it
   stays open in the security overview as a critical even after the PR alert
   is closed. (Alternatively, after the PR merges and the old line vanishes,
   #13 may auto-close; verify post-merge.)

**Justification text:**

> The `DocumentBuilderFactory` returned by
> `XmlBeansUtil.DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE` is configured in
> `platform/api/.../XmlBeansUtil.documentBuilderFactory(true)` with full XXE
> mitigation in place: `external-general-entities=false`,
> `external-parameter-entities=false`,
> `nonvalidating/load-external-dtd=false`, `FEATURE_SECURE_PROCESSING=true`,
> `XIncludeAware=false`, `expandEntityReferences=false`. Only
> `disallow-doctype-decl` is relaxed (to `false`) so that NCBI's eSummary
> response — which begins with
> `<!DOCTYPE eSummaryResult PUBLIC ... esummary-v1.dtd>` — can be parsed at
> all. The external DTD URL is never fetched and any `&entity;` references
> are never expanded. `NcbiUtils.TestCase.testParseScientificNamesBlocksXxe`
> (added in this PR) provides a regression test against XXE: it declares
> `<!ENTITY xxe SYSTEM "file:///etc/passwd">` and asserts the entity is not
> resolved into the parsed output. CodeQL cannot see the factory
> configuration because it lives in a different module (`platform`).

### Audit notes (so we don't re-derive next time)

- No CodeQL/LGTM config exists anywhere in `release-branch`. No
  `.lgtm.yml`, no `.github/codeql/`, no inline `lgtm[...]` suppressions, no
  `@SuppressWarnings("java:S2755")`, no `// codeql` annotations, no code
  comment mentioning XXE / external entity / CodeQL / false positive. There
  is no established suppression pattern in the labkey codebase — this would
  be the first one.
- `MacCossLabModules` and `platform` repos do **not** have a checked-in
  CodeQL workflow file. `commonAssays/.github/workflows/codeql.yml` and
  `targetedms/.github/workflows/codeql.yml` exist; that's it. CodeQL on
  MacCossLabModules is enabled via GitHub's "Default setup" at the repo level.
- The other panoramapublic callers of `XmlBeansUtil.DOCUMENT_BUILDER_FACTORY`
  (`PsiInstrumentParser`, `UnimodParser`, `FilesMetadataImporter`,
  `FilesMetadataWriter`) are not flagged by CodeQL because their input does
  not reach a CodeQL taint source — they parse local module resources or
  `VirtualFile` round-trips, not network input.
- `DavController.handlePropfind/proppatch/lock` (in `platform`) parses the
  servlet request body XML with the same `XmlBeansUtil.DOCUMENT_BUILDER_FACTORY`
  against `getInputStream()`, which is the textbook `java/xxe` taint source.
  If/when platform gets CodeQL enabled, those should also fire and need the
  same dismissal pattern. Out of scope for this TODO.

## Followups (out of scope)

- The MacCossLabModules repo has **13 open CodeQL alerts** on `develop` as
  of 2026-04-08 (the `13` badge in the Security and quality overview). Worth
  triaging that backlog separately — most are likely false positives in the
  same vein as ours, but there may be real findings hiding in there. File a
  separate issue / TODO when there's bandwidth.

## Files Touched

**MacCossLabModules**:
- `panoramapublic/src/org/labkey/panoramapublic/proteomexchange/NcbiUtils.java`
  — `parseScientificNames(InputStream)` seam, `getDocumentBuilder()` consumes
  the new platform constant, `TestCase` inner class
- `panoramapublic/src/org/labkey/panoramapublic/PanoramaPublicModule.java`
  — register `NcbiUtils.TestCase`

**platform**:
- `server/modules/platform/api/src/org/labkey/api/util/XmlBeansUtil.java`
  — add `DOCUMENT_BUILDER_FACTORY_ALLOWING_DOCTYPE` + private
  `documentBuilderFactory(boolean)` helper. Existing `DOCUMENT_BUILDER_FACTORY`
  also routed through the helper so both DOM factories are configured in one
  place.
