"""Discovery and listing tools for MailChimp MCP server.

Tools for exploring MailChimp resources:
- ping: Verify API connectivity
- list_audiences: List audience/subscriber lists
- list_templates: List email templates
- list_campaigns: List campaigns with filters
- get_campaign: Get campaign details and content
"""

import logging
import urllib.error
from pathlib import Path

from .common import mc_request

logger = logging.getLogger("mailchimp_mcp")


def register_tools(mcp):
    """Register discovery tools."""

    @mcp.tool()
    async def mailchimp_ping() -> str:
        """Verify MailChimp API connectivity and authentication.

        Returns:
            Health status message from MailChimp API.
        """
        try:
            result = mc_request("/ping")
            return f"MailChimp API OK: {result.get('health_status', 'unknown')}"
        except urllib.error.HTTPError as e:
            return f"MailChimp API error: HTTP {e.code} {e.reason}"
        except Exception as e:
            return f"MailChimp connection failed: {e}"

    @mcp.tool()
    async def mailchimp_list_audiences() -> str:
        """List MailChimp audiences (subscriber lists).

        Returns:
            Formatted list of audiences with ID, name, and member count.
        """
        result = mc_request("/lists?count=100&fields=lists.id,lists.name,lists.stats.member_count,lists.date_created")
        lists = result.get("lists", [])

        if not lists:
            return "No audiences found."

        lines = [f"Found {len(lists)} audience(s):", ""]
        for lst in lists:
            stats = lst.get("stats", {})
            lines.append(
                f"  ID: {lst['id']}  |  {lst['name']}  |  "
                f"{stats.get('member_count', '?')} members  |  "
                f"Created: {lst.get('date_created', '?')}"
            )
        return "\n".join(lines)

    @mcp.tool()
    async def mailchimp_list_templates(include_builtin: bool = False) -> str:
        """List MailChimp email templates.

        Args:
            include_builtin: Include MailChimp's built-in templates (default: user-created only)

        Returns:
            Formatted list of templates with ID, name, and type.
        """
        endpoint = "/templates?count=100&fields=templates.id,templates.name,templates.type,templates.active,templates.date_created"
        result = mc_request(endpoint)
        templates = result.get("templates", [])

        if not include_builtin:
            templates = [t for t in templates if t.get("type") == "user"]

        if not templates:
            return "No templates found." + (" Try include_builtin=True for built-in templates." if not include_builtin else "")

        lines = [f"Found {len(templates)} template(s):", ""]
        for t in templates:
            active = "active" if t.get("active") else "inactive"
            lines.append(
                f"  ID: {t['id']}  |  {t['name']}  |  "
                f"{t.get('type', '?')}  |  {active}  |  "
                f"Created: {t.get('date_created', '?')}"
            )
        return "\n".join(lines)

    @mcp.tool()
    async def mailchimp_list_campaigns(
        status: str = None,
        count: int = 10,
        since_send_time: str = None,
    ) -> str:
        """List MailChimp campaigns with optional filters.

        Args:
            status: Filter by status: 'save' (draft), 'sent', 'paused', 'schedule', or None for all
            count: Maximum number of results (default 10)
            since_send_time: Only campaigns sent after this ISO date (e.g. '2024-01-01')

        Returns:
            Formatted list of campaigns with status, subject, and stats.
        """
        params = [f"count={count}"]
        params.append("fields=campaigns.id,campaigns.settings.title,campaigns.settings.subject_line,"
                       "campaigns.status,campaigns.send_time,campaigns.report_summary.opens,"
                       "campaigns.report_summary.clicks,campaigns.emails_sent")
        if status:
            params.append(f"status={status}")
        if since_send_time:
            params.append(f"since_send_time={since_send_time}")

        endpoint = f"/campaigns?{'&'.join(params)}"
        result = mc_request(endpoint)
        campaigns = result.get("campaigns", [])

        if not campaigns:
            return "No campaigns found."

        lines = [f"Found {len(campaigns)} campaign(s):", ""]
        for c in campaigns:
            settings = c.get("settings", {})
            report = c.get("report_summary", {})
            subject = settings.get("subject_line", "(no subject)")
            title = settings.get("title", "")
            status_str = c.get("status", "?")
            sent = c.get("emails_sent", 0)

            line = f"  ID: {c['id']}  |  {status_str}"
            if c.get("send_time"):
                line += f"  |  Sent: {c['send_time']}"
            line += f"  |  Subject: {subject}"
            if sent:
                opens = report.get("opens", 0)
                clicks = report.get("clicks", 0)
                line += f"  |  {sent} sent, {opens} opens, {clicks} clicks"
            if title and title != subject:
                line += f"  |  Title: {title}"
            lines.append(line)
        return "\n".join(lines)

    @mcp.tool()
    async def mailchimp_get_campaign(campaign_id: str, include_content: bool = False) -> str:
        """Get details for a specific MailChimp campaign.

        Args:
            campaign_id: The campaign ID
            include_content: Also retrieve campaign HTML content (can be large)

        Returns:
            Campaign details including settings, status, and optionally content.
        """
        result = mc_request(f"/campaigns/{campaign_id}")
        settings = result.get("settings", {})
        recipients = result.get("recipients", {})

        lines = [
            f"Campaign: {campaign_id}",
            f"  Status: {result.get('status', '?')}",
            f"  Title: {settings.get('title', '?')}",
            f"  Subject: {settings.get('subject_line', '?')}",
            f"  Preview text: {settings.get('preview_text', '')}",
            f"  From: {settings.get('from_name', '?')} <{settings.get('reply_to', '?')}>",
            f"  List ID: {recipients.get('list_id', '?')}",
            f"  List name: {recipients.get('list_name', '?')}",
        ]

        if result.get("send_time"):
            lines.append(f"  Sent: {result['send_time']}")
            lines.append(f"  Emails sent: {result.get('emails_sent', '?')}")

        if result.get("archive_url"):
            lines.append(f"  Archive URL: {result['archive_url']}")

        if include_content:
            try:
                content = mc_request(f"/campaigns/{campaign_id}/content")
                lines.append("")
                lines.append("--- Content ---")

                # Show template sections if present
                template = content.get("template", {})
                if template:
                    sections = template.get("sections", {})
                    if sections:
                        lines.append(f"Template ID: {template.get('id', '?')}")
                        lines.append(f"Sections: {', '.join(sections.keys())}")
                        for name, html in sections.items():
                            preview = html[:500] if html else "(empty)"
                            lines.append(f"  [{name}]: {preview}...")

                # Save full HTML to file (can be large)
                html = content.get("html", "")
                if html:
                    # Find repo root by looking for ai/.tmp
                    tmp_dir = Path(__file__).resolve().parents[2] / ".tmp"
                    tmp_dir.mkdir(parents=True, exist_ok=True)
                    safe_id = campaign_id.replace("/", "_")
                    html_file = tmp_dir / f"campaign-{safe_id}.html"
                    html_file.write_text(html, encoding="utf-8")
                    lines.append(f"  HTML saved to: {html_file}")
                    lines.append(f"  HTML size: {len(html):,} bytes")

                # Show plain text if available
                plain = content.get("plain_text", "")
                if plain:
                    lines.append(f"  Plain text preview: {plain[:300]}...")
            except Exception as e:
                lines.append(f"  Content retrieval failed: {e}")

        return "\n".join(lines)
