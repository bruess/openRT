# openRTApp - RoundTrip Drive Management Tools

A collection of Perl scripts for managing RoundTrip drives and accessing their data.

## Scripts

- **rtStatus.pl** - Checks the status of RoundTrip drives
- **rtMetadata.pl** - Extracts metadata from the drive
- **rtFileMount.pl** - Mounts agent data for file access
- **rtImport.pl** - Handles importing and exporting ZFS pools

## Pool Name Support

By default, the scripts look for pools matching these patterns:
- `rtPool-\d+` (e.g., rtPool-123)
- `revRT*` (e.g., revRT-456)

You can customize pool detection using environment variables:

### Environment Variables

- `RT_POOL_NAME` - Exact pool name to use (highest priority)
- `RT_POOL_PATTERN` - Custom regex pattern to match pool names
- `RT_AGENTS_PATH` - Custom path to agents directory (defaults to "home/agents")
- `RT_EXPORT_ALL` - When set, export all pools, not just RT pools

### Examples

```bash
# Use a specific pool name
export RT_POOL_NAME="customPool"
perl rtMetadata.pl

# Match pools with a custom pattern
export RT_POOL_PATTERN="^backup.*"
perl rtMetadata.pl

# Specify a custom agents path
export RT_AGENTS_PATH="data/agents"
perl rtFileMount.pl agent1

# Export all pools, not just RT pools
export RT_EXPORT_ALL=1
perl rtImport.pl export
```

## Usage Examples

### Check Drive Status
```bash
perl rtStatus.pl         # Simple status output
perl rtStatus.pl -j      # JSON output
```

### Extract Metadata
```bash
perl rtMetadata.pl       # Standard output
perl rtMetadata.pl -j    # JSON output only
```

### Mount Agent Files
```bash
perl rtFileMount.pl agent_name              # Mount the latest snapshot
perl rtFileMount.pl agent_name 1609459200   # Mount snapshot closest to epoch
perl rtFileMount.pl agent_name all          # Mount all snapshots
perl rtFileMount.pl -cleanup                # Clean up all mounts
```

### Import/Export Pools
```bash
perl rtImport.pl import                 # Auto-detect and import all available pools
perl rtImport.pl import /dev/sdb        # Import pool from specific device
perl rtImport.pl export                 # Export all pools
perl rtImport.pl export /dev/sdb        # Export pool on specific device
```

## Requirements

- Perl 5.10 or higher
- ZFS utilities installed
- Root/sudo access required

#Version Information
VER 1.1