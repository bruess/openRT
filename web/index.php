<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenRT Status</title>
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
        .status-table {
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
        /* More specific table styling to override Bootstrap */
        .table.table-striped {
            color: #fff !important;
            border-color: #373d44;
        }
        .table.table-striped > tbody > tr:nth-of-type(odd) > * {
            background-color: #343a40 !important;
            color: #fff !important;
            border-bottom-color: #373d44;
        }
        .table.table-striped > tbody > tr:nth-of-type(even) > * {
            background-color: #2c3238 !important;
            color: #fff !important;
            border-bottom-color: #373d44;
        }
        .table.table-striped > tbody > tr > td {
            border-color: #373d44;
        }
        .text-muted {
            color: #adb5bd !important;
        }
        .import-button {
            background-color: #0d6efd;
            color: white;
            border: none;
            padding: 1rem 2rem;
            font-size: 1.25rem;
            border-radius: 0.5rem;
            cursor: pointer;
            transition: background-color 0.2s;
            width: 100%;
            margin-top: 1rem;
            display: none; /* Hidden by default */
        }
        .import-button:hover {
            background-color: #0b5ed7;
        }
        .import-button:disabled {
            background-color: #0d6efd;
            opacity: 0.65;
            cursor: not-allowed;
        }
        .import-button .spinner,
        .import-button .check,
        .action-button .spinner,
        .action-button .check {
            display: none;
            width: 1.5rem;
            height: 1.5rem;
            vertical-align: middle;
            margin-right: 0.5rem;
        }
        .import-button.loading .spinner,
        .action-button.loading .spinner {
            display: inline-block;
        }
        .import-button.success .check,
        .action-button.success .check {
            display: inline-block;
        }
        .import-button.loading .button-text,
        .import-button.success .button-text,
        .action-button.loading .button-text,
        .action-button.success .button-text {
            display: none;
        }
        .button-container {
            margin-top: 1rem;
            display: flex;
            gap: 1rem;
        }
        .action-button {
            flex: 1;
            padding: 1rem 2rem;
            font-size: 1.25rem;
            border-radius: 0.5rem;
            cursor: pointer;
            transition: background-color 0.2s;
            border: none;
            color: white;
            display: none; /* Hidden by default */
        }
        .export-button {
            background-color: #dc3545;
        }
        .export-button:hover {
            background-color: #bb2d3b;
        }
        .explore-button {
            background-color: #0d6efd;
        }
        .explore-button:hover {
            background-color: #0b5ed7;
        }
        .action-button.loading .spinner {
            display: inline-block;
        }
        .action-button.success .check {
            display: inline-block;
        }
        .action-button.loading .button-text,
        .action-button.success .button-text {
            display: none;
        }
        .container {
            padding-bottom: 70px; /* Add padding to prevent overlap with footer */
        }
        .form-check-input {
            background-color: #373d44;
            border-color: #495057;
        }
        .form-check-input:checked {
            background-color: #0d6efd;
            border-color: #0d6efd;
        }
        .form-check-input:focus {
            border-color: #0d6efd;
            box-shadow: 0 0 0 0.25rem rgba(13, 110, 253, 0.25);
        }
        #automountProgress {
            display: none;
            position: fixed;
            bottom: 70px;
            left: 0;
            right: 0;
            background: rgba(26, 29, 32, 0.95);
            border-top: 1px solid #2c3238;
            padding: 1rem;
        }
        #automountProgress .progress {
            background-color: #373d44;
        }
        #automountDetails {
            max-height: 200px;
            overflow-y: auto;
            margin-top: 1rem;
            padding: 1rem;
            background-color: #2c3238;
            border-radius: 0.375rem;
            font-family: monospace;
            font-size: 0.875rem;
        }
        #automountDetails .detail-item {
            margin-bottom: 0.5rem;
            border-bottom: 1px solid #373d44;
            padding-bottom: 0.5rem;
        }
        #automountDetails .detail-item:last-child {
            margin-bottom: 0;
            border-bottom: none;
            padding-bottom: 0;
        }
        #automountDetails .detail-time {
            color: #6c757d;
            margin-right: 0.5rem;
        }
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container-fluid">
            <span class="navbar-brand">OpenRT</span>
            <span class="navbar-text fw-bold" style="position: absolute; left: 50%; transform: translateX(-50%); color: white;">
                http://<?php echo trim(shell_exec('hostname -I | awk \'{print $1}\'')); ?>
                     <br>
            <small class="text-muted">explorer: <?php echo trim(file_get_contents('/usr/local/openRT/status/explorer')); ?></small>
            </span>   
            <img src="assets/images/openRT.png" alt="OpenRT Logo" class="logo">
        </div>
    </nav>

    <div class="container mt-4">
        <div class="row">
            <div class="col">
                <div class="card">
                    <div class="card-header">
                        System Status
                        <small class="text-muted float-end" id="last-updated"></small>
                    </div>
                    <div class="card-body">
                        <table class="table table-striped status-table">
                            <tbody id="status-content">
                            </tbody>
                        </table>
                    </div>
                </div>
                <div class="button-container">
                    <button id="importButton" class="import-button">
                        <img src="assets/images/spinner.svg" alt="Loading" class="spinner">
                        <img src="assets/images/check.svg" alt="Success" class="check">
                        <span class="button-text">Import</span>
                    </button>
                    <button id="exportButton" class="action-button export-button">
                        <img src="assets/images/spinner.svg" alt="Loading" class="spinner">
                        <img src="assets/images/check.svg" alt="Success" class="check">
                        <span class="button-text">Export Pool</span>
                    </button>
                    <a href="explore.php" id="exploreButton" class="action-button explore-button text-decoration-none text-center">Explore</a>
                </div>
            </div>
        </div>
    </div>

    <footer class="fixed-bottom py-3" style="background-color: #1a1d20; border-top: 1px solid #2c3238;">
        <div id="automountProgress">
            <div class="container">
                <div class="d-flex justify-content-between align-items-center mb-2">
                    <h6 class="mb-0 text-white">Automount Progress</h6>
                    <span class="text-white" id="automountStep"></span>
                </div>
                <div class="progress">
                    <div class="progress-bar progress-bar-striped progress-bar-animated" role="progressbar" style="width: 0%"></div>
                </div>
                <div id="automountDetails"></div>
            </div>
        </div>
        <div class="container">
            <div class="d-flex justify-content-end align-items-center">
                <div class="form-check form-switch mb-0">
                    <input class="form-check-input" type="checkbox" id="automountToggle">
                    <label class="form-check-label text-white" for="automountToggle">Automount</label>
                </div>
            </div>
        </div>
    </footer>

    <!-- Local JavaScript dependencies -->
    <script src="assets/bootstrap/bootstrap.bundle.min.js"></script>
    <script>
        const importButton = document.getElementById('importButton');
        const exportButton = document.getElementById('exportButton');

        function showImportButton(show) {
            importButton.style.display = show ? 'block' : 'none';
        }

        function showActionButtons(show) {
            document.getElementById('exportButton').style.display = show ? 'block' : 'none';
            document.getElementById('exploreButton').style.display = show ? 'block' : 'none';
        }

        function setButtonState(button, state) {
            button.classList.remove('loading', 'success');
            if (state === 'loading') {
                button.classList.add('loading');
                button.disabled = true;
            } else if (state === 'success') {
                button.classList.add('success');
                button.disabled = true;
                // Refresh status after 2 seconds
                setTimeout(() => {
                    updateStatus();
                    button.disabled = false;
                    button.classList.remove('success');
                }, 2000);
            } else {
                button.disabled = false;
            }
        }

        importButton.addEventListener('click', async () => {
            setButtonState(importButton, 'loading');
            try {
                const response = await fetch('import_pool.php?action=import');
                const result = await response.json();
                
                if (result.success) {
                    setButtonState(importButton, 'success');
                } else {
                    setButtonState(importButton, 'error');
                    console.error('Import failed:', result.error);
                }
            } catch (error) {
                setButtonState(importButton, 'error');
                console.error('Import error:', error);
            }
        });

        exportButton.addEventListener('click', async () => {
            setButtonState(exportButton, 'loading');
            try {
                const response = await fetch('import_pool.php?action=export');
                const result = await response.json();
                
                if (result.success) {
                    setButtonState(exportButton, 'success');
                } else {
                    setButtonState(exportButton, 'error');
                    console.error('Export failed:', result.error);
                }
            } catch (error) {
                setButtonState(exportButton, 'error');
                console.error('Export error:', error);
            }
        });

        function updateStatus() {
            fetch('get_status.php')
                .then(response => response.json())
                .then(data => {
                    const statusContent = document.getElementById('status-content');
                    const lastUpdated = document.getElementById('last-updated');
                    
                    // Show/hide buttons based on status
                    const shouldShowButtons = data.status !== 'Not Available';
                    const hasImportedPool = data.status !== 'Available';
                    
                    // Hide all buttons if status is Not Available
                    if (!shouldShowButtons) {
                        showImportButton(false);
                        showActionButtons(false);
                    } else {
                        showImportButton(!hasImportedPool);
                        showActionButtons(hasImportedPool);
                    }
                    
                    // Clear existing content
                    statusContent.innerHTML = '';
                    
                    // Update timestamp
                    lastUpdated.textContent = `Last updated: ${data.timestamp}`;
                    
                    // Define the keys we want to show and their order
                    const desiredKeys = ['status', 'available_pools', 'drives'];
                    
                    // Filter and sort entries based on our desired keys
                    const filteredEntries = desiredKeys
                        .map(key => [key, data[key]])
                        .filter(([key]) => key in data);
                    
                    // Add each property to the table
                    for (const [key, value] of filteredEntries) {
                        const row = document.createElement('tr');
                        
                        // Format the key
                        const formattedKey = key.replace(/_/g, ' ')
                                              .split(' ')
                                              .map(word => word.charAt(0).toUpperCase() + word.slice(1))
                                              .join(' ');
                        
                        // Format the value based on its type
                        let formattedValue = value;
                        if (key === 'available_pools') {
                            formattedValue = value.length > 0 
                                ? value.map(pool => `${pool.name} (${pool.state})`).join('<br>')
                                : 'None';
                        } else if (key === 'drives') {
                            formattedValue = value.length > 0
                                ? value.map(drive => `${drive.name} (${drive.type}, ${drive.size})`).join('<br>')
                                : 'None';
                        } else if (typeof value === 'boolean') {
                            formattedValue = value ? 'Yes' : 'No';
                        }
                        
                        row.innerHTML = `
                            <td class="fw-bold">${formattedKey}</td>
                            <td>${formattedValue}</td>
                        `;
                        statusContent.appendChild(row);
                    }
                })
                .catch(error => console.error('Error fetching status:', error));
        }

        // Update immediately and then every 5 seconds
        updateStatus();
        setInterval(updateStatus, 5000);

        // Automount toggle functionality
        const automountToggle = document.getElementById('automountToggle');
        const automountProgress = document.getElementById('automountProgress');
        const automountStep = document.getElementById('automountStep');
        const progressBar = document.querySelector('.progress-bar');
        const automountDetails = document.getElementById('automountDetails');
        
        // Function to format timestamp
        function formatTime(timestamp) {
            const date = new Date(timestamp * 1000);
            return date.toLocaleTimeString();
        }

        // Function to check automount status
        async function checkAutomountStatus() {
            try {
                const response = await fetch('get_automount_status.php');
                const data = await response.json();
                
                if (data.status) {
                    const status = data.status;
                    
                    if (status.running) {
                        // Show progress section
                        automountProgress.style.display = 'block';
                        
                        // Update progress bar and step
                        progressBar.style.width = `${status.progress}%`;
                        automountStep.textContent = status.current_step;
                        
                        // Update details
                        automountDetails.innerHTML = status.details.map(detail => `
                            <div class="detail-item">
                                <span class="detail-time">${formatTime(detail.time)}</span>
                                <span class="detail-message">${detail.message}</span>
                            </div>
                        `).join('');
                        
                        // Scroll to latest detail
                        automountDetails.scrollTop = automountDetails.scrollHeight;
                    } else {
                        // Hide progress section if not running
                        automountProgress.style.display = 'none';
                    }
                }
            } catch (error) {
                console.error('Error checking automount status:', error);
            }
        }
        
        // Load initial automount state
        fetch('get_automount.php')
            .then(response => response.json())
            .then(data => {
                automountToggle.checked = data.enabled;
                if (data.enabled) {
                    checkAutomountStatus();
                }
            })
            .catch(error => console.error('Error loading automount status:', error));

        // Handle toggle changes
        automountToggle.addEventListener('change', async () => {
            try {
                const response = await fetch('set_automount.php', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        enabled: automountToggle.checked
                    })
                });
                const result = await response.json();
                if (!result.success) {
                    console.error('Failed to update automount status:', result.error);
                    automountToggle.checked = !automountToggle.checked; // Revert the toggle
                } else if (automountToggle.checked) {
                    // Start checking automount status if enabled
                    checkAutomountStatus();
                } else {
                    // Hide progress section if disabled
                    automountProgress.style.display = 'none';
                }
            } catch (error) {
                console.error('Error updating automount status:', error);
                automountToggle.checked = !automountToggle.checked; // Revert the toggle
            }
        });

        // Check automount status periodically when enabled
        setInterval(() => {
            if (automountToggle.checked) {
                checkAutomountStatus();
            }
        }, 1000);
    </script>
</body>
</html>
