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
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container-fluid">
            <span class="navbar-brand">OpenRT Status</span>
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
            </div>
        </div>
    </div>

    <!-- Local JavaScript dependencies -->
    <script src="assets/bootstrap/bootstrap.bundle.min.js"></script>
    <script>
        function updateStatus() {
            fetch('get_status.php')
                .then(response => response.json())
                .then(data => {
                    const statusContent = document.getElementById('status-content');
                    const lastUpdated = document.getElementById('last-updated');
                    
                    // Clear existing content
                    statusContent.innerHTML = '';
                    
                    // Update timestamp
                    lastUpdated.textContent = `Last updated: ${data.timestamp}`;
                    
                    // Get all entries except timestamp and sort them alphabetically
                    const sortedEntries = Object.entries(data)
                        .filter(([key]) => key !== 'timestamp')
                        .sort(([keyA], [keyB]) => keyA.localeCompare(keyB));
                    
                    // Add each property to the table
                    for (const [key, value] of sortedEntries) {
                        const row = document.createElement('tr');
                        
                        // Format the key
                        const formattedKey = key.replace(/_/g, ' ')
                                              .split(' ')
                                              .map(word => word.charAt(0).toUpperCase() + word.slice(1))
                                              .join(' ');
                        
                        // Format the value based on its type
                        let formattedValue = value;
                        if (Array.isArray(value)) {
                            formattedValue = value.length > 0 ? value.join(', ') : 'None';
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
    </script>
</body>
</html>
