---
argument-hint: [PR]
description: Spawn a fresh-context Claude agent to independently review the PR for issues Copilot may have missed
---

# Self Review (Fresh-Context Agent Pass)

Launch a Claude agent in a fresh context window to independently review
a PR. Required gate alongside Copilot — not optional. Copilot tends to
catch idiomatic / API / language issues; a Claude agent tends to catch
logic / cross-impl / spec-conformance issues, and it can read source
repos outside the PR (e.g. Rust upstream for ports) that Copilot has
no access to. Standard sequence (local-first): `/pw-self-review` on the
local branch → open the PR → Copilot review → `/pw-respond` → optional
`/ultrareview`. Running self-review before the PR makes Copilot's review
land on the final state; see the version-control skill.

## Step 1 — Resolve what to review (local branch by default)

Default: review the current LOCAL branch before any PR exists (the
local-first flow). Get the branch + base and the diff range:

```bash
git -C <repo> rev-parse --abbrev-ref HEAD
git -C <repo> log --oneline <base>..HEAD   # base is usually master
```

The agent reviews `git -C <repo> diff <base>...HEAD`. If `$ARGUMENTS`
is a PR number, review that open PR instead
(`gh pr view <N> --json number,url,headRefName,baseRefName,title`).

## Step 2 — Copilot ordering

In the local-first flow Copilot has NOT run yet — that is intended; it
reviews after the PR is opened so self-review findings get fixed first.
Do NOT wait for Copilot. (Only when reviewing an already-open PR via a
`$ARGUMENTS` PR number, list the Copilot findings already addressed so
the agent doesn't re-flag them:
`gh pr view <N> --json reviews | jq '.reviews[] | select(.author.login=="copilot-pull-request-reviewer") | {submittedAt, state}'`.)

## Step 3 — Launch the agent

Spawn a general-purpose agent in the background with a prompt that:

- Names the change under review (repo + branch and diff range, or PR
  number/title) and the upstream source it ports from when applicable,
  and tells the agent to read the diff itself.
- Explicitly tells the agent it is reviewing code authored by a
  *different* Claude session, and what classes of issue to look for
  (cross-impl divergence, correctness bugs the existing tests miss,
  hash-stability invariants, concurrency, API choices that age
  poorly). Skip nits.
- When reviewing an already-open PR, tells the agent which Copilot
  findings are already addressed (so it doesn't re-flag them).
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
3. Local-first: after the agreed findings are fixed (and build/tests
   are green), open the PR (`gh pr create`) — Copilot reviews next.
   When reviewing an already-open PR instead, offer `/pw-respond <PR#>`
   to address the agreed set, same flow as for Copilot comments.

## Notes

- The agent runs in a fresh context, so it doesn't see this
  conversation or the implementation history. The prompt has to be
  self-contained.
- It's a single Claude instance, not multi-model. Strictly weaker than
  `/ultrareview` for ensemble strength; strictly stronger than the
  current session re-reading its own diff. Use the right tool.
- Do not launch this in parallel with code edits to the same
  branch/PR — let the agent finish first so its review reflects the
  actual head.
