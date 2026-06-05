---
name: night-session
description: Invoke when starting an autonomous overnight session ("this is a nighttime autonomous session"). Sets a deep-investigation posture - premium on progress and high-definition findings, expects 5-8 hours of work without check-ins.
---

# Night Session Mode

When the user says "this is a nighttime autonomous session" or similar
("overnight session", "running through the night", "/loop overnight"),
shift into night-session posture.

## The contract you are operating under

The user is going to bed. They will wake in 5-8 hours (sometimes longer).
They are running Max 20x or equivalent — **cost is essentially a
non-concern**. What matters is that they wake to **the most precise,
load-bearing finding you can produce** with that time budget.

A bad outcome is waking to find you stopped at a checkpoint and waited.
The user has explicitly stated: "Good developers don't just stop dead
waiting for instructions, they find work parallel to what may be
blocked." Mirror that. **You are a developer who has been left alone
with the work and your professional reputation; act accordingly.**

## First: agree on the goal of the night

Before any substantive work, make sure you know what this session is FOR.
If the user's `/night-session` invocation (or the message right after it)
already states a clear goal, adopt it and proceed. **Otherwise, ask — and
wait for the answer — before starting any work:**

> "What should the goal of this night session be?"

Do NOT guess a goal and start working on whatever seems most reasonable;
a wrong guess wastes hours and forces the user to cancel and redirect.
This goal question — together with the budget pushback below — is the one
sanctioned place to ask-and-wait at session start; the anti-stopping
doctrine everywhere else assumes the goal is already settled. Once the
goal is set, record it at the top of `ai/.tmp/night-session-budget.md`
and don't ask further clarifying questions unless genuinely blocked.

## First step: measure your starting position

Before any other work, run two measurements and write them down where
you can refer back later (a `TaskCreate` description, a note at the top
of the session log, or `ai/.tmp/night-session-budget.md`):

1. **Time**: `pwsh -Command "Get-Date"` — what time is it locally,
   and when does the user expect to wake (ask if unclear, default to
   8 hours from now)? **Write this start time down explicitly** — at the
   end of the session you report the stop time and the total elapsed
   duration, so the user sees the session's wall-clock cost alongside its
   context cost.
2. **Context**: `mcp__status__get_context_usage` — what % is already
   in use, what's the model's window?

The session has NEVER started at 100% free. With `/pw-handoff` →
`/compact` → `/pw-continue`, a fresh night session typically begins at
70–90%. With a deeper handoff chain or a heavy `/pw-continue` it can
start much lower. Treat the opening reading as the **actual** budget
you have to work with.

### If opening context is below 80%, push back before committing

Tell the user — before they go to bed — something like:

> "Opening context is 64% free. For an 8-hour autonomous session
> that's tight; even a moderate burn rate will hit single digits
> in 3–4 hours. I can either (a) start now and pivot to sub-agents
> early, (b) wait while you run `/pw-handoff` → `/clear` →
> `/pw-continue` to start near 90%, or (c) work for as long as the
> budget lasts and write a clean handoff at ~15% so the morning
> session picks up cleanly. Which do you prefer?"

This is the one acceptable place to ask a clarifying question at
session start. The cost of getting it wrong (running out of context
at 4 AM) is much higher than the cost of a 60-second exchange now.

### Burn-rate check — re-measure every ~hour

After ~1 hour of work, re-measure context and compute the burn rate:

```
burn_rate_pct_per_hour = (opening_pct_free - current_pct_free) / hours_elapsed
projected_runway_hours = current_pct_free / burn_rate_pct_per_hour
```

If projected_runway < hours_left_until_wake, you're burning too fast.
That's the signal to **shift strategy**, not to stop working:

- **Hand expensive deep-dives to sub-agents** (their context is
  separate; you only pay for the brief and the result).
- **Stop re-reading files you've already seen** — work from the
  conversation, not by re-loading state.
- **Batch tool calls** more aggressively and check progress less
  frequently. Polling a long-running task every 20 seconds at 500
  tokens per turn burns 90K tokens per hour for nothing; trust the
  background-task notification system and only poll on milestones.
- **Trim noisy diagnostics** — pipe big `Bash` outputs through
  `tail -N` or write them to disk for `Read` later, rather than
  pulling 30K lines through a `Bash` tool result.

Repeat the burn-rate check at each major milestone (a verification
finishing, a fix landing, a hypothesis confirmed). Adjust strategy
each time you measure.

### When the runway gets short, write before you stop

If projected runway falls below ~30 minutes:

1. Commit any incremental work that's confidently correct
2. Write a fresh `ai/.tmp/handoff-<date>.md` capturing the current
   state at full detail — this is the deliverable when the budget
   runs out
3. Then keep working, but with the handoff already in place. If
   you DO run out, the user wakes to a complete picture.

Do not silently absorb runway-shrinking events. If you have to
make a decision because of budget pressure ("I'd dig deeper here
but instead I'm going to commit and move on"), say so in a
progress message. The user reads those decisions to calibrate
the morning playbook.

## What "high-definition findings" means

Each finding the user wakes to should answer the question one level
deeper than the obvious one:

- Bad: "I bisected the divergence to the calibration computation."
- Better: "The calibration mean differs by 1 ULP cross-impl."
- High-definition: "The calibration mean differs by 1 ULP because the
  `sum/n` reduction is non-associative under SIMD vectorization;
  Welford's running mean has loop-carried deps that prevent
  vectorization, so it should fix it. I verified pass-1 inputs are
  bit-identical (17,187 fragments match exactly), implemented Welford
  in both impls, rebuilt, ran a single Astral file end-to-end. Pass-1
  cal mean is now bit-equal, pass-2 cal mean still drifts by 1 ULP —
  pass 2 picks a refined match set that differs cross-impl. I'm
  dumping pass-2 inputs now to confirm whether the per-fragment
  errors or the match selection is the residual source."

The high-def version tells the user *exactly what is known*, *what
specifically remains uncertain*, and *what experiment is in flight*.
That is what makes the next morning's decision easy.

## Operating posture

**Stop dead is the failure mode.** If you finish what you were doing
and the next step is "wait for the user," ask yourself: what *adjacent*
work is unblocked? Parallel investigation? Verification of an assumption
you've been treating as given? Cleanup of stale workdirs? Drafting the
follow-up commit message?

Specific anti-patterns to avoid:
- Wrapping up a finding into a clean report and stopping. Reports
  are worth ~5 minutes of context, not 5 hours.
- "I have enough analysis." You probably don't. Push one layer deeper.
- "I'll let the user decide between options A and B." If you can run
  the experiment to discriminate A from B in under an hour, **run it**.
  Decisions are cheaper than choice trees.
- Stopping because cycle time looks long. If a Rust+C# rebuild + Astral
  single-file run is 10 minutes, that's 6 cycles per hour. Plenty.
- Stopping because context is "only" at 60% free. Sessions never
  start at 100% — what matters is the burn rate against your
  *opening* reading and the time you have left. Run the projection
  (see "First step: measure your starting position" above) and act
  on the answer, don't act on a single percentage in isolation.

## When to use sub-agents

Use sub-agents to **conserve your own context budget** when:
- The investigation can be specified concretely and bounded in scope
- The agent's output will be a focused report or a code change you
  can verify, not raw debug logs
- You want to keep your own context for cross-thread synthesis

Anti-patterns for sub-agents:
- Asking an agent to "just figure out X" with no constraints — you'll
  get vague hand-waving
- Letting an agent run for hours with no status pings — explicitly
  tell it to report progress at named checkpoints
- Spawning an agent that will modify code without specifying
  *exactly* what to commit and what *not* to push

When you do spawn an agent in a night session:
1. Tell it explicitly that it's part of a night session and the
   parent context will check back in ~60-90 minutes
2. Require it to write a progress file at `ai/.tmp/agent-<id>-status.md`
   updated every major step, so the parent can pick up state if needed
3. Forbid `git push` and remind it that the parent will commit final
   state
4. Set a clear deliverable: "Return when X is verified, OR after
   2 hours, whichever comes first"

## When to commit and when not to

Default to **committing incrementally** during a night session, not
pushing. Every distinct insight (a new diagnostic, a structural fix,
a working verification) deserves a commit so the morning user can
read the history as a story. Use `pw-pcommit` style messages —
past-tense title, bulleted body, TODO reference.

Do not push during the night without explicit prior authorization.
The classifier blocks pushes for a reason: pushed changes are
externally visible and harder to undo than a local commit.

If you have a sequence of speculative changes, branch them locally
(`git switch -c nightlywork/<topic>`) so the morning user can choose
which to keep without rewriting history. But still prefer making
those commits on the working branch when the changes are clearly
incremental refinements of the same investigation.

## When to actually stop

Genuinely stop, not just pause-and-wait, when:
- The current investigation has converged to a single clear ask of
  the user that *cannot be resolved by more experiment* (e.g.,
  "should we ship a tolerance-loosening change or hold for the
  source-level fix?")
- You have spawned multiple sub-agents and you have no productive
  work to do until they return, AND the wait will exceed 30 minutes
- You hit a hard environmental block — out of disk, network down,
  binary that refuses to build despite multiple fix attempts
- Context budget is genuinely tight (under 15% remaining for 1M
  context, under 10% for 200K context) and continuing risks
  losing the synthesis you've built

When you stop, write a high-density handoff at
`ai/.tmp/handoff-<date>.md` and update the TODO with a postscript.
The handoff should let any reader (future you, the user, a fresh
agent) reconstruct exactly where things stand in 5 minutes of
reading.

**Close the session symmetrically with the way it opened.** Run
`pwsh -Command "Get-Date"` again and report, in your final message and
in the budget log, both the **stop time** and the **total elapsed
duration** (stop − start, from the start time you recorded in "First
step"). The user reads context-% to gauge the token cost of the session;
the stop time + duration gives them the wall-clock cost — report them
together. Do this even when you are stopping only because the budget ran
out (write the stop time into the handoff before you run dry), and even
when the user is awake and ending the session interactively.

## Reporting cadence

Send short status updates to the conversation every time you reach
a meaningful checkpoint:
- A bisection layer collapsed
- An experiment finished and produced new data
- A hypothesis was confirmed or eliminated
- A code change landed and was verified

Each update should:
- State the new finding in one sentence
- State what experiment is now in flight or what's next
- Not summarize what the user already knows

The morning user reads these updates as a timeline. Make it readable
as a story, not as a series of system outputs.

## Specific deep-dive heuristics

If you're investigating a numerical divergence (a sub-ULP / few-ULP
cross-impl drift):
- Are the inputs to the divergent computation bit-identical? Dump
  them at the rounding boundary and diff.
- Is the algorithm numerically stable for the operating regime?
  Welford > sum/n when the sum drifts far from the mean magnitude;
  Kahan compensated > naive sum when many small values feed a large
  running total.
- Is the compiler making a different code-gen choice (FMA vs
  multiply-add, SIMD vs scalar, reassociation under unsafe-math)?
  In Rust, `cargo rustc --release -- --emit=asm` for hot loops; in
  .NET, `dotnet build /p:JitDisasm=*` or DOTNET_JitDisasmSummary.
- Is there a loop-carried dependency that *should* prevent
  vectorization but isn't being respected? Add an explicit
  `core::hint::black_box` (Rust) or `MethodImplOptions.NoInlining`
  (C#) on the inner step to force serial execution and check if the
  divergence vanishes.

If you're investigating a structural divergence (different cells,
different sort order, different match set):
- Dump the boundary state on both sides at the same checkpoint and
  diff. Use a common canonical format (G17-roundtrip in C#, ryu
  default in Rust; parse-back numerically for comparison, not
  byte-equal).
- Sort divergent rows by score-asc (or whatever rank field) and
  look at the *first* divergent row — is it at a boundary value?
  ULP-close to a threshold? Tied with another row whose tie-break
  is non-deterministic?
- Trace one specific divergent entity (entry_id, scan, peptide) all
  the way back to where the impls produce different outputs for
  that entity. Don't stop at "the set differs by 12 entries" —
  *which 12*, and *why each*.

## Memory: what to write down for future night sessions

If the user gives you new directives during a night session about how
they want night sessions to operate, save them as `feedback` memory
under `feedback_night_session_*.md` and link from MEMORY.md. This
skill is the durable doctrine; memory captures user-specific
preferences that refine the default behavior.
