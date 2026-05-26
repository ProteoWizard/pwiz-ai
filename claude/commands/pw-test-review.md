---
argument-hint: <path>
description: Honest review of test coverage at the given path — what's actually exercised by tests vs. what's nominally tested, plus prioritized recommendations for where new tests would catch real regressions.
---

# Test Coverage Review

Read the code under `$ARGUMENTS` and produce an honest assessment of
how well it is tested. The question is not "are there tests?" but
"would the existing tests catch the kinds of regressions a reasonable
maintainer would worry about?" Use only static reading; this command
is the by-eye complement to running a coverage tool like dotCover,
useful when an LLM assessment is faster (or available when the
coverage tool isn't).

## Posture: be honest, even uncomfortable

Same as `/pw-oop-review`. **The default-polite assessment is the
failure mode.** Concretely:

- If a module has tests but the tests are smoke-only or mock-heavy
  enough to be inverse-coverage, say so. Lots of green dots can hide
  zero confidence.
- If a critical piece of code has no tests, name it. Don't bury the
  finding under "consider adding tests for X."
- If the code is actually well-covered, say that plainly and back it
  with specifics. Padded "here are also some places you might want to
  test" recommendations are exactly the noise the user is trying to
  filter out.

## What "well-tested" means here

Five lenses, in priority order:

1. **Public surface coverage.** Every public type / method / entry
   point in `$ARGUMENTS` should be exercised by at least one test that
   would fail if the contract changed. If a public API isn't called
   from any test, it's an untested API regardless of whether the lines
   inside it happen to execute via some indirect path.
2. **Behavior vs. shape testing.** Do tests assert on outputs and
   side effects, or just on "method ran without throwing"? Tests with
   no assertions (or only `Assert.IsNotNull`-style structural checks)
   give a false coverage signal.
3. **Edge / error path coverage.** For each non-trivial method,
   identify the genuine edge cases: empty inputs, max sizes, null /
   missing optional parameters, error conditions, race conditions if
   concurrency is in play. Untested error paths are where real bugs
   hide.
4. **Regression gates.** Beyond unit tests, are there higher-level
   gates (snapshot regression, golden-file comparison, cross-impl
   parity, integration tests) that catch behavior drift at the
   semantic level? These often catch issues unit tests miss. Note
   their presence and effectiveness, not just unit coverage.
5. **Test quality.** Are tests resistant to coincidental change
   (e.g. they don't break for cosmetic refactors) AND sensitive to
   real regressions (they DO break when the behavior changes)? A test
   that breaks on every refactor is over-coupled to implementation
   detail; a test that doesn't break on a behavior change is
   under-coupled.

## Step 1 — Inventory the code under review

Survey `$ARGUMENTS`:

- **Public surface**: enumerate the public types, methods, and entry
  points. This is the contract that ought to be tested.
- **Critical paths**: identify the methods most likely to harbor bugs
  — complex logic, parsing, concurrency, file I/O, state machines,
  protocol/format handling. These are the high-leverage targets for
  testing.
- **Low-risk code**: identify simple getters, thin wrappers, and
  glue — these don't need direct tests if their callers are tested.
  Don't pad the recommendations list with "add a test for property X."

For larger paths, you may delegate the survey to an Explore agent
rather than reading every file yourself. Summarize what you found
before going deeper.

## Step 2 — Inventory the existing tests

Find the test code that targets `$ARGUMENTS`. Typical patterns:

- A sibling `*.Test/` or `*Tests/` project
- `[TestClass]` / `[TestMethod]` attributed C# (MSTest), `Fact` /
  `Theory` (xUnit), `Test` (NUnit), `#[test]` (Rust), `def test_*`
  (pytest)
- Integration / regression test scripts under `ai/scripts/`,
  `test/`, or similar
- Snapshot / golden-file harnesses

For each test class / file:
- What production type / surface is it testing?
- How many tests, and what shape are they (unit / integration /
  regression)?
- Are the tests doing real work (file I/O, cross-impl comparison,
  numeric assertions) or are they shape-only?

## Step 3 — Map tests to surface

Build a coverage table: for each public surface item from Step 1, is
it directly tested, indirectly tested via a higher-level path, or
untested?

- **Directly tested**: a test calls this method / type and asserts on
  its output.
- **Indirectly tested**: a higher-level test (integration, regression,
  end-to-end) exercises this code path with meaningful assertions.
  Note the protecting test by name.
- **Untested**: nothing exercises this surface. Flag.

Indirect coverage is real coverage when the higher-level test would
break if the underlying code broke. Be specific about WHICH higher-
level test protects each piece, because if it goes away, so does the
coverage.

## Step 4 — Evaluate against the five lenses

For each lens, produce a finding:

- A **grade**: Strong / Adequate / Weak / Failing.
- The **evidence**: specific file:line references — both production
  code and test code citations — showing why the grade is what it is.
- Vague findings with no evidence are worse than no finding.

Also call out, separately:

- **Tests that look like coverage but aren't**: tests with no
  assertions, tests that mock the very thing they're supposed to
  validate, tests whose green dot doesn't tell you anything because
  the failure mode the test would have to catch is structurally
  impossible to reach. Name them with file:line.
- **Tests that earn their keep**: examples of well-designed tests in
  the codebase that should be the template for new ones. Naming these
  is a service to the next contributor.
- **Coverage gaps with high consequence**: untested code that, if it
  breaks, would cause silent wrong output or production crashes — not
  just untested code. Order recommendations by this signal.

## Step 5 — Present findings

Structure the response as:

### Headline assessment

One paragraph stating the overall test health of the code under review.
Pick a posture: "test coverage is strong and growing this code is
safe", or "the existing tests are smoke-heavy and a real refactor
would not be caught", or whatever the honest read is. Do not hedge
this paragraph.

### Per-lens findings

For each of the five lenses, a short section:

- **Grade**
- **Evidence** (test file:line + production file:line citations)
- **What's missing**, if anything

### Top three places to add tests

Prioritize ruthlessly. The reason this command exists is that "here
are 12 places you might want to add a test" is noise. Pick the three
gaps where new tests would meaningfully reduce risk, in priority
order. For each:

- **What to test**: the specific method / behavior / contract.
- **Test shape**: unit test? Integration? Golden-file? Snapshot? One
  example of how the test would be structured (test name + 2-3 lines
  describing setup + assertion).
- **Effort vs. payoff**: rough size and what the test would catch.

If fewer than three meaningful gaps exist, list fewer. Do not pad.

### Open questions

Anything you couldn't determine from reading the code that the user
could clarify: planned future work, expected use patterns, whether a
particular path is reachable in production. Be specific.

## Rules

- **Indirect coverage counts only when you can name the protecting
  test.** "It's probably exercised by the integration tests" without a
  specific test reference is not coverage.
- **A test that mocks the dependency it's supposed to exercise is
  often anti-coverage.** Call those out by name. The risk is real:
  mocked tests pass while the real path breaks.
- **Snapshot / regression / cross-impl gates count as coverage** when
  they exist and run. Note their dataset / scope so the user knows
  the protection scope.
- **Match scope to argument.** A single-file path → file-level review:
  which methods of this class lack tests. A project / large folder →
  architecture-level review: which subsystems have weak coverage.
- **No emojis. No "Overall, …" wrap-ups.** End with the top three
  test recommendations or the open questions, whichever is more
  useful.
