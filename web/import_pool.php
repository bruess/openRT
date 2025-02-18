<?php
header('Content-Type: application/json');

$action = isset($_GET['action']) ? $_GET['action'] : 'import';
$output = [];
$return_var = 0;

if ($action === 'import') {
    exec('sudo /usr/local/openRT/openRTApp/rtImport.pl import -j 2>&1', $output, $return_var);
} elseif ($action === 'export') {
    exec('sudo /usr/local/openRT/openRTApp/rtImport.pl export -j 2>&1', $output, $return_var);
} else {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => 'Invalid action specified'
    ]);
    exit;
}

$response = [
    'success' => $return_var === 0,
    'output' => implode("\n", $output)
];

if ($return_var !== 0) {
    $response['error'] = ($action === 'import' ? 'Import' : 'Export') . ' failed with code ' . $return_var;
}

echo json_encode($response); 