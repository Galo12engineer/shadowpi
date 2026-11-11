<?php
/**
 * ShadowPi - Authentication Handler
 */

require_once 'config.php';

start_secure_session();

set_security_headers();

// Handle login
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    if ($action === 'login') {
        $username = sanitize_input($_POST['username'] ?? '');
        $password = $_POST['password'] ?? '';

        // Check lockout
        $lockout_key = 'lockout_' . ($_SERVER['REMOTE_ADDR'] ?? '');
        if (isset($_SESSION[$lockout_key]) && $_SESSION[$lockout_key] > time()) {
            $remaining = $_SESSION[$lockout_key] - time();
            echo json_encode(['success' => false, 'message' => "Слишком много попыток. Подождите $remaining сек."]);
            exit;
        }

        // Validate credentials
        if ($username === AUTH_USERNAME && password_verify($password, AUTH_PASSWORD_HASH)) {
            // New session ID at the privilege change: an ID planted before login
            // (session fixation) is worthless afterwards. true = delete the old session.
            session_regenerate_id(true);
            unset($_SESSION[CSRF_TOKEN_NAME]);

            $_SESSION['authenticated'] = true;
            $_SESSION['username'] = $username;
            $_SESSION['login_time'] = time();
            $_SESSION['last_activity'] = time();

            // Clear failed attempts
            unset($_SESSION['failed_attempts']);
            unset($_SESSION[$lockout_key]);

            log_action('LOGIN', 'Successful login');

            echo json_encode(['success' => true, 'redirect' => 'index.html']);
        } else {
            // Track failed attempts
            $_SESSION['failed_attempts'] = ($_SESSION['failed_attempts'] ?? 0) + 1;

            if ($_SESSION['failed_attempts'] >= MAX_LOGIN_ATTEMPTS) {
                $_SESSION[$lockout_key] = time() + LOCKOUT_TIME;
                log_action('LOGIN_LOCKOUT', 'Too many failed attempts');
            }

            log_action('LOGIN_FAILED', "Username: $username");

            echo json_encode(['success' => false, 'message' => 'Неверный логин или пароль']);
        }
        exit;
    }

    if ($action === 'logout') {
        log_action('LOGOUT', 'User logged out');
        $_SESSION = [];
        $p = session_get_cookie_params();
        setcookie(session_name(), '', [
            'expires' => time() - 3600, 'path' => $p['path'], 'secure' => $p['secure'],
            'httponly' => $p['httponly'], 'samesite' => $p['samesite'],
        ]);
        session_destroy();
        echo json_encode(['success' => true, 'redirect' => 'login.html']);
        exit;
    }

    if ($action === 'check') {
        echo json_encode(['authenticated' => is_authenticated()]);
        exit;
    }
}

// Handle GET request - check auth status
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $action = $_GET['action'] ?? '';

    if ($action === 'check') {
        echo json_encode([
            'authenticated' => is_authenticated(),
            'csrf_token' => is_authenticated() ? generate_csrf_token() : null
        ]);
        exit;
    }

    if ($action === 'csrf') {
        if (is_authenticated()) {
            echo json_encode(['token' => generate_csrf_token()]);
        } else {
            http_response_code(401);
            echo json_encode(['error' => 'Not authenticated']);
        }
        exit;
    }
}

// If accessed directly, redirect to login
if (!is_authenticated()) {
    header('Location: login.html');
    exit;
}
?>