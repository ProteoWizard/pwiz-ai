"""Build search and status tools for TeamCity MCP server."""

import logging
import urllib.parse

from .common import (
    tc_request_xml,
    tc_request_json,
    parse_build_xml,
    format_build_summary,
)

logger = logging.getLogger("teamcity_mcp")


def register_tools(mcp):
    """Register build-related tools."""

    @mcp.tool()
    async def search_builds(
        build_type_id: str,
        branch: str = None,
        state: str = None,
        status: str = None,
        count: int = 10,
    ) -> str:
        """Search for TeamCity builds by configuration, branch, and state.

        Args:
            build_type_id: Build configuration ID (e.g., 'bt209' for Skyline PRs)
            branch: Branch locator (e.g., 'pull/4038' for PR builds)
            state: Build state filter: 'running', 'finished', 'queued', or None for all
            status: Build status filter: 'SUCCESS', 'FAILURE', or None for all
            count: Maximum number of results (default 10)

        Returns:
            Formatted build list with status, branch, commit, and agent info.
        """
        try:
            # Build locator string
            parts = [f"buildType:{build_type_id}"]
            if branch:
                parts.append(f"branch:{branch}")
            if state:
                parts.append(f"state:{state}")
            if status:
                parts.append(f"status:{status}")
            parts.append(f"count:{count}")
            locator = ",".join(parts)

            # Request with fields to get detailed info
            fields = (
                "build(id,number,status,state,branchName,webUrl,href,"
                "buildType(id,name),"
                "triggered(date),"
                "agent(name),"
                "running-info,"
                "revisions(revision(version)))"
            )
            encoded_fields = urllib.parse.quote(fields, safe="(,)")
            endpoint = f"/app/rest/builds?locator={locator}&fields={encoded_fields}"

            root = tc_request_xml(endpoint)
            builds = root.findall("build")

            if not builds:
                return f"No builds found for {build_type_id}" + (
                    f" branch={branch}" if branch else ""
                ) + (f" state={state}" if state else "")

            lines = [f"Found {len(builds)} build(s):"]
            lines.append("")
            for build_elem in builds:
                build = parse_build_xml(build_elem)
                lines.append(format_build_summary(build))
            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error searching builds: {e}", exc_info=True)
            return f"Error searching builds: {e}"

    @mcp.tool()
    async def get_build_status(
        build_id: int,
    ) -> str:
        """Get detailed status for a specific build.

        Args:
            build_id: TeamCity build ID (numeric, e.g., 3867261)

        Returns:
            Detailed build info including status, progress, step, agent, and trigger info.
        """
        try:
            endpoint = f"/app/rest/builds/id:{build_id}"
            root = tc_request_xml(endpoint)
            build = parse_build_xml(root)

            lines = [f"Build #{build.get('number', '?')} (ID: {build_id})"]
            lines.append("")

            # Status and state
            state = build.get("state", "unknown")
            status = build.get("status", "unknown")
            lines.append(f"Status: {status}")
            lines.append(f"State: {state}")

            # Config and branch
            if build.get("buildTypeName"):
                lines.append(f"Configuration: {build['buildTypeName']} ({build.get('buildTypeId', '')})")
            if build.get("branch"):
                lines.append(f"Branch: {build['branch']}")

            # Commit
            if build.get("commit"):
                lines.append(f"Commit: {build['commit']}")

            # Agent
            if build.get("agent"):
                lines.append(f"Agent: {build['agent']}")

            # Trigger date
            if build.get("triggerDate"):
                lines.append(f"Triggered: {build['triggerDate']}")

            # Running info
            if state == "running":
                lines.append("")
                pct = build.get("percentageComplete", "?")
                elapsed = build.get("elapsedSeconds", "?")
                estimated = build.get("estimatedTotalSeconds", "?")
                stage = build.get("currentStageText", "")
                lines.append(f"Progress: {pct}%")
                lines.append(f"Elapsed: {elapsed}s / Estimated total: {estimated}s")
                if stage:
                    lines.append(f"Current stage: {stage}")

            # Web URL
            if build.get("webUrl"):
                lines.append("")
                lines.append(f"URL: {build['webUrl']}")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error getting build status: {e}", exc_info=True)
            return f"Error getting build status: {e}"
