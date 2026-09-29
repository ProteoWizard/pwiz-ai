# Testing Guidelines - Quick Reference

Essential testing patterns and rules. See [ai/docs/testing-patterns.md](docs/testing-patterns.md) for comprehensive details.

## Test Project Selection

| Project | Purpose | Base Class | When to Use |
|---------|---------|-----------|-------------|
| **Test.csproj** | Unit tests | `AbstractUnitTest` | Fast tests, no UI, no data files |
| **TestData.csproj** | Unit tests with data | `AbstractUnitTestEx` | Tests needing mass spec data files |
| **TestFunctional.csproj** | UI tests | `AbstractFunctionalTestEx` | **Most common** - UI workflows |
| **TestConnected.csproj** | Network tests | varies | Tests requiring real network access |
| **TestTutorial.csproj** | Tutorial automation | `AbstractFunctionalTestEx` | Automated tutorial validation |
| **TestPerf.csproj** | Performance tests | `AbstractFunctionalTestEx` | Large datasets (>100MB) |

## Critical Testing Rules

See [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) for the full list. Key rules:

### Build Before Testing
- **ALWAYS** build after edits and before running tests – the test harness executes the last compiled binaries, not your unbuilt source.

### Translation-Proof Testing
- **NEVER** use English text literals in test assertions
- **ALWAYS** use resource strings from production code
- **ALWAYS** prefer `AssertEx` over `Assert` — better diagnostics and consistency
- **ALWAYS** use `AssertEx.Contains()` instead of `Assert.IsTrue(string.Contains())`
- **ALWAYS** use `HttpClientTestHelper.GetExpectedMessage()` for network errors

### Test Structure
- **NEVER** create multiple `[TestMethod]` for related validations (causes overhead)
- **ALWAYS** consolidate validations into single test with private helper methods
- Use `RunFunctionalTest()` pattern with `DoTest()` override
- Place helper methods after the tests that use them

### Test Performance
- Functional tests have significant overhead (create/destroy SkylineWindow)
- Consolidating 4 separate tests into 1 can save 15+ seconds
- Prefer unit tests when UI is not required

## Diagnostic Sweeps - Tools, Not Tests

Some questions need the real UI driven over a matrix of states - window sizes, zoom levels, settings
combinations - to produce a table a developer reads. That is a **diagnostic tool**, not a regression test,
and it lives in a test project only because `AbstractFunctionalTestEx` is the way to drive Skyline. It
asserts nothing about the numbers it reports.

Decide which one you are writing. A tool that asserts its own output becomes a test that fails whenever
the product legitimately changes; a test that asserts nothing is dead weight in the nightly run. When the
developer has said the behavior is not worth pinning - too heavy, too UI-dependent, no single right answer -
write the tool and say so in its class comment.

Rules for a diagnostic tool in a test project:

* **Off by default, gated on an environment variable.** `if (string.IsNullOrEmpty(
  Environment.GetEnvironmentVariable(ENV_ENABLED))) return;` as the first line, so the nightly run pays
  only the cost of entering and leaving the method. Verify that cost - a disabled sweep should return in
  seconds, not load a document.
* **`[NoNightlyTesting]` and `[NoParallelTesting]`**, with the matching `TestExclusionReason`.
* **Take its inputs from environment variables too** - the document and the output path - so it can be
  pointed at a repro without editing code.
* **Write a CSV a developer can open**, and trace one line per combination as it goes, so a run that dies
  partway still leaves the rows before it readable.
* **Assert only the invariants that must hold regardless of the numbers.** Reporting coverage while
  checking "no two visible labels overlap" is the right split: the matrix informs, the invariant catches
  regressions.

### Bound every wait

A sweep visits combinations that legitimately produce nothing. `WaitForConditionUI` fails the test after
`WAIT_TIME` (360 s), so a legitimate empty cell becomes a six-minute hang and then a failure. Use
`TryWaitForConditionUI(millis, func)`, which returns false instead, record the empty result as a row, and
print why it was empty. A blank cell with no explanation is worse than no sweep.

### Wait for THIS run, not for any result

Work that runs on a worker thread and installs its result on the UI thread needs a wait keyed to the
current run, not to "a result exists". Waiting for a non-empty result returns the **previous** run's while
the current one is mid-flight, and mid-flight state is often invalid by design - partially placed, not yet
pruned, not yet filtered. Key the wait on something that identifies this run: a new result instance, a
sequence number, a completion flag cleared before the trigger. Then confirm it settles, so a later run
does not supersede the one measured.

### Offscreen where possible

A sweep that demands `-ShowUI` takes over the developer's machine for its whole run. Offscreen mode only
repositions the main window, so almost everything works there. The trap is `ResizeFormOnScreen`, which
returns **before resizing** when `Program.SkylineOffscreen` is set, because the `FormEx.ForceOnScreen` it
calls afterwards would drag a deliberately offscreen window back onto the desktop. If window size is one of
your axes, set the frame size yourself and skip only `ForceOnScreen` - do not change
`ResizeFormOnScreen`, whose early return is deliberate for screenshot tests.

Then **prove the axis did something**: a resize that silently fails reports N identical rows as though they
were N measurements. Check that the measured geometry actually varied and warn if it did not.

### Product hooks for diagnostics go behind `#if DEBUG`

When a tool needs a number the product does not expose - an intermediate stage's count, a decision that
later code discards - a hook is legitimate, but it must not reach the shipped executable. Wrap the hook and
its call site in `#if DEBUG` (`LabelLayout.SamplerReport` and its annealing CSV log are the examples), and
have the tool report that it needs a Debug build when the hook is compiled out. Keep both configurations
building warning-free: an `#if` that leaves unreachable code or an unassigned field trades a runtime cost
for a warning.

Prefer exposing the value on an existing object over a static hook. Reach for the static only when the
value is unavailable otherwise - typically when the interesting case is the one where the object is never
produced.

## Common Patterns

### Functional Test Structure
```csharp
[TestMethod]
public void MyFeatureTest()
{
    RunFunctionalTest();
}

protected override void DoTest()
{
    TestStep1();
    TestStep2();
    TestStep3();
}

private void TestStep1() { /* validation */ }
private void TestStep2() { /* validation */ }
```

### Translation-Proof Assertions
```csharp
// ✅ GOOD - Works in all locales
AssertEx.Contains(errorMessage, Resources.ErrorMessage_FileNotFound);

// ❌ BAD - Breaks in Chinese/Japanese
Assert.IsTrue(errorMessage.Contains("File not found"));
```

### Network Error Testing
```csharp
// ✅ GOOD - HttpClientTestHelper provides expected message
using (var helper = HttpClientTestHelper.SimulateHttp404())
{
    var errDlg = ShowDialog<AlertDlg>(() => operation());
    var expectedError = helper.GetExpectedMessage(uri);
    AssertEx.Contains(errDlg.Message, expectedError);
}

// ❌ BAD - Hardcoded English
Assert.IsTrue(errDlg.Message.Contains("HTTP 404"));
```

## Base Classes

### AbstractFunctionalTestEx (Prefer This)
High-level workflow helpers for common operations:
- `ImportResultsFile()` - Import with all dialogs
- `ExportReport()` - Export with configuration
- `ShareDocument()` - Share to Panorama
- `ImportPeptideSearch()` - Import with wizard
- Many more...

### AbstractFunctionalTest (Low-Level)
Only use when you need fine-grained control:
- `RunUI()` - Execute on UI thread
- `ShowDialog<T>()` - Show modal dialog
- `WaitForCondition()` - Poll for conditions
- Basic primitives only

## Dependency Injection for Testing

### Pattern 1: Constructor Injection
Use when tests construct the object directly:
```csharp
public SkypSupport(SkylineWindow skyline, Func<...> clientFactory)
{
    _clientFactory = clientFactory;
}
```

### Pattern 2: Static Test Seam + IDisposable
Use for deep call stacks (3+ layers):
```csharp
public class TestToolStoreClient : IToolStoreClient, IDisposable
{
    public TestToolStoreClient()
    {
        _original = ToolStoreUtil.ToolStoreClient;
        ToolStoreUtil.ToolStoreClient = this;  // Inject
    }

    public void Dispose()
    {
        ToolStoreUtil.ToolStoreClient = _original;  // Restore
    }
}
```

**Using IDisposable:** Prefer modern `using var` syntax (C# 8.0+) for minimal diffs. See [ai/docs/testing-patterns.md](docs/testing-patterns.md#using-idisposable-modern-using-var-syntax) for details.

## AssertEx Quick Reference

Prefer `AssertEx` methods over custom wrappers:
- `AssertEx.Contains(actualString, expectedSubstring)`
- `AssertEx.FileExists(filePath)`
- `AssertEx.ThrowsException<TEx>(() => code)`
- `AssertEx.Serializable<T>(obj)`
- `AssertEx.NoDiff(expected, actual)`

See `pwiz_tools/Skyline/TestUtil/AssertEx.cs` for full API.

**Assert whole strings from public constants, not substring fragments.** A
`Contains("part of the message")` assertion breaks on any reword and, if the literal
is English, under localization. Put the message in a public constant (or resource) the
test can reference and assert the whole value - one source of truth for the production
message and the test. Reserve `AssertEx.Contains` for composed messages where only the
resource-derived part is stable.

## Localization Testing

All tests must pass in all locales:
- English (en-US)
- Chinese Simplified (zh-CHS)
- Japanese (ja-JP)
- Turkish (tr-TR)
- French (fr-FR)

Use `SkylineTester.exe` or `TestRunner.exe /locale:ja-JP` to test in different locales.

## See Also

- [ai/docs/testing-patterns.md](docs/testing-patterns.md) - Comprehensive testing guide
- [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) - All critical testing constraints
- [ai/MEMORY.md](MEMORY.md) - DRY principles in testing
- [ai/WORKFLOW.md](WORKFLOW.md) - Build and test workflows
