# LabKey WebDAV File Access

This document describes the MCP tools for accessing files in LabKey server containers via WebDAV.

## Overview

LabKey containers can store files in a `@files` directory accessible via WebDAV. These tools provide authenticated access to list, download, and upload files from Claude Code sessions.

Common uses:
- Download daily/release installers from `/home/software/Skyline`
- Access test run logs and artifacts from nightly test containers
- Upload files to share with team members

## Available MCP Tools

| Tool | Type | Description |
|------|------|-------------|
| `list_files` | [D] Drill-down | List files in a container's file repository |
| `download_file` | [D] Drill-down | Download a file to local disk (default: `ai/.tmp/`) |
| `upload_file` | [D] Drill-down | Upload a local file to a container |

### list_files

List files in a LabKey container's `@files` directory.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `container_path` | Yes | - | Container path (e.g., `/home/software/Skyline/daily`) |
| `subfolder` | No | `""` | Subfolder within `@files` |
| `server` | No | `skyline.ms` | LabKey server hostname |

**Returns:** Table showing files with name, size (MB), and directories marked with `[DIR]`.

### download_file

Download a file from a container to local disk.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `filename` | Yes | - | Name of file to download |
| `container_path` | Yes | - | Container path |
| `subfolder` | No | `""` | Subfolder within `@files` |
| `local_path` | No | `ai/.tmp/{filename}` | Custom local save path |
| `server` | No | `skyline.ms` | LabKey server hostname |

**Returns:** Success message with download location and file size.

### upload_file

Upload a local file to a container's file repository.

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `local_file_path` | Yes | - | Path to local file |
| `container_path` | Yes | - | Target container path |
| `subfolder` | No | `""` | Subfolder within `@files` |
| `remote_filename` | No | Local filename | Override remote filename |
| `server` | No | `skyline.ms` | LabKey server hostname |

**Returns:** Success message with uploaded URL and file size.

## Common Container Paths

| Container Path | Contents |
|----------------|----------|
| `/home/software/Skyline` | Release installers (in `installers` subfolder) |
| `/home/software/Skyline/daily` | Daily build installers (ZIP and MSI) |
| `/home/development/Nightly x64` | Nightly test logs and artifacts |
| `/home/development/Nightly x64 Stress` | Stress test logs |
| `/home/development/Nightly x64 Vendor Readers` | Vendor reader test logs |
| `/home/issues/exceptions` | Exception report attachments |

## Usage Examples

**List daily builds:**
```
list_files(container_path="/home/software/Skyline/daily")
```

**Download a specific installer:**
```
download_file(
    filename="Skyline-daily (64-bit) 25.1.0.185.msi",
    container_path="/home/software/Skyline/daily"
)
```

**List files in a subfolder:**
```
list_files(
    container_path="/home/development/Nightly x64",
    subfolder="logs"
)
```

**Upload a file (release publishing):**
```
upload_file(
    local_file_path="M:/home/brendanx/tools/Skyline-daily/Skyline-daily-64_26_0_9_021.zip",
    container_path="/home/software/Skyline/daily"
)
```

**Upload to a subfolder:**
```
upload_file(
    local_file_path="path/to/Skyline-Installer-64_26_1_0_045.msi",
    container_path="/home/software/Skyline",
    subfolder="installers"
)
```

## Authentication

These tools use the same `~/.netrc` credentials as other LabKey MCP tools:

```
machine skyline.ms
login yourname+claude@domain.com
password <password>
```

The `+claude` account must be a member of the "Agents" group on skyline.ms. See [exceptions.md](exceptions.md) for full authentication setup.

## Technical Notes

- Uses WebDAV protocol (PROPFIND for listing, GET for download, PUT for upload)
- Default timeout: 30 seconds for listing, 300 seconds for transfers
- URL pattern: `https://{server}/_webdav{container_path}/@files/{subfolder}/{filename}`
- Binary files are supported for both upload and download

## Attachments vs File Repositories

**File repositories** (`@files`) are managed by these WebDAV tools. Each container has one file repository.

**Attachments** on wiki pages, announcements, and support posts are handled separately:
- Use `list_attachments` / `get_attachment` for support post attachments (see [support.md](support.md))
- Use `list_wiki_attachments` / `get_wiki_attachment` for wiki attachments (see [wiki.md](wiki.md))

Currently, attachments can only be listed and downloaded, not uploaded.

## Related Documentation

- [Exception Triage](exceptions.md) - Exception report access
- [Nightly Tests](nightly-tests.md) - Test results data (uses file tools for logs)
- [Support](support.md) - Support board and attachment access
- [Wiki](wiki.md) - Wiki page and attachment access
- [Development Guide](development-guide.md) - MCP server development patterns
