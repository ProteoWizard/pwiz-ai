# Working Reliably With LLMs: Validation, and Turning Failures Into Procedure

**Summary.** You can only improve instructions so much. Documentation, setup guides, and prompt wording are all model-interpreted: they degrade as context grows and are prone to a skipped step no matter how carefully written. There is a ceiling, and you hit it sooner than expected. When a piece of guidance matters and can be checked by code, write the check instead — prefer a shell script over an instruction. Everything below is the reasoning behind that single rule: why an LLM's output is trustworthy only as far as its verifier is real, why this holds far better for code than for claims, how to match caution to risk, and why every failure you catch should become a permanent check that prevents its recurrence.

---

## The one claim everything else follows from

An LLM is an unreliable generator. The trustworthiness of work done with it does not come from the model. It comes from the verifier wrapped around the model. You trust the system exactly as far as the verification is real, independent, and cheap — and not one step further.

This is worth stating starkly because softening it is what makes it sound like a pitch. It is not a pitch. It is a boundary. Everything below is just the consequences of taking that boundary seriously.

## How the model actually "validates" its work

It doesn't, in the sense people usually fear. The model does not look inward and certify itself. What happens in a working setup is that verification is an *external action* whose result comes back into the context as a fact the model cannot argue with: a compiler exit code, a failing test name, a query that returned zero rows, a count that didn't change.

The model's only role in validation is reacting to a verdict it did not author. That distinction is the entire defense against the failure mode that worries careful people — the model asserting something false, confidently, and persisting in it. That behavior is only dangerous when the assertion *is* the deliverable. Put a real external verifier in front of it and the same tendency becomes nearly harmless: the model can be as confident as it likes; the failing test calls the bluff before the claim reaches a human.

The engineering response to "the model gets things wrong and won't back down" is therefore not "make the model stop." It is: never let an unverified assertion be the deliverable.

## Why this works far better for code than for claims

Code has cheap, deterministic verifiers that the model does not control. A compiler cannot be talked around. A test suite returns the same verdict no matter how confidently the code was asserted to be correct. That indifference to the model's confidence is the whole source of trust.

An abstract claim — "this will scale," "this is the cleaner design" — has no compiler. Its only verifier is judgment, human or model. So the usable rule is:

> The trustworthiness of an LLM on a task is bounded above by the strength and independence of the verifier available for that task.

Code sits near the top of that ordering. Unverifiable claims sit at the bottom. This is also the honest, skeptic-proof version of "good tasks for an agent are verifiable ones," stated as its contrapositive: *a task with no cheap independent verifier gets you exactly the reliability of a confident junior who never says "I'm not sure" — useful, but never to be believed without a check.*

## Match containment to the blast radius before you start

A common reaction is to treat all LLM work as maximum-risk and conclude *therefore don't*. It can be more productive to weigh the risk the way the risk of a scientific experiment is weighed: characterize the failure modes, match the containment to the consequence, and proceed accordingly.

- **Gloves and goggles** — a cheap deterministic verifier exists and a failure announces itself immediately. Greenfield code under a good test suite; a refactor with the suite passing; a script whose output will be inspected anyway. Proceed with ordinary care; agonizing over this tier is wasted effort.
- **Fume hood** — failure is recoverable but would escape quietly if you weren't actively venting it. The wrong change no test catches, noticed only after it's expensive to undo. Containment is engineered extraction: a checkpoint taken before the action, a forced readback, an inspectable result. Build the venting, then proceed.
- **Isolation chamber** — failure is irreversible or its blast radius exceeds your ability to contain it after the fact. The unverifiable architectural commitment everything else will be built on. This tier does not get an unsupervised model behind a weak verifier. It gets a domain expert as the verifier, because the only verifier strong enough is judgment and there is no cheap substitute. Note this still does not mean *don't* — it means the containment matches the consequence.

The useful judgment is identifying which tier a task falls in *before* starting, rather than after.

## Where expert skepticism actually sits in this

It is not a soft contribution adjacent to the real work. In this framework it has a precise job: the experienced person is the verifier for the class of claims that have no cheap deterministic verifier. The compiler handles the cheap end of the spectrum. The expert handles the expensive end — the architectural call, the "is this what's actually needed" call. That is the engineering, at the one place the automated loop structurally cannot reach.

Deep domain context and a clear design spec are not secondary to this either. They are how you move more of a project's claims *into* the cheaply-verifiable region in the first place. Restructuring a problem so that "is this right" becomes something a test can answer, instead of something only judgment can answer, is the highest-leverage thing a domain expert can do to a codebase. It matters more than writing the code.

## The virtuous cycle: failures become permanent verifiers

The standard does not rise because the model gets better at checking itself. It rises because **every failure the loop catches is converted into a permanent, cheap verifier for that failure class.**

A defect gets through. You do not just fix it. You add the check — a test, a lint rule, a validation step — that would have caught it. That check now runs forever at near-zero cost, and that failure mode cannot silently recur. The bar the model must clear is now strictly higher than it was, and higher in a deterministic way rather than by another model's opinion. The next, subtler failure becomes the most prominent one, and the flywheel turns again.

Two failure-handling procedures encode this directly, and they are worth following as rules:

- **Don't guess — bisect and add diagnostics until the root cause is *proven*.** This is a procedural ban on substituting a confident assertion for an established fact. The output of the procedure is a proof, not a claim.
- **Implement a test that fails on the current code and passes on the fix.** This forces the fix to leave behind the cheap permanent verifier that prevents its own recurrence. The bug is not allowed to be fixed without also being gated forever after.

These are not just good habits. They are expert skepticism *externalized into rules the loop runs unattended.* How long the work can safely proceed without supervision is a direct function of how much expert judgment has been converted from an in-the-moment act into a procedure that runs on its own — and of how strong the weakest verifier guarding the unwatched work is. Returning to useful progress is then not luck, and not the model being good. It is the encoded procedures having held the line on work whose containment tier was correctly matched before it was left to run.

## The most concrete form: prefer coded validation over instructions

This is the principle reduced to something actionable, and it was arrived at by failure, not theory.

**You can only improve instructions so much.** Instructions — documentation, setup guides, prompt wording, a CLAUDE.md — are model-interpreted. They degrade as context grows and they are prone to a step being skipped or a detail being misread, no matter how carefully written. There is a ceiling on how reliable prose guidance can be made, and you hit it sooner than you expect.

A validation *script* is a deterministic verifier. It does not interpret, does not skip, does not degrade with context, and returns the same verdict every time.

Concretely: the developer setup assistance documentation, written carefully, was still too prone to skipping something or making a mistake when followed. Adding an external system-setup validation script alongside it fixed that — not by improving the prose further, but by replacing "trust that the steps were followed" with "prove the resulting state is correct." The documentation explains; the script verifies. Only the script's verdict is trusted.

Stated as the rule:

> When a piece of guidance matters and can be checked by code, write the check. Prefer a shell script over an instruction. Improve instructions until you hit their ceiling, then stop improving them and write the verifier instead.

Every principle above is a longer way of saying that one thing.

## See also

- [ai/docs/debugging-principles.md](debugging-principles.md) — debugging methodology that implements these principles for the bug-fix loop (cycle time, bisection, instrumentation, failing-test-first).
- [ai/CRITICAL-RULES.md](../CRITICAL-RULES.md) — the project's hard rules; each is intended to be backed by a verifier (build, test, inspection).
- [ai/claude/skills/debugging/SKILL.md](../claude/skills/debugging/SKILL.md) — the loaded-on-demand debugging skill.
