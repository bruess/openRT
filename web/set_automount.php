<?php
header('Content-Type: application/json');

// Get JSON input
$input = json_decode(file_get_contents('php://input'), true);

if (!isset($input['enabled'])) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Missing enabled parameter'
    ]);
    exit;
}

$status_file = '/usr/local/openRT/status/automount';
$enabled = $input['enabled'] ? '1' : '0';

// Try to write the status
if (file_put_contents($status_file, $enabled) !== false) {
    // Set proper permissions
    chmod($status_file, 0644);
    chown($status_file, 'openrt');
    chgrp($status_file, 'openrt');
    
    echo json_encode([
        'success' => true,
        'enabled' => $enabled === '1'
    ]);
} else {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Failed to write automount status'
    ]);
} 