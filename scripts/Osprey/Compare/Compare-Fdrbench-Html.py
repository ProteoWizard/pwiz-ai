#!/usr/bin/env python3
"""
Compare-Fdrbench-Html.py -- validate the Osprey --model-diagnostics HTML FDR
calibration against FDRBench's own fdp.csv on the SAME run.

One Osprey binary emits both the interactive HTML report and the FDRBench input
TSV (--model-diagnostics --fdrbench <tsv> [--fdrbench-pass 1|2]). This script
runs the FDRBench jar on that TSV and diffs the resulting fdp.csv against the
experiment-scope FDP view embedded in the HTML, at a set of q thresholds. The
experiment-scope view is the one that is supposed to reproduce FDRBench (FDRBench
merely passes Osprey's own q through); the per-run view is a separate picture.

Usage:
  python Compare-Fdrbench-Html.py --dir <run-output-dir> \
      --manifest <pairing.tsv> [--jar <fdrbench.jar>] [--no-jar] [--pass 1]

--no-jar reuses an existing <stem>_fdp.csv instead of re-running the jar.

Exit code 0 when every checked q point matches within tolerance, else 1.
"""
import argparse, bisect, csv, glob, json, os, re, subprocess, sys

# q thresholds to report and gate on.
Q_POINTS = [0.001, 0.002, 0.003, 0.005, 0.008, 0.01, 0.015, 0.02]
# Gate tolerance (absolute, in FDP fraction) at the q points that both grids
# land on cleanly. Off-grid points differ only by curve sampling and are shown
# for context but not gated.
GATE_Q = [0.001, 0.002, 0.005, 0.01, 0.02]
GATE_TOL = 5e-4  # 0.05 percentage points


def find_one(dir_, pattern):
    hits = glob.glob(os.path.join(dir_, pattern))
    if not hits:
        sys.exit(f"ERROR: no file matching {pattern} in {dir_}")
    if len(hits) > 1:
        sys.exit(f"ERROR: multiple files match {pattern} in {dir_}: {hits}")
    return hits[0]


def run_jar(jar, tsv, manifest, out_csv):
    cmd = ["java", "-Xmx8G", "-jar", jar, "-i", tsv, "-level", "precursor",
           "-score", "score:1", "-pep", manifest, "-entrapment_label",
           "_p_target", "-o", out_csv]
    print("Running FDRBench: " + " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if re.search(r"Invalid|unique FDR|Error", line):
            print("  " + line)
    if r.returncode != 0:
        print(r.stderr[-2000:])
        sys.exit(f"ERROR: FDRBench jar exited {r.returncode}")


def load_html(html_path):
    html = open(html_path, encoding="utf-8").read()
    m = re.search(r'<script[^>]*id="osprey-data"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        sys.exit("ERROR: no osprey-data script block in HTML")
    D = json.loads(m.group(1).strip())
    views = D.get("fdpViews") or []
    exp = [v for v in views if v.get("scope") == "experiment"]
    if not exp:
        sys.exit("ERROR: no experiment-scope FDP view in HTML (no entrapment?)")
    return exp[0]


def load_golden(csv_path):
    rows = []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            rows.append((float(row["q_value"]), float(row["combined_fdp"]),
                         float(row["lower_bound_fdp"]), float(row["paired_fdp"]),
                         int(row["n_t"]), int(row["n_p"])))
    rows.sort(key=lambda r: r[0])
    return rows


def sample(qs, arr, thr):
    i = bisect.bisect_right(qs, thr) - 1
    return (qs[i], arr[i]) if i >= 0 else (None, None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="Run output dir with HTML + *_fdrbench.tsv")
    ap.add_argument("--manifest", default=None,
                    help="Fallback external pairing manifest (used only if Osprey's "
                         "<tsv>.pairing.tsv is absent)")
    ap.add_argument("--jar", default="D:/test/fdrbench/fdrbench-1.1.1/fdrbench-1.1.1.jar")
    ap.add_argument("--no-jar", action="store_true", help="Reuse existing *_fdp.csv")
    ap.add_argument("--pass", dest="pass_", default=None, help="Label only (1 or 2)")
    args = ap.parse_args()

    tsv = find_one(args.dir, "*_fdrbench.tsv")
    html = find_one(args.dir, "*.model-diagnostics.html")
    stem = re.sub(r"_fdrbench\.tsv$", "", os.path.basename(tsv))
    fdp_csv = os.path.join(args.dir, stem + "_fdp.csv")

    # Prefer the pairing manifest Osprey emits from the searched library (complete
    # by construction, so FDRBench drops nothing) over an external manifest.
    emitted = tsv + ".pairing.tsv"
    manifest = emitted if os.path.exists(emitted) else args.manifest
    print(f"Using pairing manifest: {manifest}"
          + ("  (Osprey-emitted, library-derived)" if manifest == emitted else "  (external)"))

    if not args.no_jar:
        run_jar(args.jar, tsv, manifest, fdp_csv)
    elif not os.path.exists(fdp_csv):
        sys.exit(f"ERROR: --no-jar but {fdp_csv} does not exist")

    exp = load_html(html)
    Q, comb, lb = exp["q"], exp["combined"], exp["lowerBound"]
    paired, nt = exp.get("paired"), exp["nTargetAccepted"]
    golden = load_golden(fdp_csv)
    gq = [r[0] for r in golden]

    print(f"\n=== {stem} (pass {args.pass_ or '?'}) HTML vs FDRBench fdp.csv ===")
    print(f"HTML experiment view: {len(Q)} points, ratio={exp.get('entrapmentRatio'):.4f}")
    hdr = f"{'q':>7} | {'HTML  comb   low   pair   (n_t)':>34} | {'FDRBench comb   low   pair (n_t/n_p)':>38} | gate"
    print(hdr); print("-" * len(hdr))
    ok = True
    for thr in Q_POINTS:
        mq, mc = sample(Q, comb, thr); _, ml = sample(Q, lb, thr)
        _, mp = sample(Q, paired, thr); _, mnt = sample(Q, nt, thr)
        gi = bisect.bisect_right(gq, thr) - 1
        _, gc, gl, gp, gnt, gnp = golden[gi]
        gate = ""
        if thr in GATE_Q:
            d = abs(mc - gc)
            gate = "PASS" if d <= GATE_TOL else f"FAIL d={d*100:.3f}pp"
            if d > GATE_TOL:
                ok = False
        print(f"{thr:>7.3f} | {mc*100:6.3f} {ml*100:6.3f} {mp*100:6.3f} ({mnt:6d}) | "
              f"{gc*100:6.3f} {gl*100:6.3f} {gp*100:6.3f} ({gnt:6d}/{gnp:4d}) | {gate}")
    print("\n" + ("RESULT: MATCH" if ok else "RESULT: MISMATCH"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
