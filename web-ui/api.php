<?php
/**
 * ShadowPi API
 * Provides status and control for VPN, V2Ray, Tor, WiFi
 * With authentication, CSRF protection, and logging
 */

// Config, then the hardened session (cookie flags, idle timeout)
require_once 'config.php';

start_secure_session();

// Set security headers
set_security_headers();
header('Content-Type: application/json');

$action = $_REQUEST['action'] ?? '';

// State-changing actions: POST only, with a CSRF token.
$write_actions = [
    'vpn_start',
    'vpn_stop',
    'vpn_restart',
    'tor_start',
    'tor_stop',
    'wifi_start',
    'wifi_stop',
    'start_all',
    'stop_all',
    'restart_all',
    'run_tests',
    'wan_switch',
    'modem_setup'
];

// Default-deny: every action needs an authenticated session. Hotspot clients share
// the router's LAN, so "local network" is not a trust boundary.
if (!is_authenticated()) {
    http_response_code(401);
    die(json_encode(['error' => 'Authentication required', 'redirect' => 'login.html']));
}

if (in_array($action, $write_actions, true)) {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        die(json_encode(['error' => 'POST required']));
    }

    $csrf_token = $_POST['csrf_token'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
    if (!verify_csrf_token($csrf_token)) {
        http_response_code(403);
        log_action('CSRF_FAIL', "Action: $action");
        die(json_encode(['error' => 'Invalid CSRF token']));
    }

    // Rate limiting
    if (!check_rate_limit($action)) {
        http_response_code(429);
        die(json_encode(['error' => 'Rate limit exceeded']));
    }

    // Log the action
    log_action('API_ACTION', $action);
}

// Security: Only allow from localhost or local network
$allowed_ips = ['127.0.0.1', '::1'];
$client_ip = $_SERVER['REMOTE_ADDR'];

// Allow local network (10.0.0.x and 192.168.x.x)
$is_local = in_array($client_ip, $allowed_ips)
    || preg_match('/^10\.0\.0\./', $client_ip)
    || preg_match('/^192\.168\./', $client_ip);

if (!$is_local && !is_authenticated()) {
    http_response_code(403);
    die(json_encode(['error' => 'Access denied']));
}

// Route actions
switch ($action) {
    // Status endpoints
    case 'vpn_status':
        echo json_encode(getVPNStatus());
        break;

    case 'v2ray_status':
        echo json_encode(getV2RayStatus());
        break;

    case 'tor_status':
        echo json_encode(getTorStatus());
        break;

    case 'wifi_status':
        echo json_encode(getWiFiStatus());
        break;

    case 'public_ip':
        echo json_encode(getPublicIP());
        break;

    case 'system_stats':
        echo json_encode(getSystemStats());
        break;

    case 'get_logs':
        echo json_encode(getLogs());
        break;

    case 'get_csrf':
        echo json_encode(['token' => generate_csrf_token()]);
        break;

    // Control actions (require auth + CSRF)
    case 'vpn_start':
        echo json_encode(controlService('openvpn-windscribe', 'start'));
        break;

    case 'vpn_stop':
        echo json_encode(controlService('openvpn-windscribe', 'stop'));
        break;

    case 'vpn_restart':
        echo json_encode(controlService('openvpn-windscribe', 'restart'));
        break;

    case 'tor_start':
        echo json_encode(controlService('tor', 'start'));
        break;

    case 'tor_stop':
        echo json_encode(controlService('tor', 'stop'));
        break;

    case 'wifi_start':
        echo json_encode(startWiFi());
        break;

    case 'wifi_stop':
        echo json_encode(stopWiFi());
        break;

    case 'start_all':
        echo json_encode(startAll());
        break;

    case 'stop_all':
        echo json_encode(stopAll());
        break;

    case 'restart_all':
        echo json_encode(restartAll());
        break;

    case 'run_tests':
        echo json_encode(runTests());
        break;

    // WAN Management
    case 'wan_status':
        echo json_encode(getWANStatus());
        break;

    case 'wan_switch':
        $target = sanitize_input($_POST['target'] ?? 'auto');
        echo json_encode(switchWAN($target));
        break;

    case 'modem_status':
        echo json_encode(getModemStatus());
        break;

    case 'modem_setup':
        echo json_encode(setupModem());
        break;

    default:
        echo json_encode(['error' => 'Unknown action']);
}

// Status Functions

function getVPNStatus()
{
    $active = isServiceActive('openvpn-windscribe');
    $ip = '';
    $server = '';

    if ($active) {
        $ip = @file_get_contents('/opt/shadowpi/status/vpn-ip.txt') ?: '';
        $ip = trim($ip);

        $config = @file_get_contents('/etc/openvpn/client/windscribe.conf');
        if (preg_match('/remote\s+([^\s]+)/', $config, $matches)) {
            $server = $matches[1];
        }
    }

    return [
        'active' => $active,
        'ip' => $ip,
        'server' => $server
    ];
}

function getV2RayStatus()
{
    $active = isServiceActive('v2raya');
    $servers = 0;

    if ($active) {
        $servers = 1;
    }

    return [
        'active' => $active,
        'servers' => $servers
    ];
}

function getTorStatus()
{
    return [
        'active' => isServiceActive('tor')
    ];
}

function getWiFiStatus()
{
    $active = isServiceActive('hostapd');
    $ssid = '';
    $clients = 0;

    if ($active) {
        $config = @file_get_contents('/etc/hostapd/hostapd.conf');
        if (preg_match('/ssid=(.+)/', $config, $matches)) {
            $ssid = trim($matches[1]);
        }

        $output = shell_exec('iw dev wlan0 station dump 2>/dev/null | grep -c "^Station"');
        $clients = (int) trim($output);
    }

    return [
        'active' => $active,
        'ssid' => $ssid,
        'clients' => $clients
    ];
}

function getPublicIP()
{
    // Use multiple services for reliability, no single tracking
    $services = [
        'https://api.ipify.org?format=json',
        'https://ipapi.co/json/'
    ];

    foreach ($services as $service) {
        $context = stream_context_create([
            'http' => ['timeout' => 5]
        ]);
        $ip_info = @file_get_contents($service, false, $context);

        if ($ip_info) {
            $data = json_decode($ip_info, true);
            return [
                'ip' => $data['ip'] ?? $data['ip'] ?? '-',
                'country' => $data['country'] ?? $data['country_name'] ?? '-',
                'city' => $data['city'] ?? '-',
                'org' => $data['org'] ?? $data['org'] ?? '-',
                'lat' => $data['latitude'] ?? null,
                'lon' => $data['longitude'] ?? null
            ];
        }
    }

    return [
        'ip' => 'Ошибка',
        'country' => '-',
        'city' => '-',
        'org' => '-'
    ];
}

function getSystemStats()
{
    // CPU
    $load = sys_getloadavg();
    $cpu = round($load[0] * 25, 1);

    // Memory
    $mem_info = shell_exec('free | grep Mem');
    preg_match_all('/\d+/', $mem_info, $matches);
    $memory = 0;
    if (isset($matches[0][1]) && isset($matches[0][0]) && $matches[0][0] > 0) {
        $memory = round(($matches[0][1] / $matches[0][0]) * 100, 1);
    }

    // Temperature (Raspberry Pi specific)
    $temp_raw = @file_get_contents('/sys/class/thermal/thermal_zone0/temp');
    $temperature = $temp_raw ? round($temp_raw / 1000, 1) : 0;

    // Uptime
    $uptime_raw = @file_get_contents('/proc/uptime');
    $uptime_seconds = (int) $uptime_raw;
    $uptime = formatUptime($uptime_seconds);

    return [
        'cpu' => $cpu,
        'memory' => $memory,
        'temperature' => $temperature,
        'uptime' => $uptime
    ];
}

function formatUptime($seconds)
{
    $days = floor($seconds / 86400);
    $hours = floor(($seconds % 86400) / 3600);
    $minutes = floor(($seconds % 3600) / 60);

    if ($days > 0) {
        return "{$days}д {$hours}ч";
    } elseif ($hours > 0) {
        return "{$hours}ч {$minutes}м";
    } else {
        return "{$minutes}м";
    }
}

function getLogs()
{
    $log_files = [
        '/var/log/shadowpi/panel.log',
        '/var/log/openvpn/openvpn.log',
        '/var/log/shadowpi/status.log'
    ];

    $logs = '';
    foreach ($log_files as $file) {
        if (file_exists($file)) {
            $logs .= "=== " . basename($file) . " ===\n";
            $logs .= shell_exec("tail -n 20 " . escapeshellarg($file) . " 2>/dev/null");
            $logs .= "\n\n";
        }
    }

    return ['logs' => $logs ?: 'Нет логов'];
}

// Control Functions

function controlService($service, $action)
{
    $allowed_actions = ['start', 'stop', 'restart'];
    $allowed_services = ['openvpn-windscribe', 'v2raya', 'tor', 'hostapd', 'dnsmasq'];

    if (!in_array($action, $allowed_actions) || !in_array($service, $allowed_services)) {
        return ['success' => false, 'message' => 'Invalid action or service'];
    }

    $output = shell_exec("sudo systemctl " . escapeshellarg($action) . " " . escapeshellarg($service) . " 2>&1");
    sleep(1);

    $is_active = isServiceActive($service);
    $success = ($action === 'stop') ? !$is_active : $is_active;

    log_action('SERVICE_CONTROL', "$action $service - " . ($success ? 'success' : 'failed'));

    return [
        'success' => $success,
        'message' => ucfirst($action) . ' ' . $service . ($success ? ' успешно' : ' ошибка')
    ];
}

function startWiFi()
{
    shell_exec('sudo systemctl start hostapd 2>&1');
    shell_exec('sudo systemctl start dnsmasq 2>&1');
    sleep(1);

    $success = isServiceActive('hostapd');
    log_action('WIFI', 'start - ' . ($success ? 'success' : 'failed'));

    return [
        'success' => $success,
        'message' => 'WiFi Hotspot запущен'
    ];
}

function stopWiFi()
{
    shell_exec('sudo systemctl stop hostapd 2>&1');
    shell_exec('sudo systemctl stop dnsmasq 2>&1');
    sleep(1);

    $success = !isServiceActive('hostapd');
    log_action('WIFI', 'stop - ' . ($success ? 'success' : 'failed'));

    return [
        'success' => $success,
        'message' => 'WiFi Hotspot остановлен'
    ];
}

function startAll()
{
    shell_exec('sudo /opt/shadowpi/scripts/start-all.sh 2>&1');
    sleep(2);

    log_action('ALL_SERVICES', 'start');

    return [
        'success' => true,
        'message' => 'Все сервисы запускаются...'
    ];
}

function stopAll()
{
    shell_exec('sudo /opt/shadowpi/scripts/stop-all.sh 2>&1');
    sleep(2);

    log_action('ALL_SERVICES', 'stop');

    return [
        'success' => true,
        'message' => 'Все сервисы останавливаются...'
    ];
}

function restartAll()
{
    shell_exec('sudo /opt/shadowpi/scripts/restart-all.sh 2>&1');
    sleep(2);

    log_action('ALL_SERVICES', 'restart');

    return [
        'success' => true,
        'message' => 'Все сервисы перезапускаются...'
    ];
}

function runTests()
{
    shell_exec('sudo /opt/shadowpi/scripts/test-all.sh > /var/log/shadowpi/test-results.log 2>&1 &');

    log_action('TESTS', 'started');

    return [
        'success' => true,
        'message' => 'Тесты запущены... Смотрите логи через 30 секунд'
    ];
}

// Helper Functions

function isServiceActive($service)
{
    $output = shell_exec("systemctl is-active " . escapeshellarg($service) . " 2>/dev/null");
    return trim($output) === 'active';
}

// WAN Management Functions

function getWANStatus()
{
    $wan_status = [];

    // Read WAN status file
    $status_file = '/opt/shadowpi/status/wan-status.json';
    if (file_exists($status_file)) {
        $wan_status = json_decode(file_get_contents($status_file), true) ?: [];
    }

    // Get current default gateway interface
    $current_gw = trim(shell_exec("ip route show default 2>/dev/null | grep -oP 'dev \\K\\S+' | head -1"));

    // Get available interfaces
    $interfaces = [];

    // eth0
    if (file_exists('/sys/class/net/eth0')) {
        $eth_status = trim(@file_get_contents('/sys/class/net/eth0/operstate'));
        $eth_ip = trim(shell_exec("ip -4 addr show eth0 2>/dev/null | grep -oP 'inet \\K[\\d.]+'"));
        $interfaces['eth0'] = [
            'name' => 'Ethernet',
            'status' => $eth_status,
            'ip' => $eth_ip,
            'active' => ($current_gw === 'eth0')
        ];
    }

    // USB modem interfaces
    foreach (['usb0', 'usb1', 'eth1', 'wwan0'] as $iface) {
        if (file_exists("/sys/class/net/$iface")) {
            $status = trim(@file_get_contents("/sys/class/net/$iface/operstate"));
            $ip = trim(shell_exec("ip -4 addr show $iface 2>/dev/null | grep -oP 'inet \\K[\\d.]+'"));
            $interfaces[$iface] = [
                'name' => 'USB Modem',
                'status' => $status,
                'ip' => $ip,
                'active' => ($current_gw === $iface)
            ];
        }
    }

    // Check for enx* interfaces (USB Ethernet from modem)
    $enx_ifaces = glob('/sys/class/net/enx*');
    foreach ($enx_ifaces as $path) {
        $iface = basename($path);
        $status = trim(@file_get_contents("$path/operstate"));
        $ip = trim(shell_exec("ip -4 addr show $iface 2>/dev/null | grep -oP 'inet \\K[\\d.]+'"));
        $interfaces[$iface] = [
            'name' => 'USB Modem (Ethernet)',
            'status' => $status,
            'ip' => $ip,
            'active' => ($current_gw === $iface)
        ];
    }

    return [
        'current' => $current_gw ?: 'none',
        'type' => $wan_status['type'] ?? 'unknown',
        'interfaces' => $interfaces
    ];
}

function switchWAN($target)
{
    $allowed_targets = ['auto', 'ethernet', 'modem', 'eth0', 'usb0', 'usb1', 'eth1', 'wwan0'];

    // Also allow enx* interfaces
    if (!in_array($target, $allowed_targets) && !preg_match('/^enx[a-f0-9]{12}$/', $target)) {
        return ['success' => false, 'message' => 'Недопустимый интерфейс'];
    }

    $output = shell_exec("sudo /opt/shadowpi/scripts/wan-switch.sh " . escapeshellarg($target) . " 2>&1");

    log_action('WAN_SWITCH', "Switched to: $target");

    // Re-read status
    sleep(2);
    $status = getWANStatus();

    return [
        'success' => true,
        'message' => "WAN переключен на: " . $status['current'],
        'current' => $status['current'],
        'output' => $output
    ];
}

function getModemStatus()
{
    $modem_status = [];

    // Read modem status file
    $status_file = '/opt/shadowpi/status/modem-status.json';
    if (file_exists($status_file)) {
        $modem_status = json_decode(file_get_contents($status_file), true) ?: [];
    }

    // Get ModemManager info
    $mm_output = shell_exec('mmcli -L 2>/dev/null');
    $modem_found = strpos($mm_output, 'Modem') !== false;

    // Get modem details if available
    $modem_info = [];
    if ($modem_found) {
        $modem_index = trim(shell_exec("mmcli -L 2>/dev/null | grep -oP 'Modem/\\K\\d+' | head -1"));
        if ($modem_index !== '') {
            $details = shell_exec("mmcli -m $modem_index 2>/dev/null");

            // Parse signal quality
            if (preg_match('/signal quality: (\d+)/', $details, $matches)) {
                $modem_info['signal'] = (int) $matches[1];
            }

            // Parse state
            if (preg_match('/state: ([a-z]+)/i', $details, $matches)) {
                $modem_info['state'] = $matches[1];
            }

            // Parse operator
            if (preg_match("/operator name: '([^']+)'/", $details, $matches)) {
                $modem_info['operator'] = $matches[1];
            }
        }
    }

    return [
        'detected' => $modem_found || !empty($modem_status['status']),
        'status' => $modem_status['status'] ?? ($modem_found ? 'detected' : 'not_found'),
        'interface' => $modem_status['interface'] ?? '',
        'ip' => $modem_status['ip'] ?? '',
        'modem' => $modem_status['modem'] ?? '',
        'signal' => $modem_info['signal'] ?? null,
        'state' => $modem_info['state'] ?? null,
        'operator' => $modem_info['operator'] ?? null
    ];
}

function setupModem()
{
    $apn = sanitize_input($_POST['apn'] ?? 'internet');

    $output = shell_exec("sudo /opt/shadowpi/scripts/setup-modem.sh " . escapeshellarg($apn) . " 2>&1");

    log_action('MODEM_SETUP', "APN: $apn");

    // Re-read status
    sleep(3);
    $status = getModemStatus();

    return [
        'success' => $status['status'] === 'connected',
        'message' => $status['status'] === 'connected' ? 'Модем настроен!' : 'Ошибка настройки модема',
        'status' => $status,
        'output' => $output
    ];
}
