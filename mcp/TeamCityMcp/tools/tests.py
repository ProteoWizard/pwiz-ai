"""Test failure retrieval tools for TeamCity MCP server.

This is the most important module - it provides structured test failure data
that replaces manual TeamCity browsing. Uses the /app/rest/testOccurrences
endpoint which returns test names, status, and detailed failure stack traces.
"""

import logging
import xml.etree.ElementTree as ET

from .common import tc_request_xml

logger = logging.getLogger("teamcity_mcp")


def register_tools(mcp):
    """Register test-related tools."""

    @mcp.tool()
    async def get_failed_tests(
        build_id: int,
    ) -> str:
        """Get structured test failure data for a build.

        Returns test names and detailed failure messages/stack traces for all
        failed tests in the specified build. This is equivalent to the "Tests"
        tab in the TeamCity web UI.

        Args:
            build_id: TeamCity build ID (numeric, e.g., 3867261)

        Returns:
            Formatted list of failed tests with names and failure details.
        """
        try:
            endpoint = (
                f"/app/rest/testOccurrences"
                f"?locator=build:(id:{build_id}),status:FAILURE"
                f"&fields=testOccurrence(name,status,details,duration)"
            )

            root = tc_request_xml(endpoint)
            occurrences = root.findall("testOccurrence")

            if not occurrences:
                return f"No failed tests in build {build_id}."

            lines = [f"{len(occurrences)} failed test(s) in build {build_id}:"]
            lines.append("")

            for i, occ in enumerate(occurrences, 1):
                name = occ.get("name", "unknown")
                duration_ms = occ.get("duration")
                details_elem = occ.find("details")
                details = details_elem.text if details_elem is not None and details_elem.text else "(no details)"

                lines.append(f"--- Failed Test {i} ---")
                lines.append(f"Name: {name}")
                if duration_ms:
                    duration_s = int(duration_ms) / 1000
                    lines.append(f"Duration: {duration_s:.1f}s")
                lines.append(f"Details:")
                lines.append(details)
                lines.append("")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error getting failed tests: {e}", exc_info=True)
            return f"Error getting failed tests: {e}"

    @mcp.tool()
    async def get_test_summary(
        build_id: int,
    ) -> str:
        """Get test count summary for a build (passed, failed, ignored).

        Args:
            build_id: TeamCity build ID (numeric, e.g., 3867261)

        Returns:
            Test count summary.
        """
        try:
            # Get build details which include test count info
            endpoint = f"/app/rest/builds/id:{build_id}"
            root = tc_request_xml(endpoint)

            status_text = root.get("statusText", "")

            # Parse test counts from statusText (e.g., "Tests passed: 1583")
            # Also check for explicit testOccurrences count
            test_occurrences = root.find("testOccurrences")
            if test_occurrences is not None:
                count = test_occurrences.get("count", "?")
                passed = test_occurrences.get("passed", "?")
                failed = test_occurrences.get("failed", "0")
                ignored = test_occurrences.get("muted", "0")
                lines = [
                    f"Test summary for build {build_id}:",
                    f"  Total: {count}",
                    f"  Passed: {passed}",
                    f"  Failed: {failed}",
                    f"  Muted/Ignored: {ignored}",
                ]
                if status_text:
                    lines.append(f"  Status text: {status_text}")
                return "\n".join(lines)

            return f"Status: {status_text}" if status_text else f"No test data available for build {build_id}"

        except Exception as e:
            logger.error(f"Error getting test summary: {e}", exc_info=True)
            return f"Error getting test summary: {e}"
