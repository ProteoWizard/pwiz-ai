"""MailChimp MCP Tools package.

This package contains tool modules for the MailChimp MCP server.
Each module exports a `register_tools(mcp)` function to register its tools.

Modules:
- common: Shared utilities (config loading, HTTP client)
- discovery: Read-only tools for listing audiences, templates, campaigns
"""

from . import common
from . import discovery


def register_all_tools(mcp):
    """Register all tools from all modules."""
    discovery.register_tools(mcp)
