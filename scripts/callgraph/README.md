# callgraph — shared core

Animated callgraph viewer. Walks a project's git history and emits a
self-contained HTML page that plays back how the codebase grew: nodes fade
in when first touched, edges appear when references are added, and group
labels float at the centroid of each cluster.

Derived from [davidbau/mandelbrot](https://github.com/davidbau/mandelbrot)'s
page-growth viewer. Most of the force-simulation and animation code came
from there; this layer adds the git-history extractor, the shared patch
pipeline, compact-encoded timeline data, group/label system, transport
controls, stats panel, and project-configurable hooks.

## Files

- **extract.py** — the git-history extractor. `ExtractConfig` + `Source`
  describe the repos (several, merged by commit time, for a project that
  moved), which files become nodes, and how they are grouped and labeled;
  `extract(cfg, end_ts=None)` returns the commits, nodes (with their
  first/last commit) and edges (folder containment plus relative markdown
  links). `end_ts` stops the timeline at a moment, to reproduce an earlier
  generation. Import as `from callgraph import extract`.
- **core.py** — the renderer. `ProjectConfig`, `build_registry_and_timeline`,
  `patch_html`, `write_data_files`, `write_dated_html`. Import as
  `from callgraph import core`.
- **base.html** — the template that gets patched. Pristine mandelbrot-page
  HTML plus the transport row, overlays, and stats panel.
- **vendor/d3.v7.min.js** — pinned d3. Inlined into the output HTML so the
  generated file has zero CDN dependencies.
- **__init__.py** — makes the directory an importable package.

Until 2026-10 the extractor lived only in an uncommitted `ai/.tmp/` folder
and was lost; `extract.py` is its reconstruction, checked against the data
it had produced.

## Data files and long histories

`write_data_files(..., stamp="YYYY-MM-DD")` names the data
`callgraph-<stamp>-manifest.js` / `callgraph-<stamp>-data-*.js`, and
`write_dated_html(..., stamp=...)` points that date's page at them, so each
generation keeps its own data. Without a stamp the files are the undated
`callgraph-manifest.js` / `callgraph-data-*.js`.

`delta=True` writes each snapshot after the first as the nodes and edges
added and removed since the previous one; the page decodes it into
keyframes and builds a snapshot's nodes and edges only when it is shown.
Use it for any long history: the pwiz-ai data is 1 MB that way and 85 MB
written in full. Pages decode both forms.

## Example consumers

- **[`ai/docs/callgraph/`](../../docs/callgraph/)** (this repo) — pwiz-ai
  tooling, split across the `pwiz` and `pwiz-ai` repos. Exercises the
  two-source extractor, dual-repo `commit_repo_base_js`, per-commit line
  counts via batched `git cat-file`, archival-group reclassification,
  spawn-from-group flow, dated data and delta encoding.
- **[`brendanx67/wordz/callgraph/`](https://github.com/brendanx67/wordz/tree/master/callgraph)**
  — public wordz repo. Shows shadcn/ui reclassification into a distinct UI
  group, `end_commit_sha` truncation (freeze the story at a milestone), and
  per-commit `lineCount`/`testCount` via `git ls-tree` + `cat-file`. It
  still reads a `snapshots.json`; switching it to `extract.py` is a matter
  of an `ExtractConfig` like pwiz-ai's.

## Adding a new project

Copy `ai/docs/callgraph/build.py` next to wherever you want the generated
HTML to live. Point `SHARED` at this directory, replace the `ExtractConfig`
(repos, file filter, `classify`, `label`) and the `ProjectConfig` (group
colors, labels, biases, commit URLs), and run.

Running `build.py` is 100% local — no network. The generated HTML is
fully self-contained relative to its co-located manifest and data files;
serve the directory as a unit via raw.githack, jsdelivr, GitHub Pages, or
open via `file://`.
