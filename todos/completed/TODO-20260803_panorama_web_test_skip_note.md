# TODO-20260803_panorama_web_test_skip_note.md

## Branch Information
- **Branch**: `Skyline/work/20260803_panorama_web_test_skip_note`
- **Base**: `master`
- **Created**: 2026-08-03
- **Status**: Completed
- **Module**: `skyline`
- **GitHub Issue**: [#4519](https://github.com/ProteoWizard/pwiz/issues/4519)
- **PR**: [#4524](https://github.com/ProteoWizard/pwiz/pull/4524) (merged 2026-08-11)

## Motivation

`TestPanoramaDownloadFileWeb` reports PASSED on every CI run while executing
nothing. Its body is guarded by `if (AllowInternetAccess || IsRecordMode)` with
no `else`, and `AllowInternetAccess` is
`TestContext.GetBoolValue("AccessInternet", false)` - false unless explicitly
enabled. Nothing in the automated path enables it: only SkylineTester's
Access Internet menu option sets `internet=on` (SkylineTester/Main.cs:274, 284),
and neither SkylineNightly nor the TeamCity configurations pass it.

Confirmed in bt210 build #5134, where the test completed in 0 sec while its
sibling `TestPanoramaDownloadFile` took 7 sec on recorded playback.

This matters because `TestPanoramaDownloadFileWeb` is the only variant that
exercises live behaviour, and the class header warns:

```
/// THIS TEST DEPENDS ON THE PANORAMA FOLDER: ForPanoramaClientTest
/// IF TEST IS FAILING, CHECK THAT THE FOLDER HAS NOT BEEN DELETED
```

The folder could be deleted from panoramaweb.org, the `skyline_tester`
credential rotated, or live UI ordering diverge from the recording, and both
TestMethods would stay green indefinitely.

## Scope

Add an `else` branch emitting the house skip note, matching the nine existing
sites in `TestConnected` (Ardia tests) and `EncyclopeDiaSearchTest`:

```csharp
Console.Error.WriteLine("NOTE: skipping TestPanoramaDownloadFileWeb because internet access is disabled");
```

`Assert.Inconclusive` was considered and rejected: there is no handling of
`Inconclusive` anywhere in `TestRunnerLib` or `TestRunner`, so
`AssertInconclusiveException` would be reported as a test failure and turn CI
red.

## Known limitation

The note goes to stderr. It appears on the console and in TeamCity as
`[Test Error Output]` at warning level - the same treatment the Ardia notes get -
but not in TestRunner's own `log=` file, which records only the structured
per-test summary line. The test also still reports PASSED.

Making the results summary itself honest requires excluding the test from the
TeamCity configuration, which is a separate decision. Unlike the
`skip=TestConnected.dll` experiment on bt210, it would cost nothing: this test
short-circuits in 0 sec and contributes zero coverage. The note is worth having
either way, since a TeamCity-only decision is what made the earlier
`skip=TestConnected.dll` entry impossible to interpret later.

## Verification

- `TestPanoramaDownloadFileWeb` - passes, note emitted, 0.8s
- CodeInspection
- ReSharper full-solution inspection

## Progress Log

### 2026-08-11 - Merged

PR #4524 merged as commit e39f346, closing issue #4519. What shipped is the
minimal change from Scope: a 4-line `else` in `PanoramaClientDownloadTest.cs`
emitting the house stderr skip note when `AllowInternetAccess` is false, so the
skip is visible in the console and TeamCity build log instead of the test
silently reporting PASSED in 0 sec. The squash subject landed without the
`skyline: ` module prefix.

Deferred, per Known limitation: the test still reports PASSED and the note does
not appear in TestRunner's `log=` file. Making the results summary itself honest
means excluding the test from the TeamCity configuration - a separate decision,
not filed as an issue.
