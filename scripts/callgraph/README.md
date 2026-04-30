# callgraph — shared core

Animated callgraph viewer. Given a per-commit `snapshots.json`, emits a
self-contained HTML page that plays back how the codebase grew: nodes fade
in when first touched, edges appear when references are added, and group
labels float at the centroid of each cluster.

Derived from [davidbau/mandelbrot](https://github.com/davidbau/mandelbrot)'s
page-growth viewer. Most of the force-simulation and animation code came
from there; this layer adds the shared patch pipeline, compact-encoded
timeline data, group/label system, transport controls, stats panel, and
project-configurable hooks.

## Files

- **core.py** — the module. `ProjectConfig`, `build_registry_and_timeline`,
  `patch_html`, `write_data_files`, `write_dated_html`. Import as
  `from callgraph import core`.
- **base.html** — the template that gets patched. Pristine mandelbrot-page
  HTML plus the transport row, overlays, and stats panel.
- **vendor/d3.v7.min.js** — pinned d3. Inlined into the output HTML so the
  generated file has zero CDN dependencies.
- **__init__.py** — makes the directory an importable package.

## Example consumers

- **[`ai/docs/callgraph/`](../../docs/callgraph/)** (this repo) — pwiz-ai
  tooling, split across the `pwiz` and `pwiz-ai` repos. Exercises dual-repo
  `commit_repo_base_js`, per-commit line counts via batched `git cat-file`,
  archival-group reclassification, and spawn-from-group flow.
- **[`brendanx67/wordz/callgraph/`](https://github.com/brendanx67/wordz/tree/master/callgraph)**
  — public wordz repo. Shows shadcn/ui reclassification into a distinct UI
  group, `end_commit_sha` truncation (freeze the story at a milestone), and
  per-commit `lineCount`/`testCount` via `git ls-tree` + `cat-file`.

## Adding a new project

Copy either consumer's `build.py` next to wherever you want the generated
HTML to live. Point `SHARED` at this directory, edit the `ProjectConfig`
(group colors, labels, biases, commit URLs), adjust the data-loading logic
if your extractor's shape differs, and run.

Running `build.py` is 100% local — no network. The generated HTML is
fully self-contained relative to its co-located `callgraph-manifest.js`
and `callgraph-data-*.js`; serve the directory as a unit via raw.githack,
jsdelivr, GitHub Pages, or open via `file://`.
