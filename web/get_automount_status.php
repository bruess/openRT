<?php
header('Content-Type: application/json');

$status_file = '/usr/local/openRT/status/automount_status.json';

if (file_exists($status_file)) {
    $status = json_decode(file_get_contents($status_file), true);
    echo json_encode([
        'success' => true,
        'status' => $status
    ]);
} else {
    echo json_encode([
        'success' => true,
        'status' => null
    ]);
} 