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

## Design 1 (near-term, low-risk): a fail-fast `PerFileEntryBuffer`

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

## Design 2 (further memory lever): a windowed ring buffer -- ONLY where access is sequential

Brendan's ring-buffer idea for the case where a stage must process a large logical sequence
in order but only needs a bounded window resident at once. Present a sliding window over a
hypothetical large array with three scalars:

- `startListIndex`  -- global index of the window's first entry,
- `countEntries`    -- entries currently resident,
- `startEntryIndex` -- physical head in the small backing array,
- address global index `g` at physical slot `(startEntryIndex + (g - startListIndex)) % capacity`.

This is a correct, standard circular buffer. Refinements:
- **Power-of-two capacity + `& (capacity - 1)`** instead of `%` on the hot path (millions of
  rows) -- avoids integer division.
- **Slot type must be the LEAN element (a struct: `FdrProjection`, or raw scalars), NOT the
  fat `FdrEntry` class.** Then the backing `T[]` is inline; advancing the window just
  **overwrites** slots -- zero GC, no nulling. Nulling only matters if the array stays a
  class array, which defeats the memory goal.
- **Precondition: forward-sequential (monotonic) access only.** A window + throw-on-miss is
  correct for streaming; it breaks or thrashes under random/backward access. So this is the
  right tool **iff** we can name a consumer whose access to these entries is strictly
  ordered. Do NOT build it speculatively -- identify the sequential consumer first, else it
  is complexity without payoff.
- Out-of-window access: **throw** (tripwire) if the consumer is supposed to be sequential;
  **page-in from the backing store** (parquet) only if a bounded look-back is genuinely
  needed. Note `ParquetScoreCache` already yields **one row-group at a time**
  (`ReadFdrStubScalars`), which is a coarser natural "window" that may remove the need to
  hand-roll a ring at all -- prefer processing at the storage's own chunk grain if the
  consumer allows it.

Unify: Design 1's buffer interface (`Count` + defined-throw row access) is the seam; the ring
buffer is just a third implementation (`Windowed`) behind it. #4400 needs only Materialized +
Projected; Windowed is the future lever.

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
