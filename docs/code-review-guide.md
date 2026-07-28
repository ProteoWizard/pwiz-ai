# Code Review Guide

Rubrics for reviewing code you intend to keep: the architecture/OOP review, the generic
PR review criteria, and the review posture both share.

Test-coverage review lives in `testing-patterns.md` § "Assessing test coverage by
reading" — it belongs beside the tool-based coverage material rather than here.

The slash commands `/pw-oop-review`, `/pw-test-review` and `/pw-review` are entry points
into this guide. Everything needed to perform a review is here.

## Posture: be honest, even uncomfortable

**This is the shared foundation of every review rubric below, and the reason these
reviews are requested explicitly.**

An LLM does not volunteer this kind of assessment unless asked, and when asked it drifts
toward diplomacy. **Do not soften.** This is not a place for "this is good *but*
consider…". Call out genuine weaknesses by name. The author already knows what they are
proud of; they want to know what the next engineer to inherit the code would critique.

If the code is genuinely good, **say so plainly and back it with evidence** — that
finding is as useful as a teardown. The failure mode to avoid is the lukewarm "looks
fine, here are some nits" review that never engages with whether the design holds
together.

Two corollaries that apply to every rubric here:

- **Do not invent issues to seem thorough.** Padding a review with nits is precisely the
  failure these commands exist to prevent. If a lens shows the code is strong, grade it
  strong and move on.
- **Evidence or it does not count.** Every finding carries specific `file:line`
  references with quoted code or method names. A vague finding is worse than no finding,
  because it costs the reader time and cannot be acted on.

---

# Architecture / OOP review

Requested when the author has decided the code is something they intend to maintain and
grow long-term — past proof-of-concept, into kept-and-released-software territory. The
question is no longer "does it work?" but **"will this scale to another year of growth
without rotting?"**

## The five lenses, in priority order

1. **Separation of concerns.** Does each class/module do one thing, and is that thing
   named in the class name? Are mixed responsibilities — orchestration + business logic
   + I/O + logging — bleeding into a single type?
2. **Encapsulation.** Is internal state actually internal? Or are private implementation
   details exposed through public fields, pass-through properties, or back-reference
   pointers that let other classes reach in? Is there an explicit "is owned by this
   class" posture for each piece of state?
3. **Modularity.** Are modules / projects / namespaces drawn around genuine concept
   boundaries, or have they accreted by accident? Could a new contributor identify "where
   does X live?" from the directory structure alone?
4. **Cohesion (high).** Inside each class, do the members all serve the same purpose? Are
   there feature-envy methods that should live elsewhere? Are there "utility dumping
   ground" classes gathering unrelated helpers?
5. **Coupling (low).** Between classes, how tight are the dependency webs? Does a change
   in A require touching B, C and D? Are there `_pipeline._ctx = ctx` style cross-instance
   reaches, friend access via `internal` that suggests the class boundaries are wrong, or
   circular-dependency smells?

## Step 1 — Scope and inventory

- **File / class inventory**: every source file under the path, with line counts. Flag
  any file > 1,000 LOC immediately — those always merit inspection.
- **Public surface area**: the entry points (CLI mains, exported types, public
  interfaces), and what the rest of the code does in service of them.
- **Module / project boundaries**: if the path spans multiple projects / namespaces /
  folders, what each is responsible for and whether that division is actually respected.

For a large path, delegate surveying rather than reading every file yourself. Summarize
what you found before going deeper.

## Step 2 — Spot-read the suspects

Read these in full, not in excerpts:

- **The largest file(s)** — almost always the most informative.
- **"main" / "pipeline" / "manager" / "controller" / "service" classes** that orchestrate
  other types. This is where separation-of-concerns failures land.
- **Anything named `Util`, `Helper`, `Common`, `Misc`** — dumping-ground risk.
- **Anything `partial` spanning multiple files** — partials can hide cohesion problems.

While reading, build a map of *who calls whom* and *who owns what state*. A sketch of the
actual dependency graph is worth more than a list of issues.

## Step 3 — Evaluate against the five lenses

Per lens: a **grade** (Strong / Adequate / Weak / Failing) with one sentence justifying
it, and **evidence** — 2–5 specific `file:line` references with quoted code.

Then, separately:

- **Monolithic tendencies** — any single class/file accreting too many responsibilities.
  **The threshold is not a LOC number.** A 3,000-line file that is all `switch` cases
  dispatching on a discrete enum is fine; a 700-line class mixing I/O, orchestration and
  domain logic is not.
- **Spaghetti tendencies** — tangled control flow, deeply nested conditionals, methods
  spanning hundreds of lines, state mutations in non-obvious places, hidden global state,
  back-references between classes that should be peers.
- **Promising patterns** — where the existing design is sound and worth preserving or
  extending. These are the seams the next phase should build on.

## Step 4 — Present findings

**Headline assessment** — one paragraph on overall health. Pick a posture: "this is
well-architected and growing it further is safe", or "this has accreting-monolith risk in
area X and is worth refactoring before adding feature Y". **Do not hedge this paragraph.**

**Per-lens findings** — grade, evidence, and a recommendation where there is something
concrete to do. Some lenses need no recommendation; say so.

**Top three recommendations** — prioritize ruthlessly. More than three usually means none
happen. Each carries **action** (what to do), **effort** (a one-day refactor, a one-PR
cleanup, a multi-sprint project) and **payoff** (clearer ownership, easier onboarding,
ability to add feature X).

**Open questions** — what you could not determine from the code: intent, planned work,
why a pattern was chosen. Be specific.

## Rules

- **Do not extrapolate from one example to a sweeping claim.** "This class is a god class
  because of X, Y, Z" — not "the project is a mess."
- **Distinguish prescriptive from descriptive.** When suggesting an extraction, be clear
  whether it is a strong recommendation, an option, or a passing thought. The author
  calibrates their decisions on your phrasing.
- **Match scope to the argument.** A single class → class-scoped review: responsibilities,
  method organization, internal state. A project or large folder → architecture-scoped:
  module boundaries, dependency direction, where the seams are.
- **No emojis. No "Overall, …" wrap-ups.** End with the open questions or the top three
  recommendations, whichever is more useful.

---

# Pull request review criteria

Used when reviewing a specific PR rather than auditing a subsystem.

**Read the surrounding context, not just the diff.** For each substantially changed file,
read the full file or the relevant sections, to see how the change fits its
class/module, whether callers or dependents are affected, and whether it is consistent
with existing patterns.

## Quality criteria

**Correctness**
- Does the logic do what the PR description claims?
- Are edge cases handled?
- Off-by-one errors, null reference risks, race conditions?

**Architecture and design**
- Does the change follow existing patterns in the codebase?
- Unnecessary duplication that should use an existing helper?
- Are new abstractions justified, or premature?

**Style and consistency**
- Existing naming conventions followed
- No unrelated formatting changes
- Comments only where the logic is not self-evident

**Test coverage**
- Are new features/fixes covered by tests?
- Do existing tests need updating?
- For depth here, see `testing-patterns.md` § "Assessing test coverage by reading"

## Skyline-specific rules — check the real source

These are frequently-violated rules worth checking on every PR. **Each is stated in one
place; check that place rather than trusting a restated copy** (this list has drifted
before — three of these were previously attributed to `CRITICAL-RULES.md` when two of
them live elsewhere):

| Rule | Actual source |
|------|---------------|
| No `async`/`await` — use `ActionUtil.RunAsync()` | `../CRITICAL-RULES.md` |
| No hardcoded UI strings — use `.resx` resources | `../CRITICAL-RULES.md` |
| Solution builds with zero warnings | `../CRITICAL-RULES.md` |
| No `MessageBox.Show()` — use `MessageDlg` / `MultiButtonMsgDlg` / `AlertDlg` | `architecture-error-handling.md` § "Dialog patterns" |
| No new `using System.Windows.Forms` in the Model layer | `architecture-error-handling.md` |

## Related

- `testing-patterns.md` — test-coverage review rubric and the tool-based coverage workflow
- `architecture-error-handling.md` — dialog and exception rules cited above
- `version-control-guide.md` — the review chain (`/code-review` before opening the PR)
- `debugging-principles.md` — investigation methodology when a review turns into a hunt
