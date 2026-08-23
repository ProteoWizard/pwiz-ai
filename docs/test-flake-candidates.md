# Flake candidates from static code shape

A ranked starting population for the sweep in `ai/docs/test-flakiness-method.md`, derived
from code shape alone - no test runs. This is step 3 of the sweep order: what to soak after
the history-seeded priorities, and what to confirm with the cheap class-1 instrument.

Generated 2026-08-23 over `pwiz_tools/Skyline/TestFunctional/`. Line numbers are from that
date; re-derive if they have drifted.

**How to use this**: class 1 first. Those are confirmable in minutes and deterministically,
with `Run-Tests.ps1 -TestName <name> -Loop 3 -Summary` (serial). A real class-1 leak fails
from the SECOND execution onward, every time - not intermittently. Class 3 needs a soak;
class 2 needs the neighbour reproduced.

## Class 1 - state that can leak between executions in one process

The cheapest and most certain class. Confirm each with `-Loop 3` serial.

| test file | evidence | shape |
|---|---|---|
| AssayLibraryImportTest.cs | `:74-75` `private static bool _asSmallMolecules; _smallMolDemo;` set in `Preamble()` `:69` | static mutable, no reset on exception path |
| AuditLogTest.cs | `:573` `private static int _expectedAuditLogEntryCount;` incremented `:620`, raced at `:621` | static counter shared across instances, plus an unbounded wait on it |
| ChromGraphTransformTest.cs | `:52,134,164` writes `Settings.Default.TransformTypeChromatogram` / `SplitChromatogramGraph`, no `Cleanup()` override | global setting never restored |
| ReporterIonTest.cs | `:72,126` writes `Settings.Default.MeasuredIonList`, no `Cleanup()` | global list never restored |
| EncyclopeDiaSearchTest.cs | `:62-63` writes `Settings.Default.KoinaIntensityModel` / `KoinaRetentionTimeModel`, no `Cleanup()` | leaks into later Koina-dependent tests |
| KoinaSkylineIntegrationTest.cs | `:82-533`, 10+ writes to `Settings.Default.ShowBIons/ShowYIons/Koina/KoinaNCE/LibMatchMirror` | many globals, no restore found |
| AreaCVHistogramTest.cs | `:46-48` mutable static ints (not const/readonly) | lower risk, appear write-once |

`[ThreadStatic]` in TestFunctional: **none** (searched; explicit null result).

## Class 2 - contention with something outside the test

| test file | evidence |
|---|---|
| DdaSearchTest.cs | `:288-303` `CleanupDownloadedFiles(...)` deletes the SHARED `SimpleFileDownloader.GetCachedDownloadsDirectory()` and tool `InstallPath`; called from `:135,157,180,211,233,260,319` |
| SkylineCmdTest.cs | `:52,57,65,78` spawns external `SkylineCmd.exe` |
| SkylineMcpTest.cs | `:205,221` spawns an external MCP server process |
| WatersConnectMethodExportTest.cs | `:120,178,209,...` drives a remote server; `:337` clears the static `WatersConnectAccount._authenticationTokens` |

`DdaSearchTest` is where `TestDdaSearchDependencyErrors` lives - the 60% overnight failure -
and this row is why: it is the only test that forces a real re-extraction every run.

## Class 3 - shortest explicit timeouts

The default wait is 3 minutes, so these are deliberate impatience. Shortest first.

| timeout | site |
|---|---|
| 100 ms | UpgradeTest.cs:132 `TryWaitForCondition(100, ...)` |
| 200 ms | UpgradeTest.cs:115, :159 `TryWaitForOpenForm<UpgradeDlg>(200)` |
| 800 ms | UpgradeTest.cs:112 `TryWaitForOpenForm<LongWaitDlg>(800)` |
| 1000 ms | AssociateProteinsDlgTest.cs:889 |
| 1000 ms | WatersConnectMethodExportTest.cs:121,128,179,187 and `:72` WaitForOpenForm |
| 2000 ms | DdaSearchTest.cs:1208,1232,1239,1241 |
| 2000 ms | DiaSearchTest.cs:475,487 |
| 2000 ms | PasteMoleculesTest.cs:1789,1838 |
| 2000 ms | LibraryExplorerSpeedTest.cs:70 |
| 3000-5000 ms | AssayLibraryImportTest.cs:1104; WatersConnectMethodExportTest.cs:283,328; PythonInstallerLegacyDlgTest.cs:555,561; RInstallerTest.cs:371; ImportPeptideSearchTest.cs:591,646; ManageResultsTest.cs:429 |
| 9000 ms x6 | TestPanoramaClient.cs:93,127,163,200,246,301,335 `WaitForCondition(9000, () => remoteDlg.IsLoaded)` |

`UpgradeTest` is the standout: a 100 ms window for a condition and 200 ms for a dialog to
appear are far below anything else in the suite.

### Selection-then-graph-wait-then-assert (the PeakAreaDotpGraphTest shape)

`WaitForGraphs()` immediately after a selection change and immediately before an assertion is
the exact shape that made `PeakAreaDotpGraphTest` flake, because `IsGraphUpdatePending` can go
false without the pane having updated. Files carrying it:

AlignedIdTimesTest, AreaCVHistogramTest, CalibrationTest, ChromGraphTransformTest,
CrosslinkingTest - with ChromGraphTransformTest repeating it six times
(`:83,133,161,183` selection then `:86,118,136,154,166,185` wait then asserts).

These should wait on the pane reflecting the selection, as
`TestPeakAreaDotpGraph.WaitForPaneShowingSelection` now does, rather than on graph idleness.

## Counts

* class 1: 7 files
* class 2: 4 files
* class 3: 19 files with timeouts <= 5000 ms, plus 5 with the graph-selection shape
