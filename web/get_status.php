<?php
header('Content-Type: application/json');
header('Cache-Control: no-cache, must-revalidate');

$statusFile = '../status/rtStatus.json';

if (file_exists($statusFile)) {
    $status = file_get_contents($statusFile);
    if ($status === false) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to read status file']);
    } else {
        echo $status;
    }
} else {
    http_response_code(404);
    echo json_encode(['error' => 'Status file not found']);
}
