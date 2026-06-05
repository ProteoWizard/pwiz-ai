"""Status MCP Server for Claude Code.

Provides system status information including:
- Current timestamp with timezone
- Git repository status for multiple directories
- Active project tracking for statusline display
- Screenshot retrieval (Win+Shift+S from Pictures/Screenshots, with clipboard fallback)
- Clipboard image retrieval (for images copied from editors, not Win+Shift+S)

This is a lightweight server for basic system context. For LabKey/Panorama
data access, use the LabKeyMcp server instead.

Setup:
    pip install mcp Pillow
    claude mcp add status -- python ./ai/mcp/StatusMcp/server.py
"""

import json
import logging
import os
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

# Configure logging to stderr (required for STDIO transport)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("status_mcp")

# State file for active project (read by statusline.ps1)
# Derive ai/ root from script location: ai/mcp/StatusMcp/server.py -> ai/
_AI_ROOT = Path(__file__).resolve().parent.parent.parent
STATE_DIR = _AI_ROOT / ".tmp"
ACTIVE_PROJECT_FILE = STATE_DIR / "active-project.json"

# Initialize FastMCP server
mcp = FastMCP("status")


def run_command(cmd: list[str], cwd: Optional[str] = None) -> Optional[str]:
    """Run a command and return its output, or None on failure.

    IMPORTANT: stdin=subprocess.DEVNULL prevents subprocess from inheriting
    MCP server's stdin, which would cause hangs.
    """
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except Exception:
        return None


def get_git_status(directory: str, verbose: bool = False) -> Optional[dict]:
    """Get git status for a directory."""
    git_root = run_command(["git", "rev-parse", "--show-toplevel"], cwd=directory)
    if not git_root:
        return None

    branch = run_command(["git", "branch", "--show-current"], cwd=directory) or "HEAD detached"
    remote = run_command(["git", "config", "--get", "remote.origin.url"], cwd=directory)

    # Parse git status --porcelain
    porcelain = run_command(["git", "status", "--porcelain"], cwd=directory) or ""
    lines = [line for line in porcelain.split("\n") if line]

    modified_count = 0
    staged_count = 0
    untracked_count = 0
    modified_files = []
    staged_files = []
    untracked_files = []

    for line in lines:
        if len(line) < 2:
            continue
        index_status = line[0]
        worktree_status = line[1]
        filename = line[3:]  # Skip status chars and space

        if index_status == "?" and worktree_status == "?":
            untracked_count += 1
            if verbose:
                untracked_files.append(filename)
        else:
            if index_status not in (" ", "?"):
                staged_count += 1
                if verbose:
                    staged_files.append(filename)
            if worktree_status not in (" ", "?"):
                modified_count += 1
                if verbose:
                    modified_files.append(filename)

    # Get ahead/behind count
    ahead = 0
    behind = 0
    tracking = run_command(["git", "rev-parse", "--abbrev-ref", "@{upstream}"], cwd=directory)
    if tracking:
        ahead_behind = run_command(
            ["git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            cwd=directory
        )
        if ahead_behind:
            parts = ahead_behind.split("\t")
            if len(parts) == 2:
                ahead = int(parts[0]) if parts[0].isdigit() else 0
                behind = int(parts[1]) if parts[1].isdigit() else 0

    result = {
        "branch": branch,
        "remote": remote,
        "modified": modified_count,
        "staged": staged_count,
        "untracked": untracked_count,
        "ahead": ahead,
        "behind": behind,
    }

    if verbose:
        result["modifiedFiles"] = modified_files
        result["stagedFiles"] = staged_files
        result["untrackedFiles"] = untracked_files

    return result


def get_directory_status(directory: str, verbose: bool = False) -> dict:
    """Get status for a single directory."""
    path = Path(directory)
    return {
        "path": str(path),
        "name": path.name,
        "git": get_git_status(directory, verbose=verbose),
    }


def _ensure_root_claude_md_link(project_root: Path) -> Optional[str]:
    """Ensure project-root CLAUDE.md is a hard link to ai/root-CLAUDE.md.

    Replaces the legacy Copy-Item-based sync: instead of duplicating
    content and tracking mtimes, the two paths now share an NTFS inode so
    edits at either path show up at the other for free. Idempotent: a
    no-op when the file is already linked.

    Also handles the in-the-wild migration cases:
    - Pre-hard-link setup left a regular copy at CLAUDE.md
    - An editor or `git pull` overwrote ai/root-CLAUDE.md by atomic rename,
      breaking the previous hard link

    In both cases the existing CLAUDE.md is removed and a fresh hard link
    is created. Returns a one-line message describing the action taken, or
    None when nothing changed.
    """
    source = _AI_ROOT / "root-CLAUDE.md"
    target = project_root / "CLAUDE.md"

    if not source.exists():
        return None

    # Already linked: same inode → nothing to do.
    if target.exists() and target.samefile(source):
        return None

    # Determine which case we're in for a clear migration message, then
    # remove the existing entry. Unlinking a hard link only drops the
    # directory entry, not the underlying inode.
    if target.exists():
        action = "Re-linked"  # legacy copy or broken hard link
        target.unlink()
    else:
        action = "Created hard link for"

    try:
        os.link(str(source), str(target))
    except OSError as e:
        return f"Failed to create hard link {target} -> {source}: {e}"

    return f"{action} {target} -> {source}"


@mcp.tool()
def get_project_status(verbose: bool = False) -> str:
    """Get git status for all repositories under the project root.

    Auto-discovers git repos by scanning subdirectories of the project root
    (derived from the ai/ folder location). Call this at session start to
    orient yourself — no arguments needed.

    Also ensures the project-root CLAUDE.md is a hard link to
    ai/root-CLAUDE.md, creating or re-linking it as needed. This replaces
    the older copy-and-sync mechanism, so legacy machines installed with
    the Copy-Item-based setup are migrated transparently on the next call.

    Args:
        verbose: If True, include lists of modified/staged/untracked files (default: False)
    """
    project_root = _AI_ROOT.parent  # e.g., C:\proj

    # Ensure root CLAUDE.md is hard-linked to ai/root-CLAUDE.md
    sync_message = _ensure_root_claude_md_link(project_root)

    subdirs = sorted([
        d for d in project_root.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    ])

    directory_statuses = []
    for d in subdirs:
        status = get_directory_status(str(d), verbose=verbose)
        if status["git"] is not None:
            directory_statuses.append(status)

    now_utc = datetime.now(timezone.utc)
    now_local = datetime.now().astimezone()

    result = {
        "timestamp": now_utc.isoformat(),
        "localTimestamp": now_local.strftime("%Y-%m-%d %H:%M:%S"),
        "timezone": str(now_local.tzinfo),
        "projectRoot": str(project_root),
        "repositories": directory_statuses,
    }

    if sync_message:
        result["claudeMdSync"] = sync_message

    return json.dumps(result, indent=2)


@mcp.tool()
def get_status(directories: Optional[list[str]] = None, verbose: bool = False) -> str:
    """Get current system status including timestamp and git info for one or more directories.

    Call this to get accurate time and repository context.

    Args:
        directories: Directories to check (optional, defaults to cwd).
                    Example: ['C:/proj/ai', 'C:/proj/pwiz']
        verbose: If True, include lists of modified/staged/untracked files (default: False)
    """
    now_utc = datetime.now(timezone.utc)
    now_local = datetime.now().astimezone()
    cwd = os.getcwd()

    dirs_to_check = directories if directories else [cwd]
    directory_statuses = [get_directory_status(d, verbose=verbose) for d in dirs_to_check]

    status = {
        "timestamp": now_utc.isoformat(),
        "localTimestamp": now_local.strftime("%Y-%m-%d %H:%M:%S"),
        "timezone": str(now_local.tzinfo),
        "platform": f"{platform.system()} {platform.machine()}",
        "pythonVersion": platform.python_version(),
        "directories": directory_statuses,
    }

    return json.dumps(status, indent=2)


def _get_session_dir() -> Path:
    """Get the session screenshots directory, creating it if needed."""
    session_dir = _AI_ROOT / ".tmp" / "screenshots" / "sessions"
    session_dir.mkdir(parents=True, exist_ok=True)
    return session_dir


def _move_screenshots(screenshots: list[Path], session_dir: Path) -> list[dict]:
    """Move screenshots from ~/Pictures/Screenshots into the project folder.

    Returns list of result dicts with path, filename, source, modified, size_bytes.
    """
    import shutil
    results = []
    for src in screenshots:
        mtime = datetime.fromtimestamp(src.stat().st_mtime)
        dest = session_dir / src.name
        try:
            shutil.move(str(src), str(dest))
            result_path = dest
            source = "screenshots_folder_moved"
        except Exception as e:
            logger.warning(f"Failed to move screenshot to project folder: {e}")
            result_path = src
            source = "screenshots_folder"
        results.append({
            "path": str(result_path),
            "filename": result_path.name,
            "source": source,
            "modified": mtime.strftime("%Y-%m-%d %H:%M:%S"),
            "size_bytes": result_path.stat().st_size,
        })
    return results


@mcp.tool()
def get_last_screenshot(count: int = 1) -> str:
    """Get the most recent Win+Shift+S screenshot(s) from Windows.

    On Windows 11, Win+Shift+S saves screenshots to ~/Pictures/Screenshots.
    This tool finds the most recent one(s), moves them into the project folder
    (ai/.tmp/screenshots/sessions/) to avoid permission prompts, and returns
    the path(s) for Claude to read.

    Use count > 1 when the user says "grab my last 3 screenshots" or wants
    to show multiple images (e.g., A vs B comparison).

    Falls back to clipboard if ~/Pictures/Screenshots doesn't exist (Windows 10).

    For clipboard images from an image editor (not Win+Shift+S), use
    get_clipboard_image instead.

    Args:
        count: Number of most recent screenshots to retrieve (default: 1)
    """
    pictures = Path(os.path.expanduser("~/Pictures/Screenshots"))

    if pictures.exists():
        screenshots = sorted(pictures.glob("*.png"),
                             key=lambda p: p.stat().st_mtime, reverse=True)
        if screenshots:
            # Filter: no older than 1 hour, and no older than the most recent
            # file already moved to sessions/ (prevents walking backwards)
            now = datetime.now().timestamp()
            one_hour_ago = now - 3600

            session_dir = _get_session_dir()
            existing = sorted(session_dir.glob("*.png"),
                              key=lambda p: p.stat().st_mtime, reverse=True)
            last_moved_time = existing[0].stat().st_mtime if existing else 0

            cutoff = max(one_hour_ago, last_moved_time)
            recent = [s for s in screenshots if s.stat().st_mtime > cutoff]

            if not recent:
                return json.dumps({
                    "error": "No new screenshots found",
                    "suggestion": "Take a new screenshot with Win+Shift+S (rectangle mode)"
                })

            to_move = recent[:count]
            results = _move_screenshots(to_move, session_dir)

            if count == 1:
                return json.dumps({
                    **results[0],
                    "instruction": "Use the Read tool to view this image file"
                }, indent=2)
            else:
                return json.dumps({
                    "screenshots": results,
                    "count": len(results),
                    "instruction": "Use the Read tool to view each image file"
                }, indent=2)

    # Fall back to clipboard (Windows 10 — no ~/Pictures/Screenshots)
    clipboard_result = _try_clipboard()
    if clipboard_result:
        return clipboard_result

    return json.dumps({
        "error": "No screenshots found in ~/Pictures/Screenshots and no image on clipboard",
        "suggestion": "Take a screenshot with Win+Shift+S, or copy an image to clipboard"
    })


@mcp.tool()
def get_clipboard_image() -> str:
    """Get an image from the Windows clipboard and save it.

    Use this when the user has copied an image from an image editor, browser,
    or other application — NOT for Win+Shift+S screenshots (use get_last_screenshot
    for those).

    Requires the Pillow package: pip install Pillow
    """
    result = _try_clipboard()
    if result:
        return result

    return json.dumps({
        "error": "Could not retrieve clipboard image",
        "pillow_installed": _is_pillow_available(),
        "suggestion": "Install Pillow for clipboard support: pip install Pillow"
            if not _is_pillow_available()
            else "No image found on the clipboard. Copy an image first.",
    })


def _is_pillow_available() -> bool:
    """Check if Pillow is installed."""
    try:
        from PIL import ImageGrab  # noqa: F401
        return True
    except ImportError:
        return False


def _try_clipboard() -> Optional[str]:
    """Try to get an image from clipboard. Returns JSON string or None."""
    try:
        from PIL import ImageGrab

        image = ImageGrab.grabclipboard()
        if image is None:
            return None

        session_dir = _get_session_dir()
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = session_dir / f"clipboard_{timestamp}.png"
        image.save(output_path, "PNG")

        return json.dumps({
            "path": str(output_path),
            "filename": output_path.name,
            "source": "clipboard",
            "modified": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "size_bytes": output_path.stat().st_size,
            "instruction": "Use the Read tool to view this image file"
        }, indent=2)
    except ImportError:
        logger.warning("PIL not available for clipboard image capture")
        return None
    except Exception as e:
        logger.warning(f"Failed to get clipboard image: {e}")
        return None


@mcp.tool()
def set_active_project(path: str) -> str:
    """Set the active project for the statusline display.

    Call this when switching focus between repositories
    (e.g., pwiz, pwiz-ai, skyline_26_1).

    Per-session state is keyed by the Claude Code process's PID (this server's
    parent process), which the statusline also reads, so concurrent Claude Code
    sessions do not overwrite each other's status display.

    Args:
        path: Path to the project directory. Example: 'C:/proj/pwiz'
    """
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    project_path = Path(path)
    active = {
        "path": str(project_path),
        "name": project_path.name,
        "setAt": datetime.now(timezone.utc).isoformat(),
    }

    payload = json.dumps(active, indent=2)
    target = _per_session_active_project_file() or ACTIVE_PROJECT_FILE
    target.write_text(payload, encoding="utf-8")

    return f"Active project set to: {active['name']} ({active['path']})"


# Cache the Claude Code PID across all calls in this server's lifetime.
# Claude Code doesn't relocate; one walk-up is enough.
_CLAUDE_PID_CACHE: Optional[int] = None


def _find_claude_code_pid() -> Optional[int]:
    """Walk up the process tree from this server until we find a process
    named 'claude' (case-insensitive). The same walk in statusline.ps1
    converges on the same PID, so files keyed by it are sharable.

    On Windows the StatusMcp's direct parent IS claude.exe (so the walk
    terminates after one step), but the statusline is launched via a
    short-lived bash/pwsh wrapper, so it has to walk further. Both sides
    use the same algorithm to ensure agreement.

    Implementation shells out to pwsh once (cached) so we don't add a
    psutil dependency. ~150ms one-time cost, negligible relative to
    server lifetime.
    """
    global _CLAUDE_PID_CACHE
    if _CLAUDE_PID_CACHE is not None:
        return _CLAUDE_PID_CACHE

    cmd = (
        f"$cur = {os.getpid()}; "
        "$d = 0; "
        "while ($cur -and $cur -ne 0 -and $d -lt 16) { "
        "  $p = Get-CimInstance Win32_Process -Filter \"ProcessId = $cur\" -ErrorAction SilentlyContinue; "
        "  if (-not $p) { break } "
        "  if ($p.Name -match '^claude') { Write-Host $p.ProcessId; exit 0 } "
        "  $cur = $p.ParentProcessId; $d++ "
        "}"
    )
    try:
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-Command", cmd],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        out = result.stdout.strip()
        if out.isdigit():
            _CLAUDE_PID_CACHE = int(out)
            logger.info(f"Found Claude Code PID via process-tree walk: {_CLAUDE_PID_CACHE}")
            return _CLAUDE_PID_CACHE
    except Exception as e:
        logger.warning(f"Failed to find Claude Code PID: {e}")

    # Fallback: use direct parent. On Windows that's already claude.exe
    # in the StatusMcp's case (the walk would have found it at depth 0
    # if pwsh didn't error), so this is harmless on the happy path.
    try:
        _CLAUDE_PID_CACHE = os.getppid()
    except OSError:
        return None
    return _CLAUDE_PID_CACHE


def _per_session_active_project_file() -> Optional[Path]:
    """Path to this Claude Code session's active-project file. Keyed by
    the Claude Code PID (walked up the process tree) so the statusline
    and StatusMcp share the same identity."""
    pid = _find_claude_code_pid()
    if not pid:
        return None
    return STATE_DIR / f"active-project-{pid}.json"


def _per_session_context_state_file() -> Optional[Path]:
    """Path to this Claude Code session's context-usage snapshot file. The
    statusline writes it on every tick; this server reads it on demand."""
    pid = _find_claude_code_pid()
    if not pid:
        return None
    return STATE_DIR / f"context-state-{pid}.json"


@mcp.tool()
def get_context_usage() -> str:
    """Get the current Claude Code session's context-window usage.

    Returns the same numbers the statusline displays — same model,
    same calibration (97% consumed = 0% left, matching Claude Code's
    auto-compact warning point on the 1M-context tier). The snapshot
    is refreshed by the statusline every tick, so it lags the live
    state by at most one turn.

    Use this BEFORE suggesting end-of-session, handoff, or compact —
    don't estimate from feel. Many users are comfortable pushing
    sessions into single-digit percentages remaining; suggesting a
    handoff at 40% wastes their session.

    Returns JSON with:
      model                       — display name of current model
      context_window_size         — total tokens (e.g. 1000000 for Opus 4.7-1m)
      input_tokens                — non-cached input tokens this turn
      cache_creation_input_tokens — tokens entering the cache
      cache_read_input_tokens     — tokens served from cache
      used_tokens                 — sum of the three above
      used_pct                    — used / window * 100 (raw)
      left_pct                    — usable headroom % (97% - used_pct, floored to 0)
      usable_max_pct              — calibration ceiling (97 for the 1M tier)
      calibrated_at               — UTC timestamp of the snapshot

    On a fresh session before the statusline has run once, returns an
    empty/error payload — that itself signals "very early in session,
    plenty of context."
    """
    state_file = _per_session_context_state_file()
    if not state_file or not state_file.exists():
        return json.dumps({
            "error": "Context state file not found",
            "expected_path": str(state_file) if state_file else None,
            "hint": (
                "The statusline writes this file on every tick. If you "
                "are seeing this, either the session just started (no "
                "tick yet) or the statusline isn't configured. Either "
                "way, plenty of context is almost certainly available."
            ),
        }, indent=2)

    try:
        payload = state_file.read_text(encoding="utf-8")
    except OSError as e:
        return json.dumps({
            "error": f"Failed to read context state: {e}",
            "path": str(state_file),
        }, indent=2)

    return payload


@mcp.tool()
def get_pr_checks(pr: Optional[int] = None) -> str:
    """Return a normalized CI + mergeability verdict for a GitHub PR.

    Use this in merge / gating flows (e.g. /pw-complete) instead of reading
    `gh pr view --json statusCheckRollup` by hand. GitHub's statusCheckRollup
    mixes two node types that report status in DIFFERENT fields, which makes
    raw reads error-prone and has repeatedly caused a fully-green PR to be
    misreported as having "pending" checks:
      - CheckRun nodes (GitHub Actions / app checks): .status + .conclusion
      - StatusContext nodes (legacy commit statuses, e.g. TeamCity): .state
    This tool coalesces (.conclusion // .state // .status) per node and
    returns a single verdict, so callers never re-derive pass/fail.

    Args:
        pr: PR number. Omit to resolve the PR for the current branch of the
            pwiz repo.

    Returns JSON with: pr, title, url, headRefName, state, mergeable,
    reviewDecision, total, all_green, ready_to_merge, by_state, failing[],
    pending[]. Decision rule for callers:
      - failing non-empty (or mergeable != "MERGEABLE")  -> STOP
      - pending non-empty                                 -> wait or merge --auto
      - ready_to_merge == true                            -> green; merge on approval
    """
    pwiz_dir = str(_AI_ROOT.parent / "pwiz")
    fields = "number,title,url,state,headRefName,mergeable,reviewDecision,statusCheckRollup"
    cmd = ["gh", "pr", "view"]
    if pr is not None:
        cmd.append(str(pr))
    cmd += ["--json", fields]

    try:
        proc = subprocess.run(
            cmd,
            cwd=pwiz_dir,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        return json.dumps({"error": "gh CLI not found on PATH"}, indent=2)
    except subprocess.TimeoutExpired:
        return json.dumps({"error": "gh pr view timed out after 30s"}, indent=2)

    if proc.returncode != 0:
        return json.dumps({
            "error": "gh pr view failed",
            "stderr": (proc.stderr or "").strip(),
            "hint": "No open PR for the current branch? Pass pr=<number> explicitly.",
        }, indent=2)

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        return json.dumps({"error": f"Could not parse gh output: {e}"}, indent=2)

    rollup = data.get("statusCheckRollup") or []
    green_states = {"SUCCESS", "NEUTRAL", "SKIPPED"}
    failing_states = {
        "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED",
        "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE",
    }

    by_state: dict[str, int] = {}
    failing: list[dict] = []
    pending: list[dict] = []
    for node in rollup:
        # CheckRun -> conclusion (when COMPLETED) else status; StatusContext -> state.
        eff = (node.get("conclusion") or node.get("state")
               or node.get("status") or "PENDING").upper()
        by_state[eff] = by_state.get(eff, 0) + 1
        if eff in green_states:
            continue
        entry = {
            "name": node.get("name") or node.get("context") or "(unnamed)",
            "typename": node.get("__typename"),
            "effective": eff,
            "status": node.get("status"),
            "conclusion": node.get("conclusion"),
            "state": node.get("state"),
        }
        (failing if eff in failing_states else pending).append(entry)

    mergeable = data.get("mergeable")
    state = data.get("state")
    all_green = not failing and not pending
    result = {
        "pr": data.get("number"),
        "title": data.get("title"),
        "url": data.get("url"),
        "headRefName": data.get("headRefName"),
        "state": state,
        "mergeable": mergeable,
        "reviewDecision": data.get("reviewDecision"),
        "total": len(rollup),
        "all_green": all_green,
        "ready_to_merge": all_green and mergeable == "MERGEABLE" and state == "OPEN",
        "by_state": by_state,
        "failing": failing,
        "pending": pending,
    }
    return json.dumps(result, indent=2)


def main():
    """Run the MCP server."""
    logger.info("Starting Status MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
