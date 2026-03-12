"""Build search and status tools for TeamCity MCP server."""

import json
import logging
import re
import urllib.parse

from .common import (
    tc_request,
    tc_post,
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

    @mcp.tool()
    async def get_build_log(
        build_id: int,
        search: str = None,
        context: int = 5,
        tail: int = 0,
    ) -> str:
        """Search or tail the build log for a TeamCity build.

        Use 'search' to find specific text (exceptions, errors, test names).
        Use 'tail' to get the last N lines of the log.
        If neither is specified, returns a summary with line count and
        the last 30 lines.

        For test failures, often the build log contains the real diagnostic
        info (stack traces, assembly load errors) that the test results API
        doesn't capture.

        Args:
            build_id: TeamCity build ID (numeric, e.g., 3867235)
            search: Regex pattern to search for (e.g., 'Could not load|exception')
            context: Number of context lines around each match (default 5)
            tail: Return last N lines of the log (0 = disabled)

        Returns:
            Matching log lines with context, or tail of the log.
        """
        try:
            data = tc_request(
                f"/downloadBuildLog.html?buildId={build_id}",
                accept="text/plain",
                timeout=60,
            )
            log_text = data.decode("utf-8", errors="replace")
            lines = log_text.split("\n")
            total = len(lines)

            if tail > 0:
                # Return last N lines
                start = max(0, total - tail)
                result_lines = [f"Build {build_id} log — last {tail} of {total} lines:"]
                result_lines.append("")
                for i in range(start, total):
                    result_lines.append(lines[i].rstrip())
                return "\n".join(result_lines)

            if search:
                # Search with context
                try:
                    pattern = re.compile(search, re.IGNORECASE)
                except re.error as e:
                    return f"Invalid regex pattern: {e}"

                matches = []
                for i, line in enumerate(lines):
                    if pattern.search(line):
                        matches.append(i)

                if not matches:
                    return f"No matches for '{search}' in build {build_id} log ({total} lines)."

                # Deduplicate overlapping context windows
                result_lines = [
                    f"Build {build_id} log — {len(matches)} match(es) "
                    f"for '{search}' in {total} lines:"
                ]
                result_lines.append("")

                shown = set()
                for match_idx in matches:
                    start = max(0, match_idx - context)
                    end = min(total, match_idx + context + 1)
                    if start in shown:
                        continue
                    if shown:
                        result_lines.append("---")
                    for j in range(start, end):
                        marker = ">>>" if j == match_idx else "   "
                        result_lines.append(f"{marker} {j}: {lines[j].rstrip()}")
                        shown.add(j)

                return "\n".join(result_lines)

            # Default: summary + last 30 lines
            result_lines = [f"Build {build_id} log — {total} lines total."]
            result_lines.append("")
            result_lines.append("Last 30 lines:")
            result_lines.append("")
            start = max(0, total - 30)
            for i in range(start, total):
                result_lines.append(lines[i].rstrip())
            return "\n".join(result_lines)

        except Exception as e:
            logger.error(f"Error getting build log: {e}", exc_info=True)
            return f"Error getting build log: {e}"

    @mcp.tool()
    async def trigger_build(
        build_type_id: str,
        branch: str = None,
        agent_name: str = None,
    ) -> str:
        """Trigger a new build on TeamCity.

        Common build configuration IDs:
        - bt209: Skyline master and PRs (Windows x86_64)
        - bt210: Skyline master and PRs (Windows x86_64 debug, with code coverage)
        - ProteoWizard_SkylinePrPerfAndTutorialTestsWindowsX8664: Skyline PR Perf and Tutorial tests
        - ProteoWizard_SkylineMasterAndPRsTestConnectedTests: TestConnected tests
        - ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks: Code Inspection
        - ProteoWizard_ZSkylineSingleTestTroubleshooting: Single test troubleshooting
        - bt83: Core Windows x86_64

        Args:
            build_type_id: Build configuration ID (e.g., 'bt209')
            branch: Branch name (e.g., 'Skyline/work/20260123_feature' or 'pull/3861').
                    For named branches, 'refs/heads/' is prepended automatically.
                    For PR branches like 'pull/NNN', they are used as-is.
                    If not specified, the build uses its default branch.
            agent_name: Agent name to run on (e.g., 'MacCoss TeamCity Agent 1').
                        The agent ID is resolved automatically by name lookup.
                        If not specified, TeamCity assigns an available agent.

        Returns:
            Build queue info with ID and URL for monitoring.
        """
        try:
            # Build the JSON payload
            payload = {
                "buildType": {"id": build_type_id},
            }

            if branch:
                # PR branches (pull/NNN) are used as-is; named branches get refs/heads/ prefix
                if branch.startswith("pull/"):
                    payload["branchName"] = branch
                else:
                    payload["branchName"] = f"refs/heads/{branch}"

            if agent_name:
                # Look up agent ID by name
                encoded_name = urllib.parse.quote(agent_name)
                agent_data = tc_request_json(
                    f"/app/rest/agents?locator=name:{encoded_name}"
                )
                agents = agent_data.get("agent", [])
                if not agents:
                    return f"Agent not found: '{agent_name}'"
                payload["agent"] = {"id": agents[0]["id"]}

            body = json.dumps(payload)
            data = tc_post(
                "/app/rest/buildQueue", body,
                content_type="application/json",
            )
            result = json.loads(data.decode("utf-8"))

            build_id = result.get("id", "?")
            web_url = result.get("webUrl", "")
            state = result.get("state", "queued")
            branch_name = result.get("branchName", branch or "default")
            build_type_name = result.get("buildType", {}).get("name", build_type_id)

            lines = [
                f"Build triggered successfully!",
                f"",
                f"Configuration: {build_type_name}",
                f"Branch: {branch_name}",
                f"State: {state}",
                f"Build ID: {build_id}",
            ]
            if agent_name:
                lines.append(f"Agent: {agent_name} (id: {payload['agent']['id']})")
            if web_url:
                lines.append(f"URL: {web_url}")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error triggering build: {e}", exc_info=True)
            return f"Error triggering build: {e}"

    @mcp.tool()
    async def cancel_build(
        build_id: int,
        comment: str = "Cancelled via MCP",
    ) -> str:
        """Cancel a queued or running build on TeamCity.

        Args:
            build_id: TeamCity build ID (numeric, e.g., 3886466)
            comment: Optional cancellation comment

        Returns:
            Confirmation of cancellation.
        """
        try:
            body = json.dumps({
                "comment": comment,
                "readdIntoQueue": False,
            })
            data = tc_post(
                f"/app/rest/builds/id:{build_id}", body,
                content_type="application/json",
            )
            result = json.loads(data.decode("utf-8"))

            state = result.get("state", "unknown")
            status = result.get("status", "")
            build_number = result.get("number", "?")

            return (
                f"Build #{build_number} (ID: {build_id}) cancelled.\n"
                f"State: {state}\n"
                f"Status: {status}"
            )

        except Exception as e:
            logger.error(f"Error cancelling build: {e}", exc_info=True)
            return f"Error cancelling build: {e}"
