"""TeamCity MCP Tools package.

This package contains tool modules for the TeamCity MCP server.
Each module exports a `register_tools(mcp)` function to register its tools.

Modules:
- common: Shared utilities (config loading, HTTP client, config ID reference)
- builds: Build search and status tools
- tests: Test failure retrieval tools
"""

from . import common
from . import builds
from . import tests


def register_all_tools(mcp):
    """Register all tools from all modules."""
    builds.register_tools(mcp)
    tests.register_tools(mcp)
