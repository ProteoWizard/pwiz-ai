# Phase 2: PostgreSQL

**Goal**: Install and configure PostgreSQL for LabKey development.

## Prerequisites
Check state.json for target PostgreSQL version (17 or 18).

## Step 2.1: Install PostgreSQL

**Skip if**: Environment check showed correct PostgreSQL version [OK]

**Install**:
```bash
# For PostgreSQL 17:
powershell.exe -Command "winget install PostgreSQL.PostgreSQL.17 --source winget --interactive"

# For PostgreSQL 18:
powershell.exe -Command "winget install PostgreSQL.PostgreSQL.18 --source winget --interactive"
```

**User must**:
- Click through installer dialogs
- Set postgres password (have them note it down)
- Accept default port 5432
- Accept default locale
- **Uncheck "Run StackBuilder" when installation is complete**

**Verify service running**:
```bash
powershell.exe -Command "Get-Service -Name 'postgresql*' | Select-Object Name, Status"
```

Should show Status: Running

**If not running**:
```bash
powershell.exe -Command "Start-Service postgresql-x64-<version>"
```

**Update state.json**:
```json
{
  "completed": ["phase-2-step-2.1"],
  "postgres_password": "<user-should-note-this>"
}
```

## Step 2.2: Create LabKey Database and User

**Connect to PostgreSQL**:
```bash
# User runs this in their terminal (requires postgres password)
psql -U postgres
```

**Create database and user** (user pastes these SQL commands):
```sql
CREATE DATABASE labkey WITH ENCODING='UTF8';
CREATE USER labkey WITH PASSWORD 'labkey';
GRANT ALL PRIVILEGES ON DATABASE labkey TO labkey;
\q
```

**Verify connection**:
```bash
psql -U labkey -d labkey -h localhost
```

User should successfully connect. Type `\q` to exit.

**Update state.json**:
```json
{"completed": ["phase-2-step-2.2"]}
```

## Completion

PostgreSQL configured for LabKey.

**Next**: Phase 3 - Repository Setup
