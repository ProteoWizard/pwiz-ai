---
argument-hint: <path>
description: Honest OOP / architecture review of a code path for modularity, encapsulation, separation of concerns, cohesion, and coupling — calling out monolithic or spaghetti tendencies.
---

# OOP / Architecture Review

Deliberate object-oriented design review of the code under `$ARGUMENTS`. Requested when
the author intends to maintain and grow this code long-term — the question is no longer
"does it work?" but "will this scale to another year of growth without rotting?"

**Read**: [ai/docs/code-review-guide.md](../../docs/code-review-guide.md) — the review
posture, the five lenses, survey heuristics, the monolithic-vs-spaghetti calibration, and
the presentation structure.

## Quick reference

**Posture — do not soften.** The reason this command exists is that the assessment is not
volunteered unless asked. A lukewarm "looks fine, here are some nits" review is the
failure mode. If the code is genuinely good, say so plainly with evidence.

Five lenses, in priority order:

1. Separation of concerns
2. Encapsulation
3. Modularity
4. Cohesion (high)
5. Coupling (low)

1. **Scope and inventory** — file/class list with line counts, public surface, module
   boundaries. Flag files > 1,000 LOC.
2. **Spot-read the suspects** — largest files; `manager`/`controller`/`service`
   orchestrators; `Util`/`Helper`/`Common`; multi-file `partial`s.
3. **Grade each lens** — Strong / Adequate / Weak / Failing, with 2–5 `file:line`
   citations. Then monolithic tendencies, spaghetti tendencies, promising patterns.
4. **Present** — unhedged headline assessment, per-lens findings, top three
   recommendations (action / effort / payoff), open questions.

Match scope to the argument: a single class gets a class-scoped review, a project gets an
architecture-scoped one. No emojis, no "Overall, …" wrap-ups.

## Related

- `/pw-test-review` — the coverage counterpart
- `/pw-review` — reviewing a specific GitHub PR
