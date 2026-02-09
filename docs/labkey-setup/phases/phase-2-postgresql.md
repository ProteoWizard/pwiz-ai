# Phase 2: PostgreSQL

**Goal**: Install and configure PostgreSQL for LabKey development.

## Prerequisites
Check state.json for target PostgreSQL version. If the LabKey version supports
multiple PostgreSQL versions (e.g. 25.11.x supports both 17 and 18), **ASK the
user which version they want** before proceeding. Update state.json with their choice.

## Step 2.1: Install PostgreSQL

**Skip if**: Environment check showed correct PostgreSQL version [OK]

If not found, **brief the user before launching the installer:**

> The PostgreSQL installer will open a GUI. Here's what you'll encounter:
>
> 1. **UAC prompt** — Click **Yes** to allow changes
> 2. **Component Selection** — Keep all components selected (PostgreSQL Server, pgAdmin, Command Line Tools)
> 3. **Password** — You will be asked to create a password for the `postgres` database superuser. **Choose a password and remember it** — you'll need it later when configuring LabKey's database connection
> 4. **Port** — Keep the default **5432** (unless you know another PostgreSQL instance is using it)
> 5. **Locale** — Keep the default locale
> 6. **Stack Builder** — On the final screen, **uncheck "Launch Stack Builder"**. Stack Builder downloads optional extensions (PostGIS, etc.) that are not needed for LabKey development
>
> Are you ready to start the installer?

**Wait for the user to confirm**, then run the appropriate installer. 

**Run the install** (assistant runs this, not the user):
```bash
# For PostgreSQL 17:
powershell.exe -Command 'winget install PostgreSQL.PostgreSQL.17 --source winget --interactive'

# For PostgreSQL 18:
powershell.exe -Command 'winget install PostgreSQL.PostgreSQL.18 --source winget --interactive'
```

**Verify service running**:
```bash
powershell.exe -Command 'Get-Service -Name "postgresql*" | Select-Object Name, Status'
```

Should show Status: Running

**If not running**:
```bash
powershell.exe -Command 'Start-Service postgresql-x64-<version>'
```

**Update state.json**:
```json
{"completed": ["phase-2-step-2.1"]}
```

## Completion

PostgreSQL installed and running. Database and user setup is handled
automatically during the LabKey build (Phase 5).

**Next**: Phase 3 - Repository Setup
