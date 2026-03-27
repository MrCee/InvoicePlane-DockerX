<?php
declare(strict_types=1);

$stateDir = '/state';
$requestFile = $stateDir . '/finalize.request';
$statusFile = $stateDir . '/status.json';
$logFile = $stateDir . '/finalizer.log';
$waitPage = '/finalize_install.php';

function respond_json(int $statusCode, array $payload): never
{
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function redirect_to_wait_page(string $waitPage): never
{
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
    header('Location: ' . $waitPage, true, 302);
    exit;
}

function read_state(string $statusFile): array
{
    $default = [
        'state' => 'idle',
        'message' => 'Waiting for finalize request.',
        'timestamp' => null,
    ];

    if (!is_file($statusFile)) {
        return $default;
    }

    $raw = @file_get_contents($statusFile);
    if ($raw === false || $raw === '') {
        return $default;
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return $default;
    }

    return [
        'state' => isset($decoded['state']) && is_string($decoded['state']) ? $decoded['state'] : $default['state'],
        'message' => isset($decoded['message']) && is_string($decoded['message']) ? $decoded['message'] : $default['message'],
        'timestamp' => array_key_exists('timestamp', $decoded) && (is_string($decoded['timestamp']) || $decoded['timestamp'] === null)
            ? $decoded['timestamp']
            : null,
    ];
}

function write_state(string $statusFile, string $state, string $message): void
{
    $payload = [
        'state' => $state,
        'message' => $message,
        'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
    ];

    file_put_contents(
        $statusFile,
        json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
        LOCK_EX
    );
}

function ensure_state_dir(string $stateDir, string $logFile): void
{
    if (!is_dir($stateDir)) {
        if (!mkdir($stateDir, 0775, true) && !is_dir($stateDir)) {
            throw new RuntimeException('Failed to create state directory.');
        }
    }

    if (!is_file($logFile)) {
        touch($logFile);
    }
}

function ensure_finalize_requested(string $stateDir, string $requestFile, string $statusFile, string $logFile): array
{
    ensure_state_dir($stateDir, $logFile);

    $current = read_state($statusFile);
    $state = $current['state'];

    if (in_array($state, ['updating', 'recreating', 'waiting'], true)) {
        return [
            'ok' => true,
            'created' => false,
            'state' => $state,
            'message' => 'Finalization is already in progress.',
        ];
    }

    if ($state === 'complete') {
        return [
            'ok' => true,
            'created' => false,
            'state' => $state,
            'message' => 'Finalization has already completed.',
        ];
    }

    if ($state === 'requested' && is_file($requestFile)) {
        return [
            'ok' => true,
            'created' => false,
            'state' => 'requested',
            'message' => 'Finalize request already exists.',
        ];
    }

    write_state(
        $statusFile,
        'requested',
        'Finalize requested. Waiting for finalizer to begin.'
    );

    file_put_contents($requestFile, "1\n", LOCK_EX);

    return [
        'ok' => true,
        'created' => true,
        'state' => 'requested',
        'message' => 'Finalize request created.',
    ];
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

try {
    if ($method === 'GET') {
        ensure_finalize_requested($stateDir, $requestFile, $statusFile, $logFile);
        redirect_to_wait_page($waitPage);
    }

    if ($method !== 'POST') {
        respond_json(405, [
            'ok' => false,
            'message' => 'Method not allowed.',
        ]);
    }

    $action = isset($_POST['action']) && is_string($_POST['action']) ? trim($_POST['action']) : '';
    if ($action !== 'finalize') {
        respond_json(400, [
            'ok' => false,
            'message' => 'Invalid action.',
        ]);
    }

    $result = ensure_finalize_requested($stateDir, $requestFile, $statusFile, $logFile);

    respond_json(200, [
        'ok' => true,
        'message' => $result['message'],
        'state' => $result['state'],
        'created' => $result['created'],
    ]);
} catch (Throwable $e) {
    if ($method === 'POST') {
        respond_json(500, [
            'ok' => false,
            'message' => 'Failed to create finalize request.',
            'error' => $e->getMessage(),
        ]);
    }

    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Failed to start finalization: ' . $e->getMessage();
    exit;
}
