"""Common utilities for TeamCity MCP server.

This module contains:
- Config loading from ~/.teamcity-mcp/config.json
- HTTP client for TeamCity REST API with Bearer token auth
- Build configuration ID reference table
- XML response parsing helpers
"""

import json
import logging
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

logger = logging.getLogger("teamcity_mcp")


# =============================================================================
# Configuration
# =============================================================================

_config = None


def get_config() -> dict:
    """Load TeamCity config from ~/.teamcity-mcp/config.json.

    Returns:
        Dict with 'url' and 'token' keys.

    Raises:
        FileNotFoundError: If config file doesn't exist.
        KeyError: If required fields are missing.
    """
    global _config
    if _config is not None:
        return _config

    config_path = Path.home() / ".teamcity-mcp" / "config.json"
    if not config_path.exists():
        raise FileNotFoundError(
            f"TeamCity config not found at {config_path}. "
            "Create it with {\"url\": \"https://teamcity.labkey.org\", \"token\": \"...\"}"
        )

    with open(config_path) as f:
        _config = json.load(f)

    for key in ("url", "token"):
        if key not in _config:
            raise KeyError(f"Missing '{key}' in {config_path}")

    # Strip trailing slash from URL
    _config["url"] = _config["url"].rstrip("/")

    logger.info(f"Loaded TeamCity config for {_config['url']}")
    return _config


# =============================================================================
# HTTP Client
# =============================================================================

def tc_request(
    endpoint: str,
    accept: str = "application/xml",
    timeout: int = 30,
) -> bytes:
    """Make an authenticated GET request to the TeamCity REST API.

    Args:
        endpoint: REST API path (e.g., '/app/rest/builds?locator=...')
        accept: Accept header value (application/xml or application/json)
        timeout: Request timeout in seconds

    Returns:
        Response body as bytes
    """
    config = get_config()
    url = f"{config['url']}{endpoint}"

    request = urllib.request.Request(url)
    request.add_header("Authorization", f"Bearer {config['token']}")
    request.add_header("Accept", accept)

    logger.info(f"GET {url}")

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        logger.error(f"HTTP {e.code} {e.reason}: {body}")
        raise


def tc_request_json(endpoint: str, timeout: int = 30) -> dict:
    """Make an authenticated GET request and return parsed JSON."""
    data = tc_request(endpoint, accept="application/json", timeout=timeout)
    return json.loads(data.decode("utf-8"))


def tc_request_xml(endpoint: str, timeout: int = 30) -> ET.Element:
    """Make an authenticated GET request and return parsed XML."""
    data = tc_request(endpoint, accept="application/xml", timeout=timeout)
    return ET.fromstring(data.decode("utf-8"))


# =============================================================================
# Build Configuration ID Reference
# =============================================================================

# Maps GitHub check names (from `gh pr checks`) to TeamCity build config IDs.
# This mapping rarely changes; update here when new configs are added.

PR_CHECK_CONFIG_MAP = {
    "teamcity - Skyline master and PRs (Windows x86_64)": "bt209",
    "teamcity - Core Windows x86_64": "bt83",
    "teamcity - Core Linux x86_64": "bt17",
    "teamcity - Core Windows x86_64 (no vendor DLLs)": "bt143",
    "teamcity - ProteoWizard and Skyline Docker container (Wine x86_64)": "ProteoWizardAndSkylineDockerContainerWineX8664",
    "teamcity - Skyline master and PRs TestConnected tests": "ProteoWizard_SkylineMasterAndPRsTestConnectedTests",
    "teamcity - Bumbershoot Linux x86_64": "ProteoWizard_BumbershootLinuxX8664",
    "teamcity - Bumbershoot Windows x86_64": "ProteoWizard_BumbershootWindowsX8664",
}

# Reverse map: config ID -> short display name
CONFIG_DISPLAY_NAMES = {
    "bt209": "Skyline master and PRs (Win x64)",
    "bt83": "Core Windows x64",
    "bt17": "Core Linux x64",
    "bt143": "Core Windows x64 (no vendor DLLs)",
    "ProteoWizardAndSkylineDockerContainerWineX8664": "Docker (Wine x64)",
    "ProteoWizard_SkylineMasterAndPRsTestConnectedTests": "TestConnected",
}


# =============================================================================
# XML Parsing Helpers
# =============================================================================

def parse_build_xml(build_elem: ET.Element) -> dict:
    """Parse a <build> XML element into a dict.

    Args:
        build_elem: An XML Element representing a TeamCity build

    Returns:
        Dict with build fields
    """
    result = {
        "id": build_elem.get("id"),
        "number": build_elem.get("number"),
        "status": build_elem.get("status"),
        "state": build_elem.get("state"),
        "branch": build_elem.get("branchName"),
        "href": build_elem.get("href"),
        "webUrl": build_elem.get("webUrl"),
    }

    # Optional nested elements
    build_type = build_elem.find("buildType")
    if build_type is not None:
        result["buildTypeId"] = build_type.get("id")
        result["buildTypeName"] = build_type.get("name")

    triggered = build_elem.find("triggered")
    if triggered is not None:
        result["triggerDate"] = triggered.get("date")

    agent = build_elem.find("agent")
    if agent is not None:
        result["agent"] = agent.get("name")

    # Running build info
    running_info = build_elem.find("running-info")
    if running_info is not None:
        result["percentageComplete"] = running_info.get("percentageComplete")
        result["elapsedSeconds"] = running_info.get("elapsedSeconds")
        result["estimatedTotalSeconds"] = running_info.get("estimatedTotalSeconds")
        result["currentStageText"] = running_info.get("currentStageText")

    # Revision (commit hash)
    revisions = build_elem.find("revisions")
    if revisions is not None:
        revision = revisions.find("revision")
        if revision is not None:
            result["commit"] = revision.get("version")

    return result


def format_build_summary(build: dict) -> str:
    """Format a build dict into a readable summary line."""
    parts = [f"Build #{build.get('number', '?')} (ID: {build.get('id', '?')})"]

    status = build.get("status", "")
    state = build.get("state", "")
    if state == "running":
        pct = build.get("percentageComplete", "?")
        stage = build.get("currentStageText", "")
        parts.append(f"RUNNING ({pct}%)")
        if stage:
            parts.append(f"- {stage}")
    else:
        parts.append(status)

    commit = build.get("commit", "")
    if commit:
        parts.append(f"[{commit[:8]}]")

    agent = build.get("agent", "")
    if agent:
        parts.append(f"on {agent}")

    return "  ".join(parts)
