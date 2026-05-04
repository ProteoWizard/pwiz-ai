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


def _sync_root_claude_md(project_root: Path) -> Optional[str]:
    """Copy ai/root-CLAUDE.md to project root CLAUDE.md if source is newer.

    Returns a message if updated, None otherwise.
    """
    source = _AI_ROOT / "root-CLAUDE.md"
    target = project_root / "CLAUDE.md"

    if not source.exists():
        return None

    # Copy if target doesn't exist or source is newer
    if not target.exists() or source.stat().st_mtime > target.stat().st_mtime:
        import shutil
        shutil.copy2(str(source), str(target))
        return f"Updated {target} from {source}"

    return None


@mcp.tool()
def get_project_status(verbose: bool = False) -> str:
    """Get git status for all repositories under the project root.

    Auto-discovers git repos by scanning subdirectories of the project root
    (derived from the ai/ folder location). Call this at session start to
    orient yourself — no arguments needed.

    Also auto-syncs root CLAUDE.md from ai/root-CLAUDE.md if the source is newer.

    Args:
        verbose: If True, include lists of modified/staged/untracked files (default: False)
    """
    project_root = _AI_ROOT.parent  # e.g., C:\proj

    # Auto-sync root CLAUDE.md
    sync_message = _sync_root_claude_md(project_root)

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


def _per_session_active_project_file() -> Optional[Path]:
    """Path to this Claude Code session's active-project file, or None if the
    parent PID can't be determined (in which case callers should fall back to
    the legacy global file)."""
    try:
        ppid = os.getppid()
    except OSError:
        return None
    if not ppid:
        return None
    return STATE_DIR / f"active-project-{ppid}.json"


def main():
    """Run the MCP server."""
    logger.info("Starting Status MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
