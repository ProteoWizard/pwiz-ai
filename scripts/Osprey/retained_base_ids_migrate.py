#!/usr/bin/env python3
"""One-time migration: build `<stem>.1st-pass.retained_base_ids.bin` for a run directory
produced BEFORE that artifact existed.

WHY THIS IS A SEPARATE TOOL AND NOT A FALLBACK IN OSPREY
--------------------------------------------------------
The retained base_id summary is what lets `--task PerFileRescoring` compact one run without
reading every other run's `reconciliation.json`. Osprey therefore HARD-FAILS when it is
missing, on purpose: a silent fallback to rebuilding the union from all N envelopes is exactly
the O(files) pre-pass the artifact exists to delete, and a quiet degradation back onto it would
restore the behaviour with no signal that it had happened.

That refusal is right for the search binary and wrong as a reason to re-run a FirstPassFDR that
already succeeded (5h13m on the 446-run CHS cohort). So the migration is a NAMED, EXPLICIT,
run-once operation that does the expensive thing deliberately, in a tool whose only job is that.
It does not belong on any hot path and should never be called from one.

WHAT IT COMPUTES
----------------
Exactly what `FirstPassFdrTask.PlanStage6` accumulates while planning:

    retained = first_pass_base_ids  UNION  { entry_id & 0x7FFFFFFF : every planned action target }

`first_pass_base_ids` is join-wide and byte-identical in every envelope, so it is read once from
the first file. The action targets are per-run, so every envelope must be visited - which is the
whole cost, and why this is a migration rather than something to do routinely.

Base_ids are masked to strip the decoy bit, matching `ScoringTaskShared.BASE_ID_MASK`: a target
and its paired decoy share a base_id, so retaining the base_id keeps both and preserves the
target-decoy invariant.

FORMAT (little-endian), mirroring Osprey.IO/RetainedBaseIdSidecar.cs
--------------------------------------------------------------------
    magic         [0..8]   = b"OSPRYRET"
    version       [8]      = u8 (= 1)
    pass          [9]      = u8 (= 1, first-pass)
    reserved      [10..16] = 6 zero bytes
    base_id_count [16..24] = u64
    reserved      [24..32] = 8 zero bytes
    body          [32..]   = base_id_count * u32, ASCENDING

Ascending order is required: the file has to be a function of its contents rather than of the
order the producer walked its inputs, because the regression gate compares the straight-through
and distributed artifacts byte for byte.

USAGE
-----
    python retained_base_ids_migrate.py <run-dir> [--blib-stem out] [--dry-run]

Writes `<run-dir>/<blib-stem>.1st-pass.retained_base_ids.bin`. Refuses to overwrite an existing
file - a directory that already has one was written by a build that produces it, and silently
replacing that would substitute this script's arithmetic for Osprey's own.
"""

import argparse
import json
import os
import struct
import sys
import time

BASE_ID_MASK = 0x7FFFFFFF
MAGIC = b"OSPRYRET"
FORMAT_VERSION = 1
PASS_FIRST = 1
HEADER_LENGTH = 32
ACTION_KEYS = ("forced_integration_actions", "use_cwt_peak_actions")


def build_retained(run_dir):
    """Return (retained_set, n_envelopes, n_action_targets_outside_global)."""
    envelopes = sorted(
        f for f in os.listdir(run_dir) if f.endswith(".reconciliation.json")
    )
    if not envelopes:
        raise SystemExit("no *.reconciliation.json in %s - is this a FirstPassFDR run dir?"
                         % run_dir)

    retained = set()
    global_ids = None
    started = time.time()
    for i, name in enumerate(envelopes, 1):
        with open(os.path.join(run_dir, name), "r") as handle:
            envelope = json.load(handle)
        if global_ids is None:
            # Join-wide and identical in every envelope by construction, so read it once.
            global_ids = set(envelope["first_pass_base_ids"])
            retained |= global_ids
        for key in ACTION_KEYS:
            for action in envelope.get(key) or []:
                retained.add(action["entry_id"] & BASE_ID_MASK)
        if i % 25 == 0 or i == len(envelopes):
            print("  %d/%d envelopes, %d base_ids, %.0fs elapsed"
                  % (i, len(envelopes), len(retained), time.time() - started))
    return retained, len(envelopes), len(retained) - len(global_ids)


def write_summary(path, retained):
    ids = sorted(retained)
    with open(path, "wb") as handle:
        handle.write(MAGIC)
        handle.write(struct.pack("<BB", FORMAT_VERSION, PASS_FIRST))
        handle.write(b"\x00" * 6)
        handle.write(struct.pack("<Q", len(ids)))
        handle.write(b"\x00" * 8)
        handle.write(struct.pack("<%dI" % len(ids), *ids))
    return HEADER_LENGTH + 4 * len(ids)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_dir")
    parser.add_argument("--blib-stem", default="out",
                        help="stem of the run's output blib (default: out)")
    parser.add_argument("--dry-run", action="store_true",
                        help="compute and report, write nothing")
    args = parser.parse_args()

    out_path = os.path.join(args.run_dir,
                            "%s.1st-pass.retained_base_ids.bin" % args.blib_stem)
    if os.path.exists(out_path) and not args.dry_run:
        raise SystemExit("refusing to overwrite %s - it was written by a build that produces "
                         "it, and this script's arithmetic must not silently replace Osprey's"
                         % out_path)

    retained, n_env, n_extra = build_retained(args.run_dir)
    print("envelopes read      : %d" % n_env)
    print("retained base_ids   : %d" % len(retained))
    print("action targets NOT already in the join-wide set: %d" % n_extra)
    if n_extra == 0:
        # Worth stating rather than leaving to be rediscovered: it means the planner emitted
        # actions only for entries that already pass the join-wide gate, so the union term added
        # nothing on THIS cohort. It is not guaranteed on another one.
        print("  (the union term added nothing here - every action target already passed)")

    if args.dry_run:
        print("--dry-run: not writing %s" % out_path)
        return 0
    size = write_summary(out_path, retained)
    print("wrote %s (%d bytes)" % (out_path, size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
