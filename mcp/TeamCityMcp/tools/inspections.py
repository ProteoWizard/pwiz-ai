"""Code inspection tools for TeamCity MCP server."""

import io
import logging
import xml.etree.ElementTree as ET
import zipfile

from .common import tc_request

logger = logging.getLogger("teamcity_mcp")


def register_tools(mcp):
    """Register inspection-related tools."""

    @mcp.tool()
    async def get_code_inspections(
        build_id: int,
        build_type_id: str = "ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks",
    ) -> str:
        """Get ReSharper code inspection results from a TeamCity build.

        Downloads the inspectcode_report.xml artifact from the build and
        parses the inspection issues.

        Args:
            build_id: TeamCity build ID (numeric, e.g., 3899165)
            build_type_id: Build configuration ID (default: Skyline ReSharper Checks)

        Returns:
            Formatted list of inspection issues with file paths, line numbers,
            severity, and messages. Also includes issue type definitions.
        """
        try:
            # Download the inspection report from build artifacts
            # The report is inside a zip: inspections.zip!/inspectcode_report.xml
            endpoint = (
                f"/repository/download/{build_type_id}/{build_id}:id/"
                f".teamcity/dotnet-tools-inspectcode/inspections.zip"
            )
            zip_data = tc_request(endpoint, accept="application/octet-stream", timeout=60)

            # Extract the XML report from the zip
            with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
                report_names = [n for n in zf.namelist() if n.endswith(".xml")]
                if not report_names:
                    return f"No XML report found in inspections.zip for build {build_id}"
                with zf.open(report_names[0]) as f:
                    root = ET.parse(f).getroot()

            # Parse issue types for reference
            issue_types = {}
            for it in root.findall(".//IssueType"):
                type_id = it.get("Id", "")
                issue_types[type_id] = {
                    "category": it.get("Category", ""),
                    "description": it.get("Description", ""),
                    "severity": it.get("Severity", ""),
                }

            # Parse issues grouped by project
            all_issues = []
            for project in root.findall(".//Project"):
                project_name = project.get("Name", "unknown")
                for issue in project.findall("Issue"):
                    type_id = issue.get("TypeId", "")
                    file_path = issue.get("File", "")
                    line = issue.get("Line", "")
                    message = issue.get("Message", "")
                    severity = issue_types.get(type_id, {}).get("severity", "WARNING")
                    all_issues.append({
                        "project": project_name,
                        "type": type_id,
                        "file": file_path,
                        "line": line,
                        "message": message,
                        "severity": severity,
                    })

            if not all_issues:
                return f"No inspection issues found in build {build_id}."

            # Format output grouped by severity
            errors = [i for i in all_issues if i["severity"] == "ERROR"]
            warnings = [i for i in all_issues if i["severity"] == "WARNING"]
            suggestions = [i for i in all_issues if i["severity"] not in ("ERROR", "WARNING")]

            lines = [f"Code inspection results for build {build_id}:"]
            lines.append(f"  {len(errors)} error(s), {len(warnings)} warning(s), {len(suggestions)} suggestion(s)")
            lines.append("")

            for label, issues in [("ERRORS", errors), ("WARNINGS", warnings), ("SUGGESTIONS", suggestions)]:
                if not issues:
                    continue
                lines.append(f"--- {label} ---")
                for issue in issues:
                    loc = f"{issue['file']}"
                    if issue["line"]:
                        loc += f":{issue['line']}"
                    lines.append(f"  [{issue['severity']}] {loc}")
                    lines.append(f"    {issue['type']}: {issue['message']}")
                lines.append("")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error getting code inspections: {e}", exc_info=True)
            return f"Error getting code inspections: {e}"
