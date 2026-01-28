"""Nightly test history tools for LabKey MCP server.

This module provides historical tracking for nightly test failures, leaks, and hangs,
enabling pattern detection like "this test has failed 47 times (12% rate) since June".

Modeled after exceptions.py - stores fingerprinted failures with fix tracking.
"""

import logging
from datetime import datetime, timedelta

import labkey
from labkey.query import QueryFilter

from .common import (
    get_server_context,
    get_tmp_dir,
    DEFAULT_SERVER,
)
from .stacktrace import normalize_stack_trace

logger = logging.getLogger("labkey_mcp")

# History settings
HISTORY_FILE = 'nightly-history.json'
HISTORY_SCHEMA_VERSION = 1
BACKFILL_DEFAULT_DAYS = 365  # One year of history

# Test folders to query during backfill
TEST_FOLDERS = [
    "/home/development/Nightly x64",
    "/home/development/Release Branch",
    "/home/development/Performance Tests",
    "/home/development/Release Branch Perf",
    "/home/development/Integration",
    "/home/development/Integration with Perf",
]

# URL templates
FAILURE_URL_TEMPLATE = "https://skyline.ms{container}/testresults-showFailures.view?end={date}&failedTest={test_name}"


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


def _get_history_path():
    """Get path to nightly history file in ai/.tmp/history/."""
    history_dir = get_tmp_dir() / 'history'
    history_dir.mkdir(parents=True, exist_ok=True)
    return history_dir / HISTORY_FILE


def _load_nightly_history() -> dict:
    """Load existing nightly history or create empty structure."""
    import json
    history_path = _get_history_path()

    if history_path.exists():
        try:
            with open(history_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Could not load nightly history: {e}")

    # Return empty structure
    return {
        '_schema_version': HISTORY_SCHEMA_VERSION,
        '_last_updated': None,
        '_backfill_start': None,
        '_backfill_date': None,
        'test_failures': {},
        'test_leaks': {},
        'test_hangs': {},
        'run_counts': {},
        'machine_health': {},
    }


def _save_nightly_history(history: dict, report_date: str):
    """Save nightly history to file."""
    import json
    history['_last_updated'] = report_date
    history_path = _get_history_path()

    with open(history_path, 'w', encoding='utf-8') as f:
        json.dump(history, f, indent=2, ensure_ascii=False)

    logger.info(f"Saved nightly history to {history_path}")


def _extract_fix_annotations(history: dict, section: str) -> dict:
    """Extract fix annotations from a history section.

    Returns dict mapping key -> fix info.
    """
    fixes = {}
    for key, entry in history.get(section, {}).items():
        if isinstance(entry, dict):
            # For failures, check by_fingerprint
            if 'by_fingerprint' in entry:
                for fp, fp_entry in entry['by_fingerprint'].items():
                    if fp_entry.get('fix'):
                        fixes[(key, fp)] = fp_entry['fix']
            # For leaks/hangs, check directly
            elif entry.get('fix'):
                fixes[key] = entry['fix']
    return fixes


def _get_failure_url(container: str, test_name: str, date: str) -> str:
    """Generate URL to view failure details on skyline.ms."""
    # Format date as MM/DD/YYYY for URL
    try:
        dt = datetime.strptime(date, "%Y-%m-%d")
        date_str = dt.strftime("%m/%d/%Y")
    except ValueError:
        date_str = date

    # URL encode the container path
    container_encoded = container.replace(" ", "%20")

    return FAILURE_URL_TEMPLATE.format(
        container=container_encoded,
        date=date_str.replace("/", "%2F"),
        test_name=test_name
    )


def register_tools(mcp):
    """Register nightly history tools."""

    @mcp.tool()
    async def backfill_nightly_history(
        since_date: str = None,
        server: str = DEFAULT_SERVER,
    ) -> str:
        """Backfill nightly test history from skyline.ms. → nightly-tests.md"""
        try:
            # Default to 1 year ago
            if not since_date:
                since_dt = datetime.now() - timedelta(days=BACKFILL_DEFAULT_DAYS)
                since_date = since_dt.strftime("%Y-%m-%d")

            # Load existing history to preserve fix annotations
            old_history = _load_nightly_history()
            preserved_failure_fixes = _extract_fix_annotations(old_history, 'test_failures')
            preserved_leak_fixes = _extract_fix_annotations(old_history, 'test_leaks')
            preserved_hang_fixes = _extract_fix_annotations(old_history, 'test_hangs')

            total_preserved = len(preserved_failure_fixes) + len(preserved_leak_fixes) + len(preserved_hang_fixes)
            if total_preserved > 0:
                logger.info(f"Preserving {total_preserved} fix annotations from existing history")

            # Initialize fresh history
            history = {
                '_schema_version': HISTORY_SCHEMA_VERSION,
                '_last_updated': None,
                '_backfill_start': since_date,
                '_backfill_date': datetime.now().strftime("%Y-%m-%d"),
                'test_failures': {},
                'test_leaks': {},
                'test_hangs': {},
                'run_counts': {},
                'machine_health': {},
            }

            # Convert date to timestamp for query
            start_ts = f"{since_date} 00:00:00"
            end_ts = datetime.now().strftime("%Y-%m-%d 23:59:59")

            total_failures = 0
            total_leaks = 0
            total_hangs = 0
            folders_queried = 0

            # Query each test folder
            for container_path in TEST_FOLDERS:
                try:
                    server_context = get_server_context(server, container_path)
                    folder_name = container_path.split("/")[-1]

                    # Query failures
                    failures_result = labkey.query.select_rows(
                        server_context=server_context,
                        schema_name="testresults",
                        query_name="failures_history",
                        max_rows=100000,
                        parameters={
                            "StartDate": start_ts,
                            "EndDate": end_ts,
                        },
                    )

                    if failures_result and failures_result.get("rows"):
                        rows = failures_result["rows"]
                        total_failures += len(rows)
                        _process_failure_rows(history, rows, folder_name)
                        logger.info(f"{folder_name}: {len(rows)} failures")

                    # Query leaks
                    leaks_result = labkey.query.select_rows(
                        server_context=server_context,
                        schema_name="testresults",
                        query_name="leaks_history",
                        max_rows=100000,
                        parameters={
                            "StartDate": start_ts,
                            "EndDate": end_ts,
                        },
                    )

                    if leaks_result and leaks_result.get("rows"):
                        rows = leaks_result["rows"]
                        total_leaks += len(rows)
                        _process_leak_rows(history, rows, folder_name)
                        logger.info(f"{folder_name}: {len(rows)} leaks")

                    # Query hangs
                    hangs_result = labkey.query.select_rows(
                        server_context=server_context,
                        schema_name="testresults",
                        query_name="hangs_history",
                        max_rows=100000,
                        parameters={
                            "StartDate": start_ts,
                            "EndDate": end_ts,
                        },
                    )

                    if hangs_result and hangs_result.get("rows"):
                        rows = hangs_result["rows"]
                        total_hangs += len(rows)
                        _process_hang_rows(history, rows, folder_name)
                        logger.info(f"{folder_name}: {len(rows)} hangs")

                    folders_queried += 1

                except Exception as e:
                    logger.warning(f"Error querying {container_path}: {e}")
                    continue

            # Re-apply preserved fix annotations
            # TODO: Implement fix reapplication

            # Save history
            today = datetime.now().strftime("%Y-%m-%d")
            _save_nightly_history(history, today)

            # Generate summary
            unique_failure_tests = len(history['test_failures'])
            unique_leak_tests = len(history['test_leaks'])
            unique_hang_tests = len(history['test_hangs'])

            # Count unique fingerprints for failures
            total_fingerprints = sum(
                len(entry.get('by_fingerprint', {}))
                for entry in history['test_failures'].values()
            )

            lines = [
                "# Nightly Test History Backfill Complete",
                "",
                f"**Schema**: v{HISTORY_SCHEMA_VERSION}",
                f"**Date range**: {since_date} to {today}",
                f"**Folders queried**: {folders_queried}",
                "",
                "## Summary",
                "",
                f"| Category | Records | Unique Tests | Fingerprints |",
                f"|----------|---------|--------------|--------------|",
                f"| Failures | {total_failures} | {unique_failure_tests} | {total_fingerprints} |",
                f"| Leaks | {total_leaks} | {unique_leak_tests} | - |",
                f"| Hangs | {total_hangs} | {unique_hang_tests} | - |",
                "",
                f"Saved to: {_get_history_path()}",
            ]

            # Show top failing tests
            if history['test_failures']:
                lines.extend([
                    "",
                    "## Top 5 Failing Tests (by total failures)",
                    "",
                ])
                sorted_tests = sorted(
                    history['test_failures'].items(),
                    key=lambda x: sum(len(fp.get('reports', [])) for fp in x[1].get('by_fingerprint', {}).values()),
                    reverse=True
                )[:5]
                for test_name, entry in sorted_tests:
                    total = sum(len(fp.get('reports', [])) for fp in entry.get('by_fingerprint', {}).values())
                    fp_count = len(entry.get('by_fingerprint', {}))
                    lines.append(f"- **{test_name}**: {total} failures, {fp_count} fingerprints")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error backfilling nightly history: {e}", exc_info=True)
            return f"Error backfilling nightly history: {e}"

    @mcp.tool()
    async def query_test_history(
        test_name: str,
    ) -> str:
        """Look up historical data for a specific test. → nightly-tests.md"""
        try:
            history = _load_nightly_history()

            lines = [f"# History for {test_name}", ""]

            # Check failures
            if test_name in history.get('test_failures', {}):
                entry = history['test_failures'][test_name]
                lines.append("## Failures")
                lines.append("")

                for fp, fp_entry in entry.get('by_fingerprint', {}).items():
                    reports = fp_entry.get('reports', [])
                    machines = set(r.get('computer') for r in reports if r.get('computer'))
                    first_seen = fp_entry.get('first_seen', '?')
                    last_seen = fp_entry.get('last_seen', '?')
                    sig = fp_entry.get('signature', '(unknown)')
                    exc_type = fp_entry.get('exception_type', '')
                    fix = _get_fix_summary(fp_entry.get('fix'))

                    lines.append(f"### Fingerprint `{fp}`")
                    lines.append("")
                    lines.append(f"**Signature**: {sig}")
                    if exc_type:
                        lines.append(f"**Exception**: {exc_type}")
                    lines.append(f"**Total failures**: {len(reports)}")
                    lines.append(f"**Machines**: {', '.join(sorted(machines))}")
                    lines.append(f"**First seen**: {first_seen} | **Last seen**: {last_seen}")

                    if fix:
                        fix_text = f"✅ **Fixed in**: {fix['pr']} ({fix['merge_date']})"
                        if fix.get('release'):
                            rel = fix['release']
                            fix_text += f" + {rel.get('pr', '?')} on {rel.get('branch', 'release')}"
                        lines.append(fix_text)

                    lines.append("")

            else:
                lines.append("No failure history found for this test.")
                lines.append("")

            # Check leaks
            if test_name in history.get('test_leaks', {}):
                entry = history['test_leaks'][test_name]
                reports = entry.get('reports', [])

                lines.append("## Leaks")
                lines.append("")
                lines.append(f"**Total leak reports**: {len(reports)}")

                # Summarize by type
                memory_leaks = [r for r in reports if r.get('leak_type') == 'memory']
                handle_leaks = [r for r in reports if r.get('leak_type') == 'handle']

                if memory_leaks:
                    machines = set(r.get('computer') for r in memory_leaks)
                    lines.append(f"**Memory leaks**: {len(memory_leaks)} on {', '.join(sorted(machines))}")
                if handle_leaks:
                    machines = set(r.get('computer') for r in handle_leaks)
                    lines.append(f"**Handle leaks**: {len(handle_leaks)} on {', '.join(sorted(machines))}")

                lines.append("")

            # Check hangs
            if test_name in history.get('test_hangs', {}):
                entry = history['test_hangs'][test_name]
                reports = entry.get('reports', [])
                machines = set(r.get('computer') for r in reports if r.get('computer'))

                lines.append("## Hangs")
                lines.append("")
                lines.append(f"**Total hangs**: {len(reports)}")
                lines.append(f"**Machines**: {', '.join(sorted(machines))}")
                lines.append("")

            return "\n".join(lines)

        except Exception as e:
            logger.error(f"Error querying test history: {e}", exc_info=True)
            return f"Error querying test history: {e}"

    def _record_test_tracking(
        test_name: str,
        fix_type: str,
        property_name: str,
        tracking_data: dict,
        fingerprint: str = None,
    ):
        """Common logic for recording issue or fix info for a test.

        Returns:
            (updated_items_list, None) on success
            (None, error_message) on failure
        """
        history = _load_nightly_history()
        updated = []

        # Map fix_type to section name
        section_map = {
            'failure': 'test_failures',
            'leak': 'test_leaks',
            'hang': 'test_hangs',
        }
        if fix_type not in section_map:
            return None, f"Invalid fix_type: {fix_type}. Use 'failure', 'leak', or 'hang'."

        section = history.get(section_map[fix_type], {})
        if test_name not in section:
            return None, f"Test '{test_name}' not found in {fix_type} history."

        if fix_type == "failure":
            # Failures have fingerprints
            if fingerprint:
                by_fp = section[test_name].get('by_fingerprint', {})
                if fingerprint not in by_fp:
                    return None, f"Fingerprint '{fingerprint}' not found for {test_name}."
                by_fp[fingerprint][property_name] = tracking_data
                updated.append(f"fingerprint `{fingerprint}`")
            else:
                for fp, fp_entry in section[test_name].get('by_fingerprint', {}).items():
                    fp_entry[property_name] = tracking_data
                    updated.append(f"fingerprint `{fp}`")
        else:
            # Leaks and hangs don't have fingerprints
            section[test_name][property_name] = tracking_data
            updated.append(f"{fix_type} entry")

        _save_nightly_history(history, datetime.now().strftime("%Y-%m-%d"))
        return updated, None

    @mcp.tool()
    async def record_test_fix(
        test_name: str,
        fix_type: str,
        pr_number: str,
        fingerprint: str = None,
        fixed_in_version: str = None,
        merge_date: str = None,
        commit: str = None,
        release_branch: str = None,
        release_pr: str = None,
        release_commit: str = None,
        release_merge_date: str = None,
        notes: str = None,
    ) -> str:
        """Record that a test failure, leak, or hang has been fixed. → nightly-tests.md"""
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
            updated, error = _record_test_tracking(test_name, fix_type, 'fix', fix_data, fingerprint)
            if error:
                return error

            # Format response
            lines = [f"Recorded fix for {test_name} ({fix_type}):"]
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
    async def record_test_issue(
        test_name: str,
        fix_type: str,
        issue_number: str,
        fingerprint: str = None,
        notes: str = None,
    ) -> str:
        """Record that a GitHub issue has been created for a test failure, leak, or hang. → nightly-tests.md"""
        try:
            # Validate issue number
            issue_num = issue_number.lstrip('#')
            if not issue_num.isdigit():
                return f"Invalid issue number: {issue_number}. Expected a number like '3878' or '#3878'."

            # Build issue data
            issue_data = {
                'number': int(issue_num),
                'recorded_date': datetime.now().strftime("%Y-%m-%d"),
                'url': f"https://github.com/ProteoWizard/pwiz/issues/{issue_num}",
            }
            if notes:
                issue_data['notes'] = notes

            # Record it
            updated, error = _record_test_tracking(test_name, fix_type, 'issue', issue_data, fingerprint)
            if error:
                return error

            # Format response
            return "\n".join([
                f"Recorded GitHub issue for {test_name} ({fix_type}):",
                f"- Issue: #{issue_num}",
                f"- URL: {issue_data['url']}",
                f"- Updated: {', '.join(updated)}",
                "",
                "Future reports will show this as a tracked issue.",
            ])

        except Exception as e:
            logger.error(f"Error recording issue: {e}", exc_info=True)
            return f"Error recording issue: {e}"


def _process_failure_rows(history: dict, rows: list, folder_name: str):
    """Process failure rows and add to history."""
    failures_db = history['test_failures']
    machine_health = history['machine_health']

    for row in rows:
        test_name = row.get('testname')
        computer = row.get('computer')
        run_id = row.get('run_id')
        run_date = row.get('run_date')
        githash = row.get('githash')
        stacktrace = row.get('stacktrace', '')

        if not test_name:
            continue

        # Convert date if needed
        if hasattr(run_date, 'strftime'):
            run_date = run_date.strftime("%Y-%m-%d")
        elif isinstance(run_date, str) and 'T' in run_date:
            run_date = run_date.split('T')[0]

        # Normalize stack trace and get fingerprint
        norm = normalize_stack_trace(stacktrace)
        fp = norm.fingerprint
        sig_frames = norm.signature_frames

        # Extract exception type from first line
        exc_type = None
        exc_brief = None
        if stacktrace:
            first_line = stacktrace.split('\n')[0].strip()
            if ':' in first_line:
                exc_type = first_line.split(':')[0].strip()
                exc_brief = first_line

        # Initialize test entry if needed
        if test_name not in failures_db:
            failures_db[test_name] = {
                'by_fingerprint': {}
            }

        by_fp = failures_db[test_name]['by_fingerprint']

        # Initialize fingerprint entry if needed
        if fp not in by_fp:
            by_fp[fp] = {
                'fingerprint': fp,
                'signature': ' → '.join(sig_frames) if sig_frames else '(unknown)',
                'exception_type': exc_type,
                'exception_brief': exc_brief,
                'first_seen': run_date,
                'last_seen': run_date,
                'reports': [],
                'fix': None,
            }

        fp_entry = by_fp[fp]

        # Update last_seen
        if run_date and run_date > fp_entry.get('last_seen', ''):
            fp_entry['last_seen'] = run_date

        # Add report
        fp_entry['reports'].append({
            'run_id': run_id,
            'date': run_date,
            'computer': computer,
            'folder': folder_name,
            'git_hash': githash,
        })

        # Update machine health
        if computer:
            if computer not in machine_health:
                machine_health[computer] = {
                    'failures': 0,
                    'leaks': 0,
                    'hangs': 0,
                    'last_seen': run_date,
                }
            machine_health[computer]['failures'] += 1
            if run_date and run_date > machine_health[computer].get('last_seen', ''):
                machine_health[computer]['last_seen'] = run_date


def _process_leak_rows(history: dict, rows: list, folder_name: str):
    """Process leak rows and add to history."""
    leaks_db = history['test_leaks']
    machine_health = history['machine_health']

    for row in rows:
        test_name = row.get('testname')
        computer = row.get('computer')
        run_id = row.get('run_id')
        run_date = row.get('run_date')
        githash = row.get('githash')
        leak_type = row.get('leak_type')
        leak_bytes = row.get('leak_bytes')
        leak_handles = row.get('leak_handles')

        if not test_name:
            continue

        # Convert date if needed
        if hasattr(run_date, 'strftime'):
            run_date = run_date.strftime("%Y-%m-%d")
        elif isinstance(run_date, str) and 'T' in run_date:
            run_date = run_date.split('T')[0]

        # Initialize test entry if needed
        if test_name not in leaks_db:
            leaks_db[test_name] = {
                'first_seen': run_date,
                'last_seen': run_date,
                'reports': [],
                'fix': None,
            }

        entry = leaks_db[test_name]

        # Update last_seen
        if run_date and run_date > entry.get('last_seen', ''):
            entry['last_seen'] = run_date

        # Add report
        entry['reports'].append({
            'run_id': run_id,
            'date': run_date,
            'computer': computer,
            'folder': folder_name,
            'git_hash': githash,
            'leak_type': leak_type,
            'leak_bytes': leak_bytes,
            'leak_handles': leak_handles,
        })

        # Update machine health
        if computer:
            if computer not in machine_health:
                machine_health[computer] = {
                    'failures': 0,
                    'leaks': 0,
                    'hangs': 0,
                    'last_seen': run_date,
                }
            machine_health[computer]['leaks'] += 1
            if run_date and run_date > machine_health[computer].get('last_seen', ''):
                machine_health[computer]['last_seen'] = run_date


def _process_hang_rows(history: dict, rows: list, folder_name: str):
    """Process hang rows and add to history."""
    hangs_db = history['test_hangs']
    machine_health = history['machine_health']

    for row in rows:
        test_name = row.get('testname')
        computer = row.get('computer')
        run_id = row.get('run_id')
        run_date = row.get('run_date')
        githash = row.get('githash')

        if not test_name:
            continue

        # Convert date if needed
        if hasattr(run_date, 'strftime'):
            run_date = run_date.strftime("%Y-%m-%d")
        elif isinstance(run_date, str) and 'T' in run_date:
            run_date = run_date.split('T')[0]

        # Initialize test entry if needed
        if test_name not in hangs_db:
            hangs_db[test_name] = {
                'first_seen': run_date,
                'last_seen': run_date,
                'reports': [],
                'fix': None,
            }

        entry = hangs_db[test_name]

        # Update last_seen
        if run_date and run_date > entry.get('last_seen', ''):
            entry['last_seen'] = run_date

        # Add report
        entry['reports'].append({
            'run_id': run_id,
            'date': run_date,
            'computer': computer,
            'folder': folder_name,
            'git_hash': githash,
        })

        # Update machine health
        if computer:
            if computer not in machine_health:
                machine_health[computer] = {
                    'failures': 0,
                    'leaks': 0,
                    'hangs': 0,
                    'last_seen': run_date,
                }
            machine_health[computer]['hangs'] += 1
            if run_date and run_date > machine_health[computer].get('last_seen', ''):
                machine_health[computer]['last_seen'] = run_date
