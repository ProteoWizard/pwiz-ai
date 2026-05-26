---
argument-hint: <path>
description: Honest OOP / architecture review of a code path for modularity, encapsulation, separation of concerns, cohesion, and coupling — calling out monolithic or spaghetti tendencies.
---

# OOP / Architecture Review

Conduct a deliberate object-oriented design review of the code under
`$ARGUMENTS`. This is requested when the user has decided the code is
something they intend to maintain and grow long-term — past
proof-of-concept, into kept-and-released-software territory. Treat the
request accordingly: the question is no longer "does it work?" but
"will this scale to another year of growth without rotting?"

## Posture: be honest, even uncomfortable

The reason this command exists is that Claude does not volunteer this
kind of assessment unless asked. **When asked, do not soften.** This is
not a place for the diplomatic phrasing pattern "this is good *but*
consider...". Call out genuine weaknesses by name. The user already
knows the things they're proud of; they want to know what you'd
critique if you were the next engineer to inherit this code.

If the code is genuinely well-architected, say so plainly and back it
with evidence — that finding is just as useful as a teardown. The
failure mode to avoid is the lukewarm "looks fine, here are some
nits" review that doesn't actually engage with whether the design
holds together.

## What "OOP review" means here

Five lenses, in priority order:

1. **Separation of concerns.** Does each class/module do one thing,
   and is that thing named in the class name? Are mixed
   responsibilities — orchestration + business logic + I/O + logging
   — bleeding into a single type?
2. **Encapsulation.** Is internal state actually internal? Or are
   private implementation details exposed through public fields,
   pass-through properties, or back-reference pointers that let other
   classes reach in? Is there an explicit "is owned by this class"
   posture for each piece of state?
3. **Modularity.** Are modules / projects / namespaces drawn around
   genuine concept boundaries, or have they accreted by accident?
   Could a new contributor identify "where does X live?" by reading
   the directory structure alone?
4. **Cohesion (high).** Inside each class, do the members all serve
   the same purpose? Are there feature-envy methods that should
   probably live elsewhere? Are there "utility dumping ground" classes
   gathering unrelated helpers?
5. **Coupling (low).** Between classes, how tight are the dependency
   webs? Does a change in A require touching B, C, and D? Are there
   `_pipeline._ctx = ctx` style cross-instance reaches, friend access
   via `internal` that suggests the class boundaries are wrong, or
   circular-dependency smells?

## Step 1 — Scope and inventory

Survey the code at `$ARGUMENTS`:

- **File / class inventory**: list every source file under the path,
  with line counts. Flag any file > 1,000 LOC immediately — those are
  always worth inspection.
- **Public surface area**: identify the entry points (CLI mains, exported
  types, public interfaces) and trace what the rest of the code is
  doing in service of them.
- **Module / project boundaries**: if the path spans multiple projects
  / namespaces / folders, note what each is supposed to be responsible
  for and whether that division is actually respected.

For a large path, you may need to delegate surveying to an Explore
agent rather than reading every file yourself. Summarize what you
found before going deeper.

## Step 2 — Spot-read the suspects

Pick the highest-leverage targets and read them in full (not just
excerpts):

- The largest file(s) — almost always the most informative.
- The "main" / "pipeline" / "manager" / "controller" / "service"
  classes that orchestrate other types. These are where SoC failures
  tend to land.
- Any file with names like `Util`, `Helper`, `Common`, `Misc` — these
  are dumping-ground risk.
- Anything with a `partial` keyword spanning multiple files — partials
  can hide cohesion problems.

While reading, build a mental map of *who calls whom* and *who owns
what state*. A picture of the actual dependency graph (even sketched
informally) is more useful than a list of issues.

## Step 3 — Evaluate against the five lenses

For each lens, produce a finding:

- A **grade or assessment**: e.g. "Strong / Adequate / Weak / Failing"
  with one sentence justifying it.
- The **evidence**: 2–5 specific file:line references that exemplify
  the assessment, with quoted code or method names. Vague findings
  with no evidence are worse than no finding.

Also call out, separately:

- **Monolithic tendencies**: any single class / file accreting too
  many responsibilities. The threshold isn't a hard LOC number — a
  3,000-line file that's all `switch`-cases dispatching on a discrete
  enum is fine; a 700-line class with mixed I/O, orchestration, and
  domain logic is not.
- **Spaghetti tendencies**: tangled control flow, deeply nested
  conditionals, methods that span hundreds of lines, state mutations
  happening in non-obvious places, hidden global state, back-references
  between classes that should be peers.
- **Promising patterns**: places where the existing design is
  load-bearing and worth preserving / extending — these are the seams
  Phase N+1 should build on.

## Step 4 — Present findings

Structure the response as:

### Headline assessment

One paragraph stating the overall health of the code under review.
Pick a posture: "this is well-architected and growing it further is
safe", or "this has accreting-monolith risk in area X and is worth
refactoring before adding feature Y", or whatever the honest read is.
Do not hedge this paragraph.

### Per-lens findings

For each of the five lenses, a short section:

- **Grade**
- **Evidence** (file:line citations with brief quotes)
- **Recommendation**, if there is something concrete to do. Some
  lenses may need no recommendation — that's fine, say so.

### Top three recommendations

If the assessment surfaces concrete improvements, prioritize them
ruthlessly to the top three. More than three suggestions usually
means none of them will happen. Each should be:

- **Action**: what to do
- **Effort**: rough size (a one-day refactor, a one-PR cleanup, a
  multi-sprint project)
- **Payoff**: what this buys (clearer ownership, easier onboarding,
  ability to add feature X, etc.)

### Open questions

Anything you couldn't determine from reading the code that the user
could clarify in discussion: intent, planned future work, why a
particular pattern was chosen. Be specific.

## Rules

- **Do not extrapolate from one example to a sweeping claim.** If you
  see a god class, say "this class is a god class because of X, Y, Z"
  — don't say "the project is a mess."
- **Distinguish prescriptive from descriptive.** When you say
  "consider extracting X into its own class", be clear whether that's
  a strong recommendation, an option to consider, or just a thought.
  The user is calibrating their own decisions on your phrasing.
- **Do not invent issues to seem thorough.** If a lens shows the code
  is strong, grade it strong and move on. Padding the review with
  nits is the failure mode this command exists to prevent.
- **Match scope to argument.** If the path is a single class, the
  review is class-scoped — discuss responsibilities, method
  organization, internal state. If the path is a project / large
  folder, the review is architecture-scoped — discuss module
  boundaries, dependency direction, where the seams are.
- **No emojis. No "Overall, …" wrap-ups.** End with the open questions
  or the top three recommendations, whichever is more useful.
