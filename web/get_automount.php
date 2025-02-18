<?php
header('Content-Type: application/json');

$status_file = '/usr/local/openRT/status/automount';

// Check if the file exists and read its content
if (file_exists($status_file)) {
    $enabled = trim(file_get_contents($status_file)) === '1';
} else {
    // Default to disabled if file doesn't exist
    $enabled = false;
}

echo json_encode([
    'success' => true,
    'enabled' => $enabled
]); 