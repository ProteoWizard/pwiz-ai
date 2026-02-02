# Troubleshooting Guide

Common issues and solutions for LabKey development.

## Build Issues

### Gradle Daemon Errors

**Symptoms**: Build fails with daemon-related errors.

**Solution**:
```powershell
.\gradlew --stop
.\gradlew deployApp
```

### Out of Memory

**Symptoms**: Build fails with "OutOfMemoryError" or "Java heap space".

**Solution**: Add to `~/.gradle/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=512m
```

### Wrong Java Version

**Symptoms**: Build fails with "Unsupported class file major version".

**Solution**:
1. Verify JAVA_HOME: `echo $env:JAVA_HOME`
2. Verify Java version: `java -version`
3. Should match LabKey requirements (17 for 25.x, 25 for 26.x)

### Module Not Found

**Symptoms**: Build can't find targetedms or MacCossLabModules.

**Solution**:
1. Check directory structure:
   ```
   server/externalModules/
   ├── targetedms/
   └── MacCossLabModules/
   ```
2. Verify `gradle.properties` has:
   ```
   extraModules=../externalModules/targetedms;../externalModules/MacCossLabModules
   ```
3. Run: `.\gradlew cleanBuild deployApp`

## Server Issues

### Port 8080 Already in Use

**Symptoms**: Server won't start, says port 8080 in use.

**Solution**:
```powershell
# Find process using port 8080
netstat -ano | findstr :8080

# Kill process (replace PID with actual process ID)
taskkill /PID <PID> /F

# Or configure LabKey to use different port
```

### Database Connection Failed

**Symptoms**: Server starts but can't connect to database.

**Solution**:
1. Verify PostgreSQL service running:
   ```powershell
   Get-Service -Name 'postgresql*'
   ```
2. Start if stopped:
   ```powershell
   Start-Service postgresql-x64-<version>
   ```
3. Check credentials in `pg.properties`
4. Test connection:
   ```powershell
   psql -U labkey -d labkey -h localhost
   ```
5. Rerun: `.\gradlew pickPg`

### Modules Not Appearing

**Symptoms**: TargetedMS or MacCoss modules not visible in Module Information.

**Solution**:
1. Verify repos cloned in externalModules/
2. Check `gradle.properties` extraModules setting
3. Rebuild: `.\gradlew cleanBuild deployApp`
4. Restart server
5. Check Admin Console > Module Information

## IntelliJ Issues

### Modules Not Recognized

**Symptoms**: IntelliJ doesn't see modules, red imports.

**Solution**:
1. Gradle tool window > Refresh (circular arrows icon)
2. File > Invalidate Caches > Invalidate and Restart
3. File > Project Structure > Modules > verify all present

### Project SDK Not Set

**Symptoms**: "Project SDK is not defined" error.

**Solution**:
1. File > Project Structure
2. Project Settings > Project
3. SDK: Add SDK > JDK > browse to JAVA_HOME
4. Apply

### Slow Indexing

**Symptoms**: IntelliJ indexing takes forever.

**Solution**:
1. Exclude build directories from indexing:
   - File > Settings > Build, Execution, Deployment > Compiler
   - Exclude: `build/`, `out/`, `target/`
2. Increase IntelliJ memory:
   - Help > Edit Custom VM Options
   - Add: `-Xmx4g`

## Test Issues

### ChromeDriver Version Mismatch

**Symptoms**: Tests fail with ChromeDriver incompatible with Chrome.

**Solution**:
1. Check Chrome version: chrome://settings/help
2. Download matching ChromeDriver
3. Extract to: `server/build/chromedriver/`
4. Or let Gradle download automatically (delete existing first)

### Test Database Issues

**Symptoms**: Tests fail with database errors.

**Solution**:
1. Verify labkeytest database exists:
   ```sql
   psql -U postgres -c "\l"
   ```
2. Create if missing:
   ```sql
   CREATE DATABASE labkeytest WITH ENCODING='UTF8';
   GRANT ALL PRIVILEGES ON DATABASE labkeytest TO labkey;
   ```
3. Check test.properties credentials

## Git Issues

### Line Ending Problems

**Symptoms**: Files show as modified after checkout.

**Solution**:
```bash
git config --global core.autocrlf true
```

### SSH Authentication Failed

**Symptoms**: Can't clone repos, permission denied.

**Solution**:
1. Verify SSH key exists: `ls ~/.ssh/id_ed25519.pub`
2. Test GitHub: `ssh -T git@github.com`
3. Add key to GitHub: https://github.com/settings/keys

## Getting Help

1. Check LabKey documentation: https://www.labkey.org/Documentation/
2. Search LabKey forums: https://www.labkey.org/home/Support/
3. Check MacCoss Lab wiki: https://skyline.ms/home/development/
