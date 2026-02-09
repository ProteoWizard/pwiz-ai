---
description: Configure LabKey Server development environment
---

**IMPORTANT: This command MUST be invoked from the labkey-setup directory.**

The full path should be: `<pwiz-ai root>/docs/labkey-setup`

For example:
- If you cloned pwiz-ai to `C:\proj\pwiz-ai`
- Then run this command from: `C:\proj\pwiz-ai\docs\labkey-setup`

First, check the current working directory.

If the current working directory is NOT `docs/labkey-setup`, tell the user:

```
The LabKey setup must be started from the labkey-setup directory so that
the CLAUDE.md file there is loaded. This is critical for state management
across session restarts (required during Java installation).

Please:
1. Navigate to: <pwiz-ai root>/docs/labkey-setup
2. Start a new Claude session in that directory: claude
3. Run this command again: /pw-configure-labkey
```

If the current working directory IS `docs/labkey-setup`:

Read and follow README.md
