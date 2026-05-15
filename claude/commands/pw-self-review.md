---
argument-hint: [PR]
description: Spawn a fresh-context Claude agent to independently review the PR for issues Copilot may have missed
---

# Self Review (Fresh-Context Agent Pass)

Launch a Claude agent in a fresh context window to independently review
a PR. Complements rather than replaces Copilot's automated review:
Copilot tends to catch idiomatic / API / language issues; a Claude
agent tends to catch logic / cross-impl / spec-conformance issues.
Recommended sequence is Copilot first (via `/pw-respond`), then this
command, optionally followed by `/ultrareview` for maximum rigor.

## Step 1 — Identify the PR

If `$ARGUMENTS` is set, treat it as the PR number. Otherwise resolve
the PR for the current branch:

```bash
gh pr view --json number,url,headRefName,baseRefName,title
```

Stop if no open PR is found and tell the user.

## Step 2 — Confirm Copilot has already reviewed

```bash
gh pr view <N> --json reviews | jq '.reviews[] | select(.author.login=="copilot-pull-request-reviewer") | {submittedAt, state}'
```

If Copilot has not yet reviewed, ask the user whether to proceed
anyway. The fresh-context pass is most useful as a *second* opinion;
running it before Copilot wastes one of two complementary signals.

## Step 3 — Launch the agent

Spawn a general-purpose agent in the background with a prompt that:

- Names the PR (number, repo, title) and the upstream source it ports
  from when applicable. Pull these from `gh pr view`.
- Explicitly tells the agent it is reviewing code authored by a
  *different* Claude session, and what classes of issue to look for
  (cross-impl divergence, correctness bugs the existing tests miss,
  hash-stability invariants, concurrency, API choices that age
  poorly). Skip nits.
- Tells the agent which Copilot findings have already been addressed
  (so it doesn't re-flag them).
- Caps the report length (~600 words) and asks for severity-tagged
  findings, a "what I checked and found clean" section, and one
  follow-up question for the author.

Use `subagent_type: "general-purpose"` and `run_in_background: true`.
Output goes to a transcript file the harness will surface when the
agent completes.

## Step 4 — Surface the findings

When the agent reports back, summarize for the user:

1. List each finding with the agent's severity tag, the file:line,
   and one-line description.
2. Recommend which to address now, which to defer, which to dismiss
   (with reasoning).
3. Offer to run `/pw-respond <PR#>` afterward to address the agreed
   set — same flow as for Copilot comments.

## Notes

- The agent runs in a fresh context, so it doesn't see this
  conversation or the implementation history. The prompt has to be
  self-contained.
- It's a single Claude instance, not multi-model. Strictly weaker than
  `/ultrareview` for ensemble strength; strictly stronger than the
  current session re-reading its own diff. Use the right tool.
- Do not launch this in parallel with code edits to the same PR — let
  the agent finish first so its review reflects the actual head.
