"""Common utilities for MailChimp MCP server.

This module contains:
- Config loading from ~/.mailchimp-mcp/config.json
- HTTP client for MailChimp Marketing API with Basic auth (read-only GET requests)
"""

import base64
import json
import logging
import urllib.error
import urllib.request
from pathlib import Path

logger = logging.getLogger("mailchimp_mcp")


# =============================================================================
# Configuration
# =============================================================================

_config = None


def get_config() -> dict:
    """Load MailChimp config from ~/.mailchimp-mcp/config.json.

    Returns:
        Dict with api_key, server_prefix, and optional fields.

    Raises:
        FileNotFoundError: If config file doesn't exist.
        KeyError: If required fields are missing.
    """
    global _config
    if _config is not None:
        return _config

    config_path = Path.home() / ".mailchimp-mcp" / "config.json"
    if not config_path.exists():
        raise FileNotFoundError(
            f"MailChimp config not found at {config_path}. "
            "See ai/mcp/MailChimpMcp/.env.example for required fields."
        )

    with open(config_path) as f:
        _config = json.load(f)

    required_keys = ("api_key", "server_prefix")
    for key in required_keys:
        if key not in _config:
            raise KeyError(f"Missing '{key}' in {config_path}")

    logger.info(f"Loaded MailChimp config for {_config['server_prefix']}.api.mailchimp.com")
    return _config


def get_base_url() -> str:
    """Get the MailChimp API base URL for the configured datacenter."""
    config = get_config()
    return f"https://{config['server_prefix']}.api.mailchimp.com/3.0"


def _auth_header() -> str:
    """Build Basic auth header value. Username can be any string."""
    config = get_config()
    credentials = base64.b64encode(f"mcp:{config['api_key']}".encode()).decode()
    return f"Basic {credentials}"


# =============================================================================
# HTTP Client
# =============================================================================

def mc_request(endpoint: str, timeout: int = 30) -> dict:
    """Make an authenticated GET request to the MailChimp Marketing API.

    Args:
        endpoint: API path (e.g., '/ping', '/campaigns')
        timeout: Request timeout in seconds

    Returns:
        Parsed JSON response as dict
    """
    url = f"{get_base_url()}{endpoint}"

    request = urllib.request.Request(url)
    request.add_header("Authorization", _auth_header())
    request.add_header("Accept", "application/json")

    logger.info(f"GET {url}")

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            response_data = response.read()
            if not response_data:
                return {}
            return json.loads(response_data.decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = ""
        try:
            error_body = e.read().decode("utf-8", errors="replace")[:1000]
        except Exception:
            pass
        logger.error(f"HTTP {e.code} {e.reason}: {error_body}")
        raise
