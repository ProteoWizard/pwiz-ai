# MacCoss Lab Modules Reference

Overview of MacCoss Lab LabKey modules and their purposes.

## Repository Structure

### Main Repositories

1. **targetedms** (separate repo)
   - Repository: https://github.com/LabKey/targetedms
   - Primary Panorama module
   - Mass spectrometry data management
   - Deployed on: panoramaweb.org

2. **MacCossLabModules** (contains multiple modules)
   - Repository: https://github.com/LabKey/MacCossLabModules
   - Collection of related modules
   - See individual modules below

## Modules in MacCossLabModules

### Skyline.ms Modules

**SkylineToolsStore**
- Skyline External Tool Store management
- Allows users to upload and share Skyline tools
- Deployed on: skyline.ms

**signup**
- Custom user self-registration
- Specific to skyline.ms workflow
- Deployed on: skyline.ms

**testresults**
- Skyline nightly test statistics
- Test result visualization and tracking
- Deployed on: skyline.ms

### Panorama Modules

**panoramapublic**
- Panorama Public functionality
- Public data sharing features
- Deployed on: panoramaweb.org

**pwebdashboard**
- Dashboard charts and queries
- Analytics and monitoring
- Deployed on: panoramaweb.org

**lincs**
- LINCS project-specific features
- Library of Integrated Network-Based Cellular Signatures
- Deployed on: panoramaweb.org

## External CPTAC Module

**CPTAC Assay Portal**
- Separate repository: https://github.com/CPTAC/panorama
- Managed by CPTAC developers
- Custom SQL scripts, queries, R scripts
- Not typically included in local dev setups

## Module Dependencies

```
targetedms (core)
├── panoramapublic (extends targetedms)
└── pwebdashboard (uses targetedms data)

MacCossLabModules
├── SkylineToolsStore (standalone)
├── signup (standalone)
├── testresults (standalone)
└── lincs (standalone)
```

## Development Notes

### Building Individual Modules

```powershell
# TargetedMS
.\gradlew :server:modules:targetedms:deployModule

# Any MacCossLabModules module
.\gradlew :server:modules:MacCossLabModules:panoramapublic:deployModule
.\gradlew :server:modules:MacCossLabModules:SkylineToolsStore:deployModule
```

### Module Locations

After build, modules are deployed to:
```
server/build/deploy/labkeywebapp/
└── WEB-INF/
    └── classes/
        └── (module files)
```

### Verifying Module Installation

1. Start LabKey Server
2. Login as admin
3. Admin Console > Module Information
4. Look for:
   - TargetedMS
   - PanoramaPublic
   - SkylineToolsStore
   - (other installed modules)

## Production Deployments

**Important**: For Panorama (panoramaweb.org) and Skyline (skyline.ms):
- Use TeamCity builds, not local production builds
- Local production builds are for testing only
- TeamCity ensures consistent, tested deployments

## Module Documentation

- TargetedMS: https://www.labkey.org/project/home/PanoramaWeb/
- General modules: https://www.labkey.org/Documentation/
- MacCoss Lab wiki: https://skyline.ms/home/development/
