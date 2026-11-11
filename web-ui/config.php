<?php
/**
 * ShadowPi - Configuration File
 * Centralized configuration for the control panel
 */

// Session configuration
define('SESSION_NAME', 'shadowpi_session');
define('SESSION_LIFETIME', 3600);  // idle timeout: 1 hour without any request
define('SESSION_MAX_AGE', 43200);  // absolute cap: 12 hours after login, even if the open
                                   // panel tab keeps polling (polling counts as activity)

// Authentication
define('AUTH_USERNAME', 'admin');
define('AUTH_PASSWORD_HASH', '$2y$10$defaulthashchangethis'); // Change with: password_hash('your_password', PASSWORD_DEFAULT)

// CSRF Token
define('CSRF_TOKEN_NAME', 'shadowpi_csrf');

// Paths
define('SCRIPTS_PATH', '/opt/shadowpi/');
define('LOG_FILE', '/var/log/shadowpi/panel.log');

// Rate limiting
define('MAX_LOGIN_ATTEMPTS', 5);
define('LOCKOUT_TIME', 300); // 5 minutes

// API settings
define('API_RATE_LIMIT', 60); // requests per minute

// Security headers
function set_security_headers() {
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('X-XSS-Protection: 1; mode=block');
    header('Referrer-Policy: strict-origin-when-cross-origin');
    header('Content-Security-Policy: default-src \'self\'; script-src \'self\' \'unsafe-inline\'; style-src \'self\' \'unsafe-inline\';');
}

// Logging function
function log_action($action, $details = '') {
    $timestamp = date('Y-m-d H:i:s');
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $user = $_SESSION['username'] ?? 'anonymous';
    $log_entry = "[$timestamp] [$ip] [$user] $action: $details\n";
    
    $log_dir = dirname(LOG_FILE);
    if (!is_dir($log_dir)) {
        @mkdir($log_dir, 0755, true);
    }
    
    @file_put_contents(LOG_FILE, $log_entry, FILE_APPEND | LOCK_EX);
}

// CSRF token functions
function generate_csrf_token() {
    if (empty($_SESSION[CSRF_TOKEN_NAME])) {
        $_SESSION[CSRF_TOKEN_NAME] = bin2hex(random_bytes(32));
    }
    return $_SESSION[CSRF_TOKEN_NAME];
}

function verify_csrf_token($token) {
    return isset($_SESSION[CSRF_TOKEN_NAME]) && hash_equals($_SESSION[CSRF_TOKEN_NAME], $token);
}

// Input sanitization
function sanitize_input($input) {
    return htmlspecialchars(strip_tags(trim($input)), ENT_QUOTES, 'UTF-8');
}

// Start the session with hardened cookie settings and enforce the timeouts.
// Every entry point (auth.php, api.php) must call this instead of session_start().
function start_secure_session() {
    // The panel is served over plain HTTP on the hotspot (HTTPS is on the roadmap), so the
    // Secure flag can only be set when the request really came over TLS.
    $https = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';

    ini_set('session.use_strict_mode', '1');   // refuse session IDs the server did not issue
    ini_set('session.use_only_cookies', '1');
    ini_set('session.gc_maxlifetime', (string) SESSION_MAX_AGE);

    session_name(SESSION_NAME);
    session_set_cookie_params([
        'lifetime' => 0,          // session cookie: gone when the browser closes
        'path'     => '/',
        'secure'   => $https,
        'httponly' => true,       // not readable from JavaScript
        'samesite' => 'Strict',   // not sent on cross-site requests
    ]);
    session_start();

    if (!empty($_SESSION['authenticated'])) {
        $now  = time();
        $idle = $now - (int) ($_SESSION['last_activity'] ?? 0);
        $age  = $now - (int) ($_SESSION['login_time'] ?? 0);
        if ($idle > SESSION_LIFETIME || $age > SESSION_MAX_AGE) {
            $_SESSION = [];
            session_regenerate_id(true);
        } else {
            $_SESSION['last_activity'] = $now;
        }
    }
}

// Check if user is authenticated
function is_authenticated() {
    return isset($_SESSION['authenticated']) && $_SESSION['authenticated'] === true;
}

// Rate limiting check
function check_rate_limit($action) {
    $key = 'rate_' . $action . '_' . ($_SERVER['REMOTE_ADDR'] ?? '');
    if (!isset($_SESSION[$key])) {
        $_SESSION[$key] = ['count' => 0, 'reset' => time() + 60];
    }
    
    if (time() > $_SESSION[$key]['reset']) {
        $_SESSION[$key] = ['count' => 0, 'reset' => time() + 60];
    }
    
    $_SESSION[$key]['count']++;
    
    return $_SESSION[$key]['count'] <= API_RATE_LIMIT;
}
?>
