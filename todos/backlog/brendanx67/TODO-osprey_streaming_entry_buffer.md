# TODO-osprey_streaming_entry_buffer.md -- Fail-fast (and optionally windowed) entry buffer for the streaming FDR path

## Problem

The Osprey memory campaign turned several large resident buffers into streamed/released
ones, but the *type* stayed a plain `List<FdrEntry>`, which cannot distinguish "legitimately
empty" from "released / never-materialized." That makes misuse **silently wrong** instead of
a crash:

- **#4400 (#4397) lean path**: `PerFileScoringTask` publishes an **empty** `List<FdrEntry>`
  per file (to keep the per-file key + file-count guard) while the real rows are streamed
  straight into an `FdrProjectionSet`. A consumer that reads *rows* off `ScoredEntries` on
  that path gets nothing -> fewer IDs / zeroed areas, no error.
- **#4378 `BuildFromEntries(releaseStubs: true)`**: each file's stub list is `Clear()`ed the
  instant its projection rows are built. A later reader of a cleared file sees an empty list.
- **#4394**: per-file rescore transients nulled after use.

Today the "nobody reads these rows anymore" invariant is enforced only by a comment + a
human reading the consumers + the byte-identical regression staying green. This is exactly
the `feedback_hard_fail_over_warn_proceed` case: proceeding on invalid state silently
produces output a user would trust. Make it fail loud at the point of misuse.

Origin: raised by Brendan off the #4400 review question "does anything read the
progressively-nulled/empty buffer and get taken by surprise?" -- see #4400 (#4397).

## Design: a fail-fast `PerFileEntryBuffer`

Replace the bare `List<FdrEntry>` value in `List<KeyValuePair<string, List<FdrEntry>>>`
(threaded through `PerFileScoringTask` / `FirstJoinTask` and consumers) with a small buffer
type carrying an explicit state:

- **Materialized** -- wraps a real `List<FdrEntry>`; full access. Used by the resident path,
  rehydrate/merge, `--model-diagnostics`, and FDRBench pass 1.
- **Projected / Released** -- holds only the row **count** (+ the file key). Metadata access
  (`Count`, key, enumerating *files*) is allowed -- the file-count guard and the hand-off
  need it -- but the **row indexer / `GetEnumerator` throw**
  `InvalidOperationException("first-pass rows were streamed to the FdrProjection and never
  materialized as FdrEntry; read FdrProjectionSet, not ScoredEntries")`.

Key design point: **separate metadata access (allowed) from row access (throws)** -- that is
what lets the lean path keep publishing counts/keys while any stray *row* consumer surfaces
itself immediately, with a message that names the fix. This converts the #4400 review's
"verified by reading" into "enforced by the type," and retrofits the same guard onto
#4378/#4394's release points so the whole streaming family gets the tripwire.

Cost: `perFileEntries` is typed `List<KeyValuePair<string, List<FdrEntry>>>` throughout the
join; slotting the class in means changing the value type to an interface
(`IReadOnlyList<FdrEntry>` or the buffer type) across the producers/consumers. Bounded and
mechanical; gated byte-identical by `regression.ps1`.

Sequencing: **do this AFTER #4400 merges** -- keep #4400 focused (it is reviewed, retargeted
to master, byte-identical). This is a separate hardening PR that can also retrofit
#4378/#4394.

## Gates (any change here)

- Correctness: `regression.ps1 -Dataset Stellar` (and `-Dataset All` before a behaviour/perf
  merge) byte-identical, 1e-9 -- every step above is intended to be pure representation, not
  output.
- Perf: `Test-PerfGate.ps1` -- a windowed/paged access change is exactly the kind that can
  slow scoring; confirm no regression.
- Memory: `OSPREY_LOG_MEMORY` `[MEM ...]` post-GC probes are the before/after numbers.

## Related
- #4400 / #4397 (lean FDR-stub streaming -- the change that motivated this), #4378 (#4355/#4374
  releaseStubs), #4394 (#4376 reconciliation transients).
- [[reference_osprey_systemmemory_local_inspection_red]] is unrelated; the memory-lever sibling
  is `TODO-osprey_library_fragment_array_compaction.md` (flat fragment array + ChromHeaderInfo
  Fast file I/O block reads via portable Span/RandomAccess).
- Principle: fail loud on silently-invalid state (`feedback_hard_fail_over_warn_proceed`);
  structural-debt cadence (`project_osprey_organic_growth_needs_iterative_oop_review`).
