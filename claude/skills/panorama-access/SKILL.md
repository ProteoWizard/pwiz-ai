---
name: panorama-access
description: Use when a task needs files or folders on Panorama (panoramaweb.org, a LabKey server): listing a folder, downloading or uploading data files, or checking whether a file is already stored there. Also use when a user needs to get access to Panorama and store their credential safely.
---

# Accessing Panorama (panoramaweb.org)

Panorama is a LabKey server. Project data lives in LabKey containers (folders), and each
container has a file area reachable over WebDAV. Wiki pages and table queries are covered by the
`skyline-wiki` skill and the LabKey MCP server; this skill is for **files** and for **getting
access**.

This file contains no project folder details because the repository is public. Keep a project's
folder map in that project's own README.

## Getting access (once per person)

### 1. An account with the right folder role

1. Register at https://panoramaweb.org (the sign-in page has a **Register** link).
2. Ask the administrator of the folder you need to give your account a role on it:
   **Reader** to list and download, **Editor** (or Author) to upload. Ask for the least you need.

### 2. An API key (recommended over your password)

An API key can be limited to read-only, expires, and can be deleted without changing your
password.

1. Sign in, click your user name (top right), and choose **External Tool Access**.
2. Click **Generate API Key**, enter a description such as `claude <machine name>`, and set
   **Restrict Permissions** to **Reader** if you only need to download.
3. Click **Generate API Key** again and copy the key. It is shown once, and nobody, including
   administrators, can retrieve it later. If it is lost, delete it and generate a new one.

If **External Tool Access** is missing, the server has API keys turned off: ask a site administrator,
or put your account password in the netrc instead (use a dedicated account where your team has
one; see `ai/mcp/LabKeyMcp/README.md` for the `+claude` accounts used on skyline.ms).

### 3. Store it in your netrc, outside every repository

Create the file yourself in a text editor. Do not paste the key into a chat or ask an agent to
write it.

- Location: `~/.netrc` (Windows: `%USERPROFILE%\.netrc` or `%USERPROFILE%\_netrc`)
- Contents (the login is the literal word `apikey`):

```
machine panoramaweb.org
login apikey
password PASTE_YOUR_KEY_HERE
```

- Restrict the file to yourself:
  - macOS/Linux: `chmod 600 ~/.netrc`
  - Windows: `icacls "%USERPROFILE%\.netrc" /inheritance:r /grant:r "%USERNAME%:(F)"`
- One netrc can hold several `machine` entries (for example `skyline.ms` too).
- If a key is ever exposed (committed, pasted, logged), delete it under **External Tool Access**
  immediately and generate a new one.

### 4. Check that it works

```bash
curl -sn -o /dev/null -w "%{http_code}\n" "https://panoramaweb.org/_webdav/<container>/@files?method=JSON"
```

`200` means access works. `401` means no netrc entry, or a wrong, expired, or revoked key.
`403` means your account lacks a role on that folder. `404` means a wrong container path.

## Credentials: rules for agents

- **Never read, print, log, or commit the netrc or the key.** Use tools that read it themselves:
  `curl -n`, the LabKey Python API (`labkey`), or the LabKey MCP server.
- To check that an entry exists, list host names only: `grep -o "^machine [^ ]*" ~/.netrc`.
- Never put the key in a command line, URL, script, environment variable, commit, skill, memory
  file, or chat message.
- Do not try to sign in through a browser; use the commands below.

## File commands

A container path plus `@files` addresses a folder's file area, for example
`https://panoramaweb.org/_webdav/<container path>/@files`.

```bash
BASE=https://panoramaweb.org/_webdav/<container path>/@files

# List a folder (JSON: name, size, collection flag, dates)
curl -sn "$BASE?method=JSON"
curl -sn "$BASE/<subfolder>?method=JSON"

# Download one file. -C - resumes an interrupted transfer.
curl -n -C - -o <name> "$BASE/<subfolder>/<name>"

# Upload one file (PUT creates or overwrites)
curl -n -T <local file> "$BASE/<subfolder>/<name>"
```

Listing and downloading are verified. Upload uses the same standard LabKey WebDAV interface but
has not been exercised from this skill, so check the result afterwards. File names with spaces
need URL encoding. Large files go in a single request; use `-C -` to resume and verify with a
checksum afterwards.

## Rules

- **Listing and downloading are read-only; do them freely** when the task needs them.
- **Uploading, overwriting, renaming, or deleting changes shared data: ask the user first,**
  naming the file, its size, and the destination folder. List the destination first and never
  overwrite without saying what is there.
- After a transfer, compare the size, and a checksum when the project keeps a manifest.
- Do not copy data from a private container into a public repository or a public folder.
- Files over 100 MB cannot go in GitHub. Store them on Panorama and record the location,
  size, and SHA-256 checksum in the repository.

## Using this skill outside the `ai/` tree

Skills here reach sessions started under the `ai/` checkout. To use it in any project on your
machine, copy or symlink this folder into your user skills directory
(`~/.claude/skills/panorama-access`).
