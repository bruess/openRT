# openRT

OpenRT is an open-source system for mounting and managing backup volumes from various vendors (Currently only tested with Datto and RevRT). It provides a web-based interface for easy management and automation of backup volume mounting operations.

## What's New in v1.2

- **Enhanced Logging**: Comprehensive logging system for better troubleshooting and monitoring
- **Web-based Log Viewer**: Built-in log viewer in the web interface for easy access to system logs
- **RevRT Support**: Added support for RevRT pool and metadata formats
- **Improved Reliability**: Enhanced robustness in OpenRTApp Perl scripts for better error handling

## Features

- **Web Interface**: Modern, responsive web UI for managing backup volumes
- **Automated Mounting**: Support for automatic mounting of backup volumes
- **Multi-vendor Support**: Compatible with various backup vendor formats (Datto, RevRT)
- **ZFS Integration**: Efficient handling of backup volumes using ZFS clones
- **VMDK Generation**: Automatic creation of VMDK descriptors for VM import
- **Security**: Built-in user management and secure mounting operations
- **Comprehensive Logging**: Detailed logging with web-based log viewer for monitoring and troubleshooting

## System Requirements

- Ubuntu Server 22.04 LTS
- Root/sudo privileges
- Minimum 4GB RAM (8GB recommended)
- 12GB+ available storage space
- Network connectivity

## ⚠️ Important Disclaimer

**THIS SOFTWARE IS INTENDED FOR LAB/TEST ENVIRONMENTS ONLY**

This tool is designed for accessing and examining backup data in controlled environments. It is NOT meant to be:
- Deployed as a public-facing server
- Used in production environments
- Exposed to the internet
- Used as a permanent running system

Please ensure this system is deployed only in isolated lab/test environments with appropriate security controls in place.

## Download Pre-built Image

The easiest way to install openRT is to download the pre-built image from the releases page. These are bootable in VirtualBox and VMWare and Hyper-V.

[Download for x86_64](https://www.slide.recipes/openRT/OpenRT-x86VM.zip)

[Download for Arm64](https://www.slide.recipes/openRT/OpenRT-Arm64VM.zip)


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


## Screenshots
<img width="300" alt="Screenshot 2025-02-18 at 10 46 16 AM" src="https://github.com/user-attachments/assets/2516ba68-4826-45f8-a273-3c51f4ba96ed" />
<img width="300" alt="Screenshot 2025-02-18 at 10 46 24 AM" src="https://github.com/user-attachments/assets/7a14e570-9a2d-4c8e-a0ac-249c81604ada" />
<img width="300" alt="Screenshot 2025-02-18 at 11 06 46 AM" src="https://github.com/user-attachments/assets/0a165195-6a6b-4605-b47a-dbb6f3a8fc95" />
<img width="300" alt="Screenshot 2025-02-18 at 11 06 59 AM" src="https://github.com/user-attachments/assets/d779774f-4097-4c96-a01a-33af40aba3cb" />

## Demo Video
https://github.com/user-attachments/assets/83ed608c-4cb5-4de2-9e44-deba69126fbd




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
   - View system logs and troubleshoot issues

## Command Line Tools

OpenRT provides several command-line utilities in `/usr/local/openRT/openRTApp/` with enhanced robustness and error handling:

- `rtFileMount.pl`: Mount backup volumes
- `rtAutoMount.pl`: Configure automatic mounting
- `rtStatus.pl`: Check system status
- `rtMetadata.pl`: Manage backup metadata
- `rtImport.pl`: Import backup volumes

*Note: All Perl scripts have been enhanced in v1.2 with improved error handling and robustness for better reliability.*

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
