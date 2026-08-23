# Finding and clearing intermittent test failures

How to stop needing an all-night full-suite run to discover what a targeted soak can find
in minutes, and how to say "this test is solid" and mean something by it.

Written 2026-08-22 from three real failures traced end to end that night. Every claim below
is grounded in one of them. Where a rule exists because a method FAILED, that is called out,
because those are the expensive lessons.

## 1. The measurement discipline

**Rates, in executions, never in runs.** A test that fails 2% of the time shows up once in
~50 executions. Counted in whole-suite runs that reads as "once in six nights", which sounds
hopeless and unreproducible. Counted in executions it is trivially soakable. The denominator
decides whether a flake looks tractable, and flakes have been discarded as undiagnosable
purely because nobody wrote one down.

**Denominators or it did not happen.** "It passed" is not a result. "0 failures in 100
executions, 20 per language, 8 workers, git sha X" is a result.

**Beware cumulative counters.** In the test log the `N failures,` field on a test line is
that worker's RUNNING TOTAL, not that execution's outcome. Counting lines with a non-zero
value overstates failures badly - it reads 344 failures where there was 1. Count
`!!! <TestName> FAILED` markers instead.

## 2. Fix the message before you fix the bug

**If the failure message cannot say what happened, improving it is the first fix, not a
detour.** This is the highest-return rule in this document.

Two of the three failures were diagnosed by the FIRST occurrence after the message was
improved, having survived an entire 48,272-execution overnight run undiagnosed:

* `TestWatersConnectExportMethodDlg` said only "Template selection dialog is not populated
  within allotted time." Adding the actual count and the item names turned the next failure
  into `Expected 11 items, found 13: NewTestFolder, RefreshedFolder, ...`. Those two names
  are folders the test creates later in its own run, which identified the cause on sight.
* `PeakAreaDotpGraphTest` asserted with no message at all: `Expected:<0.93>. Actual:<0.99>.`
  Adding the replicate, pane, unrounded value and the point/label counts turned it into a
  failure that rules things out on sight: 7 points against 7 labels means it is not an index
  misalignment, so the graph was showing a different precursor.

A mute assertion is itself the bug to fix first. It is the cheapest possible fix, it is
permanent, and it pays off on a failure nobody was watching.

## 3. Three classes of flake, and why one instrument cannot find them all

This is the part that is easy to get wrong, and the reason a soak can return a beautiful
number that means nothing.

### Class 1 - state leaking between executions in one process

Not a race at all. **Deterministic**: the first execution in a process passes and every
later one fails. It looks intermittent only because a suite run spreads executions across
worker processes, so the observed rate is just the share that were not first.

Example: `TestWatersConnectExportMethodDlg`, 45% overnight. `WatersConnectAccount`'s static
constructor resolves its mock HTTP handler once and `IHttpClientFactory` pools it, so
replacing the registration did nothing: every later test in that process was served the
FIRST test's mock, carrying the state it had accumulated.

* **Instrument**: run the same test repeatedly **in one process** (`loop=N`). Two passes is
  enough. No parallelism needed.
* **Cost**: trivial, and certain rather than probabilistic.
* **Blind spot of everything else**: a single execution can never see it.

### Class 2 - contention with something outside the test

Needs a neighbour: another process holding a file, a port, a directory.

Example: `TestDdaSearchDependencyErrors`, 60% overnight. Crux extraction cannot overwrite
`msvcp140.dll` because a live process has it loaded.

* **Instrument**: must reproduce the neighbour.
* **The trap**: a single-test soak is structurally blind here. Soaking that test alone
  returned **0 failures in 100 executions** - not because it was fixed, but because
  TestRunner's parallel queue reserves tools directories
  (`QueuedTestInfo.RequiredToolsDirectories`), so the contention being hunted *cannot occur*
  in that configuration.
* **Consequence**: a clean soak number is worth only as much as the instrument's ability to
  produce the failure. Record the configuration or the number is a lie by omission.

### Class 3 - a genuine timing or ordering race

The classic flake: a wait that returns before the thing waited for has happened.

Example: `PeakAreaDotpGraphTest`, ~1 in 460. The test selects a precursor then calls
`WaitForGraphs()`, which waits for `!IsGraphUpdatePending` - but "idle right now" does not
mean the selection-driven update has been SCHEDULED yet, so the assertion can read the
previous selection's graph.

* **Instrument**: high-N soak, all languages, production parallel width.
* **Cost**: high. At a 0.2% rate you need ~1,500 executions to expect three failures. This
  is the class that genuinely needs the big soak.

**The rule that falls out of this:** a test is not cleared until it has been exercised by an
instrument capable of detecting each class. Clearing against class 3 only - which is what a
naive soak does - says nothing about classes 1 and 2.

## 4. Clearance, and what the number is worth

**Rule of three**: zero failures in N executions gives 95% confidence the true failure rate
is below `3/N`.

| executions, 0 failures | clears a rate above |
|---|---|
| 300 | 1% |
| 1,000 | 0.3% |
| 3,000 | 0.1% |

For scale, the 2026-08-21 overnight aggregate was 46 failures in 48,272 executions - about
0.095%, or 1 in 1,050.

A clearance record must carry the configuration, not just the count, because section 3 shows
the configuration decides what could have been found:

| field | why it is recorded |
|---|---|
| test name | |
| date, git sha | a clearance expires when the test or the code under it changes |
| executions, languages | the denominator |
| parallel width | |
| **harness and mode** | `parallelmode=server` cannot produce tools-directory contention |
| **passes per process** | one pass cannot detect a class-1 state leak |
| classes covered | which of 1/2/3 this run could actually have caught |

Re-clear when the test changes, when code under it changes, or when the harness changes.

## 5. A sweep order that spends effort where it pays

Cheapest and most certain first. Do not walk the suite alphabetically.

**Step 1 - the whole-suite class-1 sweep. Do this first; it is the bargain of the whole
programme.** Run the entire suite with `loop=2` in one language. Every class-1 state leak in
the codebase becomes a deterministic failure, and this class is otherwise invisible. Cost is
about two single-language suite runs. This one sweep would have caught the Waters failure
outright - no soak, no statistics, no overnight run.

**Step 2 - seed priorities from history already collected.**
`mcp__labkey__query_test_history` holds years of nightly results. Tests with historical
intermittent failures are the population worth soaking. Tests never observed failing anywhere
are the lowest priority and can be cleared in bulk later.

**Step 3 - static risk ranking for the unmeasured remainder**, cheapest signal first:

* explicit short timeouts (`WaitForConditionUI(1000, ...)`) - a hard-coded budget far below
  the 3-minute default is deliberate impatience and a class-3 candidate
* `WaitForGraphs` or `WaitForConditionUI` immediately after a selection or document change -
  the exact class-3 shape from section 3
* static or `[ThreadStatic]` mutable state, static constructors, cached clients or sessions -
  class-1 shapes
* anything launching an external process, or extracting into a shared directory - class 2

**Step 4 - soak the ranked candidates** across all 5 languages at production width, to the
clearance bar, and record each result with its configuration.

**Step 5 - fix, then re-measure the same way.** A single passing run proves nothing at a 60%
rate, let alone at 2%.

## 6. Things that will waste a night

* **Do not trust a soak whose harness removes the failure mode.** Ask first: in this
  configuration, could the failure being hunted even happen?
* **Do not theorise past the first informative failure.** Both root causes fell out
  immediately once the message carried its data. The reading and reasoning that preceded
  that produced several confident wrong answers.
* **Do not assert runtime behaviour from reading code.** The Waters cause was settled by
  logging an object identity hash and seeing a stale one, after code reading had produced
  three plausible and wrong explanations.
* **Search for the concept, not the API.** A duplicate Restart Manager wrapper got written
  because the search was for `RmGetList` and `RestartManager`;
  `FileLockingProcessFinder.GetProcessesUsingFile` had existed all along, in the same
  assembly, used by three callers.
* **Check for leftovers before believing a hang.** A staging step sitting silently for hours
  is usually a previous run's worker still holding the mounted checkout open.
