"""Common utilities for LabKey MCP server.

This module contains:
- Constants for default server configuration
- Shared helper functions (credentials, HTTP requests)
- WebDAV file operations (list, upload, download)
- Limited discovery (list_queries only - for proposing schema documentation)
"""

import json
import logging
import base64
import netrc
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote, urlencode

import labkey
from labkey.query import ServerContext

logger = logging.getLogger("labkey_mcp")

# =============================================================================
# Default Server Configuration
# =============================================================================

DEFAULT_SERVER = "skyline.ms"
DEFAULT_CONTAINER = "/home/issues/exceptions"

# Exception data schema (discovered from skyline.ms)
EXCEPTION_SCHEMA = "announcement"
EXCEPTION_QUERY = "Announcement"

# Testresults schema
TESTRESULTS_SCHEMA = "testresults"
DEFAULT_TEST_CONTAINER = "/home/development/Nightly x64"

# Wiki schema
WIKI_SCHEMA = "wiki"
DEFAULT_WIKI_CONTAINER = "/home/software/Skyline"

# Support board schema
ANNOUNCEMENT_SCHEMA_SUPPORT = "announcement"
DEFAULT_SUPPORT_CONTAINER = "/home/support"

# Issues schema
ISSUES_SCHEMA = "issues"
DEFAULT_ISSUES_CONTAINER = "/home/issues"


# =============================================================================
# Shared Helper Functions
# =============================================================================

def get_server_context(server: str, container_path: str) -> ServerContext:
    """Create a LabKey server context for API calls.

    Authentication is handled automatically via netrc file in standard locations:
    - ~/.netrc (Unix/Windows)
    - ~/_netrc (Windows)
    """
    return ServerContext(
        server,
        container_path,
        use_ssl=True,
    )


def get_netrc_credentials(server: str) -> tuple[str, str]:
    """Get credentials from netrc file.

    Args:
        server: The server hostname to get credentials for

    Returns:
        Tuple of (login, password)

    Raises:
        Exception: If no credentials found for server
    """
    home = Path.home()
    netrc_paths = [home / ".netrc", home / "_netrc"]

    for netrc_path in netrc_paths:
        if netrc_path.exists():
            try:
                nrc = netrc.netrc(str(netrc_path))
                auth = nrc.authenticators(server)
                if auth:
                    login, _, password = auth
                    return login, password
            except Exception:
                continue

    raise Exception(f"No credentials found for {server} in netrc")


def make_authenticated_request(
    server: str,
    url: str,
    method: str = "GET",
    data: bytes = None,
    headers: dict = None,
    timeout: int = 30
) -> bytes:
    """Make an authenticated HTTP request to a LabKey server.

    Args:
        server: Server hostname for credential lookup
        url: Full URL to request
        method: HTTP method (GET, POST, etc.)
        data: Optional request body bytes
        headers: Optional additional headers
        timeout: Request timeout in seconds

    Returns:
        Response body as bytes
    """
    login, password = get_netrc_credentials(server)

    request = urllib.request.Request(url, data=data, method=method)
    credentials = base64.b64encode(f"{login}:{password}".encode()).decode()
    request.add_header("Authorization", f"Basic {credentials}")

    if headers:
        for key, value in headers.items():
            request.add_header(key, value)

    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def discovery_request(server: str, container_path: str, api_action: str, params: dict = None) -> dict:
    """Make a discovery API request using credentials from netrc.

    The labkey SDK doesn't expose getSchemas/getQueries/getContainers directly,
    so we use direct HTTP requests with authentication.

    Args:
        server: LabKey server hostname
        container_path: Container/folder path
        api_action: API action (e.g., 'query-getSchemas.api')
        params: Optional query parameters

    Returns:
        Parsed JSON response as dict
    """
    # Build URL with proper encoding for paths with spaces
    encoded_path = quote(container_path, safe="/")
    url = f"https://{server}{encoded_path}/{api_action}"
    if params:
        url = f"{url}?{urlencode(params)}"

    response_bytes = make_authenticated_request(server, url)
    return json.loads(response_bytes.decode())


def get_tmp_dir() -> Path:
    """Get the ai/.tmp directory for saving files.

    Creates the directory if it doesn't exist.

    Returns:
        Path to ai/.tmp directory
    """
    # Navigate from tools/ -> LabKeyMcp/ -> mcp/ -> ai/ -> .tmp/
    tmp_dir = Path(__file__).parent.parent.parent.parent / ".tmp"
    tmp_dir.mkdir(exist_ok=True)
    return tmp_dir


# =============================================================================
# WebDAV File Operations
# =============================================================================

# WebDAV URL structure: https://{server}/_webdav{container_path}/@files/{subfolder}/{filename}
# Examples:
#   - Skyline-daily files: /_webdav/home/software/Skyline/daily/@files/
#   - Major release installers: /_webdav/home/software/Skyline/@files/installers/


def build_webdav_url(server: str, container_path: str, subfolder: str = "", filename: str = "") -> str:
    """Build a WebDAV URL for a LabKey container's file repository.

    Args:
        server: LabKey server hostname
        container_path: Container path (e.g., "/home/software/Skyline/daily")
        subfolder: Optional subfolder within @files
        filename: Optional filename

    Returns:
        Full WebDAV URL
    """
    encoded_container = quote(container_path, safe="/")
    parts = [f"https://{server}/_webdav{encoded_container}/%40files"]
    if subfolder:
        parts.append(quote(subfolder, safe="/"))
    if filename:
        parts.append(quote(filename))
    return "/".join(parts)


def list_files_webdav(
    server: str,
    container_path: str,
    subfolder: str = "",
    timeout: int = 30,
) -> dict:
    """List files in a LabKey container's file repository via WebDAV PROPFIND.

    Args:
        server: LabKey server hostname
        container_path: Container path (e.g., "/home/software/Skyline/daily")
        subfolder: Optional subfolder within @files
        timeout: Request timeout in seconds

    Returns:
        Dict with 'success', 'files' (list of dicts with name, size, modified), and optionally 'error'
    """
    import xml.etree.ElementTree as ET

    url = build_webdav_url(server, container_path, subfolder)
    if not url.endswith("/"):
        url += "/"

    logger.info(f"Listing files at {url}")

    try:
        login, password = get_netrc_credentials(server)
        credentials = base64.b64encode(f"{login}:{password}".encode()).decode()

        # PROPFIND request with Depth: 1 to list immediate children
        request = urllib.request.Request(url, method="PROPFIND")
        request.add_header("Authorization", f"Basic {credentials}")
        request.add_header("Depth", "1")
        request.add_header("Content-Type", "application/xml")

        with urllib.request.urlopen(request, timeout=timeout) as response:
            xml_content = response.read().decode("utf-8")

        # Parse WebDAV XML response
        # Namespace handling for DAV:
        ns = {"d": "DAV:"}
        root = ET.fromstring(xml_content)

        files = []
        for response_elem in root.findall("d:response", ns):
            href = response_elem.find("d:href", ns)
            if href is None:
                continue

            href_text = href.text or ""
            # Skip the directory itself (first entry)
            if href_text.rstrip("/") == url.replace("https://" + server, "").rstrip("/"):
                continue

            # Extract filename from href
            filename = href_text.rstrip("/").split("/")[-1]
            if not filename:
                continue

            # Get properties
            propstat = response_elem.find("d:propstat", ns)
            if propstat is None:
                continue

            prop = propstat.find("d:prop", ns)
            if prop is None:
                continue

            # Check if it's a collection (directory)
            resourcetype = prop.find("d:resourcetype", ns)
            is_dir = resourcetype is not None and resourcetype.find("d:collection", ns) is not None

            # Get size and modified date
            size_elem = prop.find("d:getcontentlength", ns)
            size = int(size_elem.text) if size_elem is not None and size_elem.text else 0

            modified_elem = prop.find("d:getlastmodified", ns)
            modified = modified_elem.text if modified_elem is not None else ""

            files.append({
                "name": filename,
                "size": size,
                "modified": modified,
                "is_directory": is_dir,
            })

        # Sort: directories first, then by name
        files.sort(key=lambda x: (not x["is_directory"], x["name"].lower()))

        return {
            "success": True,
            "url": url.replace("%40", "@"),
            "files": files,
        }

    except urllib.error.HTTPError as e:
        logger.error(f"List failed: HTTP {e.code} {e.reason}")
        return {"success": False, "error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        logger.error(f"List failed: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


def download_file_webdav(
    server: str,
    container_path: str,
    filename: str,
    subfolder: str = "",
    local_path: str = None,
    timeout: int = 300,
) -> dict:
    """Download a file from a LabKey container's file repository via WebDAV.

    Args:
        server: LabKey server hostname
        container_path: Container path (e.g., "/home/software/Skyline/daily")
        filename: Name of file to download
        subfolder: Optional subfolder within @files
        local_path: Local path to save file (defaults to ai/.tmp/)
        timeout: Download timeout in seconds

    Returns:
        Dict with 'success', 'local_path', 'size', and optionally 'error'
    """
    url = build_webdav_url(server, container_path, subfolder, filename)

    logger.info(f"Downloading {url}")

    try:
        login, password = get_netrc_credentials(server)
        credentials = base64.b64encode(f"{login}:{password}".encode()).decode()

        request = urllib.request.Request(url, method="GET")
        request.add_header("Authorization", f"Basic {credentials}")

        with urllib.request.urlopen(request, timeout=timeout) as response:
            content = response.read()

        # Determine local path
        if local_path:
            save_path = Path(local_path)
        else:
            save_path = get_tmp_dir() / filename

        save_path.write_bytes(content)

        return {
            "success": True,
            "url": url.replace("%40", "@"),
            "local_path": str(save_path),
            "size": len(content),
        }

    except urllib.error.HTTPError as e:
        logger.error(f"Download failed: HTTP {e.code} {e.reason}")
        return {"success": False, "error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        logger.error(f"Download failed: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


def upload_file_webdav(
    server: str,
    container_path: str,
    local_file_path: str,
    subfolder: str = "",
    remote_filename: str = None,
    timeout: int = 300,
) -> dict:
    """Upload a file to a LabKey container's file repository via WebDAV.

    Args:
        server: LabKey server hostname
        container_path: Container path (e.g., "/home/software/Skyline/daily")
        local_file_path: Path to local file to upload
        subfolder: Optional subfolder within @files (e.g., "installers")
        remote_filename: Optional remote filename (defaults to local filename)
        timeout: Upload timeout in seconds (default 300 for large files)

    Returns:
        Dict with 'success', 'url', 'size', and optionally 'error'
    """
    local_path = Path(local_file_path)
    if not local_path.exists():
        return {"success": False, "error": f"File not found: {local_file_path}"}

    filename = remote_filename or local_path.name
    file_size = local_path.stat().st_size

    url = build_webdav_url(server, container_path, subfolder, filename)

    logger.info(f"Uploading {local_path.name} ({file_size:,} bytes) to {url}")

    try:
        login, password = get_netrc_credentials(server)
        credentials = base64.b64encode(f"{login}:{password}".encode()).decode()

        # Read file content
        with open(local_path, "rb") as f:
            file_data = f.read()

        # Create PUT request
        request = urllib.request.Request(url, data=file_data, method="PUT")
        request.add_header("Authorization", f"Basic {credentials}")
        request.add_header("Content-Type", "application/octet-stream")
        request.add_header("Content-Length", str(file_size))

        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            logger.info(f"Upload complete: HTTP {status}")

        return {
            "success": True,
            "url": url.replace("%40", "@"),  # Return human-readable URL
            "size": file_size,
            "status": status,
        }

    except urllib.error.HTTPError as e:
        error_body = ""
        try:
            error_body = e.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        logger.error(f"Upload failed: HTTP {e.code} {e.reason}: {error_body}")
        return {
            "success": False,
            "url": url.replace("%40", "@"),
            "error": f"HTTP {e.code}: {e.reason}",
            "details": error_body,
        }
    except Exception as e:
        logger.error(f"Upload failed: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


# =============================================================================
# Limited Discovery Tools
# =============================================================================

def register_tools(mcp):
    """Register limited discovery tools.

    Only list_queries is exposed - enough to see what tables exist,
    but not enough to poke around with raw queries. When Claude needs
    data from a table, it should propose schema documentation work
    rather than trying to query directly.
    """

    @mcp.tool()
    async def list_queries(
        schema_name: str,
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_CONTAINER,
    ) -> str:
        """[?] See available tables/queries. → development-guide.md"""
        try:
            result = discovery_request(
                server,
                container_path,
                "query-getQueries.api",
                {"schemaName": schema_name}
            )

            if result and "queries" in result:
                queries = result["queries"]
                lines = [
                    f"Queries/tables in '{schema_name}' at {container_path}:",
                    "",
                ]
                for q in sorted(queries, key=lambda x: x.get("name", "")):
                    name = q.get("name", "unknown")
                    title = q.get("title", "")
                    if title and title != name:
                        lines.append(f"  - {name} ({title})")
                    else:
                        lines.append(f"  - {name}")

                lines.extend([
                    "",
                    "To access a table, propose schema documentation:",
                    "  1. Create stub: LabKeyMcp/queries/{schema}/{table}-schema.md",
                    "  2. Human populates from LabKey Schema Browser",
                    "  3. Design server-side query as .sql file",
                    "  4. Add high-level MCP tool",
                ])
                return "\n".join(lines)
            return f"No queries found in schema '{schema_name}'."

        except Exception as e:
            logger.error(f"Error listing queries: {e}", exc_info=True)
            return f"Error listing queries: {e}"

    @mcp.tool()
    async def fetch_labkey_page(
        view_name: str,
        server: str = DEFAULT_SERVER,
        container_path: str = DEFAULT_TEST_CONTAINER,
        params: dict = None,
    ) -> str:
        """[E] Fetch authenticated LabKey page (HTML). → development-guide.md"""
        try:
            # Build URL with proper encoding for paths with spaces
            encoded_path = quote(container_path, safe="/")
            url = f"https://{server}{encoded_path}/{view_name}"
            if params:
                url = f"{url}?{urlencode(params)}"

            logger.info(f"Fetching page: {url}")
            response_bytes = make_authenticated_request(server, url, timeout=60)
            html_content = response_bytes.decode('utf-8', errors='replace')

            # Save to file to avoid overwhelming context
            # Generate filename from view_name, params, and date
            from datetime import datetime
            import re
            date_stamp = datetime.now().strftime("%Y%m%d")
            safe_view = view_name.replace('.view', '').replace('-', '_')
            folder = container_path.split('/')[-1].replace(' ', '_')
            if params:
                # Sanitize param values to be filesystem-safe
                param_str = '_'.join(f"{k}{re.sub(r'[^a-zA-Z0-9]', '', str(v))}" for k, v in params.items())
                filename = f"page-{safe_view}-{param_str}-{date_stamp}.html"
            else:
                filename = f"page-{safe_view}-{folder}-{date_stamp}.html"

            filepath = get_tmp_dir() / filename
            filepath.write_text(html_content, encoding='utf-8')

            # Return summary and filepath
            lines = [
                f"Saved {len(html_content):,} chars to: {filepath}",
                f"URL: {url}",
                "",
                "Use Read tool to examine the file content.",
            ]
            return "\n".join(lines)

        except urllib.error.HTTPError as e:
            return f"HTTP Error {e.code}: {e.reason}"
        except Exception as e:
            logger.error(f"Error fetching page: {e}", exc_info=True)
            return f"Error fetching page: {e}"

    @mcp.tool()
    async def list_files(
        container_path: str,
        subfolder: str = "",
        server: str = DEFAULT_SERVER,
    ) -> str:
        """[D] List files in container via WebDAV. → files.md"""
        try:
            result = list_files_webdav(
                server=server,
                container_path=container_path,
                subfolder=subfolder,
            )

            if result["success"]:
                files = result["files"]
                if not files:
                    return f"No files found at {result['url']}"

                lines = [f"Files at {result['url']}:", ""]
                for f in files:
                    if f["is_directory"]:
                        lines.append(f"  [DIR] {f['name']}/")
                    else:
                        size_mb = f["size"] / (1024 * 1024)
                        lines.append(f"  {f['name']} ({size_mb:.1f} MB)")
                return "\n".join(lines)
            else:
                return f"List failed: {result.get('error', 'Unknown error')}"

        except Exception as e:
            logger.error(f"Error listing files: {e}", exc_info=True)
            return f"Error listing files: {e}"

    @mcp.tool()
    async def download_file(
        filename: str,
        container_path: str,
        subfolder: str = "",
        local_path: str = None,
        server: str = DEFAULT_SERVER,
    ) -> str:
        """[D] Download file from container via WebDAV. Saves to ai/.tmp/. → files.md"""
        try:
            result = download_file_webdav(
                server=server,
                container_path=container_path,
                filename=filename,
                subfolder=subfolder,
                local_path=local_path,
            )

            if result["success"]:
                size_mb = result["size"] / (1024 * 1024)
                return f"Downloaded {result['url']} ({size_mb:.1f} MB) to {result['local_path']}"
            else:
                return f"Download failed: {result.get('error', 'Unknown error')}"

        except Exception as e:
            logger.error(f"Error downloading file: {e}", exc_info=True)
            return f"Error downloading file: {e}"

    @mcp.tool()
    async def upload_file(
        local_file_path: str,
        container_path: str,
        subfolder: str = "",
        remote_filename: str = None,
        server: str = DEFAULT_SERVER,
    ) -> str:
        """[D] Upload file to container via WebDAV. → files.md"""
        try:
            result = upload_file_webdav(
                server=server,
                container_path=container_path,
                local_file_path=local_file_path,
                subfolder=subfolder,
                remote_filename=remote_filename,
            )

            if result["success"]:
                size_mb = result["size"] / (1024 * 1024)
                return f"Uploaded successfully: {result['url']} ({size_mb:.1f} MB)"
            else:
                error_msg = f"Upload failed: {result.get('error', 'Unknown error')}"
                if "details" in result:
                    error_msg += f"\nDetails: {result['details']}"
                return error_msg

        except Exception as e:
            logger.error(f"Error uploading file: {e}", exc_info=True)
            return f"Error uploading file: {e}"
