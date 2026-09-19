---
description: Review this machine's Claude Code auto-memory against ai/ - delete what is redundant, move what is team-wide into the docs, interview the developer on conflicts
---
Read and follow `ai/docs/memory-cleanup-guide.md`.

Memory is per machine and per developer, so this runs on each machine separately and
nothing here is visible to the team until it lands in `ai/`. Measure first, back up
before touching anything, classify every file against the durable docs, write the
review to the session folder, and put each contradiction to the developer with
`AskUserQuestion` in plain prose - assume they have not read the memories.

Deleting is the normal outcome: most memories are already captured in `ai/` or a
completed TODO by the time anyone looks. The other normal outcome is a move - the
memory is deleted in the same step its content lands in a doc.

If the developer says `report` only, stop after the review file and the interview; do
not delete or move anything.
