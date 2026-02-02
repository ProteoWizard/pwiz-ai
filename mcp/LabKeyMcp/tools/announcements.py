"""Announcement tools for LabKey MCP server.

This module contains tools for posting announcements to LabKey containers,
primarily for posting Skyline-daily release notes.

Uses the announcement controller (not SDK insert_rows) to ensure email
notifications are sent to subscribers — immediate, per-thread, and daily digest.
"""

import logging
from urllib.parse import quote

import labkey

from .common import (
    get_labkey_session,
    get_server_context,
    DEFAULT_SERVER,
)

logger = logging.getLogger("labkey_mcp")

DEFAULT_ANNOUNCEMENT_CONTAINER = "/home/software/Skyline/daily"


def register_tools(mcp):
    """Register announcement tools."""

    @mcp.tool()
    async def post_announcement(
        title: str,
        body: str,
        renderer_type: str = "MARKDOWN",
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_ANNOUNCEMENT_CONTAINER,
    ) -> str:
        """[D] Post new announcement thread. CAUTION: Creates live content. → announcements.md"""
        try:
            # Step 1: Establish authenticated session with CSRF token
            logger.info(f"Establishing session for announcement in {container_path}")
            session, csrf_token = get_labkey_session(server)

            # Step 2: Normalize line endings
            normalized_body = body.replace("\r\n", "\n").replace("\r", "\n")

            # Step 3: Build the POST URL
            encoded_path = quote(container_path, safe="/")
            post_url = f"https://{server}{encoded_path}/announcements-insert.view"

            # Step 4: Build form payload matching LabKey's announcement insert form
            # Required fields: title, body, rendererType
            # Hidden fields: X-LABKEY-CSRF, cancelUrl, returnUrl, discussionSrcIdentifier
            payload = {
                "title": title,
                "body": normalized_body,
                "rendererType": renderer_type,
                "X-LABKEY-CSRF": csrf_token,
                "cancelUrl": "",
                "returnUrl": "",
                "discussionSrcIdentifier": "",
            }

            headers = {
                "X-Requested-With": "XMLHttpRequest",
                "Origin": f"https://{server}",
                "Referer": f"https://{server}{encoded_path}/announcements-insert.view",
            }

            # Step 5: POST the form
            logger.info(f"Posting announcement: {title}")
            status_code, response_text = session.post_form(
                post_url, payload, headers=headers
            )

            # Step 6: Check for errors
            if status_code not in (200, 302):
                error_snippet = response_text[:500] if response_text else "(empty response)"
                return (
                    f"Announcement post failed with status {status_code}:\n"
                    f"  Response: {error_snippet}"
                )

            # Step 7: Query for the newly created thread to get its RowId
            row_id = None
            try:
                server_context = get_server_context(server, container_path)
                result = labkey.query.select_rows(
                    server_context=server_context,
                    schema_name="announcement",
                    query_name="Announcement",
                    filter_array=[
                        labkey.query.QueryFilter("Title", title),
                        labkey.query.QueryFilter("Parent", "", "ISBLANK"),
                    ],
                    sort="-RowId",
                    max_rows=1,
                    columns="RowId,Title",
                )
                rows = result.get("rows", [])
                if rows:
                    row_id = rows[0].get("RowId")
            except Exception as e:
                logger.warning(f"Could not query for new announcement RowId: {e}")

            if row_id:
                view_url = f"https://{server}{container_path}/announcements-thread.view?rowId={row_id}"
                return (
                    f"Announcement posted successfully:\n"
                    f"  title: {title}\n"
                    f"  container: {container_path}\n"
                    f"  renderer: {renderer_type}\n"
                    f"  row_id: {row_id}\n"
                    f"\nView at: {view_url}"
                )
            else:
                list_url = f"https://{server}{container_path}/announcements-begin.view"
                return (
                    f"Announcement posted successfully:\n"
                    f"  title: {title}\n"
                    f"  container: {container_path}\n"
                    f"  renderer: {renderer_type}\n"
                    f"\nCould not look up row ID.\n"
                    f"View announcements at: {list_url}"
                )

        except Exception as e:
            logger.error(f"Error posting announcement: {e}", exc_info=True)
            return f"Error posting announcement: {e}"
