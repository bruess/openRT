<?php
header('Content-Type: application/json');

$output = [];
$return_var = 0;

// Execute cleanup command with '1' to indicate cleanup all
exec("sudo /usr/local/openRT/openRTApp/rtFileMount.pl cleanup -j 2>&1", $output, $return_var);
exec("sudo /usr/local/openRT/openRTApp/rtFileMount.pl -cleanup=1 -j 2>&1", $output, $return_var);

// Get the JSON output
$json_output = implode("\n", $output);
$result = json_decode($json_output, true);

// If we got valid JSON, use it for the response
if (json_last_error() === JSON_ERROR_NONE && $result) {
    echo json_encode($result);
} else {
    // Otherwise, construct our own response
    $response = [
        'success' => $return_var === 0,
        'output' => $json_output
    ];

    if ($return_var !== 0) {
        $response['error'] = 'Unmount failed with code ' . $return_var;
    }

    echo json_encode($response);
} 