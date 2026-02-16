"""Exception triage tools for LabKey MCP server.

This module contains tools for querying Skyline exception reports
from the skyline.ms exception tracking system.

Enhanced with stack trace normalization (2025-12-31) to:
- Group exceptions by fingerprint (same bug = same fingerprint)
- Track unique users via Installation ID (dedupe frustrated users)
- Track software versions for known-fix correlation
"""

import logging
import re
from datetime import datetime, timedelta

import labkey
from labkey.query import QueryFilter

from .common import (
    get_server_context,
    get_tmp_dir,
    get_daily_history_dir,
    DEFAULT_SERVER,
    DEFAULT_CONTAINER,
    EXCEPTION_SCHEMA,
    EXCEPTION_QUERY,
)
from .stacktrace import normalize_stack_trace

logger = logging.getLogger("labkey_mcp")

# Patterns for parsing exception body
INSTALLATION_ID_PATTERN = re.compile(
    r'Installation ID:\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
)
VERSION_PATTERN = re.compile(
    r'Skyline version:\s*(\d+\.\d+\.\d+\.\d+(?:-[0-9a-fA-F]+)?)\s*\((\d+-bit)\)'
)
# Email pattern - users sometimes provide contact info
EMAIL_PATTERN = re.compile(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
)
# User comments pattern - between "User comments:" and "Skyline version:"
USER_COMMENTS_PATTERN = re.compile(
    r'User comments:\s*(.*?)\s*(?=Skyline version:|Installation ID:|$)',
    re.DOTALL
)
STACK_TRACE_SEPARATOR = '--------------------'

# History settings
HISTORY_FILE = 'exception-history.json'
RETENTION_MONTHS = 9  # Cover full release cycle + buffer
HISTORY_SCHEMA_VERSION = 2  # v2: stores individual reports with row_ids

# Current major release anchor for backfill
MAJOR_RELEASE_VERSION = "25.1"
MAJOR_RELEASE_DATE = "2025-05-22"

# URL format for exception details
EXCEPTION_URL_TEMPLATE = "https://skyline.ms/home/issues/exceptions/announcements-thread.view?rowId={row_id}"


def _get_exception_url(row_id: int) -> str:
    """Generate URL to view exception details on skyline.ms."""
    return EXCEPTION_URL_TEMPLATE.format(row_id=row_id)


def _parse_version_tuple(version_str: str):
    """Parse a Skyline version string into a tuple of ints for comparison.

    Handles formats like "25.1.0.237", "25.1.0.237-7401c644b4" (with commit hash).
    Returns None for unparseable versions.
    """
    if not version_str:
        return None
    # Strip commit hash suffix
    base = version_str.split('-')[0]
    parts = base.split('.')
    try:
        return tuple(int(p) for p in parts)
    except (ValueError, TypeError):
        return None


def _get_fix_summary(fix_data: dict) -> dict:
    """Extract summary info from fix data (handles both old and new schema).

    Old schema (v1):
        {'pr_number': 'PR#1234', 'merge_date': '...', 'fixed_in_version': '...', 'commit': '...'}

    New schema (v2):
        {'master': {'pr': 'PR#1234', 'commit': '...', 'merged': '...'},
         'release': {'branch': '...', 'pr': '...', 'commit': '...', 'merged': '...'},
         'first_fixed_version': '...'}

    Returns dict with:
        pr: Primary PR number (from master branch)
        commit: Commit hash on master
        merge_date: Date merged to master
        version: First version containing the fix
        release: Release branch info dict (if any)
    """
    if not fix_data:
        return None

    # New schema has 'master' key
    if 'master' in fix_data:
        master = fix_data['master']
        return {
            'pr': master.get('pr', 'Unknown PR'),
            'commit': master.get('commit'),
            'merge_date': master.get('merged', 'Unknown'),
            'version': fix_data.get('first_fixed_version'),
            'release': fix_data.get('release'),
        }

    # Old schema has 'pr_number' key
    return {
        'pr': fix_data.get('pr_number', 'Unknown PR'),
        'commit': fix_data.get('commit'),
        'merge_date': fix_data.get('merge_date', 'Unknown'),
        'version': fix_data.get('fixed_in_version'),
        'release': None,
    }


def _parse_exception_body(body: str) -> dict:
    """Parse structured data from exception FormattedBody.

    Returns dict with:
        installation_id: GUID identifying the user's installation
        version: Skyline version string (e.g., "25.1.0.237-519d29babc")
        bitness: "64-bit" or "32-bit"
        email: User's email if provided
        user_comment: User's description of the issue (normalized to single line)
        stack_trace: The actual stack trace after the separator
    """
    result = {
        'installation_id': None,
        'version': None,
        'bitness': None,
        'email': None,
        'user_comment': None,
        'stack_trace': '',
    }

    # Extract Installation ID
    match = INSTALLATION_ID_PATTERN.search(body)
    if match:
        result['installation_id'] = match.group(1)

    # Extract version
    match = VERSION_PATTERN.search(body)
    if match:
        result['version'] = match.group(1)
        result['bitness'] = match.group(2)

    # Extract email if provided (before the stack trace separator)
    header = body.split(STACK_TRACE_SEPARATOR)[0] if STACK_TRACE_SEPARATOR in body else body
    email_match = EMAIL_PATTERN.search(header)
    if email_match:
        result['email'] = email_match.group(0)

    # Extract user comments and normalize to single line
    comment_match = USER_COMMENTS_PATTERN.search(header)
    if comment_match:
        raw_comment = comment_match.group(1).strip()
        if raw_comment:
            # Normalize: collapse whitespace/newlines to single spaces, truncate
            normalized = ' '.join(raw_comment.split())
            if len(normalized) > 300:
                normalized = normalized[:300] + "..."
            result['user_comment'] = normalized

    # Extract stack trace (after the separator line)
    if STACK_TRACE_SEPARATOR in body:
        parts = body.split(STACK_TRACE_SEPARATOR, 1)
        if len(parts) > 1:
            result['stack_trace'] = parts[1].strip()

    return result


def _get_history_path():
    """Get path to exception history file in ai/.tmp/daily/history/."""
    return get_daily_history_dir() / HISTORY_FILE


def _load_exception_history() -> dict:
    """Load existing exception history or create empty structure."""
    import json
    history_path = _get_history_path()

    if history_path.exists():
        try:
            with open(history_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Could not load exception history: {e}")

    # Return empty structure (schema v2: individual reports with row_ids)
    return {
        '_schema_version': HISTORY_SCHEMA_VERSION,
        '_last_updated': None,
        '_retention_months': RETENTION_MONTHS,
        '_release_anchor': MAJOR_RELEASE_VERSION,
        '_release_date': MAJOR_RELEASE_DATE,
        'exceptions': {}
    }


def _extract_fix_annotations(old_history: dict) -> dict:
    """Extract fix annotations from old history format.

    Returns dict mapping fingerprint -> fix info.
    """
    fixes = {}
    for fp, entry in old_history.get('exceptions', {}).items():
        if entry.get('fix'):
            fixes[fp] = entry['fix']
    return fixes


def _extract_issue_annotations(old_history: dict) -> dict:
    """Extract issue annotations from old history.

    Returns dict mapping fingerprint -> issue info.
    """
    issues = {}
    for fp, entry in old_history.get('exceptions', {}).items():
        if entry.get('issue'):
            issues[fp] = entry['issue']
    return issues


def _apply_fix_annotations(history: dict, fixes: dict) -> int:
    """Apply fix annotations to history entries.

    Returns count of fixes applied.
    """
    applied = 0
    for fp, fix_info in fixes.items():
        if fp in history.get('exceptions', {}):
            history['exceptions'][fp]['fix'] = fix_info
            applied += 1
    return applied


def _apply_issue_annotations(history: dict, issues: dict) -> int:
    """Apply issue annotations to history entries.

    Returns count of issues applied.
    """
    applied = 0
    for fp, issue_info in issues.items():
        if fp in history.get('exceptions', {}):
            history['exceptions'][fp]['issue'] = issue_info
            applied += 1
    return applied


def _save_exception_history(history: dict, report_date: str):
    """Save exception history to file."""
    import json
    history['_last_updated'] = report_date
    history_path = _get_history_path()

    with open(history_path, 'w', encoding='utf-8') as f:
        json.dump(history, f, indent=2, ensure_ascii=False)

    logger.info(f"Saved exception history to {history_path}")


def _age_out_old_entries(history: dict, current_date: str) -> int:
    """Remove entries not seen in RETENTION_MONTHS. Returns count removed."""
    current = datetime.strptime(current_date, "%Y-%m-%d")
    # Approximate months as 30 days each
    cutoff = current - timedelta(days=RETENTION_MONTHS * 30)
    cutoff_str = cutoff.strftime("%Y-%m-%d")

    to_remove = []
    for fp, entry in history.get('exceptions', {}).items():
        last_seen = entry.get('last_seen', '')
        if last_seen and last_seen < cutoff_str:
            to_remove.append(fp)

    for fp in to_remove:
        del history['exceptions'][fp]

    if to_remove:
        logger.info(f"Aged out {len(to_remove)} exceptions not seen since {cutoff_str}")

    return len(to_remove)


def _update_history_with_exceptions(history: dict, parsed_exceptions: list, report_date: str):
    """Merge new exceptions into history.

    Schema v2: Stores individual reports with row_id, date, version, installation_id, email.
    Computed fields (total_reports, unique_users, etc.) are derived from reports list.

    Args:
        history: The history dict to update (modified in place)
        parsed_exceptions: List of parsed exception dicts with fingerprint, etc.
        report_date: Current report date YYYY-MM-DD
    """
    exceptions_db = history.setdefault('exceptions', {})

    for exc in parsed_exceptions:
        fp = exc['fingerprint']
        row_id = exc.get('row_id')
        install_id = exc.get('installation_id')
        version = exc.get('version')
        email = exc.get('email')
        sig_frames = exc.get('signature_frames', [])

        if fp not in exceptions_db:
            # New fingerprint - create entry with v2 schema
            exceptions_db[fp] = {
                'fingerprint': fp,
                'signature': ' → '.join(sig_frames) if sig_frames else '(unknown)',
                'exception_type': exc.get('title', '').split('|')[0].strip() if exc.get('title') else None,
                'first_seen': report_date,
                'last_seen': report_date,
                'reports': [],  # v2: list of individual reports
                'fix': None,
            }

        entry = exceptions_db[fp]
        entry['last_seen'] = report_date

        # Add individual report (v2 schema)
        report_entry = {
            'row_id': row_id,
            'date': report_date,
            'version': version,
            'installation_id': install_id,
            'email': email,
        }
        entry['reports'].append(report_entry)


def _get_entry_stats(entry: dict) -> dict:
    """Compute derived statistics from an exception entry's reports list.

    Returns dict with: total_reports, unique_users, emails, versions, replies_count, comments_count
    """
    reports = entry.get('reports', [])

    unique_users = set()
    emails = set()
    versions = set()
    replies_count = 0
    comments_count = 0

    for r in reports:
        if r.get('installation_id'):
            unique_users.add(r['installation_id'])
        if r.get('email'):
            emails.add(r['email'])
        if r.get('version'):
            versions.add(r['version'])
        if r.get('reply'):
            replies_count += 1
        if r.get('comment'):
            comments_count += 1

    return {
        'total_reports': len(reports),
        'unique_users': len(unique_users),
        'emails': sorted(emails),
        'versions': sorted(versions),
        'replies_count': replies_count,
        'comments_count': comments_count,
    }


def _get_priority_score(entry: dict) -> int:
    """Calculate priority score for an exception entry.

    Higher score = higher priority.
    """
    stats = _get_entry_stats(entry)
    score = 0

    # More users = higher priority
    score += stats['unique_users'] * 10

    # Has email = actionable
    if stats['emails']:
        score += 20

    # More reports = more impact
    score += min(stats['total_reports'], 10)  # Cap at 10 to not over-weight

    # Fixed but still appearing = critical (regression check done separately)
    if entry.get('fix'):
        # Will be handled in annotation logic
        pass

    return score


def _get_status_annotations(entry: dict, today_reports: int, today_users: int, report_date: str) -> list:
    """Generate status annotations for an exception entry.

    Returns list of annotation strings with emoji.
    """
    stats = _get_entry_stats(entry)
    annotations = []

    # New today?
    if entry.get('first_seen') == report_date:
        annotations.append("🆕 NEW - First seen today")

    # Has email?
    if stats['emails']:
        annotations.append(f"📧 Has user email ({len(stats['emails'])} contact(s) for follow-up)")

    # Multi-user?
    first_seen = entry.get('first_seen', report_date)
    if stats['unique_users'] > 1 or stats['total_reports'] > today_reports:
        annotations.append(f"👥 {stats['total_reports']} total reports from {stats['unique_users']} users since {first_seen}")

    # Tracked issue?
    issue = entry.get('issue')
    if issue:
        issue_num = issue.get('number', '?')
        issue_url = issue.get('url', f"https://github.com/ProteoWizard/pwiz/issues/{issue_num}")
        annotations.append(f"📋 TRACKED - GitHub [#{issue_num}]({issue_url})")

    # Known fix?
    fix_raw = entry.get('fix')
    fix = _get_fix_summary(fix_raw)
    if fix:
        pr = fix['pr']
        merge_date = fix['merge_date']
        fixed_version = fix['version']

        annotation = f"✅ KNOWN - Fixed in {pr} (merged {merge_date})"
        if fix.get('release'):
            rel = fix['release']
            annotation += f" + {rel.get('pr', '?')} on {rel.get('branch', 'release')}"
        annotations.append(annotation)

        # Check for regression - if reports are from versions after fix
        if fixed_version and stats['versions']:
            fixed_tuple = _parse_version_tuple(fixed_version)
            if fixed_tuple:
                for v in stats['versions']:
                    v_tuple = _parse_version_tuple(v)
                    if v_tuple and v_tuple >= fixed_tuple:
                        annotations.append(f"🔴 REGRESSION? Report from {v} (AFTER fix in {fixed_version})")
                        break

    return annotations


def _needs_attention(entry: dict, today_versions: list) -> tuple:
    """Determine if an exception needs attention or is already handled.

    Returns (needs_attention: bool, reason: str, detail: str).
    """
    fix_raw = entry.get('fix')
    fix = _get_fix_summary(fix_raw)
    issue = entry.get('issue')

    # Check fix status first
    if fix:
        fixed_version = fix.get('version')
        pr = fix.get('pr', 'Unknown PR')
        merge_date = fix.get('merge_date', '')

        if fixed_version:
            # Compare today's report versions against fix version
            fixed_tuple = _parse_version_tuple(fixed_version)
            if fixed_tuple:
                has_post_fix = False
                for v in today_versions:
                    v_tuple = _parse_version_tuple(v)
                    if v_tuple and v_tuple >= fixed_tuple:
                        has_post_fix = True
                        break
                if has_post_fix:
                    return (True, 'regression', f"Reports from versions AFTER fix in {pr}")
            # All versions are pre-fix (or unparseable)
            detail = f"Fixed in {pr}"
            if merge_date:
                detail += f" (merged {merge_date})"
            return (False, 'fixed', detail)
        else:
            # Fix recorded but no version — trust it
            detail = f"Fixed in {pr}"
            if merge_date:
                detail += f" (merged {merge_date})"
            return (False, 'fixed', detail)

    # Check tracked issue
    if issue:
        issue_num = issue.get('number', '?')
        return (False, 'tracked', f"Tracked as GitHub #{issue_num}")

    # No fix, no issue — needs attention
    stats = _get_entry_stats(entry)
    if entry.get('first_seen') == entry.get('last_seen', ''):
        return (True, 'new', 'First seen today')
    if stats['emails']:
        return (True, 'email', f"User email available ({len(stats['emails'])} contact(s))")
    return (True, 'recurring', f"{stats['total_reports']} reports from {stats['unique_users']} users")


def register_tools(mcp):
    """Register exception triage tools."""

    @mcp.tool()
    async def query_exceptions(
        days: int = 7,
        max_rows: int = 50,
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_CONTAINER,
    ) -> str:
        """[D] Browse recent exceptions. Prefer save_exceptions_report. → exceptions.md"""
        try:
            server_context = get_server_context(server, container_path)

            # Calculate date filter
            # Filter for Parent IS NULL to get only original posts, not responses
            since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
            filter_array = [
                QueryFilter("Created", since_date, "dategte"),
                QueryFilter("Parent", "", "isblank"),
            ]

            result = labkey.query.select_rows(
                server_context=server_context,
                schema_name=EXCEPTION_SCHEMA,
                query_name=EXCEPTION_QUERY,
                max_rows=max_rows,
                sort="-Created",
                filter_array=filter_array,
            )

            if result and result.get("rows"):
                rows = result["rows"]
                total = result.get("rowCount", len(rows))
                lines = [
                    f"Found {total} exceptions in the last {days} days (showing {len(rows)}):",
                    "",
                ]
                for i, row in enumerate(rows, 1):
                    title = row.get("Title", "Unknown")
                    created = row.get("Created", "Unknown")
                    row_id = row.get("RowId", "?")
                    status = row.get("Status") or "Unassigned"
                    body = row.get("FormattedBody", "")

                    body_preview = body[:200] + "..." if len(body) > 200 else body

                    lines.append(f"--- Exception #{row_id} ---")
                    lines.append(f"  Title: {title}")
                    lines.append(f"  Created: {created}")
                    lines.append(f"  Status: {status}")
                    lines.append(f"  Preview: {body_preview}")
                    lines.append("")

                return "\n".join(lines)
            else:
                return f"No exceptions found in the last {days} days."

        except Exception as e:
            logger.error(f"Error querying exceptions: {e}", exc_info=True)
            return f"Error querying exceptions: {e}"

    @mcp.tool()
    async def get_exception_details(
        exception_id: int,
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_CONTAINER,
    ) -> str:
        """[D] Full stack trace for one exception. → exceptions.md"""
        try:
            server_context = get_server_context(server, container_path)
            filter_array = [QueryFilter("RowId", str(exception_id), "eq")]

            result = labkey.query.select_rows(
                server_context=server_context,
                schema_name=EXCEPTION_SCHEMA,
                query_name=EXCEPTION_QUERY,
                max_rows=1,
                filter_array=filter_array,
            )

            if result and result.get("rows"):
                row = result["rows"][0]
                lines = [f"Exception #{exception_id} Full Details:", ""]

                lines.append(f"Title: {row.get('Title', 'Unknown')}")
                lines.append(f"Created: {row.get('Created', 'Unknown')}")
                lines.append(f"Modified: {row.get('Modified', 'Unknown')}")
                lines.append(f"Status: {row.get('Status') or 'Unassigned'}")
                lines.append(f"Assigned To: {row.get('AssignedTo') or 'Nobody'}")
                lines.append("")

                lines.append("=== Full Report ===")
                lines.append(row.get("FormattedBody", "No body content"))
                lines.append("")

                return "\n".join(lines)
            return f"No exception found with RowId={exception_id}"

        except Exception as e:
            logger.error(f"Error getting exception details: {e}", exc_info=True)
            return f"Error getting exception details: {e}"

    @mcp.tool()
    async def save_exceptions_report(
        report_date: str,
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_CONTAINER,
    ) -> str:
        """[P] Daily exception report with fingerprints. Saves to ai/.tmp/exceptions-report-YYYYMMDD.md. → exceptions.md"""
        try:
            # Parse report_date for the 24-hour window
            date_obj = datetime.strptime(report_date, "%Y-%m-%d")
            next_day = date_obj + timedelta(days=1)

            # Filter from start of day to start of next day
            start_date = date_obj.strftime("%Y-%m-%d")
            end_date = next_day.strftime("%Y-%m-%d")

            server_context = get_server_context(server, container_path)

            # Query exceptions created on the report date
            # Filter for Parent IS NULL to get only original posts, not responses
            filter_array = [
                QueryFilter("Created", start_date, "dategte"),
                QueryFilter("Created", end_date, "datelt"),
                QueryFilter("Parent", "", "isblank"),
            ]

            result = labkey.query.select_rows(
                server_context=server_context,
                schema_name=EXCEPTION_SCHEMA,
                query_name=EXCEPTION_QUERY,
                max_rows=500,
                sort="-Created",
                filter_array=filter_array,
            )

            if not result or not result.get("rows"):
                return f"No exceptions found for {report_date}."

            rows = result["rows"]

            # Load exception history
            history = _load_exception_history()

            # Parse each exception and compute fingerprints
            parsed_exceptions = []
            for row in rows:
                body = row.get("FormattedBody", "")
                parsed = _parse_exception_body(body)

                # Normalize stack trace and get fingerprint
                norm = normalize_stack_trace(parsed['stack_trace'])

                parsed_exceptions.append({
                    'row_id': row.get("RowId", "?"),
                    'title': row.get("Title", "Unknown"),
                    'created': row.get("Created", "Unknown"),
                    'modified': row.get("Modified", "Unknown"),
                    'status': row.get("Status") or "Unassigned",
                    'assigned_to': row.get("AssignedTo") or "Nobody",
                    'body': body,
                    'installation_id': parsed['installation_id'],
                    'version': parsed['version'],
                    'bitness': parsed['bitness'],
                    'email': parsed['email'],
                    'fingerprint': norm.fingerprint,
                    'signature_frames': norm.signature_frames,
                })

            # Update history with today's exceptions
            _update_history_with_exceptions(history, parsed_exceptions, report_date)

            # Age out old entries
            aged_out = _age_out_old_entries(history, report_date)

            # Group by fingerprint
            fingerprint_groups = {}
            for exc in parsed_exceptions:
                fp = exc['fingerprint']
                if fp not in fingerprint_groups:
                    fingerprint_groups[fp] = []
                fingerprint_groups[fp].append(exc)

            # Build the report
            lines = [
                f"# Exception Report: {report_date}",
                "",
                f"**Total Reports**: {len(rows)}",
                f"**Unique Bugs (by fingerprint)**: {len(fingerprint_groups)}",
                "",
            ]

            # Executive summary - unique bugs
            lines.append("## Executive Summary")
            lines.append("")
            lines.append("| Fingerprint | Reports | Users | Versions | Signature |")
            lines.append("|-------------|---------|-------|----------|-----------|")

            for fp, group in sorted(fingerprint_groups.items(),
                                    key=lambda x: len(x[1]), reverse=True):
                reports = len(group)
                unique_users = len(set(e['installation_id'] for e in group
                                       if e['installation_id']))
                versions = sorted(set(e['version'] for e in group if e['version']))
                versions_str = ', '.join(versions[:3])
                if len(versions) > 3:
                    versions_str += f" (+{len(versions) - 3})"

                # Signature (top frame)
                sig = group[0]['signature_frames']
                sig_str = sig[0] if sig else "(no frames)"

                lines.append(f"| `{fp}` | {reports} | {unique_users} | {versions_str} | {sig_str} |")

            lines.append("")
            lines.append("---")
            lines.append("")

            # Classify each fingerprint as needs-attention or already-handled
            def get_sort_key(item):
                fp, group = item
                entry = history.get('exceptions', {}).get(fp, {})
                return (-_get_priority_score(entry), -len(group))

            attention_items = []  # (fp, group, annotations, attention_info)
            handled_items = []    # (fp, group, annotations, attention_info)

            for fp, group in sorted(fingerprint_groups.items(), key=get_sort_key):
                reports = len(group)
                unique_users = len(set(e['installation_id'] for e in group
                                       if e['installation_id']))
                history_entry = history.get('exceptions', {}).get(fp, {})
                annotations = _get_status_annotations(history_entry, reports, unique_users, report_date)
                today_versions = [e['version'] for e in group if e['version']]
                attention_info = _needs_attention(history_entry, today_versions)

                if attention_info[0]:
                    attention_items.append((fp, group, annotations, attention_info))
                else:
                    handled_items.append((fp, group, annotations, attention_info))

            # Helper to render a full bug detail section
            def _render_bug_detail(lines, fp, group, annotations):
                reports = len(group)
                unique_users = len(set(e['installation_id'] for e in group
                                       if e['installation_id']))
                sig = group[0]['signature_frames']
                sig_str = ' → '.join(sig) if sig else "(no signature frames)"

                lines.append(f"### Bug `{fp}` ({reports} reports, {unique_users} users)")
                lines.append("")

                if annotations:
                    for ann in annotations:
                        lines.append(ann)
                    lines.append("")

                lines.append(f"**Signature**: {sig_str}")
                lines.append("")

                versions = sorted(set(e['version'] for e in group if e['version']))
                if versions:
                    lines.append(f"**Versions**: {', '.join(versions)}")
                    lines.append("")

                lines.append("**Reports:**")
                lines.append("")

                for exc in group:
                    row_id = exc['row_id']
                    title = exc['title']
                    created = exc['created']
                    install_id = exc['installation_id'] or 'Unknown'
                    version = exc['version'] or 'Unknown'
                    email = exc.get('email')

                    if isinstance(created, str) and "T" in created:
                        time_str = created.split("T")[1][:8]
                    else:
                        time_str = str(created)

                    url = _get_exception_url(row_id)
                    lines.append(f"- [**#{row_id}**]({url}) at {time_str}")
                    user_info = f"User: `{install_id[:8]}...`"
                    if email:
                        user_info += f" ({email})"
                    lines.append(f"  - {user_info} | Version: {version}")
                    lines.append(f"  - Title: {title[:60]}{'...' if len(title) > 60 else ''}")
                    lines.append("")

                lines.append("<details>")
                lines.append("<summary>Full stack trace (reference)</summary>")
                lines.append("")
                lines.append("```")
                lines.append(group[0]['body'])
                lines.append("```")
                lines.append("</details>")
                lines.append("")
                lines.append("---")
                lines.append("")

            # Needs Attention section
            lines.append(f"## Needs Attention ({len(attention_items)} bugs)")
            lines.append("")
            if attention_items:
                for fp, group, annotations, attention_info in attention_items:
                    _render_bug_detail(lines, fp, group, annotations)
            else:
                lines.append("No exceptions need attention today.")
                lines.append("")

            # Already Handled section
            lines.append(f"## Already Handled ({len(handled_items)} bugs)")
            lines.append("")
            if handled_items:
                for fp, group, annotations, attention_info in handled_items:
                    _, reason, detail = attention_info
                    reports = len(group)
                    sig = group[0]['signature_frames']
                    sig_str = sig[0] if sig else "(no frames)"
                    versions = sorted(set(e['version'] for e in group if e['version']))
                    versions_str = ', '.join(versions[:3])

                    row_id = group[0]['row_id']
                    url = _get_exception_url(row_id)
                    lines.append(f"- **`{fp}`** ({reports} reports) — {detail} | {sig_str} | Versions: {versions_str} | [#{row_id}]({url})")
            else:
                lines.append("No already-handled exceptions today.")
            lines.append("")

            # Save to file
            content = "\n".join(lines)
            date_str = date_obj.strftime("%Y%m%d")
            file_path = get_tmp_dir() / f"exceptions-report-{date_str}.md"
            file_path.write_text(content, encoding="utf-8")

            # Save updated history
            _save_exception_history(history, report_date)
            history_path = _get_history_path()

            # Return summary
            summary_lines = [
                f"Saved exceptions report to {file_path}",
                f"Updated exception history: {history_path}",
                "",
                f"**{report_date}**: {len(rows)} reports → {len(fingerprint_groups)} unique bugs",
                f"  - **{len(attention_items)} need attention**, {len(handled_items)} already handled",
                "",
            ]

            # Count history stats
            total_tracked = len(history.get('exceptions', {}))
            if aged_out > 0:
                summary_lines.append(f"📊 History: {total_tracked} bugs tracked ({aged_out} aged out)")
            else:
                summary_lines.append(f"📊 History: {total_tracked} bugs tracked")
            summary_lines.append("")

            # Highlight items needing attention
            if attention_items:
                summary_lines.append("**Needs attention:**")
                for fp, group, annotations, attention_info in attention_items[:5]:
                    _, reason, detail = attention_info
                    sig = group[0]['signature_frames']
                    sig_str = sig[0] if sig else fp
                    if reason == 'regression':
                        summary_lines.append(f"- 🔴 `{fp}`: REGRESSION - {sig_str}")
                    elif reason == 'new':
                        summary_lines.append(f"- 🆕 `{fp}`: {sig_str}")
                    elif reason == 'email':
                        summary_lines.append(f"- 📧 `{fp}`: {sig_str} - {detail}")
                    else:
                        summary_lines.append(f"- `{fp}`: {sig_str} - {detail}")

            return "\n".join(summary_lines)

        except Exception as e:
            logger.error(f"Error generating exceptions report: {e}", exc_info=True)
            return f"Error generating exceptions report: {e}"

    def _record_exception_tracking(fingerprint: str, property_name: str, tracking_data: dict):
        """Common logic for recording issue or fix info for an exception fingerprint.

        Returns:
            (entry, stats, None) on success
            (None, None, error_message) on failure
        """
        history = _load_exception_history()
        exceptions_db = history.get('exceptions', {})

        if fingerprint not in exceptions_db:
            return None, None, f"Fingerprint `{fingerprint}` not found in history. Run save_exceptions_report first to populate history."

        entry = exceptions_db[fingerprint]
        entry[property_name] = tracking_data

        _save_exception_history(history, datetime.now().strftime("%Y-%m-%d"))

        stats = _get_entry_stats(entry)
        return entry, stats, None

    @mcp.tool()
    async def record_exception_issue(
        fingerprint: str,
        issue_number: str,
        notes: str = None,
    ) -> str:
        """Record that a GitHub issue has been created for an exception fingerprint. → exceptions.md"""
        try:
            # Validate issue number
            issue_num = issue_number.lstrip('#')
            if not issue_num.isdigit():
                return f"Invalid issue number: {issue_number}. Expected a number like '3880' or '#3880'."

            # Build issue data
            issue_data = {
                'number': int(issue_num),
                'recorded_date': datetime.now().strftime("%Y-%m-%d"),
                'url': f"https://github.com/ProteoWizard/pwiz/issues/{issue_num}",
            }
            if notes:
                issue_data['notes'] = notes

            # Record it
            entry, stats, error = _record_exception_tracking(fingerprint, 'issue', issue_data)
            if error:
                return error

            # Format response
            sig = entry.get('signature', fingerprint)
            return "\n".join([
                f"Recorded GitHub issue for `{fingerprint}`:",
                f"- Signature: {sig}",
                f"- Issue: #{issue_num}",
                f"- URL: {issue_data['url']}",
                f"- Reports: {stats['total_reports']} from {stats['unique_users']} users",
                "",
                "Future reports will show this as a tracked issue.",
            ])

        except Exception as e:
            logger.error(f"Error recording issue: {e}", exc_info=True)
            return f"Error recording issue: {e}"

    @mcp.tool()
    async def record_exception_fix(
        fingerprint: str,
        pr_number: str,
        fixed_in_version: str = None,
        merge_date: str = None,
        commit: str = None,
        release_branch: str = None,
        release_pr: str = None,
        release_commit: str = None,
        release_merge_date: str = None,
        notes: str = None,
    ) -> str:
        """Record that an exception fingerprint has been fixed. → exceptions.md"""
        try:
            # Normalize PR number formats
            def normalize_pr(pr):
                if pr and not pr.upper().startswith('PR'):
                    return f"PR#{pr}"
                return pr

            pr_number = normalize_pr(pr_number)
            release_pr = normalize_pr(release_pr)

            # Build fix data
            fix_data = {
                'recorded_date': datetime.now().strftime("%Y-%m-%d"),
                'first_fixed_version': fixed_in_version,
            }
            if pr_number:
                fix_data['master'] = {
                    'pr': pr_number,
                    'commit': commit,
                    'merged': merge_date or datetime.now().strftime("%Y-%m-%d"),
                }
            if release_branch or release_pr:
                fix_data['release'] = {
                    'branch': release_branch,
                    'pr': release_pr,
                    'commit': release_commit,
                    'merged': release_merge_date,
                }
            if notes:
                fix_data['notes'] = notes

            # Record it
            entry, stats, error = _record_exception_tracking(fingerprint, 'fix', fix_data)
            if error:
                return error

            # Format response
            sig = entry.get('signature', fingerprint)
            lines = [
                f"Recorded fix for `{fingerprint}`:",
                f"- Signature: {sig}",
            ]
            if 'master' in fix_data:
                lines.append(f"- Master: {fix_data['master']['pr']}")
                if fix_data['master'].get('commit'):
                    lines.append(f"  - Commit: {fix_data['master']['commit'][:12]}...")
                lines.append(f"  - Merged: {fix_data['master']['merged']}")
            if 'release' in fix_data:
                branch = fix_data['release'].get('branch', 'unknown')
                lines.append(f"- Release ({branch}): {fix_data['release'].get('pr', 'N/A')}")
                if fix_data['release'].get('commit'):
                    lines.append(f"  - Commit: {fix_data['release']['commit'][:12]}...")
                if fix_data['release'].get('merged'):
                    lines.append(f"  - Merged: {fix_data['release']['merged']}")
            lines.extend([
                f"- First fixed version: {fixed_in_version or 'Not yet tagged'}",
                "",
                "Future reports will show this as a known fix.",
            ])

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error recording fix: {e}", exc_info=True)
            return f"Error recording fix: {e}"

    @mcp.tool()
    async def query_exception_history(
        top_n: int = 10,
        min_users: int = 1,
        show_fixed: bool = False,
    ) -> str:
        """Query exception history for high-priority bugs. → exceptions.md"""
        try:
            history = _load_exception_history()
            exceptions_db = history.get('exceptions', {})

            if not exceptions_db:
                return "No exceptions in history. Run backfill_exception_history to populate."

            schema_version = history.get('_schema_version', 1)

            # Filter and score
            scored = []
            for fp, entry in exceptions_db.items():
                # Compute stats from reports list (v2) or use legacy fields (v1)
                stats = _get_entry_stats(entry)

                # Skip if below user threshold
                if stats['unique_users'] < min_users:
                    continue

                # Skip fixed unless requested
                if entry.get('fix') and not show_fixed:
                    continue

                score = _get_priority_score(entry)
                scored.append((score, fp, entry, stats))

            # Sort by score descending
            scored.sort(key=lambda x: -x[0])

            if not scored:
                return f"No exceptions match criteria (min_users={min_users}, show_fixed={show_fixed})"

            lines = [
                f"# Top {min(top_n, len(scored))} Priority Exceptions",
                "",
                f"History contains {len(exceptions_db)} tracked bugs (schema v{schema_version}).",
                f"Last updated: {history.get('_last_updated', 'Unknown')}",
                "",
            ]

            for i, (score, fp, entry, stats) in enumerate(scored[:top_n], 1):
                sig = entry.get('signature', '(unknown)')
                first_seen = entry.get('first_seen', '?')
                last_seen = entry.get('last_seen', '?')
                fix = _get_fix_summary(entry.get('fix'))

                lines.append(f"## {i}. `{fp}` (score: {score})")
                lines.append("")
                lines.append(f"**Signature**: {sig}")
                lines.append(f"**Users**: {stats['unique_users']} | **Reports**: {stats['total_reports']}")
                lines.append(f"**First seen**: {first_seen} | **Last seen**: {last_seen}")

                if stats['emails']:
                    lines.append(f"📧 **Contact emails**: {', '.join(stats['emails'])}")
                    # Show URLs for reports with emails (v2 schema)
                    reports = entry.get('reports', [])
                    for r in reports:
                        if r.get('email') and r.get('row_id'):
                            url = _get_exception_url(r['row_id'])
                            reply_marker = " 💬" if r.get('reply') else ""
                            lines.append(f"   - {r['email']} ({r.get('date', '?')}): {url}{reply_marker}")
                            # Show user comment if present
                            if r.get('comment'):
                                lines.append(f"     \"{r['comment']}\"")
                            # Show reply if present
                            if r.get('reply'):
                                reply = r['reply']
                                lines.append(f"     ↳ Reply ({reply.get('date', '?')}): \"{reply.get('text', '')}\"")

                # Show reply summary
                if stats['replies_count'] > 0:
                    lines.append(f"💬 **Has replies**: {stats['replies_count']} post(s) with responses")

                if fix:
                    fix_text = f"✅ **Fixed in**: {fix['pr']} ({fix['merge_date']})"
                    if fix.get('release'):
                        rel = fix['release']
                        fix_text += f" + {rel.get('pr', '?')} on {rel.get('branch', 'release')}"
                    lines.append(fix_text)

                # Show tracked issue
                issue = entry.get('issue')
                if issue:
                    issue_num = issue.get('number', '?')
                    issue_url = issue.get('url', f"https://github.com/ProteoWizard/pwiz/issues/{issue_num}")
                    lines.append(f"📋 **Tracked in**: [#{issue_num}]({issue_url})")

                if stats['versions']:
                    lines.append(f"**Versions**: {', '.join(stats['versions'][:5])}")

                # Show latest report URL (v2 schema)
                reports = entry.get('reports', [])
                if reports and reports[-1].get('row_id'):
                    latest = reports[-1]
                    url = _get_exception_url(latest['row_id'])
                    lines.append(f"**Latest report**: {url}")

                lines.append("")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error querying history: {e}", exc_info=True)
            return f"Error querying history: {e}"

    @mcp.tool()
    async def backfill_exception_history(
        since_date: str = MAJOR_RELEASE_DATE,
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_CONTAINER,
    ) -> str:
        """Backfill exception history from skyline.ms. → exceptions.md"""
        try:
            # Load existing history to preserve fix and issue annotations
            old_history = _load_exception_history()
            preserved_fixes = _extract_fix_annotations(old_history)
            preserved_issues = _extract_issue_annotations(old_history)
            if preserved_fixes:
                logger.info(f"Preserving {len(preserved_fixes)} fix annotations from existing history")
            if preserved_issues:
                logger.info(f"Preserving {len(preserved_issues)} issue annotations from existing history")

            server_context = get_server_context(server, container_path)

            # Query all exceptions since the anchor date
            # Filter for Parent IS NULL to get only original posts, not responses
            filter_array = [
                QueryFilter("Created", since_date, "dategte"),
                QueryFilter("Parent", "", "isblank"),
            ]

            result = labkey.query.select_rows(
                server_context=server_context,
                schema_name=EXCEPTION_SCHEMA,
                query_name=EXCEPTION_QUERY,
                max_rows=10000,  # Should be plenty
                sort="Created",  # Oldest first for proper first_seen tracking
                filter_array=filter_array,
                columns="RowId,EntityId,Title,Created,Modified,Status,AssignedTo,FormattedBody,Parent",
            )

            if not result or not result.get("rows"):
                return f"No exceptions found since {since_date}."

            rows = result["rows"]
            logger.info(f"Backfilling {len(rows)} exceptions since {since_date}")

            # Query all replies (Parent IS NOT NULL) to match with parent posts
            reply_filter = [
                QueryFilter("Created", since_date, "dategte"),
                QueryFilter("Parent", "", "isnonblank"),
            ]

            reply_result = labkey.query.select_rows(
                server_context=server_context,
                schema_name=EXCEPTION_SCHEMA,
                query_name=EXCEPTION_QUERY,
                max_rows=10000,
                sort="Created",
                filter_array=reply_filter,
            )

            # Build lookup: parent RowId -> reply info
            replies_by_parent = {}
            if reply_result and reply_result.get("rows"):
                for reply in reply_result["rows"]:
                    # Parent might be a dict with value or just an int
                    parent_raw = reply.get("Parent")
                    if isinstance(parent_raw, dict):
                        parent_id = parent_raw.get("value") or parent_raw.get("RowId")
                    else:
                        parent_id = parent_raw
                    if parent_id:
                        # Extract just the text content, skip stack traces
                        body = reply.get("FormattedBody", "")
                        # Replies typically don't have stack traces, just text
                        reply_text = body.strip()
                        # Truncate long replies for storage
                        if len(reply_text) > 500:
                            reply_text = reply_text[:500] + "..."

                        created = reply.get("Created", "")
                        if isinstance(created, str) and "T" in created:
                            reply_date = created.split("T")[0]
                        else:
                            reply_date = str(created)[:10]

                        # CreatedBy might be a dict with displayValue or just an int
                        created_by = reply.get("CreatedBy")
                        if isinstance(created_by, dict):
                            author = created_by.get("displayValue", "Unknown")
                        else:
                            author = str(created_by) if created_by else "Unknown"

                        replies_by_parent[parent_id] = {
                            'text': reply_text,
                            'date': reply_date,
                            'author': author,
                        }

                logger.info(f"Found {len(replies_by_parent)} replies to exception posts")

            # Start fresh history with v2 schema
            history = {
                '_schema_version': HISTORY_SCHEMA_VERSION,
                '_last_updated': None,
                '_retention_months': RETENTION_MONTHS,
                '_release_anchor': MAJOR_RELEASE_VERSION,
                '_release_date': MAJOR_RELEASE_DATE,
                '_backfill_date': datetime.now().strftime("%Y-%m-%d"),
                '_backfill_count': len(rows),
                'exceptions': {}
            }

            exceptions_db = history['exceptions']
            unparseable_rows = []  # Track RowIds we can't parse

            # Process each exception
            for row in rows:
                row_id = row.get("RowId")
                entity_id = row.get("EntityId")  # Used for reply matching
                body = row.get("FormattedBody", "")
                parsed = _parse_exception_body(body)
                created = row.get("Created", "")

                # Extract date from Created timestamp
                if isinstance(created, str) and "T" in created:
                    report_date = created.split("T")[0]
                elif isinstance(created, str) and " " in created:
                    report_date = created.split(" ")[0]
                else:
                    report_date = str(created)[:10]

                # Normalize stack trace and get fingerprint
                norm = normalize_stack_trace(parsed['stack_trace'])
                fp = norm.fingerprint
                sig_frames = norm.signature_frames

                # Track unparseable rows (empty fingerprint = no frames parsed)
                if norm.frame_count == 0:
                    if row_id:
                        unparseable_rows.append(row_id)

                install_id = parsed.get('installation_id')
                version = parsed.get('version')
                email = parsed.get('email')
                user_comment = parsed.get('user_comment')

                if fp not in exceptions_db:
                    # New fingerprint - create entry with v2 schema
                    exceptions_db[fp] = {
                        'fingerprint': fp,
                        'signature': ' → '.join(sig_frames) if sig_frames else '(unknown)',
                        'exception_type': row.get('Title', '').split('|')[0].strip() if row.get('Title') else None,
                        'first_seen': report_date,
                        'last_seen': report_date,
                        'reports': [],  # v2: list of individual reports
                        'fix': None,
                    }

                entry = exceptions_db[fp]

                # Update last_seen (rows are sorted by Created ascending)
                entry['last_seen'] = report_date

                # Add individual report (v2 schema)
                report_entry = {
                    'row_id': row_id,
                    'date': report_date,
                    'version': version,
                    'installation_id': install_id,
                    'email': email,
                }

                # Add user comment if present
                if user_comment:
                    report_entry['comment'] = user_comment

                # Add reply if one exists for this post (matched by EntityId)
                if entity_id and entity_id in replies_by_parent:
                    report_entry['reply'] = replies_by_parent[entity_id]

                entry['reports'].append(report_entry)

            # Re-apply preserved fix and issue annotations
            fixes_applied = _apply_fix_annotations(history, preserved_fixes)
            issues_applied = _apply_issue_annotations(history, preserved_issues)

            # Save unparseable RowIds in history for investigation
            if unparseable_rows:
                history['_unparseable_rowids'] = unparseable_rows

            # Save the history
            today = datetime.now().strftime("%Y-%m-%d")
            _save_exception_history(history, today)

            # Generate summary using stats helper
            total_fingerprints = len(exceptions_db)
            multi_user = sum(1 for e in exceptions_db.values()
                             if _get_entry_stats(e)['unique_users'] > 1)
            with_email = sum(1 for e in exceptions_db.values()
                             if _get_entry_stats(e)['emails'])
            with_replies = sum(1 for e in exceptions_db.values()
                               if _get_entry_stats(e)['replies_count'] > 0)
            total_replies = len(replies_by_parent)
            with_comments = sum(1 for e in exceptions_db.values()
                                if _get_entry_stats(e)['comments_count'] > 0)

            # Find top issues by report count
            top_issues = sorted(
                exceptions_db.values(),
                key=lambda e: _get_entry_stats(e)['total_reports'],
                reverse=True
            )[:5]

            lines = [
                f"# Exception History Backfill Complete",
                "",
                f"**Schema**: v{HISTORY_SCHEMA_VERSION} (individual reports with row_ids)",
                f"**Source**: {len(rows)} exceptions since {since_date}",
                f"**Replies found**: {total_replies}",
                f"**Unique bugs**: {total_fingerprints} fingerprints",
                f"**Multi-user bugs**: {multi_user}",
                f"**Bugs with contact email**: {with_email}",
                f"**Bugs with user comments**: {with_comments}",
                f"**Bugs with replies**: {with_replies}",
            ]

            if fixes_applied > 0:
                lines.append(f"**Fix annotations preserved**: {fixes_applied}")
            if issues_applied > 0:
                lines.append(f"**Issue annotations preserved**: {issues_applied}")

            lines.extend([
                "",
                f"Saved to: {_get_history_path()}",
                "",
                "## Top 5 Most Reported Issues",
                "",
            ])

            for i, entry in enumerate(top_issues, 1):
                fp = entry.get('fingerprint', '?')
                sig = entry.get('signature', '(unknown)')
                stats = _get_entry_stats(entry)
                first = entry.get('first_seen', '?')
                last = entry.get('last_seen', '?')

                lines.append(f"{i}. `{fp}` - {stats['total_reports']} reports, {stats['unique_users']} users")
                lines.append(f"   {sig[:60]}{'...' if len(sig) > 60 else ''}")
                lines.append(f"   First: {first} | Last: {last}")

                # Show sample row_id for direct linking
                if entry.get('reports'):
                    sample_report = entry['reports'][-1]  # Most recent
                    url = _get_exception_url(sample_report['row_id'])
                    lines.append(f"   Latest: {url}")

                lines.append("")

            # Add unparseable RowIds section if any
            if unparseable_rows:
                lines.append("## Unparseable Exceptions")
                lines.append(f"")
                lines.append(f"{len(unparseable_rows)} rows could not be parsed. RowIds:")
                lines.append(f"")
                # Show up to 20, or all if fewer
                display_rows = unparseable_rows[:20]
                lines.append(", ".join(str(r) for r in display_rows))
                if len(unparseable_rows) > 20:
                    lines.append(f"... and {len(unparseable_rows) - 20} more (see _unparseable_rowids in history file)")
                lines.append("")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error backfilling history: {e}", exc_info=True)
            return f"Error backfilling history: {e}"
