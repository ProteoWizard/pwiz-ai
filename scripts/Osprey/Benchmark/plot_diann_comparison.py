"""Plots for Run-DiannComparison.ps1: Osprey vs DIA-NN wall time and precursor ID overlap.

  library <compare dir> <out.png>   library generation from the FASTA, one panel per dataset
  search  <compare dir> <out.png>   the search with that library, one panel per dataset
                                    (separate figures: the library is built on the GPU, the search
                                    is not, so the two are never summed); each bar is split into
                                    phases parsed from the tools' own logs
  overlap <compare dir> <out.png>   per dataset, an UpSet plot of run-level precursor IDs at 1% FDR
  summary <compare dir>             the phase table both plots are drawn from, as text

<compare dir> holds one folder per dataset (stellar, astral), each with the four step folders and
timing.tsv that Run-DiannComparison.ps1 writes. White background, for PRs, papers and slides.
"""
import os
import re
import sqlite3
import sys
from datetime import datetime
from itertools import combinations

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402

DATASETS = ('stellar', 'astral')
TOOLS = ('DIA-NN', 'Osprey', 'Osprey CPU')   # Osprey CPU: the library figure's reference bar

# The search phases of the earlier Osprey vs DIA-NN chart, and their colors.
SEARCH_PHASES = [
    ('setup', 'Setup & library load', '#4c9f9f'),
    ('calibration', 'File loading & calibration', '#7f6aac'),
    ('main', 'Main search', '#e08a3c'),
    ('fdr', 'Statistical modeling & FDR', '#c4504d'),
    ('second', 'Second pass & refinement', '#5b8f5b'),
    ('output', 'Cross-run & output', '#8c8f94'),
]
LIBRARY_PHASES = [
    ('lib_setup', 'Start-up & digest', '#9aa3b0'),
    ('lib_initial', 'Predict pretrained library', '#8fb9d9'),
    ('lib_search', 'Search middle run (training export)', '#3a4787'),
    ('lib_tune', 'Fine-tune MS2 + RT', '#b04a60'),
    ('lib_final', 'Predict final library', '#2b8a6c'),
    ('lib_predict', 'Predict library', '#4f86b6'),
]
INK = '#18202e'
MUTED = '#5a6475'
GRID = '#e8ecf2'

OSPREY_TS = re.compile(r'^\[(\d{4}/\d\d/\d\d \d\d:\d\d:\d\d)\]\s?(.*)$')
DIANN_TS = re.compile(r'^\[(\d+):(\d\d)\]\s(.*)$')


def read_timing(dataset_dir):
    rows = pd.read_csv(os.path.join(dataset_dir, 'timing.tsv'), sep='\t')
    rows = rows[rows['exit_code'] == 0]
    # The last successful run of each step is the one its folder holds.
    return {r.step: r for r in rows.itertuples()}


def cpu_osprey_library(ddir):
    """The latest Osprey library build on the CPU, when the current one ran on the GPU: drawn as a
    reference bar in the library figure. Earlier runs live in <step>-<datetime> folders (the runner
    moves a step's folder aside before re-running it), found by the log's first timestamp."""
    rows = pd.read_csv(os.path.join(ddir, 'timing.tsv'), sep='\t')
    rows = rows[(rows['exit_code'] == 0) & (rows['step'] == 'osprey-library')]
    rows = [r for r in rows.itertuples() if 'cuda' not in str(r.exe).lower()]
    if not rows:
        return None
    row = rows[-1]
    start = parse_start(row.start)
    for folder in sorted(os.listdir(ddir)):
        log = os.path.join(ddir, folder, 'osprey.log')
        if folder.startswith('osprey-library') and os.path.exists(log):
            lines = osprey_lines(log)
            if lines and abs((lines[0][0] - start).total_seconds()) <= 2:
                return osprey_library_phases(log, start, row.wall_s)
    return None


def osprey_lines(path):
    lines = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = OSPREY_TS.match(line.rstrip('\n'))
            if m:
                lines.append((datetime.strptime(m.group(1), '%Y/%m/%d %H:%M:%S'), m.group(2)))
    return lines


def diann_lines(path):
    lines = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = DIANN_TS.match(line.strip())
            if m:
                lines.append((int(m.group(1)) * 60 + int(m.group(2)), m.group(3)))
    return lines


def seconds_after(ts, start):
    # Osprey's log stamps whole seconds and the runner's start has a fraction, so a line written
    # as the process starts can read up to a second before it: clamp, or it sorts ahead of setup.
    return max((ts - start).total_seconds(), 0.0)


def segments_from_marks(marks, wall_s, first_key, last_key):
    """marks: [(seconds from process start, phase key)], each phase running to the next mark.
    Time before the first mark goes to first_key, time after the last log line to last_key, so the
    phases always sum to the measured wall time."""
    phases = {}
    marks = sorted(marks, key=lambda m: m[0])
    if marks:
        phases[first_key] = phases.get(first_key, 0.0) + max(marks[0][0], 0.0)
    for (t0, key), (t1, _) in zip(marks, marks[1:]):
        phases[key] = phases.get(key, 0.0) + max(t1 - t0, 0.0)
    end = marks[-1][0] if marks else 0.0
    phases[last_key] = phases.get(last_key, 0.0) + max(wall_s - end, 0.0)
    return phases


def osprey_search_phases(log, start, wall_s):
    lines = osprey_lines(log)
    marks = []
    for ts, text in lines:
        t = seconds_after(ts, start)
        if text.startswith('Scoring file '):
            marks.append((t, 'calibration'))
        elif text.startswith('Scoring isolation windows'):
            marks.append((t, 'main'))
        elif text.startswith('[TASK] FirstPassFDR:starting'):
            marks.append((t, 'fdr'))
        elif text.startswith('[TASK] PerFileRescoring:starting'):
            marks.append((t, 'second'))
        elif text.startswith('Running protein-level FDR') or text.startswith('Selecting peptides passing'):
            if not marks or marks[-1][1] != 'output':
                marks.append((t, 'output'))
    marks.insert(0, (0.0, 'setup'))
    return segments_from_marks(marks, wall_s, 'setup', 'output')


def osprey_library_phases(log, start, wall_s):
    marks = [(0.0, 'lib_setup')]
    names = {'PredictTrainingLibrary': 'lib_initial', 'PerFileScoring': 'lib_search',
             'TrainModel': 'lib_tune', 'PredictLibrary': 'lib_final'}
    for ts, text in osprey_lines(log):
        m = re.match(r'\[TASK\] (\w+):starting', text)
        if m and m.group(1) in names:
            key = names[m.group(1)]
            if key != marks[-1][1]:
                marks.append((seconds_after(ts, start), key))
    return segments_from_marks(marks, wall_s, 'lib_setup', 'lib_final')


def diann_search_phases(log, wall_s):
    marks = [(0, 'setup')]
    cross_runs = 0
    for t, text in diann_lines(log):
        if text.startswith('File #'):
            # A run starts: the second pass's runs (after the empirical library) are refinement.
            marks.append((t, 'second' if cross_runs else 'calibration'))
        elif text.startswith('Main search') and not cross_runs:
            marks.append((t, 'main'))
        elif text.startswith('Training neural networks') and not cross_runs:
            marks.append((t, 'fdr'))
        elif text.startswith('Cross-run analysis'):
            cross_runs += 1
            marks.append((t, 'output'))
        elif text.startswith('Generating spectral library') and cross_runs == 1:
            marks.append((t, 'second'))
    return segments_from_marks(marks, wall_s, 'setup', 'output')


def diann_library_phases(log, wall_s):
    marks = [(0, 'lib_setup')]
    for t, text in diann_lines(log):
        if text.startswith('Predicting') or text.startswith('Deep learning'):
            marks.append((t, 'lib_predict'))
            break
    return segments_from_marks(marks, wall_s, 'lib_setup', 'lib_predict')


def collect(compare_dir):
    """{dataset: {tool: {'library': {phase: s}, 'search': {phase: s}}}}"""
    result = {}
    for dataset in DATASETS:
        ddir = os.path.join(compare_dir, dataset)
        if not os.path.exists(os.path.join(ddir, 'timing.tsv')):
            continue
        timing = read_timing(ddir)
        # The library and the search are separate figures, so either can be drawn without the other.
        entry = {}
        lib, search = timing.get('diann-library'), timing.get('diann-search')
        if lib is not None or search is not None:
            entry['DIA-NN'] = {
                'label': 'DIA-NN ' + exe_version((lib if lib is not None else search).exe),
                'library': diann_library_phases(os.path.join(ddir, 'diann-library', 'step.log'),
                                                lib.wall_s) if lib is not None else {},
                'search': diann_search_phases(os.path.join(ddir, 'diann-search', 'step.log'),
                                              search.wall_s) if search is not None else {},
            }
        lib, search = timing.get('osprey-library'), timing.get('osprey-search')
        if lib is not None or search is not None:
            device = 'GPU' if lib is not None and 'cuda' in str(lib.exe).lower() else 'CPU'
            entry['Osprey'] = {
                'label': f'Osprey ({device})' if lib is not None else 'Osprey',
                'library': osprey_library_phases(os.path.join(ddir, 'osprey-library', 'osprey.log'),
                                                 parse_start(lib.start), lib.wall_s) if lib is not None else {},
                'search': osprey_search_phases(os.path.join(ddir, 'osprey-search', 'osprey.log'),
                                               parse_start(search.start), search.wall_s) if search is not None else {},
            }
            cpu = cpu_osprey_library(ddir) if device == 'GPU' else None
            if cpu:
                entry['Osprey CPU'] = {'label': 'Osprey (CPU)', 'library': cpu, 'search': {}}
        if entry:
            result[dataset] = entry
    return result


def exe_version(path):
    m = re.search(r'DIA-NN[\\/]([\d.]+)[\\/]', str(path))
    return m.group(1) if m else ''


def parse_start(text):
    # PowerShell's round-trip format: local time with a UTC offset, seconds to 7 decimals.
    stamp = datetime.fromisoformat(re.sub(r'(\.\d{6})\d+', r'\1', text))
    return stamp.replace(tzinfo=None)


def style(ax):
    ax.set_facecolor('white')
    for side in ('top', 'right', 'left'):
        ax.spines[side].set_visible(False)
    ax.spines['bottom'].set_color('#d8dde6')
    ax.tick_params(colors=MUTED, labelsize=9)
    ax.xaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def draw_bars(ax, data, part, phases, xmax):
    used = []
    tools = [t for t in TOOLS if t in data and data[t][part]]
    for y, tool in enumerate(tools):
        x = 0.0
        for key, label, color in phases:
            minutes = data[tool][part].get(key, 0.0) / 60
            if minutes <= 0:
                continue
            ax.barh(y, minutes, left=x, height=0.55, color=color, edgecolor='white', linewidth=0.8)
            if minutes > xmax * 0.07:
                light = color in ('#9aa3b0', '#8fb9d9', '#8c8f94')
                ax.text(x + minutes / 2, y, f'{minutes:.1f}', ha='center', va='center', fontsize=8,
                        color=INK if light else 'white')
            x += minutes
            if key not in used:
                used.append(key)
        total = sum(data[tool][part].values()) / 60   # the title's sum, so the two round alike
        ax.text(x + xmax * 0.01, y, f'{total:.1f} min', va='center', ha='left', fontsize=10,
                fontweight='bold', color=INK)
    ax.set_yticks(range(len(tools)))
    # The device is where Osprey's library was predicted; the search runs on the CPU either way.
    labels = [data[t]['label'] for t in tools]
    if part == 'search':
        labels = [re.sub(r' \((GPU|CPU)\)$', '', lbl) for lbl in labels]
    ax.set_yticklabels(labels, fontsize=10, color=INK)
    ax.set_ylim(-0.6, len(tools) - 0.4)
    ax.set_xlim(0, xmax)
    ax.invert_yaxis()
    return used


PART_TITLES = {
    'library': 'Library generation from the FASTA, wall clock',
    'search': 'Search of 3 runs with the predicted library, wall clock',
}


def plot_part(compare_dir, out_png, part):
    """One figure per part, library generation or search, never both: one panel per dataset."""
    phases = LIBRARY_PHASES if part == 'library' else SEARCH_PHASES
    data = {d: e for d, e in collect(compare_dir).items() if e}
    if not data:
        sys.exit(f'No complete datasets under {compare_dir}')
    fig, axes = plt.subplots(len(data), 1, figsize=(11, 2.3 * len(data) + 1.4), facecolor='white',
                             squeeze=False)
    used = []
    for ax, (dataset, entry) in zip(axes[:, 0], data.items()):
        style(ax)
        totals = {t: sum(entry[t][part].values()) / 60 for t in entry if entry[t][part]}
        if not totals:
            continue
        xmax = max(totals.values()) * 1.18
        for key in draw_bars(ax, entry, part, phases, xmax):
            if key not in used:
                used.append(key)
        title = dataset.capitalize()
        if 'Osprey' in totals and 'DIA-NN' in totals:
            o, d = totals['Osprey'], totals['DIA-NN']
            if o < d:
                title += f'  -  Osprey {o:.1f} min vs DIA-NN {d:.1f} min ({(1 - o / d) * 100:.0f}% faster)'
            else:
                title += f'  -  Osprey {o:.1f} min vs DIA-NN {d:.1f} min ({o / d:.1f}x longer)'
        ax.set_title(title, fontsize=11, color=INK, loc='left')
        ax.set_xlabel('Minutes', fontsize=9, color=MUTED)
    fig.suptitle(PART_TITLES[part], fontsize=12.5, color=INK, x=0.02, ha='left')
    handles = [plt.Rectangle((0, 0), 1, 1, color=c) for k, _, c in phases if k in used]
    labels = [lbl for k, lbl, _ in phases if k in used]
    fig.legend(handles, labels, loc='lower center', ncol=3, frameon=False, fontsize=9)
    fig.tight_layout(rect=(0, 0.1, 1, 0.95), h_pad=2.2)
    fig.savefig(out_png, dpi=200, facecolor='white')
    print(f'Wrote {out_png}')


def print_summary(compare_dir):
    data = collect(compare_dir)
    names = {k: lbl for k, lbl, _ in LIBRARY_PHASES + SEARCH_PHASES}
    for dataset, entry in data.items():
        for tool, parts in entry.items():
            for part in ('library', 'search'):
                total = sum(parts[part].values()) / 60
                print(f'{dataset:8s} {tool:13s} {part:8s} {total:6.1f} min')
                for key, s in parts[part].items():
                    print(f'{"":32s} {names[key]:38s} {s / 60:6.2f}')


# --- precursor ID overlap ---------------------------------------------------------------------

def stripped(seq):
    return re.sub(r'\[[^\]]*\]|\([^)]*\)', '', seq)


def osprey_ids(blib, qvalue=0.01):
    """Run-level IDs: precursors in the result (experiment q <= 0.01) whose run q <= 0.01."""
    con = sqlite3.connect(f'file:{blib}?mode=ro', uri=True)
    rows = con.execute(
        'SELECT s.fileName, r.peptideModSeq, r.precursorCharge FROM RetentionTimes t '
        'JOIN RefSpectra r ON r.id = t.RefSpectraID '
        'JOIN SpectrumSourceFiles s ON s.id = t.SpectrumSourceID '
        'WHERE t.score <= ? AND r.score <= ?', (qvalue, qvalue)).fetchall()
    con.close()
    ids = {}
    for path, seq, z in rows:
        ids.setdefault(run_label(path), set()).add((stripped(seq), int(z)))
    return ids


def diann_ids(report, qvalue=0.01):
    """Run-level IDs: Q.Value <= 0.01 and, as Osprey's experiment filter, Global.Q.Value <= 0.01."""
    df = pd.read_parquet(report, columns=['Run', 'Stripped.Sequence', 'Precursor.Charge', 'Q.Value',
                                          'Global.Q.Value'])
    df = df[(df['Q.Value'] <= qvalue) & (df['Global.Q.Value'] <= qvalue)]
    ids = {}
    for run, seq, z in zip(df['Run'], df['Stripped.Sequence'], df['Precursor.Charge']):
        ids.setdefault(run_label(run), set()).add((seq, int(z)))
    return ids


def run_label(path):
    m = re.search(r'_(\d+)(?:\.\w+)?$', os.path.basename(str(path)).replace('\\', '/'))
    return m.group(1) if m else os.path.basename(str(path))


def draw_upset(fig_area, sets, title, max_bars=14):
    names = list(sets)
    universe = set().union(*sets.values())
    membership = {}
    for item in universe:
        key = tuple(item in sets[n] for n in names)
        membership[key] = membership.get(key, 0) + 1
    combos = sorted(membership.items(), key=lambda kv: -kv[1])[:max_bars]

    gs = fig_area.add_gridspec(2, 2, width_ratios=[1, 3.2], height_ratios=[1.6, 1], wspace=0.04, hspace=0.04)
    ax_bar = fig_area.add_subplot(gs[0, 1])
    ax_dots = fig_area.add_subplot(gs[1, 1], sharex=ax_bar)
    ax_size = fig_area.add_subplot(gs[1, 0], sharey=ax_dots)
    colors = ['#4a6fb0' if n.startswith('DIA') else '#e08a3c' for n in names]

    xs = range(len(combos))
    ax_bar.bar(xs, [c for _, c in combos], color='#4c9f9f', width=0.7)
    for x, (_, c) in zip(xs, combos):
        ax_bar.text(x, c, f'{c}', ha='center', va='bottom', fontsize=7, rotation=90, color=INK)
    ax_bar.set_ylabel('Precursors', fontsize=9, color=INK)
    ax_bar.set_title(title, fontsize=10.5, color=INK)
    for side in ('top', 'right'):
        ax_bar.spines[side].set_visible(False)
    ax_bar.tick_params(axis='x', bottom=False, labelbottom=False)

    for x, (key, _) in zip(xs, combos):
        ys = [i for i, inside in enumerate(key) if inside]
        for i in range(len(names)):
            ax_dots.scatter(x, i, s=55, color=colors[i] if key[i] else '#dddddd', zorder=2)
        if len(ys) > 1:
            ax_dots.plot([x, x], [min(ys), max(ys)], color='#555555', linewidth=1.4, zorder=1)
    ax_dots.set_yticks(range(len(names)))
    ax_dots.set_yticklabels(names, fontsize=9)
    for tick, c in zip(ax_dots.get_yticklabels(), colors):
        tick.set_color(c)
    ax_dots.invert_yaxis()
    ax_dots.tick_params(axis='x', bottom=False, labelbottom=False)
    ax_dots.yaxis.tick_right()
    for side in ('top', 'right', 'left', 'bottom'):
        ax_dots.spines[side].set_visible(False)

    ax_size.barh(range(len(names)), [len(sets[n]) for n in names], color=colors)
    ax_size.invert_xaxis()
    ax_size.set_xlabel('Set size', fontsize=9)
    ax_size.tick_params(axis='y', left=False, labelleft=False)
    for side in ('top', 'left'):
        ax_size.spines[side].set_visible(False)


def plot_overlap(compare_dir, out_png):
    panels = []
    for dataset in DATASETS:
        ddir = os.path.join(compare_dir, dataset)
        blib = os.path.join(ddir, 'osprey-search', 'osprey.blib')
        report = os.path.join(ddir, 'diann-search', 'report.parquet')
        if not (os.path.exists(blib) and os.path.exists(report)):
            continue
        sets = {}
        for run, ids in sorted(diann_ids(report).items()):
            sets[f'DIA-NN {run}'] = ids
        for run, ids in sorted(osprey_ids(blib).items()):
            sets[f'Osprey {run}'] = ids
        panels.append((dataset, sets))
        for name, ids in sets.items():
            print(f'{dataset:8s} {name:12s} {len(ids):7d}')
        union_d = set().union(*(v for k, v in sets.items() if k.startswith('DIA')))
        union_o = set().union(*(v for k, v in sets.items() if k.startswith('Osprey')))
        print(f'{dataset:8s} any-run union: DIA-NN {len(union_d)}, Osprey {len(union_o)}, '
              f'both {len(union_d & union_o)}')
    if not panels:
        sys.exit(f'No complete searches under {compare_dir}')
    fig = plt.figure(figsize=(9 * len(panels), 6), facecolor='white')
    areas = fig.subfigures(1, len(panels), squeeze=False)[0]
    for area, (dataset, sets) in zip(areas, panels):
        draw_upset(area, sets, f'{dataset.capitalize()} - precursor ID overlap (run-level, 1% FDR)')
    fig.savefig(out_png, dpi=200, facecolor='white', bbox_inches='tight')
    print(f'Wrote {out_png}')


if __name__ == '__main__':
    if len(sys.argv) < 3 or sys.argv[1] not in ('library', 'search', 'overlap', 'summary'):
        sys.exit(__doc__)
    if sys.argv[1] == 'summary':
        print_summary(sys.argv[2])
    elif sys.argv[1] in ('library', 'search'):
        plot_part(sys.argv[2], sys.argv[3], sys.argv[1])
    else:
        plot_overlap(sys.argv[2], sys.argv[3])
