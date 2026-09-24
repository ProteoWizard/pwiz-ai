# TODO-20260924_httpclient_to_progress_continued.md

## Branch Information
- **Branch**: `Skyline/work/20260924_httpclient_to_progress_continued`
- **Base**: `master`
- **Created**: 2026-09-24
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4700](https://github.com/ProteoWizard/pwiz/pull/4700)
- **Objective**: Retire the last `WebClient` and `HttpWebRequest` uses in Skyline and
  its tools, and decide what to do about bare `HttpClient` - so every HTTP call goes
  through `HttpClientWithProgress`, or plain `HttpClient` where the project cannot
  reference it

## Background

The 2025 migration made `HttpClientWithProgress` the project standard (core Skyline,
`.skyp`, PanoramaClient, WebEnabledFastaImporter). PR #4648 (merged 2026-09-10,
`completed/TODO-20260824_webclient_prohibition.md`) finished the batch tools
(SkylineBatch, SharedBatch, AutoQC) and added the `CodeInspectionTest` rule
against constructing a `WebClient`, with a **tolerated count of 3** that tracks
the survivors.

Both `WebClient` and `HttpWebRequest`/`WebRequest.Create` are obsolete on .NET 10
(SYSLIB0014). Doing this on master, as #4648 did, means the .NET port
(PR #4619, `Skyline/work/20260612_net8_port`) inherits the fix instead of carrying it.

## Inventory (2026-09-23)

Taken from `origin/master` (`043f279cc0`) and the port branch with `git grep`. The two
are identical apart from line numbers, except for `pwiz-sharp/`, which exists only on the port.

### 1. `new WebClient` - 3 tracked by the inspection rule
| File | Plan |
|---|---|
| `SkylineNightly/Nightly.cs` (line 613) | Plain `HttpClient`. The project has no `ProjectReference`s, so `HttpClientWithProgress` is not available |
| `SkylineNightlyShim/Program.cs:141` | Plain `HttpClient`. It is deliberately tiny; keep it that way |
| `Executables/Installer/SetupDeployProject.cs:109` | **Defer.** The installer is being replaced as part of the .NET port |

Lower the `CodeInspectionTest` tolerance from 3 to 1 once Nightly and the Shim are done.
Out of scope: `Bumbershoot/idpicker/Deploy/SetupDeployProject.cs` (outside the scan root).

### 2. `HttpWebRequest` / `WebRequest.Create`
| File | Notes |
|---|---|
| `Skyline/Program.cs:496, 551` | Google Analytics pings |
| `Skyline/Alerts/ReportErrorDlg.cs:257, 324` | Exception report post and CSRF token fetch. Needs cookie handling (`CookieContainer`), as PanoramaClient does |
| `Executables/SkylineBatch/SkylineBatch/Program.cs:285` | Analytics ping - the batch tools' last obsolete HTTP API use |
| `SkylineNightly/Nightly.cs:1175, 1242, 1435` | Same plain-`HttpClient` constraint as above; do with section 1 |

Out of scope: `Bumbershoot/idpicker/Util/CookieAwareWebClient.cs`.

### 3. Bare `new HttpClient` in test and developer tools (lowest priority)
`SkylineTester/TabBuild.cs:150`, `DevTools/ImageComparer/ImageComparerWindow.cs:399`,
`TestUtil/ScreenshotPreviewForm.cs:637`, `TestUtil/UniprotApiVersionCheck.cs:66`,
`TestFunctional/StartPageTest.cs:150`. These are not user-facing. Migrate the ones that
are simple to change and allow the rest by exception in any new inspection rule
(section 5).

### 4. pwiz-sharp (port branch only)
`pwiz-sharp/pwiz/src/Vendor/UNIFI/AbstractWatersHttpClient.cs:64`,
`pwiz-sharp/Tools/MsConvertGUI/src/UnifiBrowserForm.cs:167`,
`pwiz-sharp/pwiz/src/Vendor/Common/VendorSdkLoader.cs:403`. pwiz-sharp does not
reference `pwiz_tools/Shared/Common*`, so `HttpClientWithProgress` is not available there
without a new dependency. **Decision needed**: leave pwiz-sharp on plain `HttpClient`,
or share the wrapper. The ~20 other `new HttpClient(handler)` hits under
`pwiz-sharp/pwiz/test/UNIFI.Tests` are mock-handler injection and are fine.

### Excluded: Ardia
`Alerts/ArdiaLoginDlg.cs` (7 bare `HttpClient`), `ToolsUI/EditRemoteAccountDlg.cs:290`,
and `Shared/CommonMsData/RemoteApi/Ardia/ArdiaClient.cs` (bare `HttpClient` at 142/368,
`HttpWebRequest` at 204) are **deliberately left alone**. Ardia's future beyond the
.NET port depends on whether Thermo funds it, and until that is decided it gets as
little development time as possible. The port branch does compile it (the
`Skyline.csproj` comment lists "Ardia remote" among restored features), but it has
likely had no real testing there. Do not migrate, refactor, or add tests for Ardia code
under this TODO. Any new inspection rule must exempt these files rather than count
them as work to do.

## Task Checklist

### Phase 1: SkylineNightly and SkylineNightlyShim
- [x] Replace `WebClient` in `Nightly.cs` and `SkylineNightlyShim/Program.cs` with plain `HttpClient`
- [x] Replace the three `HttpWebRequest` uses in `Nightly.cs` (log post, email notification, CSRF token)
- [x] Lower the `CodeInspectionTest` WebClient tolerance from 3 to 1
- [ ] Verify by running SkylineNightly for real: posting results, and a Shim self-update check

Done 2026-09-24. Build, CodeInspection and QuickInspection (SkylineNightly,
SkylineNightlyShim, Test) all clean. Live verification is still open: the dev
machine has no `TEAMCITY_NIGHTLY_TEST_AUTH_TOKEN`, and the posts write to the shared
results database and send email.

Design:
- Both downloads go through a new `TeamCityNightlyAuth.DownloadArtifact(url, path, token)`,
  which replaced `ConfigureClient(WebClient, token)`. The file is already linked into the
  Shim, so there is one implementation.
  - Uses `ResponseHeadersRead` and streams to disk, so the 100 s `HttpClient.Timeout` covers only
    the headers and does not cut off a large SkylineTester zip.
  - Deletes the partial file on failure, as `WebClient.DownloadFile` did.
  - Wraps `HttpRequestException`/`TaskCanceledException` in an `IOException` whose message
    includes the inner exceptions. Both callers log only `ex.Message`, and HttpClient's own
    message ("An error occurred while sending the request") says nothing about the cause.
- `CreateLabKeyClient(logFileName, timeout)` in Nightly.cs replaced `SetCSRFToken(HttpWebRequest)`.
  It returns an `HttpClient` whose handler has a `CookieContainer` and `UseDefaultCredentials`,
  and adds the X-LABKEY-CSRF header from the session cookie. On failure it throws, and the
  callers' existing retry loops catch it.
- Kept from the old requests:
  - the results post: HTTP/1.0, a 100 s timeout, and a multipart part with exactly
    `name="xml_file"; filename="..."` (no `filename*`);
  - the email post: a 30 s timeout and a bare `application/x-www-form-urlencoded`
    content type (no charset).
- Non-2xx responses still throw (`EnsureSuccessStatusCode`), so the retry loops behave as before.

### Phase 2: Core Skyline and SkylineBatch `HttpWebRequest`
- [x] `Skyline/Program.cs` GA4 hit -> `HttpClientWithProgress.SendRequest`
- [x] Universal Analytics (v=1, UA-9194399-1) hits **deleted** in both Skyline and SkylineBatch, per
      Brendan: Google stopped processing UA data in July 2023. SkylineBatch now sends no analytics.
      Its orphaned resource string was removed too. It had sent the hit synchronously on the UI
      thread at startup, so it could delay startup by up to 100 s on a slow network.
- [x] `ReportErrorDlg.cs` -> `HttpClientWithProgress` with a `CookieContainer` for the CSRF token
- [x] Test the report post against skyline.ms

Done 2026-09-24. Skyline build, CodeInspection, `SendGa4AnalyticsHitTest` (live, debug endpoint),
QuickInspection, SkylineBatch build and inspection all clean.

- ReportErrorDlg keeps the same form: the same five fields and the same file-part names,
  including the long-standing `formFiles[00` with no closing bracket, which the server has
  always received.
  - Parts are built with `ByteArrayContent` and a hand-quoted Content-Disposition, so no
    `filename*` parameter or text/plain charset is added.
  - It is still synchronous and silent on the UI thread, as before. Adding a progress dialog
    would be a UX change, out of scope here.
- Live check: a temporary test method called `HttpUploadFiles` directly and posted exception
  **#75637** ("TEST - please delete - ...") with a `test-attachment.txt` attachment. Both the
  post and the attachment arrived. The test was reverted, not committed.
  **#75637 needs deleting on skyline.ms.**

### Phase 3: Test and developer tools
- [ ] Migrate the simple ones from section 3; note the rest as allowed exceptions

### Phase 4: pwiz-sharp (after the port merges, or on the port branch)
- [ ] Make the decision in section 4 and apply it

### Phase 5: Inspection
- [ ] Add a `CodeInspectionTest` rule against `WebRequest.Create` / `HttpWebRequest`, with a tolerance equal to the Ardia count
- [ ] Consider a bare `new HttpClient` rule for product code, exempting Ardia and the test and dev tools
- [ ] When the WebClient tolerance reaches 0, or everything is on net10 and SYSLIB0014 covers it, delete that rule (see the prohibition TODO)

### Separate: Connected tests organization
Carried over from the previous version of this TODO. It is related to this work but
can be its own branch.
- [ ] TeamCity "TestConnected" runs without `AllowInternetAccess`, so `TestFastaImportWeb` exits early without testing anything
- [ ] Find tests outside `TestConnected` that need the network (e.g. `ProteomeDbTest`) and move them

## Related
- `completed/TODO-20260824_webclient_prohibition.md` - Phase 2, the inspection rule, deferred review findings
- `completed/2025/11/TODO-20251107_httpclient_to_progress.md` - previous part of this work
- `completed/2025/10/TODO-20251010_webclient_replacement.md`, `TODO-20251019_skyp_webclient_replacement.md`,
  `TODO-20251023_panorama_webclient_replacement.md` - Phase 1
- `TODO-remove_async_and_await.md` - its `ArdiaLoginDlg` item is subject to the same Ardia freeze
- `HttpClientWithProgress.cs`, `HttpClientTestHelper.cs`
