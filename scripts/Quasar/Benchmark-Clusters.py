"""Cluster benchmark (Quasar spec, Validation): Quasar's clusters against Osprey's precursors, no search.

For each Osprey precursor passing the run q-value threshold in this run, inside the m/z range of the
window, look at the Quasar clusters whose template apex lies inside Osprey's peak boundaries, and
find the one holding the most of the precursor's library fragments. Reports:

  * completeness: how many of the precursor's library fragments that best cluster holds;
  * purity: the share of that cluster's member area made of the precursor's fragments;
  * whether that cluster was accepted, how far its apex is from Osprey's, and how many Osprey
    precursors share it (co-eluting, chimeric clusters).

A library fragment matches a centroid member within the ppm tolerance, or an anchor member (stored at
its singly charged monoisotopic m/z) when the fragment's m/z at charge 1 or 2 converts to it.

Standard library only:

    python -I Benchmark-Clusters.py --clusters <clusters.tsv> --blib <osprey.blib> --stem <run>
        --mz-range 643.54-646.54 [--q 0.01] [--ppm 10]

The clusters TSV has one row per member: cluster, accepted, mode (minutes), trace, mz, anchor (0/1),
charge, amplitude, shared.
"""
import argparse
import csv
import sqlite3
import statistics
import struct
import zlib
from collections import defaultdict

PROTON = 1.007276467


def decode(blob, count, fmt, width):
    if len(blob) != count * width:
        blob = zlib.decompress(blob)
    return struct.unpack(f"<{count}{fmt}", blob)


def read_clusters(path):
    clusters = {}
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            cid = int(row["cluster"])
            c = clusters.setdefault(cid, {"accepted": row["accepted"] == "1", "mode": float(row["mode"]), "members": []})
            c["members"].append((float(row["mz"]), row["anchor"] == "1", float(row["amplitude"])))
    return clusters


def read_osprey(blib, stem, low, high, q):
    db = sqlite3.connect(f"file:{blib}?mode=ro", uri=True)
    rows = db.execute(
        """select r.id, r.peptideModSeq, r.precursorMZ, r.precursorCharge, r.numPeaks, p.peakMZ,
                  b.StartRT, b.EndRT, b.ApexRT
           from RefSpectra r
           join RefSpectraPeaks p on p.RefSpectraID = r.id
           join OspreyRunScores s on s.RefSpectraID = r.id
           join OspreyPeakBoundaries b on b.RefSpectraID = r.id and b.FileName = s.FileName
           where s.FileName like ? and s.RunQValue <= ? and r.precursorMZ >= ? and r.precursorMZ < ?""",
        (f"%{stem}%", q, low, high)).fetchall()
    return [{"id": r[0], "peptide": r[1], "mz": r[2], "charge": r[3],
             "fragments": decode(r[5], r[4], "d", 8), "start": r[6], "end": r[7], "apex": r[8]} for r in rows]


def read_traces(path):
    """Quasar TraceFile (Quasar.Core/Traces/TraceFile.cs): scan times and sparse traces."""
    with open(path, "rb") as handle:
        data = handle.read()
    pos = 0

    def take(fmt):
        nonlocal pos
        values = struct.unpack_from("<" + fmt, data, pos)
        pos += struct.calcsize("<" + fmt)
        return values

    magic, version = take("Ii")
    if magic != 0x51545246 or version != 1:
        raise ValueError("not a Quasar trace file: " + path)
    take("ddd")
    (scan_count,) = take("i")
    rt = take(f"{scan_count}d")
    (trace_count,) = take("i")
    traces = []
    for _ in range(trace_count):
        trace_id, = take("i")
        is_anchor, = take("?")
        mz, = take("d")
        take("i")
        (count,) = take("i")
        points = [take("id") for _ in range(count)]
        traces.append((trace_id, is_anchor, mz, points))
    return rt, traces


def observable(precursor, rt, traces, ppm):
    """Library fragments seen in any trace with signal inside Osprey's boundaries."""
    seen = set()
    for _, anchor, mz, points in traces:
        if not any(precursor["start"] <= rt[i] <= precursor["end"] for i, _ in points):
            continue
        for i, f in enumerate(precursor["fragments"]):
            if matches(f, mz, anchor, ppm):
                seen.add(i)
    return seen


def matches(fragment_mz, member_mz, is_anchor, ppm):
    if not is_anchor:
        return abs(member_mz - fragment_mz) <= member_mz * ppm * 1e-6
    for z in (1, 2):
        mono_1plus = (fragment_mz - PROTON) * z + PROTON
        if abs(member_mz - mono_1plus) <= member_mz * ppm * 1e-6:
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--clusters", required=True)
    parser.add_argument("--blib", required=True)
    parser.add_argument("--stem", required=True)
    parser.add_argument("--mz-range", required=True, help="isolation window, low-high")
    parser.add_argument("--q", type=float, default=0.01)
    parser.add_argument("--ppm", type=float, default=10.0)
    parser.add_argument("--traces", help="the window's Quasar trace file, to count fragments seen in any trace")
    args = parser.parse_args()
    low, high = (float(v) for v in args.mz_range.split("-"))

    clusters = read_clusters(args.clusters)
    precursors = read_osprey(args.blib, args.stem, low, high, args.q)
    rt, traces = read_traces(args.traces) if args.traces else (None, None)
    results = []
    best_of = defaultdict(list)
    spread = []
    seen_counts = []
    for p in precursors:
        if traces is not None:
            seen_counts.append(len(observable(p, rt, traces, args.ppm)))
        holding = 0
        best = None
        for cid, c in clusters.items():
            if not (p["start"] <= c["mode"] <= p["end"]):
                continue
            matched = set()
            matched_area = 0.0
            for mz, anchor, amp in c["members"]:
                hit = [i for i, f in enumerate(p["fragments"]) if matches(f, mz, anchor, args.ppm)]
                if hit:
                    matched.update(hit)
                    matched_area += amp
            total = sum(m[2] for m in c["members"])
            if matched:
                holding += 1
            key = (len(matched), matched_area)
            if best is None or key > best["key"]:
                best = {"key": key, "cluster": cid, "matched": len(matched),
                        "purity": matched_area / total if total > 0 else 0.0,
                        "accepted": c["accepted"], "apex_s": abs(c["mode"] - p["apex"]) * 60.0,
                        "members": len(c["members"])}
        results.append((p, best))
        spread.append(holding)
        if best is not None and best["matched"] > 0:
            best_of[best["cluster"]].append(p["id"])

    n = len(results)
    found = [b for _, b in results if b is not None]
    print(f"{n} Osprey precursors at q <= {args.q} in m/z {low}-{high}; {len(clusters)} Quasar clusters "
          f"({sum(c['accepted'] for c in clusters.values())} accepted)")
    print(f"  no cluster apex inside Osprey's boundaries: {n - len(found)}")
    for k in (1, 3, 6, 10):
        count = sum(1 for b in found if b["matched"] >= k)
        print(f"  best cluster holds >= {k:2d} of 20 library fragments: {count} ({count / n:.0%})")
    good = [b for b in found if b["matched"] >= 3]
    if good:
        print(f"  of those with >= 3: accepted {sum(b['accepted'] for b in good) / len(good):.0%}; "
              f"median fragments {statistics.median(b['matched'] for b in good)}; "
              f"median purity {statistics.median(b['purity'] for b in good):.2f}; "
              f"median apex difference {statistics.median(b['apex_s'] for b in good):.1f} s; "
              f"median members {statistics.median(b['members'] for b in good)}")
        shared = sum(1 for b in good if len(best_of[b["cluster"]]) > 1)
        print(f"  best cluster shared with another Osprey precursor: {shared} ({shared / len(good):.0%})")
    print(f"  clusters (apex inside the boundaries) holding any of a precursor's fragments: "
          f"median {statistics.median(spread)}, 90th percentile {sorted(spread)[int(0.9 * (len(spread) - 1))]}")
    if seen_counts:
        print(f"  library fragments seen in any trace inside the boundaries: median {statistics.median(seen_counts)} "
              f"of 20; >= 6 for {sum(1 for s in seen_counts if s >= 6) / n:.0%} of precursors")
        held = [b["matched"] if b else 0 for _, b in results]
        ratio = [h / s for h, s in zip(held, seen_counts) if s > 0]
        print(f"  best cluster's share of the seen fragments: median {statistics.median(ratio):.2f}")
    composition(results, precursors, clusters, args.ppm)


def composition(results, precursors, clusters, ppm):
    """What the members of each precursor's best cluster (>= 3 fragments) are, by count and area."""
    kinds = ("fragment", "isotope", "other precursor", "unexplained")
    counts = {k: [] for k in kinds}
    areas = {k: [] for k in kinds}
    for p, best in results:
        if best is None or best["matched"] < 3:
            continue
        c = clusters[best["cluster"]]
        others = [o for o in precursors if o["id"] != p["id"] and o["start"] <= c["mode"] <= o["end"]]
        own = [(mz, anchor) for mz, anchor, _ in c["members"]
               if any(matches(f, mz, anchor, ppm) for f in p["fragments"])]
        tally_n = dict.fromkeys(kinds, 0)
        tally_a = dict.fromkeys(kinds, 0.0)
        for mz, anchor, amp in c["members"]:
            if any(matches(f, mz, anchor, ppm) for f in p["fragments"]):
                kind = "fragment"
            elif not anchor and any(not a and any(abs(mz - (m + n * 1.003355 / z)) <= mz * ppm * 1e-6
                                                  for n in (1, 2) for z in (1, 2)) for m, a in own):
                kind = "isotope"
            elif any(matches(f, mz, anchor, ppm) for o in others for f in o["fragments"]):
                kind = "other precursor"
            else:
                kind = "unexplained"
            tally_n[kind] += 1
            tally_a[kind] += amp
        total_n = sum(tally_n.values())
        total_a = sum(tally_a.values())
        for k in kinds:
            counts[k].append(tally_n[k] / total_n)
            areas[k].append(tally_a[k] / total_a if total_a > 0 else 0.0)
    if not counts["fragment"]:
        return
    print("  members of the best clusters with >= 3 fragments, median share by count / by area:")
    for k in kinds:
        print(f"    {k:16s} {statistics.median(counts[k]):.2f} / {statistics.median(areas[k]):.2f}")


if __name__ == "__main__":
    main()
