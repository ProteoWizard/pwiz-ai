# TODO-http_failure_simulator_fidelity.md

Make `HttpClientWithProgress` failure classification match what .NET 10 actually throws, and make
`HttpClientTestHelper`'s simulations throw those same shapes, so the tests stop passing on code
users never reach.

- **Module**: `skyline`
- **Found by**: `/code-review max` on #4763 (findings #5 and #6). Same root cause as the DNS bug
  fixed there: the simulator produced an exception .NET 10 never throws, so tests passed while
  users saw something else.
- **Base**: `Skyline/work/20260612_net8_port`, after #4763 merges (it reshapes the same helper)
- **Context**: `completed/` or `active/TODO-20261002_batch_tools_net10_fixes.md`

## 1. HTTP status responses reach users as raw .NET text (#6)

In production every non-2xx response leaves `HttpClientWithProgress` as the
`NetworkRequestException` built by `CreateResponseFailedException`, with the raw
"Response status code does not indicate success: 404 (Not Found) for <url>" text, and
`MapHttpException` passes it straight through. The friendly 404/401/403/500/429 messages in
`MapHttpRequestException` (and its status-code regex and inner-exception loop) only run for the
message-only exceptions injected by `SimulateHttp404/401/403/500/429/HttpError`.

- Reviewer's probe: a local server answering 404 gives the raw text from real `DownloadString`,
  while `TestHttp404Handling` and the 401/403/500/429/503 and upload variants assert the
  friendly text and pass only because of the simulator.
- Callers that branch on `StatusCode` are unaffected; the user-facing text and test fidelity
  are not.
- Fix: map real status failures to the friendly messages (at `CreateResponseFailedException`
  or in `MapHttpException`), and change the `SimulateHttp*` helpers to produce what production
  produces.

## 2. Mid-download connection loss is never classified ConnectionLost (#5)

The `ConnectionLost` branch of `MapHttpException` keys on IOException HResults
0x8007006D/6E/50/6F (Win32 ERROR_BROKEN_PIPE/OPEN_FAILED/FILE_EXISTS/BUFFER_OVERFLOW). The
.NET 10 HTTP stack never produces those.

- Reviewer measured on .NET 10.0.12 with a loopback server: a FIN mid-body gives
  `HttpIOException(ResponseEnded)`, and an RST gives `IOException` with inner
  `SocketException(ConnectionReset)`. Both have HResult 0x80131620 and are rethrown raw.
- Effects: users see unlocalized runtime text; `catch (NetworkRequestException)` handlers such as
  `WebPanoramaClient.ValidateUri` miss these failures; `WebEnabledFastaImporter`'s UniProt
  batch-splitting branch (ConnectionLost -> url_too_long, ~line 1777) can never fire, so
  oversized batches retry at the same size.
- `TestConnectionLossHandling`, `TestUploadFileConnectionLoss`, `StartPageTest` and
  `ToolStoreDlgTest` pass only because `SimulateConnectionLoss` forces HResult 0x8007006D.
- Fix: classify `HttpIOException` (ResponseEnded and similar) and inner
  `SocketException(ConnectionReset/ConnectionAborted)` as ConnectionLost; make
  `SimulateConnectionLoss` throw those shapes.

## Verification approach (what worked on #4763)

- Measure the real shape first with pwsh (it runs on .NET 10), against a real or loopback
  endpoint, before changing classifier or simulator.
- After changing the simulator, temporarily restore the old classifier and confirm the
  simulated tests fail with the user-visible symptom; then restore.
