"""
Git-history extractor for the callgraph viewer.

Walks one or more repositories' commit histories, merged into a single
timeline by committer timestamp, and produces the (commits, nodes, edges)
structure that core.build_registry_and_timeline() consumes.

Model:
  - Each commit shows the tracked files in its own tree. When a project
    moved between repositories (pwiz-ai's ai/ folder began inside pwiz),
    list the sources oldest home first: once a later source has commits, its
    latest tree is laid over an earlier source's commits and wins any path
    both hold, so late commits in the old home do not erase the new one.
  - Nodes are the tracked files plus the folders that contain them. A node is
    alive from the first commit it appears in to the last.
  - Edges are 'contains' (folder -> child) and 'ref' (a relative markdown
    link from a file to a file or folder present at that commit).
  - A node's label comes from the content of its latest version.

Project specifics (which repos, which files, group/kind, labels, folder
collapsing) come from an ExtractConfig supplied by the project's build.py.
"""

from __future__ import annotations

import posixpath
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional


@dataclass
class Source:
    repo: Path                      # local clone
    label: str                      # value of commit["repo"] in the output
    refs: list[str]                 # refs to walk, e.g. ["origin/master"]
    prefix: str = ""                # subdirectory holding the tracked tree ("ai/")


@dataclass
class ExtractConfig:
    sources: list[Source]           # oldest home first (see module docstring)
    # Return True for (prefix-stripped) paths that become nodes.
    include: Callable[[str], bool]
    # Return (kind, group) for a file path. Folders are ("folder", "folders").
    classify: Callable[[str], tuple[str, str]]
    # Return the folder that contains a file, or None for the root. Lets a
    # project collapse per-item folders (e.g. claude/skills/<name>/SKILL.md
    # is contained directly by claude/skills).
    parent_folder: Callable[[str], Optional[str]] = field(
        default=lambda p: posixpath.dirname(p) or None)
    # Return the display label for a file given its text (None for binary).
    label: Callable[[str, Optional[str]], str] = field(
        default=lambda p, _t: p.split("/")[-1])


LINK_RE = re.compile(r"\]\(([^)\s#]+)")


def markdown_links(path: str, text: str) -> set[str]:
    """Relative markdown link targets, resolved against the file's folder."""
    out: set[str] = set()
    base = posixpath.dirname(path)
    for m in LINK_RE.finditer(text):
        tgt = m.group(1)
        if "://" in tgt or tgt.startswith("mailto:"):
            continue
        out.add(posixpath.normpath(posixpath.join(base, tgt)).rstrip("/"))
    return out


def _git(repo: Path, *args: str, data: Optional[bytes] = None) -> bytes:
    res = subprocess.run(["git", "-C", str(repo), *args],
                         input=data, capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {res.stderr.decode()}")
    return res.stdout


def _commits(src: Source) -> list[dict]:
    """Commits touching the source's tree, oldest first."""
    args = ["log", "--format=%H%x00%ct%x00%s", *src.refs]
    if src.prefix:
        args += ["--", src.prefix.rstrip("/")]
    out = []
    for line in _git(src.repo, *args).decode("utf-8", "replace").splitlines():
        sha, ct, msg = line.split("\x00", 2)
        out.append({"sha": sha, "ts": int(ct), "msg": msg, "repo": src.label,
                    "_src": src})
    out.reverse()
    return out


def _tree(src: Source, sha: str, include: Callable[[str], bool]) -> dict[str, str]:
    """{path: blob} of the tracked files at `sha`, with the prefix stripped."""
    out: dict[str, str] = {}
    raw = _git(src.repo, "ls-tree", "-r", "-z", sha, "--", src.prefix or ".")
    for rec in raw.decode("utf-8", "replace").split("\x00"):
        if not rec:
            continue
        meta, path = rec.split("\t", 1)
        _mode, typ, blob = meta.split()
        if typ != "blob" or not path.startswith(src.prefix):
            continue
        path = path[len(src.prefix):]
        if include(path):
            out[path] = blob
    return out


def _read_blobs(repo: Path, shas: list[str]) -> dict[str, Optional[str]]:
    """Text of each blob via one `git cat-file --batch` (None if not UTF-8)."""
    if not shas:
        return {}
    data = _git(repo, "cat-file", "--batch", data=("\n".join(shas) + "\n").encode())
    out: dict[str, Optional[str]] = {}
    i = 0
    while i < len(data):
        nl = data.index(b"\n", i)
        header = data[i:nl].decode().split()
        if len(header) < 3:          # "<sha> missing"
            i = nl + 1
            continue
        sha, size = header[0], int(header[2])
        body = data[nl + 1: nl + 1 + size]
        try:
            out[sha] = body.decode("utf-8")
        except UnicodeDecodeError:
            out[sha] = None
        i = nl + 1 + size + 1        # skip the newline after the content
    return out


def extract(cfg: ExtractConfig, end_ts: Optional[int] = None,
            log: Callable[[str], None] = print) -> dict:
    """Return {"commits": [...], "nodes": {...}, "edges": [...]}.

    end_ts (committer time, Unix seconds) stops the timeline at that moment,
    so an earlier generation can be reproduced exactly.
    """
    commits = [c for s in cfg.sources for c in _commits(s)]
    commits.sort(key=lambda c: c["ts"])      # stable: parents stay before children
    if end_ts is not None:
        commits = [c for c in commits if c["ts"] <= end_ts]
    log(f"  {len(commits)} commits from "
        f"{', '.join(s.label for s in cfg.sources)}")

    # Pass 1: each commit's tree and the text of every blob they hold.
    trees = [_tree(c["_src"], c["sha"], cfg.include) for c in commits]
    blobs: dict[str, Optional[str]] = {}
    for src in cfg.sources:
        need = {b for c, tr in zip(commits, trees) if c["_src"] is src
                for b in tr.values()}
        blobs.update(_read_blobs(src.repo, sorted(need)))

    parsed: dict[tuple[str, str], tuple[str, set[str]]] = {}

    def parse(path: str, blob: str) -> tuple[str, set[str]]:
        """(label, link targets) for one version of a file."""
        key = (path, blob)
        if key not in parsed:
            body = blobs.get(blob)
            refs = markdown_links(path, body) if body and path.endswith(".md") else set()
            parsed[key] = (cfg.label(path, body), refs)
        return parsed[key]

    # Pass 2: snapshots.
    order = {id(s): i for i, s in enumerate(cfg.sources)}
    latest: dict[int, dict[str, str]] = {}      # source -> its latest tree
    node_meta: dict[str, dict] = {}
    alive_nodes: dict[str, list[int]] = {}      # id -> indices alive
    alive_edges: dict[tuple, list[int]] = {}

    for idx, (c, tree) in enumerate(zip(commits, trees)):
        sid = id(c["_src"])
        latest[sid] = tree
        merged: dict[str, tuple[str, set[str]]] = {}
        for s in cfg.sources:
            if order[id(s)] >= order[sid]:
                for p, b in latest.get(id(s), {}).items():
                    merged[p] = parse(p, b)

        folders: set[str] = set()
        contains: set[tuple[str, str]] = set()
        for p in merged:
            child, parent = p, cfg.parent_folder(p)
            while parent:
                contains.add((parent, child))
                if parent in folders:
                    break
                folders.add(parent)
                child, parent = parent, posixpath.dirname(parent) or None
        present = set(merged) | folders

        for p, (name, _refs) in merged.items():
            kind, group = cfg.classify(p)
            node_meta[p] = {"kind": kind, "group": group, "name": name}
        for f in folders:
            node_meta.setdefault(f, {"kind": "folder", "group": "folders",
                                     "name": f.split("/")[-1] + "/"})
        for nid in present:
            alive_nodes.setdefault(nid, []).append(idx)
        for parent, child in contains:
            alive_edges.setdefault((parent, child, "contains"), []).append(idx)
        for p, (_name, refs) in merged.items():
            for t in refs:
                if t != p and t in present:
                    alive_edges.setdefault((p, t, "ref"), []).append(idx)

    def interval(idxs: list[int]) -> tuple[int, Optional[int]]:
        end = idxs[-1] + 1
        return idxs[0], (None if end == len(commits) else end)

    nodes = {}
    for nid, idxs in alive_nodes.items():
        first, last = interval(idxs)
        nodes[nid] = {**node_meta[nid], "first_idx": first, "last_idx": last}
    edges = []
    for (s, t, k), idxs in alive_edges.items():
        first, last = interval(idxs)
        edges.append({"from": s, "to": t, "kind": k,
                      "first_idx": first, "last_idx": last})

    out_commits = [{k: v for k, v in c.items() if not k.startswith("_")}
                   for c in commits]
    return {"commits": out_commits, "nodes": nodes, "edges": edges}
