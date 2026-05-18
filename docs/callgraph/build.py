#!/usr/bin/env python3
"""
Generate the pwiz-ai callgraph HTML from snapshots.json.

Shared pipeline lives in ai/scripts/callgraph/core.py. This file supplies
the pwiz-ai-specific data mapping: group colors, kind→type, group x-bias,
and the dual-repo commit link resolver (pwiz vs pwiz-ai).

Usage:
    python build.py [path/to/snapshots.json]

Default snapshots.json path is ai/.tmp/pwiz-ai-timeline/out/snapshots.json.
Writes callgraph-YYYY-MM-DD.html + callgraph-latest.html alongside this script.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

# --- Locate the shared core -------------------------------------------------
# This file lives at ai/docs/callgraph/build.py; the shared core lives at
# ai/scripts/callgraph/core.py. Both are in the pwiz-ai repo.
HERE = Path(__file__).resolve().parent
SHARED = HERE.parent.parent / "scripts"
sys.path.insert(0, str(SHARED))

from callgraph import core  # noqa: E402


DEFAULT_SNAPSHOTS = (
    HERE.parent.parent / ".tmp" / "pwiz-ai-timeline" / "out" / "snapshots.json"
)


# ---------------------------------------------------------------------------
# pwiz-ai project config
# ---------------------------------------------------------------------------

CONFIG = core.ProjectConfig(
    name="pwiz-ai",
    # Branded caps matches the panel title and gives the H1 the same weight.
    display_name="PWIZ-AI",
    page_title="PWIZ-AI — Growth of the AI Tooling Repo",
    github_base="https://github.com/ProteoWizard/pwiz-ai",
    commits_url="https://github.com/ProteoWizard/pwiz-ai/commits/master",
    readme_url="https://github.com/ProteoWizard/pwiz-ai#readme",
    group_colors={
        "core":            "#e06c75",
        "docs":            "#61afef",
        "skills":          "#98c379",
        "commands":        "#d19a66",
        "todos-active":    "#ef5350",
        "todos-backlog":   "#9ccc65",
        "todos-completed": "#43d17a",
        # Archived TODOs (completed + moved into a year/month subfolder).
        # Darker green — same family as completed, visually "rotated out".
        "todos-archive":   "#2e7d32",
        "todos-meta":      "#c678dd",
        "claude-meta":     "#abb2bf",
        "scripts":         "#56b6c2",
        "mcp":             "#e5c07b",
        "folders":         "#546e7a",
    },
    kind_to_type={
        "folder":  "class",     # structural anchor — large thick circle
        "todo":    "mixin",     # dashed stroke, stands out
        "skill":   "method",
        "doc":     "function",
        "command": "function",
        "script":  "function",
        "mcp":     "function",
    },
    # Horizontal bias per group (fraction of viewport width, -0.5 .. 0.5).
    # Entries ending in '*' become startsWith() checks.
    group_x_bias={
        "todos-active":    0.22,
        "todos-backlog":   0.22,
        "todos-completed": 0.22,
        "todos-archive":   0.32,   # further right so the archive pile reads
                                   # as "off to the side" from completed.
        "todos-meta":      0.22,
        "mcp":            -0.22,
        "commands":       -0.08,
        "docs":           -0.04,
        "scripts":         0.08,
    },
    # Vertical bias per group. Skills + commands stay in the upper third;
    # Scripts is pulled to the bottom so it stops getting stuck mid-graph
    # on top of TODOs. The three TODO subgroups split vertically so their
    # separate floating labels read as distinct clusters (Active top-right,
    # Backlog middle-right, Completed bottom-right).
    group_y_bias={
        "skills":          -0.22,
        "commands":        -0.24,
        "todos-active":    -0.18,
        "todos-backlog":    0.02,
        "todos-completed":  0.22,
        "todos-archive":    0.32,   # below completed — archives sink down.
        "scripts":          0.28,
    },
    # Labels for the in-graph group overlays. TODO subgroups stay separate
    # because each is an active, distinct region — merging them would hide
    # that Active keeps growing while the merged centroid drifts onto
    # Completed (which accumulates the most nodes).
    group_labels={
        "core":            "Core",
        "docs":            "Docs",
        "skills":          "Skills",
        "commands":        "Commands",
        "todos-active":    "Active",
        "todos-backlog":   "Backlog",
        "todos-completed": "Completed",
        "todos-archive":   "Archive",
        "todos-meta":      None,        # structural, too small to label
        "claude-meta":     None,        # structural, too small to label
        "scripts":         "Scripts",
        "mcp":             "MCP",
        "folders":         None,        # structural
    },
    # Spawn-from-group: new nodes stream out of their "source" cluster
    # instead of materializing mid-screen. Supports an optional dx/dy
    # direction offset for groups whose final home lies beyond the source
    # (e.g., MCP flows *out of* docs toward the left edge).
    spawn_from_group={
        # TODO lifecycle chain — backlog → active → completed → archive.
        # Each stage emerges from the one before it, so the lifecycle reads
        # as a single eastward drift through the right column.
        "todos-active":    "todos-backlog",
        "todos-completed": "todos-active",
        "todos-archive":   "todos-completed",
        # MCP files are referenced from docs (CLAUDE.md, MCP guides) and
        # land at the far left of the layout. Spawning slightly left of
        # docs' centroid lets the new-node motion flow outward leftward
        # to MCP's anchor, instead of getting hung up on docs' right edge.
        "mcp":             {"from": "docs", "dx": -0.08},
    },
    # Path-prefix fallback for nodes whose group has no spawn rule above.
    # The archive-year/month folders (`todos/completed/2025/10`,
    # `todos/completed/2026/01`, ...) are kind=folder, group="folders" —
    # generic, no per-folder spawn intent. Without this they materialize
    # at the viewport center and their contains-edges drag the archive
    # TODOs leftward while settling. Spawning them at the todos-completed
    # centroid means the contains-edges connect nodes that are already
    # near each other, so the cluster stays put.
    spawn_from_path={
        "todos/completed/": "todos-completed",
    },
    # Dual-repo: commits with repo='pwiz' link to the main pwiz repo, all
    # others to pwiz-ai.
    commit_repo_base_js=(
        "return snapshot && snapshot.repo === 'pwiz'\n"
        "        ? 'https://github.com/ProteoWizard/pwiz'\n"
        "        : 'https://github.com/ProteoWizard/pwiz-ai';"
    ),
    # Label transform: show the title/filename, strip TODO- prefix, .md suffix,
    # turn underscores into spaces.
    label_transform_js=(
        "let label = d.label || d.id.split('/').pop();\n"
        "      label = label.replace(/^TODO-\\d*_?/, '').replace(/\\.md$/, '')\n"
        "                   .replace(/_/g, ' ');\n"
        "      return label.length > 22 ? label.slice(0, 22) + '...' : label;"
    ),
    extra_css="""
    #repo-badge {
      display: inline-block; padding: 1px 6px; border-radius: 3px;
      font-size: 10px; font-weight: 600; margin-left: 8px;
      color: white; background: #6c757d;
    }
    #repo-badge.pwiz-ai { background: #2e7d32; }
""",
)


def friend_id(full_id: str, _nmeta: dict) -> str:
    """pwiz-ai uses the path as the node id (already unique)."""
    return full_id


# Anything under todos/completed/<YYYY>/ is an archival copy — split it
# into its own group so the Completed cluster shows only "recently done,
# not yet rotated out" and the Archive group shows everything older.
_ARCHIVE_PAT = re.compile(r"^todos/completed/\d{4}/")


def reclassify_archive_nodes(nodes: dict) -> int:
    """Move todos/completed/YYYY/... nodes into the todos-archive group."""
    moved = 0
    for nid, n in nodes.items():
        if n.get("group") == "todos-completed" and _ARCHIVE_PAT.match(nid):
            n["group"] = "todos-archive"
            moved += 1
    return moved


# ---------------------------------------------------------------------------
# Per-commit line counts
#
# pwiz-ai's timeline spans two repos: the original pwiz (ai/ was once a
# subdirectory there) and pwiz-ai (after the split, ai/ is the whole repo).
# Each commit's 'repo' field tells us which repo + path prefix to use.
#
# Naive approach — one subprocess per (commit, file) — is prohibitively slow
# at 584 commits × ~200 files. We instead:
#   1. Run one `git ls-tree -r <sha>` per commit to collect blob SHAs.
#   2. Dedupe blob SHAs across all commits (many files don't change each commit).
#   3. Run a single `git cat-file --batch` per repo to line-count each unique
#      blob. Sum per-commit blob-line-counts for the final totals.
# ---------------------------------------------------------------------------

AI_REPO   = HERE.parent.parent                 # C:/proj/ai           (pwiz-ai)
PWIZ_REPO = AI_REPO.parent / "pwiz"            # C:/proj/pwiz          (sibling)
COUNT_EXTS = (".md", ".py", ".ps1", ".sh")


def _tree_blobs(repo: Path, sha: str, prefix: str) -> list[str]:
    """Return the blob SHAs for matching files in the tree at `sha`."""
    res = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "-r", sha],
        capture_output=True, text=True,
    )
    if res.returncode != 0:
        return []
    out: list[str] = []
    for line in res.stdout.splitlines():
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        meta, path = parts
        if prefix and not path.startswith(prefix):
            continue
        if not path.endswith(COUNT_EXTS):
            continue
        _mode, typ, blob = meta.split()
        if typ == "blob":
            out.append(blob)
    return out


def _batch_line_counts(repo: Path, blob_shas: set[str]) -> dict[str, int]:
    """Line-count each blob via one `git cat-file --batch`."""
    if not blob_shas:
        return {}
    stdin = ("\n".join(blob_shas) + "\n").encode()
    proc = subprocess.run(
        ["git", "-C", str(repo), "cat-file", "--batch"],
        input=stdin, capture_output=True,
    )
    data = proc.stdout
    lines: dict[str, int] = {}
    i = 0
    # Stream format: "<sha> <type> <size>\n<content>\n" repeated.
    while i < len(data):
        nl = data.find(b"\n", i)
        if nl < 0:
            break
        header = data[i:nl].decode("ascii", "replace").split()
        if len(header) != 3:
            break
        sha, typ, size_str = header
        size = int(size_str)
        content = data[nl + 1: nl + 1 + size]
        lines[sha] = content.count(b"\n")
        i = nl + 1 + size + 1   # skip the trailing newline after content
    return lines


def compute_line_counts(commits: list) -> dict[str, int]:
    """sha -> total lines of ai/ docs+scripts at that commit."""
    # Collect (repo, prefix) → list of relevant commit SHAs
    by_scope: dict[tuple[str, str], list[str]] = {}
    repos = {"pwiz": (PWIZ_REPO, "ai/"), "pwiz-ai": (AI_REPO, "")}
    for c in commits:
        key = c.get("repo", "pwiz-ai")
        if key not in repos:
            continue
        by_scope.setdefault(key, []).append(c["sha"])

    commit_to_blobs: dict[str, list[str]] = {}
    for scope_key, sha_list in by_scope.items():
        repo, prefix = repos[scope_key]
        all_blobs: set[str] = set()
        per_commit: dict[str, list[str]] = {}
        for sha in sha_list:
            blobs = _tree_blobs(repo, sha, prefix)
            per_commit[sha] = blobs
            all_blobs.update(blobs)
        line_map = _batch_line_counts(repo, all_blobs)
        for sha, blobs in per_commit.items():
            commit_to_blobs[sha] = [line_map.get(b, 0) for b in blobs]

    return {sha: sum(ls) for sha, ls in commit_to_blobs.items()}


# ---------------------------------------------------------------------------
# pwiz-ai-specific post-patch: inject repo-badge update into updateGraph().
# ---------------------------------------------------------------------------

REPO_BADGE_PATCH_ANCHOR = (
    "document.getElementById('hash').textContent = snapshot.hash;"
)
REPO_BADGE_PATCH = REPO_BADGE_PATCH_ANCHOR + """
      // Show which source repo this commit came from.
      const existingBadge = document.getElementById('repo-badge');
      if (existingBadge) existingBadge.remove();
      const badge = document.createElement('span');
      badge.id = 'repo-badge';
      badge.className = snapshot.repo === 'pwiz-ai' ? 'pwiz-ai' : 'pwiz';
      badge.textContent = snapshot.repo;
      document.getElementById('hash').parentNode.insertBefore(
        badge, document.getElementById('hash').nextSibling
      );"""


def apply_pwiz_ai_patches(html: str) -> str:
    # Shorten the default "Call Graph Evolution" header to "Growth".
    html = html.replace(">Call Graph Evolution<", ">Growth<", 1)
    if REPO_BADGE_PATCH_ANCHOR not in html:
        raise ValueError("repo-badge anchor not found — template drift?")
    return html.replace(REPO_BADGE_PATCH_ANCHOR, REPO_BADGE_PATCH, 1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SNAPSHOTS
    if not src.exists():
        print(f"snapshots.json not found at {src}")
        sys.exit(1)

    data = json.loads(src.read_text(encoding="utf-8"))
    p = data["projects"]["pwiz-ai"]
    print(f"Reading {src}")

    moved = reclassify_archive_nodes(p["nodes"])
    if moved:
        print(f"  reclassified {moved} archived TODOs into todos-archive group")

    # Per-commit line counts drive the "N,NNN lines" panel row across the
    # whole playback. One batch cat-file per repo keeps it fast.
    print(f"  counting lines per commit across {len(p['commits'])} commits...")
    line_map = compute_line_counts(p["commits"])
    for c in p["commits"]:
        c["lineCount"] = line_map.get(c["sha"], 0)
    final_lines = p["commits"][-1]["lineCount"]
    CONFIG.summary_total_lines = final_lines
    print(f"  final tree: {final_lines:,} lines")

    registry, timeline = core.build_registry_and_timeline(
        p["commits"], p["nodes"], p["edges"], CONFIG, friend_id,
    )
    print(f"  {len(p['commits'])} commits, {len(registry)} unique nodes, "
          f"{len(timeline)} snapshots")

    core.write_data_files(HERE, registry, timeline, chunk_count=1)

    base = core.BASE_HTML.read_text(encoding="utf-8")
    html = core.patch_html(base, CONFIG)
    html = apply_pwiz_ai_patches(html)
    dated = core.write_dated_html(HERE, html, CONFIG.name)
    total = sum(f.stat().st_size for f in HERE.iterdir() if f.is_file())
    print(f"  wrote {dated.name} ({total:,} bytes total)")


if __name__ == "__main__":
    main()
