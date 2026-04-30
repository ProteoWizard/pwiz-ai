"""
Shared core for per-project callgraph generators.

Each project has its own build.py that knows how to load its snapshots.json
and map nodes to groups. It hands the parsed data plus a ProjectConfig to
build(), which writes the HTML + data files into out_dir.

Directory layout:
  ai/scripts/callgraph/        - this module + base.html (shared)
  ai/docs/callgraph/           - pwiz-ai build.py + generated output
  wordz/callgraph/             - wordz   build.py + generated output

The generated HTML file is self-contained relative to the co-located data
files (callgraph-manifest.js, callgraph-data-*.js). Serve the directory as
a unit via raw.githack, jsdelivr, or GitHub Pages.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

BASE_HTML = Path(__file__).resolve().parent / "base.html"
D3_MIN_JS = Path(__file__).resolve().parent / "vendor" / "d3.v7.min.js"

# Optional commit fields → compact key in the emitted snapshot.
_OPTIONAL_FIELDS = [
    ("lineCount", "l"),
    ("testCount", "t"),
]


@dataclass
class ProjectConfig:
    # --- Identity ---
    name: str                       # short key, e.g. "pwiz-ai"
    display_name: str               # shown in H1, e.g. "pwiz-ai"
    page_title: str                 # browser tab title
    # --- URLs ---
    github_base: str                # e.g. "https://github.com/brendanx67/wordz"
    commits_url: str                # link for the H1 text
    readme_url: str                 # link for the GitHub icon
    # --- Data mapping ---
    group_colors: dict[str, str]    # group -> hex
    kind_to_type: dict[str, str]    # our kind -> renderer's class/mixin/method/function
    # --- Optional customizations ---
    # Keyed by group name, value is fraction of viewport width/height in
    # [-0.5, 0.5]. Negative x = left, negative y = up. Entries ending in '*'
    # become startsWith checks (e.g., 'todos*' matches 'todos-active').
    group_x_bias: Optional[dict[str, float]] = None
    group_y_bias: Optional[dict[str, float]] = None
    # Human-readable label per group for the in-graph overlay. Multiple groups
    # can share a label (they merge into one centroid). Explicit None hides
    # the label. Missing keys fall back to the group name.
    group_labels: Optional[dict[str, Optional[str]]] = None
    # Map of group -> spawn spec for new nodes. Two forms:
    #   "sourceGroup"                          — plain source, no offset
    #   {"from": "sourceGroup", "dx": -0.05,
    #    "dy": 0}                              — source + direction, where
    #                                            dx/dy are fractions of
    #                                            viewport width/height
    # The direction form is useful when the new group's anchor lies beyond
    # the source (e.g., MCP "exits" leftward from core): new MCP nodes
    # spawn at core's centroid offset left, then drift the rest of the way
    # to MCP's own anchor. The centroid is read from a persistent cache so
    # bulk moves that temporarily empty the source still spawn correctly.
    spawn_from_group: Optional[dict] = None
    # JS function body for `commitRepoBase(snapshot) { ... }`.
    # Default returns config.github_base.
    commit_repo_base_js: Optional[str] = None
    # JS function body for label formatting: takes `d`, returns string.
    # Default takes the basename of d.id.
    label_transform_js: Optional[str] = None
    # Extra CSS inserted before </style>.
    extra_css: str = ""
    # Extra HTML inserted inside #header-right (e.g., repo badge container).
    extra_header_html: str = ""
    # Extra JS inserted after the core init.
    extra_init_js: str = ""
    # Truncate the timeline at (and including) this commit SHA. Useful when
    # you want the playback to end at a specific milestone and exclude later
    # activity — e.g. wordz freezing at the end of the original week-one burst
    # so callgraph tooling commits don't distort the narrative.
    end_commit_sha: Optional[str] = None
    # Fallback total lines when per-commit lineCount isn't tracked. The last
    # snapshot's lineCount takes precedence when present.
    summary_total_lines: Optional[int] = None
    # Panel title over the time-since-inception headline. Defaults to display_name.
    summary_title: Optional[str] = None
    # JS function body that builds the per-frame rows on the stats panel.
    # Receives (snapshot, idx) and returns an array of [label, value] pairs.
    # Default: lines (if available), files, folders, tests. Customize when
    # the project's meaningful counts don't map to those defaults.
    stats_rows_js: Optional[str] = None


# ---------------------------------------------------------------------------
# Compact timeline builder
# ---------------------------------------------------------------------------

def build_registry_and_timeline(
    commits: list,
    all_nodes: dict,
    all_edges: list,
    config: ProjectConfig,
    friend_id: Callable[[str, dict], str],
) -> tuple[list, list]:
    """
    Turn raw (commits, nodes, edges) into (registry, timeline).

    registry:  [[id, type, group, label], ...] — one entry per distinct node
    timeline:  list of compact snapshots {h,d,m,r,n:[regIdx,...],e:[[s,t,k],...]}
               where k=0 is a ref edge and k=1 is a 'contains' edge.

    Honors config.end_commit_sha — truncates the timeline at (and including)
    that commit. Nodes/edges that first appear after the truncation point are
    dropped from the registry.
    """
    # --- Apply end-commit truncation, if configured.
    if config.end_commit_sha:
        cut = None
        for i, c in enumerate(commits):
            if c["sha"].startswith(config.end_commit_sha):
                cut = i
                break
        if cut is None:
            raise ValueError(
                f"end_commit_sha {config.end_commit_sha!r} not found in commits"
            )
        commits = commits[: cut + 1]
        # Drop nodes/edges that first appear past the truncation point — they
        # would be registered but never alive in any snapshot.
        all_nodes = {
            nid: n for nid, n in all_nodes.items() if n["first_idx"] <= cut
        }
        all_edges = [e for e in all_edges if e["first_idx"] <= cut]

    nodes_sorted = sorted(all_nodes.items(), key=lambda kv: kv[1]["first_idx"])

    registry: list[list] = []
    id_to_reg_idx: dict[str, int] = {}
    for full_id, nmeta in nodes_sorted:
        fid = friend_id(full_id, nmeta)
        if fid in id_to_reg_idx:
            continue
        id_to_reg_idx[fid] = len(registry)
        registry.append([
            fid,
            config.kind_to_type.get(nmeta["kind"], "function"),
            nmeta["group"],
            nmeta.get("name", fid.split("/")[-1]),
        ])

    timeline: list[dict] = []
    for idx, c in enumerate(commits):
        alive_idx: list[int] = []
        alive_set: set[str] = set()
        for full_id, nmeta in nodes_sorted:
            if not (nmeta["first_idx"] <= idx
                    and (nmeta["last_idx"] is None or nmeta["last_idx"] > idx)):
                continue
            fid = friend_id(full_id, nmeta)
            if fid in alive_set:
                continue
            alive_set.add(fid)
            alive_idx.append(id_to_reg_idx[fid])

        edge_pairs: list[list[int]] = []
        seen: set[tuple[int, int, int]] = set()
        for e in all_edges:
            if not (e["first_idx"] <= idx
                    and (e["last_idx"] is None or e["last_idx"] > idx)):
                continue
            s_meta = all_nodes.get(e["from"])
            t_meta = all_nodes.get(e["to"])
            if not s_meta or not t_meta:
                continue
            s_fid = friend_id(e["from"], s_meta)
            t_fid = friend_id(e["to"], t_meta)
            if s_fid not in alive_set or t_fid not in alive_set or s_fid == t_fid:
                continue
            s_i, t_i = id_to_reg_idx[s_fid], id_to_reg_idx[t_fid]
            kind = 1 if e.get("kind") == "contains" else 0
            key = (s_i, t_i, kind)
            if key in seen:
                continue
            seen.add(key)
            edge_pairs.append([s_i, t_i, kind])

        snap = {
            "h": c["sha"][:7],
            "d": datetime.fromtimestamp(c["ts"]).strftime("%Y-%m-%d"),
            "m": c["msg"],
            "r": c.get("repo", config.name),
            "n": alive_idx,
            "e": edge_pairs,
        }
        # Optional per-commit stats — forwarded to the renderer if present.
        for long_key, short_key in _OPTIONAL_FIELDS:
            if long_key in c:
                snap[short_key] = c[long_key]
        timeline.append(snap)

    return registry, timeline


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

def write_data_files(out_dir: Path, registry: list, timeline: list,
                     chunk_count: int = 1) -> None:
    """Write callgraph-manifest.js + callgraph-data-*.js.

    One chunk by default. For very large projects, pass chunk_count >= 2 to
    split the timeline. The registry is always emitted in chunk 0.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    chunk_count = max(1, chunk_count)
    files = [f"callgraph-data-{i}.js" for i in range(chunk_count)]
    manifest = {"chunkCount": chunk_count, "files": files}
    (out_dir / "callgraph-manifest.js").write_text(
        f"loadCallgraphManifest({json.dumps(manifest)});", encoding="utf-8",
    )

    size = len(timeline) // chunk_count + (1 if len(timeline) % chunk_count else 0)
    for i in range(chunk_count):
        chunk = timeline[i * size: (i + 1) * size]
        prefix = ""
        if i == 0:
            prefix = f"window.__REGISTRY__ = {json.dumps(registry, separators=(',',':'))};\n"
        body = f"loadCallgraphChunk({i}, {json.dumps(chunk, separators=(',',':'))});"
        (out_dir / files[i]).write_text(prefix + body, encoding="utf-8")


def write_dated_html(out_dir: Path, html: str, project_name: str) -> Path:
    """Write callgraph-YYYY-MM-DD.html + a callgraph-latest.html copy.

    Returns the path to the dated file. The latest copy gives a stable URL
    that always points at the most recent generation; the dated file is the
    git-tracked snapshot.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    today = datetime.now().strftime("%Y-%m-%d")
    dated = out_dir / f"callgraph-{today}.html"
    latest = out_dir / "callgraph-latest.html"
    dated.write_text(html, encoding="utf-8")
    # latest is the stable shareable name (served via raw.githack / Pages).
    # dated is the git-tracked snapshot for history. Commit either or both.
    latest.write_text(html, encoding="utf-8")
    return dated


# ---------------------------------------------------------------------------
# HTML patchers
# ---------------------------------------------------------------------------

def _replace_once(html: str, old: str, new: str, where: str) -> str:
    if old not in html:
        raise ValueError(f"patch failed — '{where}': anchor not found")
    return html.replace(old, new, 1)


def patch_html(base_html: str, config: ProjectConfig) -> str:
    """Apply every common patch. Order matters: earlier anchors must survive
    later replacements."""
    html = base_html

    # --- Inline d3 so the HTML is self-contained (no CDN dependency) ------
    html = _replace_once(
        html,
        '<script src="https://d3js.org/d3.v7.min.js"></script>',
        f"<script>\n{D3_MIN_JS.read_text(encoding='utf-8')}\n</script>",
        "d3 inline",
    )

    # --- Title + header links ----------------------------------------------
    html = _replace_once(
        html,
        "<title>Mandelbrot Call Graph Evolution</title>",
        f"<title>{config.page_title}</title>",
        "page title",
    )
    html = _replace_once(
        html,
        "https://github.com/davidbau/mandelbrot/commits/main",
        config.commits_url,
        "commits link",
    )
    html = _replace_once(
        html,
        "https://github.com/davidbau/mandelbrot#readme",
        config.readme_url,
        "readme link",
    )
    html = _replace_once(
        html,
        ">Mandelbrot</a>",
        f">{config.display_name}</a>",
        "H1 project name",
    )
    html = _replace_once(
        html, "href=\"../\"", "href=\"#\"", "root link",
    )
    # pwiz-ai's mandelbrot page blobs point at /index.html; drop that for
    # projects where the root path is what we want.
    html = _replace_once(
        html,
        "/blob/${hash}/index.html",
        "/blob/${hash}/",
        "blob path",
    )

    # --- Legend CSS + HTML -------------------------------------------------
    legend_css = _LEGEND_CSS + config.extra_css + "\n  </style>"
    html = _replace_once(html, "  </style>", legend_css, "legend CSS")

    group_entries = "\n            ".join(
        f'<span><span class="g-swatch" style="background:{c}"></span>{g}</span>'
        for g, c in config.group_colors.items()
    )
    legend_html = f"""<div id="header-right">
        <div id="stats">Loading...</div>
        <div id="legend">
          <div id="mode-buttons">
            <button id="mode-time" class="active" title="Color by when the node was first added">time</button>
            <button id="mode-group">group</button>
          </div>
          <div id="legend-time">
            <span class="legend-label">older</span>
            <span class="legend-gradient"></span>
            <span class="legend-label">newer</span>
          </div>
          <div id="legend-group" style="display:none">
            {group_entries}
          </div>
        </div>
        {config.extra_header_html}
      </div>"""
    html = _replace_once(
        html, '<div id="stats">Loading...</div>', legend_html, "legend HTML",
    )

    # --- Injections into the main <script> --------------------------------
    commit_repo_body = (
        config.commit_repo_base_js
        or f"return '{config.github_base}';"
    )
    label_body = (
        config.label_transform_js
        or "let label = d.label || d.id.split('/').pop(); "
           "return label.length > 22 ? label.slice(0, 22) + '...' : label;"
    )
    group_colors_js = json.dumps(config.group_colors)
    group_x_bias_body = _make_group_bias_body(config.group_x_bias, "width")
    group_y_bias_body = _make_group_bias_body(config.group_y_bias, "height")
    group_labels_js = json.dumps(config.group_labels) if config.group_labels else "null"
    spawn_from_js = json.dumps(config.spawn_from_group) if config.spawn_from_group else "null"
    summary_title = config.summary_title or config.display_name
    stats_rows_body = config.stats_rows_js or _DEFAULT_STATS_ROWS_JS

    injection = _INJECTION_TEMPLATE.format(
        group_colors_js=group_colors_js,
        group_labels_js=group_labels_js,
        spawn_from_js=spawn_from_js,
        commit_repo_base_body=commit_repo_body,
        label_transform_body=label_body,
        group_x_bias_body=group_x_bias_body,
        group_y_bias_body=group_y_bias_body,
        summary_title_js=json.dumps(summary_title),
        summary_total_lines_js=json.dumps(config.summary_total_lines),
        stats_rows_body=stats_rows_body,
        extra_init_js=config.extra_init_js,
    )
    html = _replace_once(
        html, "    let timeline = [];", injection, "script injection",
    )

    # --- Rewire commit click handlers to use commitRepoBase() -------------
    html = _replace_once(
        html,
        "if (hash) window.open(`https://github.com/davidbau/mandelbrot/commit/${hash}`, '_blank');",
        "if (hash) window.open(`${commitRepoBase(timeline[currentIndex])}/commit/${hash}`, '_blank');",
        "hash click",
    )
    # The other two commit-info handlers are the same line repeated — use
    # replace-all style by doing two more replacements with unique context.
    html = html.replace(
        "if (hash) window.open(`https://github.com/davidbau/mandelbrot/commit/${hash}`, '_blank');",
        "if (hash) window.open(`${commitRepoBase(timeline[currentIndex])}/commit/${hash}`, '_blank');",
    )
    html = _replace_once(
        html,
        "if (hash) window.open(`https://github.com/davidbau/mandelbrot/blob/${hash}/`, '_blank');",
        "if (hash) window.open(`${commitRepoBase(timeline[currentIndex])}/blob/${hash}/`, '_blank');",
        "blob click",
    )
    html = _replace_once(
        html,
        "const url = `https://github.com/davidbau/mandelbrot/blob/${hash}/index.html${lineRange}`;",
        "const url = `${commitRepoBase(snapshot)}/blob/${hash}/${lineRange}`;",
        "node-click blob",
    )

    # --- Replace circle fill logic ----------------------------------------
    html = _replace_once(
        html,
        """      nodeMerge.select('circle')
        .attr('fill', d => {
          const t = d.firstSeen / maxIdx;
          // Offset to avoid dark colors, use brighter range (0.4 to 1.0)
          return d3.interpolateTurbo(0.15 + t * 0.7);
        });""",
        """      nodeMerge.select('circle')
        .attr('fill', d => getNodeColor(d, maxIdx));""",
        "circle fill",
    )

    # --- Replace label formatting -----------------------------------------
    html = _replace_once(
        html,
        """      nodeMerge.select('text')
        .text(d => {
          // For methods, strip class prefix (show full name on hover)
          let label = d.type === 'method' && d.id.includes('.') ? d.id.split('.').pop() : d.id;
          return label.length > 20 ? label.slice(0, 20) + '...' : label;
        });""",
        """      nodeMerge.select('text')
        .text(d => formatNodeLabel(d));""",
        "label formatting",
    )

    # --- Wire the color-mode toggle after setupSVG() ----------------------
    html = _replace_once(
        html,
        "      setupSVG();",
        """      setupSVG();

      // Wire up color-mode toggle
      document.getElementById('mode-time').addEventListener('click', () => {
        window._colorMode = 'time';
        applyNodeColors(); updateLegendDisplay();
      });
      document.getElementById('mode-group').addEventListener('click', () => {
        window._colorMode = 'group';
        applyNodeColors(); updateLegendDisplay();
      });
      updateLegendDisplay();""",
        "setupSVG toggle wiring",
    )

    # --- Expand compact snapshots before any use --------------------------
    html = _replace_once(
        html,
        "      // Track when each node first appeared",
        "      // Expand compact-encoded snapshots in place\n"
        "      timeline.forEach(expandSnapshot);\n\n"
        "      // Track when each node first appeared",
        "expandSnapshot wiring",
    )

    # --- Rewire x/y forces to use group-biased targets -------------------
    html = _replace_once(
        html,
        ".force('x', d3.forceX(0).strength(xStrength))",
        ".force('x', d3.forceX(makeGroupTargetX(width)).strength(xStrength))",
        "x-force setup",
    )
    html = _replace_once(
        html,
        ".force('y', d3.forceY(0).strength(yStrength))",
        ".force('y', d3.forceY(makeGroupTargetY(height)).strength(yStrength))",
        "y-force setup",
    )
    html = _replace_once(
        html,
        "simulation.force('x').x(0).strength(xStrength);",
        "simulation.force('x').x(makeGroupTargetX(width)).strength(xStrength);",
        "x-force update",
    )
    html = _replace_once(
        html,
        "simulation.force('y').y(0).strength(yStrength);",
        "simulation.force('y').y(makeGroupTargetY(height)).strength(yStrength);",
        "y-force update",
    )

    # --- Update group-name overlays on tick and whenever the frame changes.
    html = _replace_once(
        html,
        "        nodeMerge.attr('transform', d => `translate(${d.x},${d.y})`);\n      });",
        "        nodeMerge.attr('transform', d => `translate(${d.x},${d.y})`);\n"
        "        maybeUpdateGroupLabels();\n"
        "      });\n\n"
        "      // Snap labels immediately on frame change (ticks smooth it out).\n"
        "      updateGroupLabels();\n"
        "      // Refresh the persistent stats panel for this frame.\n"
        "      updateStatsPanel(snapshot, index);",
        "group-label + stats-panel tick hook",
    )

    # The header-bar "N lines, N classes, ..." stats text was project-agnostic
    # and often nonsensical (zero lines, meaningless class counts). Drop it —
    # the upper-right panel carries richer, project-specific rows now.
    html = _replace_once(
        html,
        "      document.getElementById('stats').textContent = parts.join(', ');",
        "      // stats text suppressed; #stats-panel shows richer rows.",
        "header stats suppression",
    )

    # --- Spawn-from-group: new-node positioning for archival-style events.
    # Replace the "new node near (0,0)" block with a centroid-aware spawn:
    # new archive nodes stream out from the group they were moved from
    # instead of materializing in the middle of the viewport.
    html = _replace_once(
        html,
        "        } else {\n"
        "          // New node: position near center (0,0) with small random offset\n"
        "          return {\n"
        "            ...nodeData,\n"
        "            x: (Math.random() - 0.5) * 100,\n"
        "            y: (Math.random() - 0.5) * 100\n"
        "          };\n"
        "        }",
        "        } else {\n"
        "          // New node: spawn from configured source-group centroid\n"
        "          // (live or cached) + optional direction offset; else\n"
        "          // near viewport center. Bulk archival events clearing\n"
        "          // the source still work thanks to the centroid cache.\n"
        "          const sourceGroup = spawnSourceFor(n.group);\n"
        "          let sx = 0, sy = 0, sourced = false;\n"
        "          if (sourceGroup) {\n"
        "            const c = groupCentroids.get(sourceGroup)\n"
        "                   || window._groupCentroidCache.get(sourceGroup);\n"
        "            if (c) { sx = c.x; sy = c.y; sourced = true; }\n"
        "            const offset = spawnOffsetFor(n.group, width, height);\n"
        "            sx += offset.dx; sy += offset.dy;\n"
        "          }\n"
        "          const jitter = sourced ? 40 : 100;\n"
        "          return {\n"
        "            ...nodeData,\n"
        "            x: sx + (Math.random() - 0.5) * jitter,\n"
        "            y: sy + (Math.random() - 0.5) * jitter\n"
        "          };\n"
        "        }",
        "new-node spawn",
    )

    # Precompute per-group centroids before the node-map runs, using the
    # positions carried forward from the previous frame, and keep a cache
    # so bulk moves that empty a source group still have a valid origin.
    html = _replace_once(
        html,
        "      // Prepare data with positions preserved from previous frame\n"
        "      const nodes = snapshot.nodes.map(n => {",
        "      // Centroids of each group at this moment. Also updates the\n"
        "      // persistent cache so bulk archival events that empty the\n"
        "      // source can still spawn from its last known location.\n"
        "      const groupCentroids = new Map();\n"
        "      if (SPAWN_FROM_GROUP) {\n"
        "        const sums = new Map();\n"
        "        snapshot.nodes.forEach(n => {\n"
        "          const pos = nodePositions.get(n.id);\n"
        "          if (!pos) return;\n"
        "          let s = sums.get(n.group);\n"
        "          if (!s) { s = {sx: 0, sy: 0, count: 0}; sums.set(n.group, s); }\n"
        "          s.sx += pos.x; s.sy += pos.y; s.count++;\n"
        "        });\n"
        "        sums.forEach((s, g) => {\n"
        "          if (s.count > 0) {\n"
        "            const c = {x: s.sx / s.count, y: s.sy / s.count};\n"
        "            groupCentroids.set(g, c);\n"
        "            window._groupCentroidCache.set(g, c);\n"
        "          }\n"
        "        });\n"
        "      }\n\n"
        "      // Prepare data with positions preserved from previous frame\n"
        "      const nodes = snapshot.nodes.map(n => {",
        "group centroid precomputation",
    )

    return html


def _make_group_bias_body(bias: Optional[dict[str, float]], dim: str) -> str:
    """Emit JS function body that returns a bias-function closure.

    `dim` is 'width' or 'height' — the variable multiplied by each fraction.
    Input: None (no bias) or a {group: fraction} map. Entries ending in '*'
    become startsWith checks.
    """
    if not bias:
        return "return (d) => 0;"
    body = "return (d) => {\n"
    for g, frac in bias.items():
        if g.endswith("*"):
            prefix = g[:-1]
            body += (f"    if (d.group && d.group.startsWith({json.dumps(prefix)}))"
                     f" return {dim} * {frac};\n")
        else:
            body += (f"    if (d.group === {json.dumps(g)})"
                     f" return {dim} * {frac};\n")
    body += "    return 0;\n  };"
    return body


_DEFAULT_STATS_ROWS_JS = """\
      const nodes = snapshot.nodes;
      const folders = nodes.filter(n => n.group === 'folders').length;
      const files = nodes.length - folders;
      const lines = snapshot.lineCount
        || (idx === timeline.length - 1 ? SUMMARY_TOTAL_LINES : 0);
      const rows = [];
      if (lines)   rows.push(['lines',   Number(lines).toLocaleString()]);
      if (files)   rows.push(['files',   files.toLocaleString()]);
      if (folders) rows.push(['folders', folders.toLocaleString()]);
      if (snapshot.testCount) {
        rows.push(['tests', snapshot.testCount.toLocaleString()]);
      }
      return rows;"""


# ---------------------------------------------------------------------------
# Static HTML fragments
# ---------------------------------------------------------------------------

_LEGEND_CSS = """
    #legend {
      display: flex; align-items: center; gap: 14px;
      font-size: 12px; color: #555; flex-wrap: wrap;
    }
    #mode-buttons { display: flex; gap: 4px; }
    #mode-buttons button {
      border: 1px solid #ccc; background: white; padding: 2px 8px;
      border-radius: 3px; cursor: pointer; font-size: 11px;
    }
    #mode-buttons button.active {
      background: #e94560; color: white; border-color: #e94560;
    }
    .legend-gradient {
      display: inline-block; width: 120px; height: 10px;
      background: linear-gradient(to right,
        #3e4a89, #31678e, #1f9e89, #6ece58,
        #fde725, #fca636, #d44842, #9f1a1a);
      border-radius: 2px;
      vertical-align: middle;
    }
    .legend-label { color: #888; font-size: 11px; }
    #legend-group { display: flex; align-items: center;
                    gap: 10px; flex-wrap: wrap; }
    .g-swatch {
      display: inline-block; width: 10px; height: 10px;
      border-radius: 50%; margin-right: 3px; vertical-align: middle;
    }
    #header-right {
      display: flex; align-items: center; gap: 20px;
      flex-wrap: wrap; justify-content: flex-end;
    }
"""


# `let timeline = [];` is the anchor. We inject a large JS block before it.
_INJECTION_TEMPLATE = r"""
    // =================================================================
    // Shared callgraph additions (color toggle, compact-encoding, group
    // positioning, label formatting, commit-repo-base override).
    // =================================================================

    // --- Color mode --------------------------------------------------
    window._colorMode = 'time';
    const GROUP_COLORS = {group_colors_js};
    // group -> display label, or null to suppress. Missing keys fall back
    // to the group name. Multiple groups mapped to the same label merge
    // into one centroid.
    const GROUP_LABELS = {group_labels_js};
    // group -> spawn spec. Two shapes:
    //   "sourceGroup"
    //   {{"from": "sourceGroup", "dx": fraction, "dy": fraction}}
    // See ProjectConfig.spawn_from_group for the rationale.
    const SPAWN_FROM_GROUP = {spawn_from_js};
    // Persistent centroid cache — the last *known* centroid for each group.
    // Keeps spawn-from-group reliable through bulk moves that temporarily
    // empty the source group (e.g., an archival wave clearing Completed):
    // the cache remembers where Completed *was* a moment ago.
    window._groupCentroidCache = new Map();
    // Helpers to normalize the two spawn-spec shapes.
    function spawnSourceFor(group) {{
      const spec = SPAWN_FROM_GROUP && SPAWN_FROM_GROUP[group];
      if (!spec) return null;
      return typeof spec === 'string' ? spec : spec.from;
    }}
    function spawnOffsetFor(group, width, height) {{
      const spec = SPAWN_FROM_GROUP && SPAWN_FROM_GROUP[group];
      if (!spec || typeof spec === 'string') return {{dx: 0, dy: 0}};
      return {{
        dx: (spec.dx || 0) * width,
        dy: (spec.dy || 0) * height,
      }};
    }}
    function getNodeColor(d, maxIdx) {{
      if (window._colorMode === 'group') {{
        return GROUP_COLORS[d.group] || '#999';
      }}
      const t = d.firstSeen / maxIdx;
      return d3.interpolateTurbo(0.15 + t * 0.7);
    }}
    function applyNodeColors() {{
      const svg = d3.select('#graph-container svg');
      if (svg.empty()) return;
      const g = svg.select('g');
      const maxIdx = currentIndex || 1;
      g.select('.nodes').selectAll('circle')
        .attr('fill', d => getNodeColor(d, maxIdx));
    }}
    function updateLegendDisplay() {{
      const groupMode = window._colorMode === 'group';
      document.getElementById('legend-time').style.display = groupMode ? 'none' : 'flex';
      document.getElementById('legend-group').style.display = groupMode ? 'flex' : 'none';
      document.getElementById('mode-time').classList.toggle('active', !groupMode);
      document.getElementById('mode-group').classList.toggle('active', groupMode);
    }}

    // --- Per-commit repo resolution (dual-repo projects override) ----
    function commitRepoBase(snapshot) {{
      {commit_repo_base_body}
    }}

    // --- Label formatting --------------------------------------------
    function formatNodeLabel(d) {{
      {label_transform_body}
    }}

    // --- Group-biased x/y positioning --------------------------------
    function makeGroupTargetX(width) {{
      {group_x_bias_body}
    }}
    function makeGroupTargetY(height) {{
      {group_y_bias_body}
    }}

    // --- Group-name overlays -----------------------------------------
    // Floating labels positioned at the centroid of each group's node
    // cluster. Visible iff the group has nodes at the current frame —
    // fade out when scrubbing back to a time before the group existed.
    window._groupLabelEls = new Map();   // label -> DOM element
    window._groupLabelPos  = new Map();  // label -> smoothed {{x, y}}
    window._groupLabelLastUpdate = 0;
    function labelFor(group) {{
      if (!group) return null;
      if (GROUP_LABELS && Object.prototype.hasOwnProperty.call(GROUP_LABELS, group)) {{
        return GROUP_LABELS[group];  // may be null → suppressed
      }}
      return group;
    }}
    function ensureGroupLabelEl(label) {{
      let el = window._groupLabelEls.get(label);
      if (el) return el;
      const host = document.getElementById('group-overlays');
      if (!host) return null;
      el = document.createElement('div');
      el.className = 'group-label';
      el.textContent = label;
      host.appendChild(el);
      window._groupLabelEls.set(label, el);
      return el;
    }}
    function updateGroupLabels() {{
      if (!simulation) return;
      const container = document.getElementById('graph-container');
      if (!container) return;
      const width = container.clientWidth;
      const height = container.clientHeight;
      const svg = d3.select('#graph-container svg');
      const transform = svg.empty() ? d3.zoomIdentity
                                    : d3.zoomTransform(svg.node());
      const sums = new Map();  // label -> {{sx, sy, count}}
      simulation.nodes().forEach(n => {{
        const lbl = labelFor(n.group);
        if (!lbl) return;
        let s = sums.get(lbl);
        if (!s) {{ s = {{sx: 0, sy: 0, count: 0}}; sums.set(lbl, s); }}
        s.sx += n.x; s.sy += n.y; s.count++;
      }});
      // Position every label we have an element for. Empty groups get dimmed
      // instead of removed, preserving the in-situ legend.
      const allLabels = new Set([...window._groupLabelEls.keys(), ...sums.keys()]);
      allLabels.forEach(lbl => {{
        const el = ensureGroupLabelEl(lbl);
        if (!el) return;
        const s = sums.get(lbl);
        if (s && s.count > 0) {{
          const cx = s.sx / s.count;
          const cy = s.sy / s.count;
          // SVG-coord → screen-coord conversion (viewBox is centered).
          const screenX = transform.applyX(cx) + width / 2;
          const screenY = transform.applyY(cy) + height / 2;
          // Exponential smoothing so the label doesn't jitter with the sim.
          const prev = window._groupLabelPos.get(lbl);
          const smX = prev ? prev.x * 0.8 + screenX * 0.2 : screenX;
          const smY = prev ? prev.y * 0.8 + screenY * 0.2 : screenY;
          window._groupLabelPos.set(lbl, {{x: smX, y: smY}});
          el.style.left = smX + 'px';
          el.style.top  = smY + 'px';
          el.classList.add('visible');
        }} else {{
          // No nodes at this frame — hide the label. It'll fade back in
          // with the CSS transition when the group populates again.
          el.classList.remove('visible');
          // Drop the smoothed position so the next appearance doesn't
          // start from a stale centroid.
          window._groupLabelPos.delete(lbl);
        }}
      }});
    }}
    function maybeUpdateGroupLabels() {{
      const now = performance.now();
      if (now - window._groupLabelLastUpdate < 100) return;
      window._groupLabelLastUpdate = now;
      updateGroupLabels();
    }}

    // --- Stats panel (persistent upper-right) ------------------------
    // Always-visible. Updated on every frame; the final frame's state is
    // the natural "punchline" — no popup to dismiss.
    const SUMMARY_TITLE = {summary_title_js};
    const SUMMARY_TOTAL_LINES = {summary_total_lines_js};
    function humanSpan(firstDate, lastDate) {{
      if (!firstDate || !lastDate) return null;
      const a = new Date(firstDate), b = new Date(lastDate);
      if (isNaN(a) || isNaN(b)) return null;
      const days = Math.max(0, Math.round((b - a) / 86400000));
      if (days === 0)       return 'day one';
      if (days === 1)       return '1 day';
      if (days < 14)        return `${{days}} days`;
      if (days < 70)        return `${{Math.round(days / 7)}} weeks`;
      if (days < 365 * 1.5) return `${{Math.round(days / 30)}} months`;
      return `${{(days / 365).toFixed(1)}} years`;
    }}
    function buildStatsRows(snapshot, idx) {{
      {stats_rows_body}
    }}
    function updateStatsPanel(snapshot, idx) {{
      if (!timeline.length) return;
      const panel = document.getElementById('stats-panel');
      if (!panel) return;
      panel.querySelector('.panel-title').textContent = SUMMARY_TITLE;
      const span = humanSpan(timeline[0].date, snapshot.date);
      panel.querySelector('.panel-headline').textContent = span || '';
      const rows = buildStatsRows(snapshot, idx);
      panel.querySelector('.panel-rows').innerHTML = rows.map(r =>
        `<div class="row"><span class="label">${{r[0]}}</span><span class="value">${{r[1]}}</span></div>`
      ).join('');
    }}

    // --- Compact-snapshot expansion ----------------------------------
    // Input snapshot: {{h, d, m, r, n:[regIdx,...], e:[[src,tgt,kind],...]}}
    // Registry:       window.__REGISTRY__ = [[id, type, group, label], ...]
    // kind: 0 = ref, 1 = contains.
    function expandSnapshot(s) {{
      if (s.nodes) return;   // already expanded
      const reg = window.__REGISTRY__;
      const nodes = [];
      for (const i of s.n) {{
        const r = reg[i];
        nodes.push({{
          id: r[0], type: r[1], group: r[2], label: r[3],
          script: 0, line: 1, endLine: 1, file: r[0],
        }});
      }}
      const edges = [];
      for (const p of s.e) {{
        edges.push({{
          source: reg[p[0]][0],
          target: reg[p[1]][0],
          type: p[2] === 1 ? 'contains' : 'refs',
        }});
      }}
      s.nodes = nodes;
      s.edges = edges;
      s.hash = s.h;
      s.date = s.d;
      s.message = s.m;
      s.repo = s.r;
      // Coauthor badges are suppressed: every commit here is Claude-assisted,
      // so a per-commit flag adds noise without signal.
      s.claudeCoauthored = false;
      s.geminiCoauthored = false;
      s.codexCoauthored  = false;
      s.lineCount = s.l ?? 0;
      s.testCount = s.t ?? 0;
      s.nodeCount = nodes.length;
      s.edgeCount = edges.length;
    }}

    {extra_init_js}
    // =================================================================

    let timeline = [];"""


# ---------------------------------------------------------------------------
# Top-level entry point
# ---------------------------------------------------------------------------

def build(
    config: ProjectConfig,
    commits: list,
    all_nodes: dict,
    all_edges: list,
    friend_id: Callable[[str, dict], str],
    out_dir: Path,
    chunk_count: int = 1,
    base_html_path: Optional[Path] = None,
) -> Path:
    """Run the full pipeline for a project.

    Returns the path of the dated HTML snapshot written into out_dir.
    """
    base = (base_html_path or BASE_HTML).read_text(encoding="utf-8")
    registry, timeline = build_registry_and_timeline(
        commits, all_nodes, all_edges, config, friend_id,
    )
    print(f"  {len(commits)} commits, {len(registry)} unique nodes, "
          f"{len(timeline)} snapshots")

    write_data_files(out_dir, registry, timeline, chunk_count)
    patched = patch_html(base, config)
    dated = write_dated_html(out_dir, patched, config.name)
    total = sum(f.stat().st_size for f in out_dir.iterdir() if f.is_file())
    print(f"  wrote {dated.name} ({total:,} bytes total)")
    return dated
