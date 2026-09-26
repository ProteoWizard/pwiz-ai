"""Timing plots for CarafeSharp performance records (white background, for PRs and docs).

  library  - the library-prediction step, before vs after a change: per-phase stacked bars from
             CarafeSharp run.log files, with the after build's writing drawn as its own lane when it
             overlaps prediction.
  pipeline - the fine-tuned-library pipeline, Carafe vs CarafeSharp: per-step stacked bars from the
             workflow drivers' logs (Run-CarafeOspreyWorkflow.ps1 / Run-CarafeSharpWorkflow.ps1).

Usage:
  plot_timings.py library <runs dir> <out.png>
      <runs dir> holds one folder per run named <Dataset>-<n>-<base|new>, each with run.log.
  plot_timings.py pipeline <e2e dir> <out.png>
      <e2e dir> holds one folder per run named <Dataset>-<tag>-<carafe|carafesharp>, each with e2e.log.
"""
import os
import re
import statistics
import sys

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402

COLORS = {
    'setup': '#9aa3b0',
    'ms2': '#3a4787',
    'rt': '#4f86b6',
    'assembly': '#c6b27a',
    'writing': '#2b8a6c',
    'convert': '#9aa3b0',
    'fasta': '#c6b27a',
    'initial': '#4f86b6',
    'search': '#3a4787',
    'data': '#cf8a36',
    'tune': '#b04a60',
    'final': '#2b8a6c',
}
INK = '#18202e'
MUTED = '#5a6475'
GRID = '#e8ecf2'
DATASETS = ('Stellar', 'Astral')


def style(ax):
    ax.set_facecolor('white')
    for side in ('top', 'right', 'left'):
        ax.spines[side].set_visible(False)
    ax.spines['bottom'].set_color('#d8dde6')
    ax.tick_params(colors=MUTED, labelsize=9)
    ax.xaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def segment_labels(ax, y, height, x0, width, value, color):
    if width > ax.get_xlim()[1] * 0.06:
        light = color in (COLORS['assembly'], COLORS['setup'], COLORS['data'])
        ax.text(x0 + width / 2, y, f'{value:.1f}' if value >= 10 else f'{value:.2f}', ha='center', va='center',
                fontsize=8.5, color=INK if light else 'white')


# ---- library step -------------------------------------------------------------------------------

PHASES = re.compile(r'MS2 ([\d.]+) s, RT ([\d.]+) s, assembly ([\d.]+) s, writing ([\d.]+) s')


def read_library_run(folder):
    text = open(os.path.join(folder, 'run.log'), encoding='utf-8', errors='replace').read()
    wall = float(re.findall(r'exit=0 wall=(\d+)s', text)[-1])
    batch = [line for line in text.splitlines() if line.startswith('Batch ')][-1]
    ms2, rt, assembly, writing = (float(v) for v in PHASES.search(batch).groups())
    finished = re.search(r'Writing finished [\d.]+ s after prediction: \d+ precursors, writing ([\d.]+) s', text)
    overlapped = finished is not None
    if overlapped:
        writing = float(finished.group(1))
    serial = ms2 + rt + assembly + (0 if overlapped else writing)
    return {'wall': wall, 'ms2': ms2, 'rt': rt, 'assembly': assembly, 'writing': writing,
            'setup': wall - serial, 'overlapped': overlapped}


def median_run(runs):
    keys = ('wall', 'ms2', 'rt', 'assembly', 'writing', 'setup')
    merged = {k: statistics.median(r[k] for r in runs) for k in keys}
    merged['overlapped'] = runs[0]['overlapped']
    merged['n'] = len(runs)
    return merged


def plot_library(runs_dir, out):
    arms = {}
    for name in sorted(os.listdir(runs_dir)):
        m = re.match(r'(\w+)-\d+-(base|new)$', name)
        if m and os.path.exists(os.path.join(runs_dir, name, 'run.log')):
            arms.setdefault((m.group(1), m.group(2)), []).append(read_library_run(os.path.join(runs_dir, name)))
    datasets = [d for d in DATASETS if (d, 'base') in arms and (d, 'new') in arms]
    fig, axes = plt.subplots(len(datasets), 1, figsize=(9, 2.3 * len(datasets) + 0.9), facecolor='white')
    axes = axes if len(datasets) > 1 else [axes]
    for ax, ds in zip(axes, datasets):
        base, new = median_run(arms[(ds, 'base')]), median_run(arms[(ds, 'new')])
        style(ax)
        ax.set_xlim(0, max(base['wall'], new['wall']) / 60 * 1.12)
        rows = [('Before', base, 2.2), ('After', new, 1.0)]
        for label, run, y in rows:
            x = 0.0
            for key in ('setup', 'ms2', 'rt', 'assembly') + (() if run['overlapped'] else ('writing',)):
                width = run[key] / 60
                ax.barh(y, width, left=x, height=0.62, color=COLORS[key], edgecolor='white', linewidth=0.6)
                segment_labels(ax, y, 0.62, x, width, width, COLORS[key])
                x += width
            ax.text(run['wall'] / 60 + ax.get_xlim()[1] * 0.012, y, f"{run['wall'] / 60:.2f} min", va='center',
                    fontsize=9.5, fontweight='bold', color=INK)
            if run['overlapped']:
                # The writer works in bursts across the whole prediction, one chunk behind it.
                start = run['setup'] / 60
                span = (run['ms2'] + run['rt'] + run['assembly']) / 60
                ax.barh(y - 0.52, span, left=start, height=0.22, color=COLORS['writing'], alpha=0.45,
                        edgecolor=COLORS['writing'], hatch='////', linewidth=0.6)
                ax.text(start + span + ax.get_xlim()[1] * 0.012, y - 0.52,
                        f"writing, {run['writing'] / 60:.2f} min in total, overlapped", va='center', fontsize=8.5,
                        color=MUTED)
        ax.set_yticks([2.2, 1.0])
        ax.set_yticklabels([f"Before  (n={base['n']})", f"After  (n={new['n']})"], fontsize=10, color=INK)
        ax.set_ylim(0.1, 2.75)
        speedup = base['wall'] / new['wall']
        ax.set_title(f"{ds}: {base['wall']:.0f} s to {new['wall']:.0f} s, {speedup:.2f}x faster",
                     loc='left', fontsize=11.5, fontweight='bold', color=INK)
        ax.set_xlabel('minutes (median of runs)', fontsize=9, color=MUTED)
    handles = [plt.Rectangle((0, 0), 1, 1, color=COLORS[k]) for k in ('setup', 'ms2', 'rt', 'assembly', 'writing')]
    fig.legend(handles, ['Other (FASTA, peptide forms, models, finishing)', 'MS2 prediction', 'RT prediction', 'Spectrum assembly',
                         'Library writing'], loc='lower center', ncol=5, frameon=False, fontsize=8.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    fig.savefig(out, dpi=160, facecolor='white')
    print('wrote', out)


# ---- pipeline -----------------------------------------------------------------------------------

STEPS = [
    ('convert', 'Raw file to mzML (msconvert)'),
    ('fasta', 'Peptide FASTAs'),
    ('initial', 'Initial library, base model'),
    ('search', 'Osprey search, training run'),
    ('data', 'Training data from the mzML'),
    ('tune', 'Fine-tuning'),
    ('final', 'Final library, fine-tuned model'),
]
DONE = re.compile(r'\[DONE\] (.+?) \(([\d.]+) min\)')


def read_pipeline_run(folder, tool):
    text = re.sub(r'\x1b\[[0-9;]*m', '', open(os.path.join(folder, 'e2e.log'), encoding='utf-8', errors='replace').read())
    steps = {}
    m = re.search(r'msconvert exit=0 seconds=(\d+)', text)
    if m:
        steps['convert'] = int(m.group(1)) / 60
    done = {name: float(minutes) for name, minutes in DONE.findall(text)}
    for name, minutes in done.items():
        low = name.lower()
        if 'fasta' in low:
            # Carafe builds its two FASTAs in parallel; CarafeSharp builds them one after the other.
            steps['fasta'] = max(steps.get('fasta', 0), minutes) if tool == 'carafe' else steps.get('fasta', 0) + minutes
        elif 'initial' in low:
            steps['initial'] = minutes
        elif 'search' in low and 'project' not in low:
            steps['search'] = minutes
    tune_stage = next(minutes for name, minutes in done.items() if 'fine' in name.lower() or 'finetune' in name.lower())
    if tool == 'carafe':
        data = float(re.findall(r'Time used for training data generation: ([\d.]+) min', text)[-1])
        training = float(re.findall(r'Time used for model training: ([\d.]+) min', text)[-1])
        steps['data'] = data
        steps['tune'] = training
        steps['final'] = tune_stage - data - training
    else:
        library = float(re.findall(r'Wrote \d+ precursors in ([\d.]+) s', text)[-1]) / 60
        steps['tune'] = tune_stage - library
        steps['final'] = library
    return steps


def plot_pipeline(e2e_dir, out):
    runs = {}
    for name in sorted(os.listdir(e2e_dir)):
        m = re.match(r'(\w+)-.+-(carafe|carafesharp)$', name)
        if m and os.path.exists(os.path.join(e2e_dir, name, 'e2e.log')):
            runs[(m.group(1), m.group(2))] = read_pipeline_run(os.path.join(e2e_dir, name), m.group(2))
    datasets = [d for d in DATASETS if (d, 'carafe') in runs and (d, 'carafesharp') in runs]
    fig, axes = plt.subplots(len(datasets), 1, figsize=(9, 2.1 * len(datasets) + 1.1), facecolor='white')
    axes = axes if len(datasets) > 1 else [axes]
    for ax, ds in zip(axes, datasets):
        carafe, sharp = runs[(ds, 'carafe')], runs[(ds, 'carafesharp')]
        totals = {k: sum(v.values()) for k, v in (('carafe', carafe), ('sharp', sharp))}
        style(ax)
        ax.set_xlim(0, max(totals.values()) * 1.12)
        for label, steps, y, key in (('Carafe 2.2.0 (Java + Python)', carafe, 1.8, 'carafe'), ('CarafeSharp', sharp, 0.8, 'sharp')):
            x = 0.0
            for step, _ in STEPS:
                width = steps.get(step, 0)
                if width <= 0:
                    continue
                ax.barh(y, width, left=x, height=0.62, color=COLORS[step], edgecolor='white', linewidth=0.6)
                segment_labels(ax, y, 0.62, x, width, width, COLORS[step])
                x += width
            ax.text(totals[key] + ax.get_xlim()[1] * 0.012, y, f'{totals[key]:.1f} min', va='center', fontsize=9.5,
                    fontweight='bold', color=INK)
        ax.set_yticks([1.8, 0.8])
        ax.set_yticklabels(['Carafe 2.2.0\n(Java + Python)', 'CarafeSharp'], fontsize=10, color=INK)
        ax.set_ylim(0.3, 2.3)
        ax.set_title(f"{ds}: {totals['carafe']:.1f} min to {totals['sharp']:.1f} min, "
                     f"{totals['carafe'] / totals['sharp']:.2f}x faster", loc='left', fontsize=11.5, fontweight='bold',
                     color=INK)
        ax.set_xlabel('minutes', fontsize=9, color=MUTED)
    handles = [plt.Rectangle((0, 0), 1, 1, color=COLORS[k]) for k, _ in STEPS]
    fig.legend(handles, [label for _, label in STEPS], loc='lower center', ncol=4, frameon=False, fontsize=8.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.tight_layout(rect=(0, 0.1, 1, 1))
    fig.savefig(out, dpi=160, facecolor='white')
    print('wrote', out)


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in ('library', 'pipeline'):
        sys.exit(__doc__)
    (plot_library if sys.argv[1] == 'library' else plot_pipeline)(sys.argv[2], sys.argv[3])
