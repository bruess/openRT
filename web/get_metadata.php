<?php
header('Content-Type: application/json');

$output = [];
$return_var = 0;

exec('sudo /usr/local/openRT/openRTApp/rtMetadata.pl -j 2>&1', $output, $return_var);

// Join the output lines into a single string
$json_output = implode("\n", $output);

// Try to decode and then re-encode to ensure valid JSON
$data = json_decode($json_output, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Failed to parse metadata JSON',
        'details' => json_last_error_msg(),
        'output' => $json_output
    ]);
    exit;
}

if ($return_var !== 0 || !isset($data['success']) || !$data['success']) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Failed to get metadata',
        'output' => $json_output
    ]);
    exit;
}

// Re-encode with pretty print for easier debugging
echo json_encode($data, JSON_PRETTY_PRINT); 