"""Status MCP Server for Claude Code.

Provides system status information including:
- Current timestamp with timezone
- Git repository status for multiple directories
- Active project tracking for statusline display
- Screenshot retrieval (clipboard first, then Pictures/Screenshots)

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


def get_clipboard_image() -> Optional[Path]:
    """Try to get an image from the Windows clipboard and save it.

    Returns the path to the saved image, or None if no image in clipboard.
    """
    try:
        from PIL import ImageGrab

        # Try to grab image from clipboard
        image = ImageGrab.grabclipboard()
        if image is None:
            return None

        # Save to temp location
        tmp_dir = Path("C:/proj/ai/.tmp/screenshots")
        tmp_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = tmp_dir / f"clipboard_{timestamp}.png"
        image.save(output_path, "PNG")

        return output_path
    except ImportError:
        logger.warning("PIL not available for clipboard image capture")
        return None
    except Exception as e:
        logger.warning(f"Failed to get clipboard image: {e}")
        return None


@mcp.tool()
def get_last_screenshot() -> str:
    """Get the path to the most recent screenshot.

    Checks the Windows default screenshot folder (Pictures/Screenshots)
    and returns the path to the newest PNG file.

    Use this when the user says "I took a screenshot" or similar.
    Then use the Read tool to view the returned path.
    """
    # First, try to get image from clipboard
    clipboard_path = get_clipboard_image()
    if clipboard_path:
        return json.dumps({
            "path": str(clipboard_path),
            "filename": clipboard_path.name,
            "source": "clipboard",
            "modified": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "size_bytes": clipboard_path.stat().st_size,
            "instruction": "Use the Read tool to view this image file"
        }, indent=2)

    # Fall back to Screenshots folder
    pictures = Path(os.path.expanduser("~/Pictures/Screenshots"))

    if not pictures.exists():
        return json.dumps({
            "error": "No image in clipboard and screenshot folder not found",
            "folder": str(pictures),
            "suggestion": "Copy a screenshot to clipboard (PrintScreen, Win+Shift+S, or Snipping Tool)"
        })

    # Find all PNG files and sort by modification time
    screenshots = list(pictures.glob("*.png"))
    if not screenshots:
        return json.dumps({
            "error": "No image in clipboard and no PNG files in screenshot folder",
            "folder": str(pictures),
            "suggestion": "Copy a screenshot to clipboard (PrintScreen, Win+Shift+S, or Snipping Tool)"
        })

    # Get the most recent
    latest = max(screenshots, key=lambda p: p.stat().st_mtime)
    mtime = datetime.fromtimestamp(latest.stat().st_mtime)

    return json.dumps({
        "path": str(latest),
        "filename": latest.name,
        "source": "screenshots_folder",
        "modified": mtime.strftime("%Y-%m-%d %H:%M:%S"),
        "size_bytes": latest.stat().st_size,
        "instruction": "Use the Read tool to view this image file"
    }, indent=2)


@mcp.tool()
def set_active_project(path: str) -> str:
    """Set the active project for the statusline display.

    Call this when switching focus between repositories
    (e.g., pwiz, pwiz-ai, skyline_26_1).

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

    ACTIVE_PROJECT_FILE.write_text(json.dumps(active, indent=2), encoding="utf-8")

    return f"Active project set to: {active['name']} ({active['path']})"


def main():
    """Run the MCP server."""
    logger.info("Starting Status MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
