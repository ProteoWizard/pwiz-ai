# Replace the waters_connect HttpClient wrappers with HttpClientWithProgress

## Branch Information
- **Branch**: `Skyline/work/20260825_watersConnectHttpClientWithProgress` (pwiz2)
- **Base**: `master`
- **Created**: 2026-08-25
- **Status**: In Progress
- **GitHub Issue**: [#4609](https://github.com/ProteoWizard/pwiz/issues/4609)
- **Module**: `skyline`
- **Other labels**: `tech-debt`
- **PR**: [#4613](https://github.com/ProteoWizard/pwiz/pull/4613)

## Objective

Port waters_connect HTTP access from its own HttpClient wrappers (IHttpClientFactory +
the handler-level HttpMessageHandlerFactory mock seam) onto the project-standard
HttpClientWithProgress, which mocks at the request level (IHttpClientTestBehavior is
consulted inside the send path on every request). This removes the pooled-handler
conditions behind the #4603 nightly failure rather than working around them, and
deletes the now-redundant mock seam.

## Tasks

- [x] Port WatersConnectSession / WatersConnectSessionAcquisitionMethod request paths
      (GetAsync/SendAsync on `_httpClient`) to HttpClientWithProgress
      (DownloadStringChecked / UploadString / SendRequest + MapToRemoteServerException)
- [x] Port WatersConnectAccount authentication: TokenClient replaced with a direct
      form POST via HttpClientWithProgress (Basic client auth, same wire format);
      IdentityModel's TokenResponse kept as the parsed shape so
      HandleAuthenticationException is unchanged
- [x] Extend HttpClientWithProgress.SendRequest to consult the request-level test
      seam (GetMockResponseStreamFromRequest) so every verb is mockable - previously
      only the GET/download path was
- [x] Rewrite WatersConnectMethodExportTest mocking onto HttpClientTestBehavior with
      a single request-routing factory; VerifyHandlerReplacement became
      VerifyBehaviorReplacement (mid-process behavior swap must take effect);
      TestBehavior cleared in finally so it cannot leak to later tests
- [x] Delete HttpMessageHandlerFactory.cs, MockHttpMessageHandler.cs (waters test was
      the only consumer), CommonApplicationSettings.HttpMessageHandlerFactory,
      Program.HttpMessageHandlerFactory + csproj entries
- [x] Build green + TestWatersConnectExportMethodDlg en,fr green in one process
- [x] Neighbor tests of the SendRequest change green: TestHttpClientWithProgressIntegration,
      TestSkyp, TestPublishToPanorama
- [x] /code-review max: 10 findings, ALL verified real and applied (see log)
- [x] Re-verified after review fixes: build green; waters test en,fr green; battery
      green (TestHttpClientWithProgressIntegration, TestSkyp, TestRInstaller,
      TestPublishToPanorama, TestJsonToolServer); QuickInspection 0/0;
      CodeInspection test green. Single commit `c6805d9c7b` (amended). Pushed;
      PR #4613 open. Pending: TeamCity green, Copilot/human review.
      (Note: one TestPublishToPanorama run on PRE-fix binaries hit a flaky
      "Objects not garbage collected" failure; 3/3 reruns + post-fix run green.)

### 2026-08-25 - /code-review max findings (all applied)

1. Basic-auth credentials now RFC 6749-escaped (EscapeClientCredential) - raw
   base64 changed the wire format for secrets with reserved characters vs the
   IdentityModel TokenClient (verified in its IL by the review).
2. RequestToken maps non-400 HTTP failures to TokenResponse(status, reason,
   body) so IsError is true even for non-OAuth bodies (was: parsed body ->
   could cache a null token); 400+body keeps the parsed protocol shape; added
   Accept: application/json.
3. Restored timeouts: RequestTimeout was decorative - now enforced in
   SendRequest via linked CTS; waters clients and token requests set 100s
   (old HttpClient default). Downloads keep per-chunk stall detection.
4. Restored TokenClient's catch-everything contract in RequestToken (blanket
   catch -> exception-type TokenResponse; Uri construction moved inside try)
   and CreateFolder's broad catch (wait dialog must not throw).
5. HttpClientWithProgress.Dispose now sets a disposed flag; CreateRequest/
   SendRequest throw ObjectDisposedException - prevents a fetch racing past
   session Dispose from sending an UNAUTHENTICATED request to a live server
   (Dispose clears the auth header).
6. SendRequest consults the mock seam OUTSIDE the exception mapping (factory
   exceptions reach callers unmapped; on VMs with only virtual adapters they
   were being rewritten to "No network connection"); HttpClientTestBehavior's
   URI/blanket fallback now answers GET only (was silently stubbing
   RInstallerTest's HEAD connectivity probe).
7. VerifyBehaviorReplacement made non-vacuous: replacement behavior closes
   over its own methods listing (was: same delegate + same field = no-op swap).
8. Test uses HttpClientTestHelper scopes (saves/restores enclosing behavior)
   instead of direct TestBehavior assignment + restore-to-null.
9. Dropped CreateAuthenticatedClient's dead (monitor, status) params.
   Follow-up noted: a standard progress-upload-with-response API would let
   UploadMethod drop its hand-built request too.
10. Removed dead Microsoft.Extensions.Http PackageReference (CommonMsData).

## Regression Test

- **Test name**: TestWatersConnectExportMethodDlg (existing; mock seam rewritten)
- **Test project**: TestFunctional
- **Fails on master**: n/a - refactor to the standard client; the multi-run-in-one-process
  scenario (en,fr single process) is the guard that the port does not reintroduce the
  #4603 stale-mock class
- **Passes on fix**: (pending)

## Progress Log

### 2026-08-25 - Session Start

Starting work on #4609 following PR #4603 (merged), whose /code-review max flagged the
dual mock-injection paths and process-lifetime handler registry this port eliminates.
Prior findings recorded in TODO-20260625_watersConnectNewFolder.md apply here:
- Authenticate() consults the static _authenticationTokens cache before any handler
  lookup; a replaced auth behavior can be masked. Consider addressing while porting.
- The production CreateClient path was never exercised by offline tests; after the
  port there is a single client path, which resolves that finding structurally.
