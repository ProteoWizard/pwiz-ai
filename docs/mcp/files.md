# File Repository Access

Access files in LabKey container file repositories via WebDAV.

## Data Location

| Property | Value |
|----------|-------|
| Server | `skyline.ms` |
| Protocol | WebDAV (HTTP PUT/GET/PROPFIND) |
| URL Pattern | `https://{server}/_webdav{container_path}/@files/{subfolder}/` |

### File Repository Containers

Each LabKey container has a file repository accessible via WebDAV:

| Container | Subfolder | Content |
|-----------|-----------|---------|
| `/home/software/Skyline/daily` | (root) | Skyline-daily ZIP and MSI installers |
| `/home/software/Skyline` | `installers` | Major release installers |

**Authentication**: Uses same netrc credentials as other LabKey operations.

## MCP Tools

| Tool | Description |
|------|-------------|
| `list_files(container_path, subfolder)` | List files in container's file repository |
| `download_file(filename, container_path, subfolder)` | Download file to `ai/.tmp/` |
| `upload_file(local_file_path, container_path, subfolder)` | Upload file to container |

## Common Usage

### Release Publishing

```python
# Skyline-daily release files
upload_file(
    local_file_path="M:/home/brendanx/tools/Skyline-daily/Skyline-daily-64_26_0_9_021.zip",
    container_path="/home/software/Skyline/daily"
)

# Major release installers
upload_file(
    local_file_path="path/to/Skyline-Installer-64_26_1_0_045.msi",
    container_path="/home/software/Skyline",
    subfolder="installers"
)
```

### Verify Uploads

```python
list_files(container_path="/home/software/Skyline/daily")
```

## Future: Attachment Modifications

Attachments on wiki pages, announcements, and issues are separate from file repositories. Future tools may include:
- Upload/replace wiki attachments
- Upload/replace announcement attachments

Currently, attachments can only be listed and downloaded (see `wiki.md`, `support.md`).
