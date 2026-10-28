# callgraph — pwiz-ai

Animated playback of how the AI-tooling tree grew, commit by commit,
across the `pwiz` repo (where `ai/` began, on `master` and the
`ai-context` branch) and the `pwiz-ai` repo it moved to on 2026-01-10.
Nodes are docs, skills, commands, TODOs, scripts, and MCP tools; edges are
markdown links and folder containment.

## Viewing

Open [`callgraph-latest.html`](callgraph-latest.html) in a browser
(`file://` works — everything inline). Click the large centered Play
button to watch the growth. The transport row (`⏮ ▶ ⏭ 1×`) and the
scrubber let you navigate frame-by-frame; Space toggles play, arrows
step, the speed button cycles 1× → 2× → 4× → 8× → 16× → 0.5×. The full
history is thousands of commits, so 8× or 16× is the comfortable way to
watch all of it.

For a shareable URL that renders HTML correctly, serve through a host
that sets the right MIME type — `raw.githack.com` or `jsdelivr.net`
work for GitHub-hosted files; `raw.githubusercontent.com` does **not**
(it serves HTML as `text/plain`).

## Files

- **`callgraph-latest.html`** — stable entry point, a copy of the newest
  dated page. This is the one to link.
- **`callgraph-YYYY-MM-DD.html`** + **`callgraph-YYYY-MM-DD-manifest.js`**
  + **`callgraph-YYYY-MM-DD-data-0.js`** — one generation. Each dated page
  loads its own data, so a new generation never changes an old one.
  - `2026-04-30` — the first generation: 584 commits, 2025-11-05 to
    2026-04-23 (`2026-04-24.html` is the same data with the renderer of
    that day).
  - `2026-10-27` — the full history to that date.
- **`build.py`** — generator: the pwiz-ai settings (repos, which files,
  groups, labels, colors, layout biases) on top of the shared
  extractor and renderer.

## Regenerating

```
python build.py                      # full history, stamped today
python build.py --end 2026-04-23     # stop at a day (or a pwiz-ai SHA)
```

Needs local clones of `pwiz-ai` (`C:/proj/ai`) and `pwiz` (`C:/proj/pwiz`)
with `origin/master` and `origin/ai-context` fetched. It reads every
commit's tree with git, so a run takes a few minutes. Commit the new
dated files and the updated `callgraph-latest.html`.

`--end` reproduces an earlier generation (as `callgraph-<end date>.*`,
leaving `callgraph-latest.html` alone), which is how the extractor was
checked: `python build.py --end 0aaf9e0` regenerates the 2026-04-30 data,
with every node and edge in every snapshot the same except one frame where
two commits share a timestamp (now in parent-before-child order) and five
labels of renamed TODOs.

## Shared code

Lives at [`../../scripts/callgraph/`](../../scripts/callgraph/):
`extract.py` walks the git history, `core.py` and `base.html` render it.
`build.py` is intentionally thin and only knows about pwiz-ai specifics.

A second consumer of the same core lives at
[`brendanx67/wordz/callgraph/`](https://github.com/brendanx67/wordz/tree/master/callgraph)
— open example of a different project's build.py.
