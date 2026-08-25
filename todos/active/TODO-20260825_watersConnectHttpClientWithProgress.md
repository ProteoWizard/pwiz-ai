# Replace the waters_connect HttpClient wrappers with HttpClientWithProgress

## Branch Information
- **Branch**: `Skyline/work/20260825_watersConnectHttpClientWithProgress` (pwiz2)
- **Base**: `master`
- **Created**: 2026-08-25
- **Status**: In Progress
- **GitHub Issue**: [#4609](https://github.com/ProteoWizard/pwiz/issues/4609)
- **Module**: `skyline`
- **Other labels**: `tech-debt`
- **PR**: (pending)

## Objective

Port waters_connect HTTP access from its own HttpClient wrappers (IHttpClientFactory +
the handler-level HttpMessageHandlerFactory mock seam) onto the project-standard
HttpClientWithProgress, which mocks at the request level (IHttpClientTestBehavior is
consulted inside the send path on every request). This removes the pooled-handler
conditions behind the #4603 nightly failure rather than working around them, and
deletes the now-redundant mock seam.

## Tasks

- [ ] Port WatersConnectSession / WatersConnectSessionAcquisitionMethod request paths
      (GetAsync/SendAsync on `_httpClient`) to HttpClientWithProgress
- [ ] Port WatersConnectAccount authentication (TokenClient built on the AUTH handler)
      to the standard path; decide TokenClient's fate (it takes an HttpMessageHandler)
- [ ] Rewrite WatersConnectMethodExportTest mocking from MockHttpMessageHandler to
      IHttpClientTestBehavior; adapt or retire VerifyHandlerReplacement (the pooled
      pipeline it guards no longer exists)
- [ ] Delete pwiz_tools/Shared/CommonUtil/Mock/HttpMessageHandlerFactory.cs,
      CommonApplicationSettings.HttpMessageHandlerFactory and its Program.cs wiring,
      and the GetRegisteredHandler check in GetAuthenticatedHttpClient
- [ ] Verify no other consumers of the deleted seam remain (MockHttpMessageHandler
      in TestUtil may stay if others use it; check)
- [ ] Build green + TestWatersConnectExportMethodDlg en,fr green in one process
- [ ] QuickInspection + CodeInspection test before push

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
