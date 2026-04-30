# callgraph — pwiz-ai

Animated playback of how the AI-tooling tree grew across 584 commits
(spanning the `pwiz` and `pwiz-ai` repos). Nodes are docs, skills, commands,
TODOs, scripts, and MCP tools; edges are markdown references and folder
containment.

## Viewing

Open [`callgraph-latest.html`](callgraph-latest.html) in a browser
(`file://` works — everything inline). Click the large centered Play
button to watch the growth. The transport row (`⏮ ▶ ⏭ 1×`) and the
scrubber let you navigate frame-by-frame; Space toggles play, arrows
step, the speed button cycles 1× → 2× → 4× → 0.5×.

For a shareable URL that renders HTML correctly, serve through a host
that sets the right MIME type — `raw.githack.com` or `jsdelivr.net`
work for GitHub-hosted files; `raw.githubusercontent.com` does **not**
(it serves HTML as `text/plain`).

## Files

- **`callgraph-latest.html`** — stable entry point, overwritten on every
  rebuild. This is the one to link.
- **`callgraph-YYYY-MM-DD.html`** — dated snapshot for historical
  comparison. Commit on purpose, not every rebuild.
- **`callgraph-manifest.js`** + **`callgraph-data-0.js`** — the timeline
  data. Must live next to the HTML.
- **`build.py`** — generator. Reads `snapshots.json`, applies the pwiz-ai
  `ProjectConfig` (group colors, biases, archive reclassification,
  dual-repo commit URLs), and writes the HTML + data files via the shared
  core.

## Regenerating

```
python build.py
```

Requires `snapshots.json` (currently produced by the extractor under
`ai/.tmp/pwiz-ai-timeline/out/`). The build is local — per-commit line
counts run against `C:/proj/ai` and `C:/proj/pwiz` via `git cat-file
--batch`, so clones of both need to be present.

## Shared core

Lives at [`../../scripts/callgraph/`](../../scripts/callgraph/). The
renderer, template, transport, overlay, and stats-panel logic all live
there — `build.py` is intentionally thin and only knows about pwiz-ai
specifics.

A second consumer of the same core lives at
[`brendanx67/wordz/callgraph/`](https://github.com/brendanx67/wordz/tree/master/callgraph)
— open example of a different project's build.py.
