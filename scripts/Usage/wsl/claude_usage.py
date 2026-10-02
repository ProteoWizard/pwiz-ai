#!/usr/bin/env python3
"""WSL/Linux port of the Claude usage snapshot tooling (see ../README.md).

Produces the same data/usage_<MACHINE>.csv format as Snapshot-ClaudeUsage.ps1 and the same
usage_combined.csv as Combine-ClaudeUsage.ps1, so WSL machines feed the shared team store
alongside Windows machines. Pricing is read from Snapshot-ClaudeUsage.ps1 ($Rates) so the
two implementations cannot drift.

Subcommands:
    resolve   print the store path and whether it is the SHARED team store
    snapshot  parse ~/.claude/projects transcripts -> <store>/data/usage_<MACHINE>.csv
    combine   union all usage_*.csv -> <store>/data/usage_combined.csv
"""
import argparse
import csv
import glob
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PS_SNAPSHOT = SCRIPT_DIR.parent / 'Snapshot-ClaudeUsage.ps1'
MARKER_FILE = 'TEAM-STORE-ID.txt'
MARKER_ID = 'SKYLINE-TEAM-USAGE-STORE'
COLUMNS = ['date', 'user', 'machine', 'model', 'sessions', 'messages', 'input_tokens',
           'cache_creation_tokens', 'cache_read_tokens', 'output_tokens', 'total_tokens',
           'web_search', 'web_fetch', 'est_cost_usd']


def is_shared_store(path):
    marker = Path(path) / MARKER_FILE
    try:
        with open(marker, encoding='utf-8-sig') as f:
            return f.readline().strip() == MARKER_ID
    except OSError:
        return False


def lnk_target(lnk):
    """Follow a Drive for Desktop "Add shortcut to Drive" .lnk via Windows interop.

    Drive serves .lnk files as virtual files that fail to read over drvfs (EIO), and its
    .shortcut-targets-by-id folder is traverse-only from WSL, so neither can be done natively.
    Interop is unavailable inside systemd services; setup resolves once and passes --store.
    """
    if not shutil.which('powershell.exe'):
        return None
    win_lnk = subprocess.run(['wslpath', '-w', lnk], capture_output=True, text=True).stdout.strip()
    ps = f"(New-Object -ComObject WScript.Shell).CreateShortcut('{win_lnk}').TargetPath"
    try:
        target = subprocess.run(['powershell.exe', '-NoProfile', '-Command', ps],
                                capture_output=True, text=True, timeout=60).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    if not target:
        return None
    return subprocess.run(['wslpath', '-u', target], capture_output=True, text=True).stdout.strip() or None


def store_candidates():
    """Mirror Resolve-UsageStore.ps1 search order over the WSL drive mounts (/mnt/<x>)."""
    mounts = sorted(glob.glob('/mnt/*/'))
    seen = []

    def add(p):
        if p and os.path.isdir(p) and p not in seen:
            seen.append(p)

    for m in mounts:
        add(m + 'My Drive/Claude/Usage')
    for m in mounts:
        for name, sub in (('Claude.lnk', 'Usage'), ('Usage.lnk', '')):
            lnk = m + 'My Drive/' + name
            if os.path.exists(lnk):
                t = lnk_target(lnk)
                if t:
                    add(os.path.join(t, sub) if sub else t)
    for pat in ('.shortcut-targets-by-id/*/Claude/Usage', '.shortcut-targets-by-id/*/Usage',
                'Shared drives/*/Claude/Usage'):
        for m in mounts:
            for p in sorted(glob.glob(m + pat)):
                add(p)
    return seen


def resolve_store(override=None):
    override = override or os.environ.get('CLAUDE_USAGE_STORE')
    if override:
        if os.path.isdir(override):
            return os.path.realpath(override)
        sys.exit(f'Usage store override path not found: {override}')
    cands = store_candidates()
    if not cands:
        sys.exit("Could not find 'My Drive/Claude/Usage' (or a Shared-drive equivalent) under "
                 "/mnt/*. Is the Google Drive letter mounted in WSL (sudo mount -t drvfs G: /mnt/g)?")
    # Prefer the real team store if a private duplicate also exists.
    for c in cands:
        if is_shared_store(c):
            return c
    return cands[0]


def require_store(args):
    store = resolve_store(args.store)
    if not is_shared_store(store) and not args.allow_unshared_store:
        sys.exit(f'NOT THE SHARED STORE: {store}\n'
                 f'No {MARKER_FILE} marker - writing here tracks only you, invisibly to the team. '
                 'Join the shared folder, or pass --allow-unshared-store to proceed deliberately.')
    return store


def load_rates():
    text = PS_SNAPSHOT.read_text(encoding='utf-8-sig')
    rates = {m: (float(i), float(o)) for m, i, o in re.findall(
        r"'([^']+)'\s*=\s*@\{\s*input\s*=\s*([\d.]+)\s*;\s*output\s*=\s*([\d.]+)\s*\}", text)}
    mults = {}
    for name in ('CacheWrite5mMult', 'CacheWrite1hMult', 'CacheReadMult'):
        m = re.search(r'\$' + name + r'\s*=\s*([\d.]+)', text)
        if not m:
            sys.exit(f'Could not read ${name} from {PS_SNAPSHOT}')
        mults[name] = float(m.group(1))
    if 'default' not in rates:
        sys.exit(f'Could not read $Rates from {PS_SNAPSHOT}')
    return rates, mults


def est_cost(rates, mults, model, inp, cw_total, cw1h, cw5m, cr, out):
    r_in, r_out = rates.get(model, rates['default'])
    base = r_in / 1e6
    if cw1h + cw5m > 0:
        cache_write = cw1h * base * mults['CacheWrite1hMult'] + cw5m * base * mults['CacheWrite5mMult']
    else:
        cache_write = cw_total * base * mults['CacheWrite5mMult']
    return round(inp * base + out * (r_out / 1e6) + cache_write + cr * base * mults['CacheReadMult'], 4)


def fmt_num(x):
    # Match PowerShell Export-Csv: 0 -> "0", 1.5 -> "1.5"
    return str(int(x)) if float(x).is_integer() else repr(x)


def default_machine():
    return socket.gethostname().upper() + '-WSL'


TIMESTAMP_RE = re.compile(r'"timestamp":"([^"]+)"')
DATED_SUFFIX_RE = re.compile(r'-\d{8}$')


def aggregate(transcript_root):
    agg = {}
    for path in Path(transcript_root).rglob('*.jsonl'):
        try:
            fh = open(path, encoding='utf-8', errors='replace')
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"output_tokens"' not in line:
                    continue
                m = TIMESTAMP_RE.search(line)
                if not m:
                    continue
                try:
                    ts = datetime.fromisoformat(m.group(1))
                    o = json.loads(line)
                except ValueError:
                    continue
                local_date = ts.astimezone().strftime('%Y-%m-%d')
                msg = o.get('message') if isinstance(o, dict) else None
                u = msg.get('usage') if isinstance(msg, dict) else None
                if not isinstance(u, dict) or u.get('output_tokens') is None:
                    continue
                model = DATED_SUFFIX_RE.sub('', str(msg.get('model') or 'unknown'))
                a = agg.setdefault((local_date, model), {
                    'messages': 0, 'input': 0, 'cache_create': 0, 'cache_read': 0, 'output': 0,
                    'cw1h': 0, 'cw5m': 0, 'web_search': 0, 'web_fetch': 0, 'sessions': set()})
                a['messages'] += 1
                a['input'] += int(u.get('input_tokens') or 0)
                a['cache_create'] += int(u.get('cache_creation_input_tokens') or 0)
                a['cache_read'] += int(u.get('cache_read_input_tokens') or 0)
                a['output'] += int(u.get('output_tokens') or 0)
                cc = u.get('cache_creation')
                if isinstance(cc, dict):
                    a['cw1h'] += int(cc.get('ephemeral_1h_input_tokens') or 0)
                    a['cw5m'] += int(cc.get('ephemeral_5m_input_tokens') or 0)
                stu = u.get('server_tool_use')
                if isinstance(stu, dict):
                    a['web_search'] += int(stu.get('web_search_requests') or 0)
                    a['web_fetch'] += int(stu.get('web_fetch_requests') or 0)
                if o.get('sessionId'):
                    a['sessions'].add(str(o['sessionId']))
    return agg


def write_csv_atomic(path, rows):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS, quoting=csv.QUOTE_ALL, extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)


def read_csv(path):
    with open(path, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def cmd_resolve(args):
    store = resolve_store(args.store)
    print(f'OK shared store: {store}' if is_shared_store(store) else f'NOT THE SHARED STORE: {store}')


def cmd_snapshot(args):
    transcript_root = os.path.expanduser(args.transcript_root)
    if not os.path.isdir(transcript_root):
        sys.exit(f'Transcript root not found: {transcript_root}')
    data_dir = args.data_dir or os.path.join(require_store(args), 'data')
    os.makedirs(data_dir, exist_ok=True)
    machine = args.machine or default_machine()
    user = args.user or f"{os.environ.get('USER', 'unknown')}@proteinms.net"
    csv_path = os.path.join(data_dir, f'usage_{machine}.csv')

    rates, mults = load_rates()
    agg = aggregate(transcript_root)

    # Skip the current local day: a partial total that self-corrects on the next run.
    today = date.today().strftime('%Y-%m-%d')
    fresh_dates, fresh_rows = set(), []
    for (d, model), a in agg.items():
        if d == today:
            continue
        fresh_dates.add(d)
        cost = est_cost(rates, mults, model, a['input'], a['cache_create'], a['cw1h'], a['cw5m'],
                        a['cache_read'], a['output'])
        fresh_rows.append({
            'date': d, 'user': user, 'machine': machine, 'model': model,
            'sessions': len(a['sessions']), 'messages': a['messages'],
            'input_tokens': a['input'], 'cache_creation_tokens': a['cache_create'],
            'cache_read_tokens': a['cache_read'], 'output_tokens': a['output'],
            'total_tokens': a['input'] + a['cache_create'] + a['cache_read'] + a['output'],
            'web_search': a['web_search'], 'web_fetch': a['web_fetch'],
            'est_cost_usd': fmt_num(cost), '_cost': cost})

    preserved = []
    if os.path.exists(csv_path):
        preserved = [r for r in read_csv(csv_path) if r['date'] not in fresh_dates and r['date'] != today]
    rows = sorted(preserved + fresh_rows, key=lambda r: (r['date'], r['model'].lower()))
    write_csv_atomic(csv_path, rows)

    days = len({r['date'] for r in rows})
    tok = sum(r['total_tokens'] for r in fresh_rows)
    cost = sum(r['_cost'] for r in fresh_rows)
    print(f'[{machine} @ {user}] {len(rows)} rows / {days} days  |  window: {len(fresh_dates)} days, '
          f'{tok:,} tokens, ~${cost:,.2f} modeled')
    print(f'CSV: {csv_path}')


def cmd_combine(args):
    data_dir = args.data_dir or os.path.join(require_store(args), 'data')
    files = sorted(p for p in glob.glob(os.path.join(data_dir, 'usage_*.csv'))
                   if os.path.basename(p) != 'usage_combined.csv')
    if not files:
        sys.exit(f'No per-machine usage_*.csv files found in {data_dir}')
    rows = [r for p in files for r in read_csv(p)]
    rows.sort(key=lambda r: (r['date'], r['user'].lower(), r['machine'].lower(), r['model'].lower()))
    combined = os.path.join(data_dir, 'usage_combined.csv')
    write_csv_atomic(combined, rows)
    print(f'Combined {len(files)} machine file(s) -> {len(rows)} rows')
    print(f'Output: {combined}')

    def summary(key):
        groups = {}
        for r in rows:
            groups.setdefault(r[key], []).append(r)
        print(f'\n--- per {key} ---')
        for name, g in sorted(groups.items()):
            print(f"{name:<40} days={len({r['date'] for r in g}):>4}  "
                  f"tokens={sum(int(r['total_tokens']) for r in g):>15,}  "
                  f"est_cost={sum(float(r['est_cost_usd']) for r in g):>10,.2f}")
    summary('user')
    summary('machine')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--store', help='Store root override (else $CLAUDE_USAGE_STORE, else scan /mnt/*)')
    ap.add_argument('--allow-unshared-store', action='store_true',
                    help='Write even though the store lacks the team marker (private folder)')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('resolve').set_defaults(func=cmd_resolve)
    sp = sub.add_parser('snapshot')
    sp.add_argument('--transcript-root', default='~/.claude/projects')
    sp.add_argument('--data-dir')
    sp.add_argument('--machine', help='Machine tag. Default: <HOSTNAME>-WSL')
    sp.add_argument('--user', help='Person tag. Default: $USER@proteinms.net')
    sp.set_defaults(func=cmd_snapshot)
    cp = sub.add_parser('combine')
    cp.add_argument('--data-dir')
    cp.set_defaults(func=cmd_combine)
    args = ap.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
