"""Scan skyline.ms nightly run logs for TestRunner process crashes, per computer.

A TestRunner process crash (the run log contains "Process TestRunner had nonzero exit
code") ends a run early. This script finds every early-ending run in the six nightly
folders, downloads its stored log (gzip in testresults.testruns.log), and records the
exit code. It then separates:

  - shared-build days: 3+ computers crashed the same day -> almost always a software bug
  - solo crashes: only this computer crashed that day   -> the failing-hardware signal

See ai/docs/failing-hardware-detection.md for how to interpret the output.

Usage (from the repo root, same Python env as the LabKey MCP server; auth via _netrc):
    python ai/mcp/LabKeyMcp/scripts/scan_testrunner_crashes.py --since 2026-06-01
    python ai/mcp/LabKeyMcp/scripts/scan_testrunner_crashes.py --since 2017-10-01 --out ai/.tmp/crash-scan.csv
    python ai/mcp/LabKeyMcp/scripts/scan_testrunner_crashes.py --since 2026-01-01 --computer SKYLINE-DEV6

--computer limits the per-computer summary, but all computers are always scanned, because
telling solo crashes from shared-build days needs every machine's crashes.
"""
import argparse
import csv
import gzip
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from urllib.parse import quote, urlencode

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.common import make_authenticated_request  # noqa: E402

SERVER = "skyline.ms"
# folder -> scheduled duration (minutes); runs shorter than duration-10 are candidates
FOLDERS = {
    "Nightly x64": 540, "Release Branch": 540, "Integration": 540,
    "Performance Tests": 720, "Release Branch Performance Tests": 720, "Integration With Perf Tests": 720,
}
HARDWARE_CODES = {
    "-1073741819": "ACCESS_VIOLATION",       # 0xC0000005
    "-1073741795": "ILLEGAL_INSTRUCTION",    # 0xC000001D
    "-1073741571": "STACK_OVERFLOW",         # 0xC00000FD
    "-1073740940": "HEAP_CORRUPTION",        # 0xC0000374
    "-1073740791": "STACK_BUFFER_OVERRUN",   # 0xC0000409 (also used for fail-fast)
}
OTHER_CODES = {"-532462766": "CLR_EXCEPTION", "-1": "MINUS_ONE", "1": "ONE"}
RE_EXIT = re.compile(r"Process TestRunner had nonzero exit code (-?\d+)")
RE_TEST = re.compile(r"^\[\d\d:\d\d\]\s+\d+\.\d+\s+(\S+)", re.M)
BATCH = 25


def api(folder, params):
    url = f"https://{SERVER}/{quote('home/development/' + folder)}/query-selectRows.api?{urlencode(params)}"
    return json.loads(make_authenticated_request(SERVER, url, timeout=300))["rows"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", required=True, help="YYYY-MM-DD (logs are stored from Oct 2017)")
    ap.add_argument("--computer", help="only summarize this computer")
    ap.add_argument("--out", help="CSV of every scanned run")
    a = ap.parse_args()

    runs = []
    for folder, sched in FOLDERS.items():
        rows = api(folder, {"schemaName": "testresults", "query.queryName": "testruns",
                            "query.columns": "id,userid/username,posttime,duration",
                            "query.duration~lt": str(sched - 10), "query.posttime~gte": a.since,
                            "query.maxRows": "100000"})
        for r in rows:
            runs.append({"folder": folder, "id": str(r["id"]), "computer": r["userid/username"],
                         "post": r["posttime"], "duration": r["duration"]})
    print(f"{len(runs)} early-ending runs since {a.since}", file=sys.stderr)

    by_folder = defaultdict(list)
    for r in runs:
        by_folder[r["folder"]].append(r)
    for folder, lst in by_folder.items():
        for i in range(0, len(lst), BATCH):
            chunk = lst[i:i + BATCH]
            got = {str(x["id"]): x.get("log") for x in api(folder, {
                "schemaName": "testresults", "query.queryName": "testruns", "query.columns": "id,log",
                "query.id~in": ";".join(c["id"] for c in chunk), "query.maxRows": str(len(chunk))})}
            for c in chunk:
                raw, c["code"], c["last_test"] = got.get(c["id"]), "", ""
                if not raw:
                    c["code"] = "NO_LOG"
                    continue
                data = bytes((b + 256) % 256 for b in raw) if isinstance(raw, list) else raw.encode("latin-1")
                text = gzip.decompress(data).decode("utf-8", "replace")
                m = RE_EXIT.findall(text)
                if m:
                    c["code"] = HARDWARE_CODES.get(m[-1]) or OTHER_CODES.get(m[-1], m[-1])
                t = RE_TEST.findall(text)
                c["last_test"] = t[-1] if t else ""
            print(f"  {folder}: {min(i + BATCH, len(lst))}/{len(lst)}", file=sys.stderr)

    hw = [r for r in runs if r["code"] in HARDWARE_CODES.values()]
    day_machines = defaultdict(set)
    for r in hw:
        day_machines[r["post"][:10]].add(r["computer"])
    for r in runs:
        r["shared_day"] = len(day_machines.get(r["post"][:10], ())) >= 3

    if a.out:
        with open(a.out, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["folder", "id", "computer", "post", "duration", "code", "last_test", "shared_day"])
            w.writeheader()
            w.writerows(runs)

    print("\nShared-build crash days (3+ computers):")
    for d, ms in sorted(day_machines.items()):
        if len(ms) >= 3:
            print(f"  {d}: {', '.join(sorted(ms))}")

    print("\nHardware-type TestRunner crashes by computer (solo = no other computer crashed that day):")
    per = defaultdict(list)
    for r in hw:
        per[r["computer"]].append(r)
    for comp, lst in sorted(per.items(), key=lambda kv: -len(kv[1])):
        if a.computer and comp != a.computer:
            continue
        solo = [r for r in lst if not r["shared_day"]]
        days = sorted({r["post"][:10] for r in lst})
        solo_days = len({r["post"][:10] for r in solo})
        tests = defaultdict(int)
        for r in solo:
            tests[r["last_test"]] += 1
        top_share = max(tests.values()) / len(solo) if solo else 0
        flag = ""
        if solo_days >= 2 and top_share < 0.5:
            flag = "  <-- HARDWARE PATTERN: solo crashes in unrelated tests"
        elif solo_days >= 2:
            top = max(tests, key=tests.get)
            flag = f"  <-- SAME-TEST PATTERN: {tests[top]}/{len(solo)} in {top} (test/resource issue first)"
        print(f"  {comp:<16} total={len(lst):3} solo={len(solo):3} tests={len(tests):2}  {days[0]} .. {days[-1]}{flag}")
        for r in sorted(solo, key=lambda r: r["post"])[-5:]:
            print(f"      {r['post'][:16]}  {r['code']:<20} run {r['id']} ({r['folder']})  last test: {r['last_test']}")


if __name__ == "__main__":
    main()
