---
description: Review PR comments, address them in code, and resolve threads
---
Address the latest review comments on the current branch's PR end-to-end:
fetch them, propose a plan, implement the agreed fixes in a single new
commit, then reply to and resolve each addressed thread on GitHub.

## Step 1 — Fetch and summarize

1. Find the open PR for the current branch:
   `gh pr view --json number,url,headRefName,reviews`
   If no PR exists, stop and tell the user.
2. Fetch inline review comments:
   `gh api repos/<OWNER>/<REPO>/pulls/<N>/comments`
3. Summarize each in a small table — file, line, severity (real bug
   vs. naming vs. doc cleanup), proposed fix. Call out any low-confidence
   Copilot suggestions that appear inside the review body summary
   (those have no inline thread, so they can be addressed but not
   "resolved" via the API).
4. Ask the user which to address, skip, or defer. Note the user's
   decision per comment so Step 3 knows which threads to resolve.

## Step 2 — Implement and commit

1. Apply the agreed fixes.
2. Run the project's pre-commit gate (build + tests + inspection). For
   Osprey this is
   `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -RunInspection -RunTests`;
   for Skyline use the gate documented in `ai/CLAUDE.md`.
3. Commit. **NEVER amend after review** — always a new commit. Use a
   message like:
   ```
   Addressed Copilot review feedback on PR #<N>

   * <fix 1>
   * <fix 2>

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```
4. `git push`. Capture the resulting commit SHA — Step 3 needs it.

## Step 3 — Reply and resolve

For each addressed comment, post a reply that references the commit
SHA, then resolve the thread. Skipped or deferred comments stay
unresolved so the human reviewer can see them.

GitHub's REST API maps an inline comment to a *thread* by GraphQL ID
only — pull the thread IDs first:

```bash
gh api graphql -f query='
  query($o: String!, $r: String!, $n: Int!) {
    repository(owner: $o, name: $r) {
      pullRequest(number: $n) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes { databaseId path line body }
            }
          }
        }
      }
    }
  }' -F o=<OWNER> -F r=<REPO> -F n=<N>
```

The `databaseId` of each thread's first comment matches the REST
`id` returned in Step 1, which is how you join thread → addressed
comment.

Reply (REST):
```bash
gh api -X POST repos/<OWNER>/<REPO>/pulls/<N>/comments \
  -f body="Fixed in <SHA> — <one-line note>." \
  -F in_reply_to=<PARENT_COMMENT_ID>
```

Resolve (GraphQL — REST has no resolve endpoint):
```bash
gh api graphql -f query='
  mutation($t: ID!) {
    resolveReviewThread(input: {threadId: $t}) {
      thread { isResolved }
    }
  }' -F t=<THREAD_ID>
```

## Rules

- One commit per round of feedback. Don't amend; squash happens at
  merge.
- Reply briefly — one line plus the SHA is enough. The diff in the
  commit speaks for itself.
- Never resolve a thread you didn't actually address. Hiding feedback
  from a human reviewer is worse than leaving it open.
- If the user wants to push back on a comment rather than fix it,
  reply with the rationale and leave the thread unresolved for the
  human reviewer to decide.
- Low-confidence suggestions inside the review summary body don't have
  inline threads — address them if the user opts in, but there's
  nothing to "resolve" via API.
