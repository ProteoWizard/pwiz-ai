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

# Fields for build lists that span configurations: which config, branch, agent and commit each
# build was, and when it started, so a sequence of builds on one agent or of one commit reads
# as a timeline.
_TIMELINE_FIELDS = (
    "build(id,number,status,state,branchName,startDate,queuedDate,"
    "buildType(id),agent(name),revisions(revision(version)))"
)


def _locator_value(value: str) -> str:
    """Quote a locator dimension value: parentheses keep commas and colons in the value from being
    read as locator syntax, and the whole value is URL-encoded for the query string."""
    return urllib.parse.quote(f"({value})", safe="")


def _format_timeline(builds, show_agent: bool, show_config: bool = True) -> list:
    """One line per build, oldest first: start time, ID, config, branch, status, commit, agent."""
    rows = []
    for b in builds:
        revision = b.find("revisions/revision")
        build_type = b.find("buildType")
        agent = b.find("agent")
        state = b.get("state") or ""
        status = b.get("status") or ""
        # The XML API returns the dates as child elements, e.g. <startDate>20261007T154249-0700</startDate>,
        # which sort correctly as text.
        when = b.findtext("startDate") or b.findtext("queuedDate") or ""
        shown = f"{when[0:4]}-{when[4:6]}-{when[6:8]} {when[9:11]}:{when[11:13]}" if len(when) >= 13 else when
        parts = [shown, f"ID {b.get('id')}"]
        if show_config:
            parts.append(build_type.get("id") if build_type is not None else "?")
        parts.append(b.get("branchName") or "<default>")
        parts.append(status if state == "finished" else (state.upper() or status))
        parts.append((revision.get("version") or "")[:10] if revision is not None else "")
        if show_agent:
            parts.append(agent.get("name") if agent is not None else "(no agent)")
        rows.append((when, "  ".join(p for p in parts if p)))
    rows.sort(key=lambda r: r[0])
    return [r[1] for r in rows]


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
            else:
                # TeamCity's /app/rest/builds defaults to state:finished. The
                # documented "None = all states" behavior needs an explicit
                # state:any, or just-queued/running builds (e.g. a freshly
                # triggered PR build) are silently missed and read as "not run".
                parts.append("state:any")
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
    async def search_builds_by_agent(
        agent_name: str,
        build_type_id: str = None,
        count: int = 20,
    ) -> str:
        """List recent builds on one agent, across every configuration, oldest first.

        Use this to reconstruct what an agent's checkout held before a failing build: build
        configs on an agent can share one checkout directory (e.g. C:\\pwiz), so a file left by
        one PR's build can be what the next build of a different PR runs against.

        Args:
            agent_name: Exact agent name (e.g. 'MacCoss TeamCity Agent 1',
                        'pwiz-windows-i-0d401c3437a3dc2a6'). Agents that have since
                        disconnected are still found.
            build_type_id: Optional config ID to narrow the list (e.g. 'bt209').
            count: Maximum number of builds (default 20, most recent).

        Returns:
            One line per build: start time, build ID, config, branch, status, commit.
        """
        try:
            parts = [f"agentName:{_locator_value(agent_name)}"]
            if build_type_id:
                parts.append(f"buildType:{build_type_id}")
            # defaultFilter:false includes personal, canceled and failed-to-start builds, and
            # state:any includes running ones; the default hides exactly the builds that explain
            # an agent's state.
            parts += ["defaultFilter:false", "state:any", f"count:{count}"]
            fields = urllib.parse.quote(_TIMELINE_FIELDS, safe="(,)")
            root = tc_request_xml(f"/app/rest/builds?locator={','.join(parts)}&fields={fields}")
            builds = root.findall("build")
            if not builds:
                return f"No builds found on agent '{agent_name}'."
            lines = [f"{len(builds)} build(s) on {agent_name}, oldest first:", ""]
            lines += _format_timeline(builds, show_agent=False)
            return "\n".join(lines)
        except Exception as e:
            logger.error(f"Error searching builds by agent: {e}", exc_info=True)
            return f"Error searching builds by agent: {e}"

    @mcp.tool()
    async def search_builds_by_revision(
        revision: str,
        count: int = 50,
    ) -> str:
        """List every build of one commit, across all configurations and agents, oldest first.

        Use this to find which agents checked out a given commit - for instance a head that
        changed .gitattributes, whose working files can outlive it on agents that reuse their
        checkout.

        Args:
            revision: Full 40-character commit SHA. TeamCity matches revisions exactly; a
                      short SHA finds nothing.
            count: Maximum number of builds (default 50).

        Returns:
            One line per build: start time, build ID, config, branch, status, agent.
        """
        try:
            if not re.fullmatch(r"[0-9a-fA-F]{40}", revision or ""):
                return (
                    f"'{revision}' is not a full 40-character SHA. TeamCity matches revisions "
                    f"exactly; expand it first with `git rev-parse {revision}`."
                )
            parts = [f"revision:{revision}", "defaultFilter:false", "state:any", f"count:{count}"]
            fields = urllib.parse.quote(_TIMELINE_FIELDS, safe="(,)")
            root = tc_request_xml(f"/app/rest/builds?locator={','.join(parts)}&fields={fields}")
            builds = root.findall("build")
            if not builds:
                return f"No builds found for revision {revision}."
            lines = [f"{len(builds)} build(s) of {revision[:10]}, oldest first:", ""]
            lines += _format_timeline(builds, show_agent=True)
            return "\n".join(lines)
        except Exception as e:
            logger.error(f"Error searching builds by revision: {e}", exc_info=True)
            return f"Error searching builds by revision: {e}"

    @mcp.tool()
    async def list_agents(
        connected_only: bool = True,
        name_contains: str = None,
    ) -> str:
        """List TeamCity build agents and whether each is connected, authorized and enabled.

        Cloud agents (pwiz-windows-i-*, pwiz-linux-i-*) are created per demand and disappear;
        a persistent agent such as 'MacCoss TeamCity Agent 1' keeps its checkout between builds.
        Use this to tell whether an agent that ran a suspect build still exists.

        Args:
            connected_only: Only agents connected now (default True). False also lists
                            disconnected agents TeamCity still remembers.
            name_contains: Optional case-insensitive substring filter on the agent name
                           (e.g. 'windows', 'Agent 1').

        Returns:
            One line per agent: name, connected, authorized, enabled, pool.
        """
        try:
            locator = "connected:true,authorized:any" if connected_only else "connected:any,authorized:any"
            fields = urllib.parse.quote("agent(id,name,connected,authorized,enabled,pool(name))", safe="(,)")
            root = tc_request_xml(f"/app/rest/agents?locator={locator}&fields={fields}")
            agents = root.findall("agent")
            if name_contains:
                needle = name_contains.lower()
                agents = [a for a in agents if needle in (a.get("name") or "").lower()]
            if not agents:
                return "No agents match."
            lines = [f"{len(agents)} agent(s):", ""]
            for a in sorted(agents, key=lambda a: a.get("name") or ""):
                pool = a.find("pool")
                flags = [
                    "connected" if a.get("connected") == "true" else "disconnected",
                    "authorized" if a.get("authorized") == "true" else "unauthorized",
                    "enabled" if a.get("enabled") == "true" else "disabled",
                ]
                pool_name = pool.get("name") if pool is not None else ""
                lines.append(f"{a.get('name')}  (id {a.get('id')})  " + ", ".join(flags)
                             + (f"  pool: {pool_name}" if pool_name else ""))
            return "\n".join(lines)
        except Exception as e:
            logger.error(f"Error listing agents: {e}", exc_info=True)
            return f"Error listing agents: {e}"

    @mcp.tool()
    async def trigger_build(
        build_type_id: str,
        branch: str = None,
        agent_name: str = None,
        clean_sources: bool = False,
        comment: str = None,
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
        - ProteoWizard_OspreyWindowsNet: Osprey Windows .NET unit build
        - ProteoWizard_OspreyWindowsNetPerfRegressionTests: Osprey Perf/Regression
          (all four datasets, ~40 min as of 2026-10, manual only - master too;
          use branch='pull/<N>', or omit branch for master)

        Args:
            build_type_id: Build configuration ID (e.g., 'bt209')
            branch: Branch name (e.g., 'Skyline/work/20260123_feature' or 'pull/3861').
                    For named branches, 'refs/heads/' is prepended automatically.
                    For PR branches like 'pull/NNN', they are used as-is.
                    NOTE: Osprey configs (ProteoWizard_Osprey*) build PR refs ONLY --
                    pass 'pull/<N>', never a named branch (which silently builds
                    master; this method refuses that combination).
                    If not specified, the build uses its default branch.
            agent_name: Agent name to run on (e.g., 'MacCoss TeamCity Agent 1').
                        The agent ID is resolved automatically by name lookup.
                        If not specified, TeamCity assigns an available agent.
            clean_sources: True deletes the build's whole checkout directory and checks out
                           fresh ("Delete all files before the build"). Use it when an agent's
                           working files may be stale - git rewrites only files whose content
                           changed, so a file left by an earlier build (for example under a
                           since-removed .gitattributes pin) survives a normal checkout. The
                           checkout directory can be shared by several configs on that agent.
            comment: Optional text recorded on the build, saying why it was queued.

        Returns:
            Build queue info with ID and URL for monitoring.
        """
        try:
            # Guard the Osprey silent-master trap. Osprey TeamCity configs watch PR
            # refs (refs/pull/<N>/head), not named branches; a Skyline/work/... branch
            # is not recognized and TeamCity silently falls back to building master --
            # a green result against the wrong commit. Refuse it and point at pull/<N>.
            # (Skyline configs legitimately use named branches, so this guard is scoped
            # to Osprey configs only.)
            if (
                branch
                and "osprey" in build_type_id.lower()
                and not branch.startswith("pull/")
                and branch not in ("master", "<default>")
            ):
                return (
                    f"Refusing to trigger '{build_type_id}' on named branch '{branch}'.\n"
                    f"Osprey TeamCity configs build PR refs (refs/pull/<N>/head); a named "
                    f"branch is not recognized and TeamCity silently builds master instead. "
                    f"Pass branch='pull/<N>' (the PR number), e.g. branch='pull/4358'."
                )

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

            if clean_sources:
                payload["triggeringOptions"] = {"cleanSources": True}
            if comment:
                payload["comment"] = {"text": comment}

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
            if clean_sources:
                lines.append("Clean sources: yes (checkout directory deleted before the build)")
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
