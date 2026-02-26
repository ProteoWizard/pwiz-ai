"""MCP Server for TeamCity CI build monitoring.

This server exposes tools for querying TeamCity at teamcity.labkey.org,
including:
- Build search by configuration, branch, and state
- Detailed build status (step, progress, estimated time)
- Structured test failure data (test names, stack traces)
- PR build status aggregation

Authentication is handled via config file at ~/.teamcity-mcp/config.json.

Setup:
1. Create ~/.teamcity-mcp/config.json with url and token
2. Install dependencies: pip install mcp
3. Register with Claude Code:
   claude mcp add teamcity -- python C:/proj/ai/mcp/TeamCityMcp/server.py
"""

import logging

from mcp.server.fastmcp import FastMCP

# Configure logging to stderr (required for STDIO transport)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("teamcity_mcp")

# Initialize FastMCP server
mcp = FastMCP("teamcity")

# Import and register tools from all modules
from tools import register_all_tools
register_all_tools(mcp)


def main():
    """Run the MCP server."""
    logger.info("Starting TeamCity MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
