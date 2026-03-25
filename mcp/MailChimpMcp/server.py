"""MCP Server for read-only MailChimp campaign queries.

This server exposes read-only tools for querying MailChimp via the
Marketing API:
- Verify API connectivity (ping)
- List audiences, templates, and campaigns
- Get campaign details and content

Campaign creation and content injection are NOT supported by this server.
MailChimp's new email editor does not support API-driven content injection
(the mc:edit section API only works with the deprecated Classic builder).
Instead, Claude generates paste-ready HTML that the developer copies into
MailChimp's designer code view. See ai/docs/release-guide.md for details.

Authentication is handled via config file at ~/.mailchimp-mcp/config.json.

Setup:
1. Create ~/.mailchimp-mcp/config.json (see .env.example for required fields)
2. Install dependencies: pip install mcp
3. Register with Claude Code:
   claude mcp add mailchimp -- python C:/proj/ai/mcp/MailChimpMcp/server.py
"""

import logging

from mcp.server.fastmcp import FastMCP

# Configure logging to stderr (required for STDIO transport)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("mailchimp_mcp")

# Initialize FastMCP server
mcp = FastMCP("mailchimp")

# Import and register tools from all modules
from tools import register_all_tools
register_all_tools(mcp)


def main():
    """Run the MCP server."""
    logger.info("Starting MailChimp MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
