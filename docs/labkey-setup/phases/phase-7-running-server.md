# Phase 7: Running LabKey Server

**Goal**: Start LabKey Server and complete initial setup.

## Step 7.1: Start Server

**User instructions**:
1. Run / Debug the configuration by selecting the following from the "Run" menu:  
  - Users of IntelliJ Community should select Run / Debug LabKey Embedded Tomcat Dev.
  - Users of IntelliJ Ultimate should select Run / Debug Spring Boot LabKey Embedded Tomcat Dev.
2. You can also click the Run button (green play icon) or Debug button (bug icon) in the menu bar
3. **Windows Security prompt:** If you see "Do you want to allow public and private network access to this app?" for OpenJDK Platform binary, click **Allow** (the server needs to accept connections on port 8080)
4. Wait for the server to start (watch the console output for module initialization)
5. The server is ready when you can access http://localhost:8080/ in a browser

**Wait for user to confirm the server is running before proceeding to Step 7.2.**

## Step 7.2 Access LabKey Server

Once the server is running:
1. Open a browser to: http://localhost:8080/
2. Follow the initial setup wizard if this is a fresh installation
3. Create an admin account when prompted

**Wait for user to confirm they have logged in before proceeding to Step 7.3.**

## Step 7.3 Verify Module Deployment

After logging in:
1. Go to Admin > Site > Admin Console
2. Click on "Module Information"
3. Verify these modules are listed:
   - targetedms
   - MacCossLabModules (SkylineToolsStore, signup, testresults, etc.)

**Wait for user to confirm modules are verified before proceeding.**

**Update state.json**:
```json
{
  "completed": ["phase-7"],
  "server_running": true
}
```

## Completion

LabKey Server running and accessible.

**Next**: Phase 8 - Test Setup (optional but recommended)
