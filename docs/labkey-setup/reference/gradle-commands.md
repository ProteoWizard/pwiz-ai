# Gradle Commands Reference

Quick reference for common LabKey Gradle commands.

## Daily Development

| Command | Description | Notes |
|---------|-------------|-------|
| `.\gradlew pickPg` | Copy PostgreSQL settings to application.properties | Run after changing pg.properties |
| `.\gradlew deployApp` | Full development build | First build: 15-30 min |
| `.\gradlew cleanBuild` | Clean all build artifacts | Use before production builds |
| `.\gradlew --stop` | Stop Gradle daemon | Use if builds are failing |

## Module-Specific Builds

| Command | Description |
|---------|-------------|
| `.\gradlew :server:modules:targetedms:deployModule` | Build/deploy targetedms only |
| `.\gradlew :server:modules:MacCossLabModules:panoramapublic:deployModule` | Build/deploy panoramapublic |
| `.\gradlew :server:modules:MacCossLabModules:SkylineToolsStore:deployModule` | Build/deploy SkylineToolsStore |
| `.\gradlew :server:modules:targetedms:clean` | Clean targetedms module |

## Running Server

| Command | Description |
|---------|-------------|
| `.\gradlew :server:tomcatRun` | Start embedded Tomcat server |
| `.\gradlew deployApp :server:tomcatRun` | Build and start server |

## Testing

| Command | Description |
|---------|-------------|
| `.\gradlew :server:test:uiTest` | Run all UI tests |
| `.\gradlew :server:test:uiTest -Ptest.module=targetedms` | Run targetedms tests only |
| `.\gradlew :server:modules:targetedms:test` | Run module unit tests |

## Production Builds

| Command | Description | Notes |
|---------|-------------|-------|
| `.\gradlew cleanBuild` | Clean first | Required |
| `.\gradlew deployApp -PdeployMode=prod` | Production build | Use TeamCity builds for Panorama |

## Build Configuration

| Command | Description |
|---------|-------------|
| `.\gradlew setPassword` | Set database admin password |
| `.\gradlew properties` | Show all Gradle properties |
| `.\gradlew tasks` | List available tasks |

## Troubleshooting

| Command | Description |
|---------|-------------|
| `.\gradlew --stop` | Stop daemon |
| `.\gradlew clean` | Clean build directory |
| `.\gradlew --refresh-dependencies` | Force dependency refresh |

## Build Performance Tips

Add to `~/.gradle/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=512m
org.gradle.parallel=true
org.gradle.workers.max=4
```
