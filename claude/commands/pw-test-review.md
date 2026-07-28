---
argument-hint: <path>
description: Honest review of test coverage at the given path — what's actually exercised by tests vs. what's nominally tested, plus prioritized recommendations for where new tests would catch real regressions.
---

# Test Coverage Review

Assess how well the code under `$ARGUMENTS` is tested, by static reading. The by-eye
complement to dotCover — useful when an LLM assessment is faster, or when the coverage
tool is not available.

The question is not "are there tests?" but **"would the existing tests catch the kinds of
regressions a reasonable maintainer would worry about?"**

**Read**: [ai/docs/testing-patterns.md](../../docs/testing-patterns.md) § "Assessing Test
Coverage by Reading" — the five lenses, the mapping procedure, and the rules. The shared
review posture is in
[ai/docs/code-review-guide.md](../../docs/code-review-guide.md).

## Quick reference

**Posture — the default-polite assessment is the failure mode.** Smoke-only or mock-heavy
tests are inverse-coverage: say so. If critical code has no tests, name it rather than
burying it under "consider adding tests for X."

Five lenses: public surface coverage · behavior vs. shape · edge and error paths ·
regression gates · test quality.

1. **Inventory the code** — public surface, critical paths, low-risk glue
2. **Inventory the tests** — what they target, their shape, real work vs. shape-only
3. **Map tests to surface** — directly tested / indirectly tested / untested. **Name the
   protecting test** for anything counted as indirect coverage
4. **Grade each lens** with production + test `file:line` citations; call out tests that
   look like coverage but are not, tests that earn their keep, and high-consequence gaps
5. **Present** — unhedged headline, per-lens findings, **top three** places to add tests
   (what / shape / effort vs. payoff), open questions

Do not pad. Fewer than three real gaps means list fewer. No emojis, no "Overall, …".

## Related

- `/pw-oop-review` — the architecture counterpart
- `/pw-cover` — run the dotCover tooling instead of reading
