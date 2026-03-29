<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

$stateFile = '/state/status.json';
$templateStatusFile = '/state/template_status.json';
$logFile   = '/state/finalizer.log';

$state = [
    'state' => 'idle',
    'message' => 'Waiting for finalize request.',
    'timestamp' => null,
];

$templateState = [
    'state' => 'pending',
    'message' => 'Waiting for compact template defaults.',
    'timestamp' => null,
];

if (is_file($stateFile)) {
    $json = @file_get_contents($stateFile);

    if ($json !== false && $json !== '') {
        $decoded = json_decode($json, true);

        if (is_array($decoded)) {
            if (isset($decoded['state']) && is_string($decoded['state'])) {
                $state['state'] = $decoded['state'];
            }

            if (isset($decoded['message']) && is_string($decoded['message'])) {
                $state['message'] = $decoded['message'];
            }

            if (array_key_exists('timestamp', $decoded)) {
                $state['timestamp'] = is_string($decoded['timestamp']) || $decoded['timestamp'] === null
                    ? $decoded['timestamp']
                    : null;
            }
        }
    }
}

if (is_file($templateStatusFile)) {
    $json = @file_get_contents($templateStatusFile);

    if ($json !== false && $json !== '') {
        $decoded = json_decode($json, true);

        if (is_array($decoded)) {
            if (isset($decoded['state']) && is_string($decoded['state'])) {
                $templateState['state'] = $decoded['state'];
            }

            if (isset($decoded['message']) && is_string($decoded['message'])) {
                $templateState['message'] = $decoded['message'];
            }

            if (array_key_exists('timestamp', $decoded)) {
                $templateState['timestamp'] = is_string($decoded['timestamp']) || $decoded['timestamp'] === null
                    ? $decoded['timestamp']
                    : null;
            }
        }
    }
}

$log = '';
$logSize = 0;
$logMtime = null;

if (is_file($logFile)) {
    clearstatcache(true, $logFile);

    $size = @filesize($logFile);
    if ($size !== false) {
        $logSize = (int)$size;
    }

    $mtime = @filemtime($logFile);
    if ($mtime !== false) {
        $logMtime = gmdate('Y-m-d\TH:i:s\Z', (int)$mtime);
    }

    $fp = @fopen($logFile, 'rb');

    if ($fp !== false) {
        $contents = stream_get_contents($fp);
        fclose($fp);

        if ($contents !== false) {
            $log = (string)$contents;
        }
    }
}

$response = [
    'state' => (string)$state['state'],
    'message' => (string)$state['message'],
    'timestamp' => $state['timestamp'],
    'template_status' => (string)$templateState['state'],
    'template_message' => (string)$templateState['message'],
    'template_timestamp' => $templateState['timestamp'],
    'log' => $log,
    'log_size' => $logSize,
    'log_mtime' => $logMtime,
];

try {
    echo json_encode($response, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    echo '{"state":"error","message":"Status encoding failure","timestamp":null,"template_status":"error","template_message":"Status encoding failure","template_timestamp":null,"log":"","log_size":0,"log_mtime":null}';
}

