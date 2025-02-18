# openRT

OpenRT is an open-source system for mounting and managing backup volumes from various vendors. It provides a web-based interface for easy management and automation of backup volume mounting operations.

## Features

- **Web Interface**: Modern, responsive web UI for managing backup volumes
- **Automated Mounting**: Support for automatic mounting of backup volumes
- **Multi-vendor Support**: Compatible with various backup vendor formats
- **ZFS Integration**: Efficient handling of backup volumes using ZFS clones
- **VMDK Generation**: Automatic creation of VMDK descriptors for VM import
- **Security**: Built-in user management and secure mounting operations

## System Requirements

- Ubuntu Server 22.04 LTS
- Root/sudo privileges
- Minimum 4GB RAM (8GB recommended)
- 12GB+ available storage space
- Network connectivity

## Installation

To install openRT on a fresh Ubuntu 22.04 Server, run:

```bash
curl -sSL https://github.com/amcchord/openRT/raw/refs/heads/main/install.sh | sudo bash
```

The installation process:

1. Checks and installs required dependencies
2. Creates necessary system directories
3. Sets up the openRT user and required permissions
4. Configures system services
5. Installs and configures:
   - Web server components
   - ZFS utilities
   - Mounting utilities
   - System monitoring services
6. Sets up automatic updates
7. Configures the web interface

## Directory Structure

```
/usr/local/openRT/
├── config/         # Configuration files
├── status/         # System status and monitoring
├── logs/          # Application logs
├── web/           # Web interface files
└── openRTApp/     # Core application scripts
```

## Mount Points

```
/rtMount/
├── [agent_name]/           # Agent-specific directory
│   └── [snapshot_date]/   # Snapshot-specific directory
│       └── [volume_name]/ # Individual volume mount points
└── zfs_block/            # Temporary ZFS clone mount points
```

## Usage

After installation:

1. Access the web interface at `http://<server-ip>`
2. Use the interface to:
   - Import backup volumes
   - Mount/unmount volumes
   - Configure automount settings
   - Monitor system status
   - Export backup pools
   - Explore mounted volumes

## Command Line Tools

OpenRT provides several command-line utilities in `/usr/local/openRT/openRTApp/`:

- `rtFileMount.pl`: Mount backup volumes
- `rtAutoMount.pl`: Configure automatic mounting
- `rtStatus.pl`: Check system status
- `rtMetadata.pl`: Manage backup metadata
- `rtImport.pl`: Import backup volumes

## Automatic Updates

The system is configured to automatically check for and apply updates from the GitHub repository. This ensures you always have the latest features and security updates.

## Support

For issues, feature requests, or contributions, please visit the GitHub repository.

## License

MIT License

Copyright (c) 2024 

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
