# OpenRT Application Logging

## Overview

All Perl scripts in the openRTApp directory now include comprehensive logging functionality that automatically activates when the `/usr/local/openRT/logs/` directory exists.

## Logging Features

### Automatic Detection
- Scripts automatically check for the existence of `/usr/local/openRT/logs/` directory
- If the directory exists, logging is enabled by default
- If the directory doesn't exist, scripts operate normally without logging
- No modification of script behavior - logging is completely transparent

### Log File Format
- **File naming**: `{script_name}_{timestamp}_{process_id}.log`
- **Example**: `rtStatus_20250529_025139_8043.log`
- **Location**: `/usr/local/openRT/logs/`

### Log Content
Each log file contains:
- **Script startup information**: timestamp, process ID, script location, working directory, user ID, command line arguments
- **Detailed operation logs**: All major operations with timestamps and log levels
- **Error and warning tracking**: Comprehensive error logging with context
- **Script completion**: Final completion timestamp

### Log Levels
- **INFO**: General operational information
- **WARN**: Warning conditions that don't prevent execution
- **ERROR**: Error conditions with detailed context
- **DEBUG**: Detailed debugging information

## Modified Scripts

The following scripts now include logging functionality:
- `rtAutoMount.pl`
- `rtFileMount.pl`
- `rtImport.pl`
- `rtMetadata.pl`
- `rtStatus.pl`

## Usage

### Enable Logging
```bash
# Create the logs directory to enable logging
sudo mkdir -p /usr/local/openRT/logs
```

### Disable Logging
```bash
# Remove or rename the logs directory to disable logging
sudo mv /usr/local/openRT/logs /usr/local/openRT/logs_disabled
```

### View Logs
```bash
# View latest log for a specific script
ls -t /usr/local/openRT/logs/rtStatus_* | head -1 | xargs cat

# Monitor real-time logging
tail -f /usr/local/openRT/logs/rtStatus_*.log

# View all logs for today
ls /usr/local/openRT/logs/*$(date +%Y%m%d)*.log
```

## Log Examples

### Startup Information
```
[2025-05-29 02:51:39] [INFO] === Starting rtStatus at 2025-05-29 02:51:39 ===
[2025-05-29 02:51:39] [INFO] Process ID: 8043
[2025-05-29 02:51:39] [INFO] Script location: /usr/local/openRT/openRTApp/rtStatus.pl
[2025-05-29 02:51:39] [INFO] Working directory: /usr/local/openRT/openRTApp
[2025-05-29 02:51:39] [INFO] User ID: 1000
[2025-05-29 02:51:39] [INFO] Command line: -j
```

### Operation Logging
```
[2025-05-29 02:51:39] [INFO] Checking connected drives
[2025-05-29 02:51:39] [INFO] Found 17 total drives/devices
[2025-05-29 02:51:39] [INFO] Drive check complete - Has extra drives: yes
```

### Error Logging
```
[2025-05-29 02:51:39] [ERROR] Pool specified in RT_POOL_NAME (mypool) not found
```

### Completion
```
[2025-05-29 02:51:39] [INFO] === Script completed at 2025-05-29 02:51:39 ===
```

## Standalone Operation

All scripts remain fully standalone and do not require external logging libraries or configurations. The logging functionality is self-contained within each script and does not depend on other files or modules.

## Benefits

1. **Troubleshooting**: Detailed logs help identify issues quickly
2. **Audit Trail**: Complete record of all operations and their outcomes
3. **Performance Monitoring**: Track execution times and system state
4. **Error Analysis**: Comprehensive error context for debugging
5. **Optional**: Logging can be easily enabled/disabled without script changes
6. **Zero Impact**: When disabled, there's no performance impact on script execution

## Log Retention

Log files are not automatically cleaned up. Consider implementing log rotation or cleanup based on your requirements:

```bash
# Example: Remove logs older than 30 days
find /usr/local/openRT/logs -name "*.log" -mtime +30 -delete
``` 