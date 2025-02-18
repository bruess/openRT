<!DOCTYPE html>
<html lang="en">
<head>
    <?php
        $server_ip = trim(shell_exec('hostname -I | awk \'{print $1}\''));
    ?>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenRT Explorer</title>
    <!-- Local Bootstrap 5 CSS -->
    <link href="assets/bootstrap/bootstrap.min.css" rel="stylesheet">
    <!-- D-Din Font -->
    <link href="assets/fonts/fonts.css" rel="stylesheet">
    <style>
        body {
            font-family: 'D-DIN', sans-serif;
            background-color: #212529;
            color: #fff;
        }
        .logo {
            max-height: 50px;
            margin: 10px;
        }
        .metadata-table {
            margin-top: 20px;
        }
        .navbar {
            background-color: #1a1d20;
            color: white;
            border-bottom: 1px solid #2c3238;
        }
        .navbar-brand {
            color: white !important;
        }
        .card {
            background-color: #2c3238;
            border-color: #373d44;
        }
        .card-header {
            background-color: #373d44;
            color: #fff;
            border-bottom-color: #2c3238;
        }
        /* Table styling to match index.php */
        .table {
            color: #fff !important;
            border-color: #373d44;
        }
        .table > thead > tr > th {
            background-color: #1a1d20 !important;
            color: #fff !important;
            border-bottom-color: #373d44;
            font-weight: 600;
        }
        .table > tbody > tr:nth-of-type(odd) > * {
            background-color: #343a40 !important;
            color: #fff !important;
            border-bottom-color: #373d44;
        }
        .table > tbody > tr:nth-of-type(even) > * {
            background-color: #2c3238 !important;
            color: #fff !important;
            border-bottom-color: #373d44;
        }
        .table > tbody > tr > td {
            border-color: #373d44;
        }
        .text-muted {
            color: #adb5bd !important;
        }
        .back-button {
            background-color: #0d6efd;
            color: white;
            text-decoration: none;
            padding: 0.5rem 1rem;
            border-radius: 0.375rem;
            transition: background-color 0.2s;
        }
        .back-button:hover {
            background-color: #0b5ed7;
            color: white;
        }
        .loading-spinner {
            width: 3rem;
            height: 3rem;
        }
        .agent-count {
            font-size: 0.875rem;
            color: #adb5bd;
        }
        code {
            color: #ffffff !important;
            background-color: #1a1d20;
            padding: 0.2rem 0.4rem;
            border-radius: 0.25rem;
            font-size: 0.875em;
            word-break: break-all;
        }
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container-fluid">
            <div class="d-flex align-items-center">
                <a href="index.php" class="back-button me-3">
                    <i class="fas fa-arrow-left"></i> Back
                </a>
                <button class="btn btn-light me-2" data-bs-toggle="modal" data-bs-target="#connectModal">
                    <i class="fas fa-network-wired"></i> SMB/NFS/FTP
                </button>
                <span class="navbar-brand"></span>
            </div>
            <span class="navbar-text fw-bold" style="position: absolute; left: 50%; transform: translateX(-50%); color: white;">
                http://<?php echo $server_ip; ?>
                <br>
                <small class="text-muted">explorer: <?php echo trim(file_get_contents('/usr/local/openRT/status/explorer')); ?></small>
            </span>
            <img src="assets/images/openRT.png" alt="OpenRT Logo" class="logo">
        </div>
    </nav>

    <!-- Connection Modal -->
    <div class="modal fade" id="connectModal" tabindex="-1" aria-labelledby="connectModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-fullscreen">
            <div class="modal-content bg-dark text-light">
                <div class="modal-header border-secondary">
                    <h5 class="modal-title" id="connectModalLabel">Connection Details</h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="container-fluid">
                        <div class="row justify-content-center">
                            <div class="col-md-4">
                                <div class="card bg-secondary mb-3">
                                    <div class="card-header">
                                        <h6 class="mb-0">SMB Connection</h6>
                                    </div>
                                    <div class="card-body">
                                        <p><strong>Path:</strong><br><code>\\<?php echo $server_ip; ?>\</code></p>
                                        <p><strong>Username:</strong><br><code>explorer</code></p>
                                        <p><strong>Password:</strong><br><code><?php echo trim(file_get_contents('/usr/local/openRT/status/explorer')); ?></code></p>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-4">
                                <div class="card bg-secondary mb-3">
                                    <div class="card-header">
                                        <h6 class="mb-0">NFS Connection</h6>
                                    </div>
                                    <div class="card-body">
                                        <p><strong>Path:</strong><br><code><?php echo $server_ip; ?>:/</code></p>
                                        <p><strong>Mount Command:</strong><br><code>mount -t nfs <?php echo $server_ip; ?>:/ /mnt/openRT</code></p>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-4">
                                <div class="card bg-secondary mb-3">
                                    <div class="card-header">
                                        <h6 class="mb-0">FTP Connection</h6>
                                    </div>
                                    <div class="card-body">
                                        <p><strong>Host:</strong><br><code>ftp://<?php echo $server_ip; ?></code></p>
                                        <p><strong>Username:</strong><br><code>explorer</code></p>
                                        <p><strong>Password:</strong><br><code><?php echo trim(file_get_contents('/usr/local/openRT/status/explorer')); ?></code></p>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="row justify-content-center">
                            <div class="col-md-12 text-center">
                                <div class="mt-3">
                                    <h6>Quick Connection Guide:</h6>
                                    <ul class="list-unstyled">
                                        <li class="mb-2"><strong>Windows:</strong> Use File Explorer → Map Network Drive (SMB) or enable NFS Client</li>
                                        <li class="mb-2"><strong>Mac:</strong> Finder → Go → Connect to Server (⌘K) for SMB or mount NFS</li>
                                        <li class="mb-2"><strong>Linux:</strong> Mount using SMB/CIFS, NFS, or use any FTP client</li>
                                    </ul>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="container-fluid mt-4">
        <div class="row">
            <div class="col">
                <div class="card">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        Agent Metadata
                        <div class="d-flex align-items-center">
                            <span class="agent-count me-3" id="agent-count"></span>
                            <small class="text-muted me-3" id="last-updated"></small>
                            <button class="btn btn-sm btn-outline-light me-2" onclick="unmountAll()">
                                <img src="assets/images/spinner.svg" alt="Loading" class="spinner d-none" style="width: 1rem; height: 1rem;">
                                <span class="button-text">Unmount All</span>
                            </button>
                            <button class="btn btn-sm btn-outline-light" onclick="updateMetadata()">
                                <img src="assets/images/spinner.svg" alt="Loading" class="spinner d-none" style="width: 1rem; height: 1rem;">
                                <span class="button-text">Refresh</span>
                            </button>
                        </div>
                    </div>
                    <div class="card-body">
                        <div id="loading" class="text-center py-5">
                            <img src="assets/images/spinner.svg" alt="Loading" class="loading-spinner">
                            <p class="mt-3">Loading metadata...</p>
                        </div>
                        <div id="table-container" style="display: none;">
                            <table class="table table-hover metadata-table">
                                <thead>
                                    <tr>
                                        <th>Hostname</th>
                                        <th>IP Address</th>
                                        <th>Operating System</th>
                                        <th>Storage</th>
                                        <th>Snapshots</th>
                                        <th>Actions</th>
                                    </tr>
                                </thead>
                                <tbody id="metadata-content">
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Local JavaScript dependencies -->
    <script src="assets/bootstrap/bootstrap.bundle.min.js"></script>
    <script>
        const SERVER_IP = '<?php echo $server_ip; ?>';
        
        function formatTimestamp(timestamp) {
            if (!timestamp) return 'Never';
            const date = new Date(timestamp * 1000);
            return date.toLocaleString();
        }

        async function unmountAll() {
            const button = document.querySelector('button[onclick="unmountAll()"]');
            const spinner = button.querySelector('.spinner');
            const buttonText = button.querySelector('.button-text');

            // Show loading state
            spinner.classList.remove('d-none');
            buttonText.classList.add('d-none');
            button.disabled = true;

            try {
                const response = await fetch('unmount_all.php');
                const result = await response.json();
                
                // Check both possible success indicators
                const isSuccess = result.success || result.status === "success";
                
                if (isSuccess) {
                    // Show success state briefly
                    buttonText.textContent = 'Unmounted!';
                    buttonText.classList.remove('d-none');
                    button.classList.remove('btn-outline-light');
                    button.classList.add('btn-success');
                    
                    // Show number of items cleaned if available
                    if (result.cleaned && result.cleaned.length > 0) {
                        console.log('Cleaned items:', result.cleaned);
                    }
                    
                    // Refresh the metadata to update the UI
                    setTimeout(() => {
                        updateMetadata();
                    }, 1000);
                    
                    // Reset button after 2 seconds
                    setTimeout(() => {
                        buttonText.textContent = 'Unmount All';
                        button.classList.remove('btn-success');
                        button.classList.add('btn-outline-light');
                        button.disabled = false;
                    }, 2000);
                } else {
                    // Show error state
                    buttonText.textContent = 'Failed';
                    buttonText.classList.remove('d-none');
                    button.classList.remove('btn-outline-light');
                    button.classList.add('btn-danger');
                    console.error('Unmount failed:', result.error || result.message || 'Unknown error');
                    
                    // Reset button after 2 seconds
                    setTimeout(() => {
                        buttonText.textContent = 'Unmount All';
                        button.classList.remove('btn-danger');
                        button.classList.add('btn-outline-light');
                        button.disabled = false;
                    }, 2000);
                }
            } catch (error) {
                // Show error state
                buttonText.textContent = 'Error';
                buttonText.classList.remove('d-none');
                button.classList.remove('btn-outline-light');
                button.classList.add('btn-danger');
                console.error('Unmount error:', error);
                
                // Reset button after 2 seconds
                setTimeout(() => {
                    buttonText.textContent = 'Unmount All';
                    button.classList.remove('btn-danger');
                    button.classList.add('btn-outline-light');
                    button.disabled = false;
                }, 2000);
            } finally {
                spinner.classList.add('d-none');
            }
        }

        // Add mount functionality
        async function mountAgent(agentId) {
            const button = document.querySelector(`button[data-agent-id="${agentId}"]`);
            const spinner = button.querySelector('.spinner');
            const buttonText = button.querySelector('.button-text');

            // Show loading state
            spinner.classList.remove('d-none');
            buttonText.classList.add('d-none');
            button.disabled = true;

            try {
                const formData = new FormData();
                formData.append('agent_id', agentId);

                const response = await fetch('mount_agent.php', {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();
                
                if (result.success || (result.status === "success" && result.mounts && result.mounts.length > 0)) {
                    // Show success state briefly
                    buttonText.textContent = 'Mounted!';
                    buttonText.classList.remove('d-none');
                    button.classList.remove('btn-primary');
                    button.classList.add('btn-success');
                    
                    // After 1 second, replace with Explore button
                    setTimeout(() => {
                        // Create new explore button
                        const td = button.parentElement;
                        const exploreButton = document.createElement('a');
                        exploreButton.href = `http://${SERVER_IP}/files/${agentId}/`;
                        exploreButton.className = 'btn btn-sm btn-info';
                        exploreButton.innerHTML = `
                            <img src="assets/images/spinner.svg" alt="Loading" class="spinner d-none" style="width: 1rem; height: 1rem;">
                            <span class="button-text">Explore Files</span>
                        `;
                        
                        // Replace mount button with explore button
                        td.replaceChild(exploreButton, button);
                    }, 1000);
                } else {
                    // Show error state
                    buttonText.textContent = 'Failed';
                    buttonText.classList.remove('d-none');
                    button.classList.remove('btn-primary');
                    button.classList.add('btn-danger');
                    console.error('Mount failed:', result.error || result.message || 'Unknown error');
                    
                    // Reset button after 2 seconds
                    setTimeout(() => {
                        buttonText.textContent = 'Mount All';
                        button.classList.remove('btn-danger');
                        button.classList.add('btn-primary');
                        button.disabled = false;
                    }, 2000);
                }
            } catch (error) {
                // Show error state
                buttonText.textContent = 'Error';
                buttonText.classList.remove('d-none');
                button.classList.remove('btn-primary');
                button.classList.add('btn-danger');
                console.error('Mount error:', error);
                
                // Reset button after 2 seconds
                setTimeout(() => {
                    buttonText.textContent = 'Mount All';
                    button.classList.remove('btn-danger');
                    button.classList.add('btn-primary');
                    button.disabled = false;
                }, 2000);
            } finally {
                spinner.classList.add('d-none');
            }
        }

        // Function to check if an agent is mounted
        async function checkMountStatus(agentId) {
            try {
                const response = await fetch(`check_mount.php?agent_id=${encodeURIComponent(agentId)}`);
                const result = await response.json();
                
                // If the check was successful, return the mounted status
                if (result.success) {
                    return result.mounted;
                }
                
                // If there was an error, log it and assume not mounted
                console.error('Error in mount status response:', result.error || 'Unknown error');
                return false;
            } catch (error) {
                console.error('Error checking mount status:', error);
                return false;
            }
        }

        // Update the metadata function to check mount status
        function updateMetadata() {
            const refreshButton = document.querySelector('.btn-outline-light');
            const spinner = refreshButton.querySelector('.spinner');
            const buttonText = refreshButton.querySelector('.button-text');

            // Show loading state
            document.getElementById('loading').style.display = 'block';
            document.getElementById('table-container').style.display = 'none';
            spinner.classList.remove('d-none');
            buttonText.classList.add('d-none');
            refreshButton.disabled = true;

            fetch('get_metadata.php')
                .then(response => response.json())
                .then(async data => {
                    const metadataContent = document.getElementById('metadata-content');
                    const lastUpdated = document.getElementById('last-updated');
                    const agentCount = document.getElementById('agent-count');
                    
                    // Update timestamp and agent count
                    lastUpdated.textContent = `Last updated: ${formatTimestamp(data.timestamp)}`;
                    agentCount.textContent = `${data.agent_count} Agent${data.agent_count !== 1 ? 's' : ''}`;
                    
                    // Clear existing content
                    metadataContent.innerHTML = '';
                    
                    // Convert agents object to array and sort by hostname
                    const agents = Object.entries(data.agents)
                        .filter(([id, info]) => {
                            // Convert snapshot_count to number and check if greater than 0
                            const snapshotCount = parseInt(info.snapshot_count || 0);
                            return snapshotCount > 0;
                        })
                        .sort(([, a], [, b]) => {
                            const hostnameA = (a.hostname || '').toLowerCase();
                            const hostnameB = (b.hostname || '').toLowerCase();
                            return hostnameA.localeCompare(hostnameB);
                        });
                    
                    // Update agent count to reflect only visible agents
                    agentCount.textContent = `${agents.length} Agent${agents.length !== 1 ? 's' : ''}`;
                    
                    // Add each agent to the table
                    for (const [agentId, info] of agents) {
                        const row = document.createElement('tr');
                        
                        // Format storage info with better readability
                        const storageInfo = [];
                        if (info.Volumes) {
                            Object.entries(info.Volumes).forEach(([mount, vol]) => {
                                // Skip Recovery volumes
                                if (mount.toLowerCase() === 'recovery' || mount.toLowerCase().includes('recovery')) {
                                    return;
                                }
                                
                                const totalGB = Math.round(parseInt(vol.capacity) / (1024 * 1024 * 1024));
                                const usedGB = Math.round(parseInt(vol.used) / (1024 * 1024 * 1024));
                                const usedPercent = Math.round((usedGB / totalGB) * 100);
                                const usageClass = usedPercent > 90 ? 'text-danger' : usedPercent > 70 ? 'text-warning' : 'text-success';
                                storageInfo.push(`
                                    <span class="${usageClass}" 
                                          data-bs-toggle="tooltip" 
                                          data-bs-placement="top" 
                                          title="Used: ${usedGB}GB / ${totalGB}GB (${usedPercent}%)"
                                    >${mount}</span>
                                `);
                            });
                        }

                        // Check if agent is mounted
                        const isMounted = await checkMountStatus(agentId);
                        const actionButton = isMounted ? 
                            `<a href="http://${SERVER_IP}/files/${agentId}/" class="btn btn-sm btn-info">
                                <img src="assets/images/spinner.svg" alt="Loading" class="spinner d-none" style="width: 1rem; height: 1rem;">
                                <span class="button-text">Explore Files</span>
                            </a>` :
                            `<button class="btn btn-sm btn-primary mount-button" 
                                    onclick="mountAgent('${agentId}')"
                                    data-agent-id="${agentId}">
                                <img src="assets/images/spinner.svg" alt="Loading" class="spinner d-none" style="width: 1rem; height: 1rem;">
                                <span class="button-text">Mount All</span>
                            </button>`;

                        row.innerHTML = `
                            <td>${info.hostname || 'Unknown'}</td>
                            <td>${info.fqdn || info.name || 'Unknown'}</td>
                            <td>${(info.os || '').split(/\s+\d/).shift() || 'Unknown'}</td>
                            <td>${storageInfo.join(', ') || 'No storage information'}</td>
                            <td>${info.snapshot_count || 0}</td>
                            <td>${actionButton}</td>
                        `;
                        metadataContent.appendChild(row);
                    }

                    // Initialize tooltips
                    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
                    tooltipTriggerList.map(function (tooltipTriggerEl) {
                        return new bootstrap.Tooltip(tooltipTriggerEl);
                    });

                    // Hide loading spinner and show table
                    document.getElementById('loading').style.display = 'none';
                    document.getElementById('table-container').style.display = 'block';
                })
                .catch(error => {
                    console.error('Error fetching metadata:', error);
                    document.getElementById('loading').innerHTML = `
                        <p class="text-danger">Error loading metadata. Please try again later.</p>
                    `;
                })
                .finally(() => {
                    // Reset refresh button state
                    spinner.classList.add('d-none');
                    buttonText.classList.remove('d-none');
                    refreshButton.disabled = false;
                });
        }

        // Load metadata once on page load
        updateMetadata();
    </script>
</body>
</html> 