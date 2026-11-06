// ShadowPi Control Panel - Enhanced JavaScript v2.0
// No external dependencies - full privacy

let updateInterval;
let statusData = {};
let csrfToken = '';

// Initialize on page load
document.addEventListener('DOMContentLoaded', async function () {
    console.log('ShadowPi Control Panel - initialized');

    // Check authentication
    try {
        const authResponse = await fetch('auth.php?action=check');
        const authData = await authResponse.json();

        if (!authData.authenticated) {
            window.location.href = 'login.html';
            return;
        }

        // Get CSRF token
        csrfToken = authData.csrf_token || '';
    } catch (error) {
        console.error('Auth check failed:', error);
    }

    // Initial update
    updateAll();

    // Auto-refresh every 5 seconds
    updateInterval = setInterval(updateAll, 5000);
});

// Logout function
async function logout() {
    try {
        await fetch('auth.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'action=logout'
        });
    } catch (error) {
        console.error('Logout error:', error);
    }
    window.location.href = 'login.html';
}

// Main update function
async function updateAll() {
    await Promise.all([
        updateVPNStatus(),
        updateV2RayStatus(),
        updateTorStatus(),
        updateWiFiStatus(),
        updateWANStatus(),
        updatePublicIP(),
        updateSystemStats()
    ]);

    updateMainStatus();
    updateProxyChain();
}

// Update VPN Status
async function updateVPNStatus() {
    try {
        const response = await fetch('api.php?action=vpn_status');
        const data = await response.json();

        statusData.vpn = data;

        const vpnBadge = document.getElementById('vpnBadge');
        const vpnStatus = document.getElementById('vpnStatus');
        const vpnIP = document.getElementById('vpnIP');
        const vpnServer = document.getElementById('vpnServer');
        const vpnButtonText = document.getElementById('vpnButtonText');
        const vpnGauge = document.getElementById('vpnGauge');
        const vpnCard = document.getElementById('vpnCard');
        const vpnChainStatus = document.getElementById('vpnChainStatus');

        if (data.active) {
            vpnBadge.textContent = 'Активен';
            vpnBadge.className = 'service-badge';
            vpnStatus.textContent = 'Подключен';
            vpnIP.textContent = data.ip || '-';
            vpnServer.textContent = data.server || '-';
            vpnButtonText.textContent = 'Остановить';
            vpnGauge.classList.add('active');
            vpnCard.classList.add('active');
            vpnChainStatus.textContent = 'Активен';
        } else {
            vpnBadge.textContent = 'Остановлен';
            vpnBadge.className = 'service-badge danger';
            vpnStatus.textContent = 'Отключен';
            vpnIP.textContent = '-';
            vpnServer.textContent = '-';
            vpnButtonText.textContent = 'Включить';
            vpnGauge.classList.remove('active');
            vpnCard.classList.remove('active');
            vpnChainStatus.textContent = 'Отключен';
        }
    } catch (error) {
        console.error('VPN status error:', error);
    }
}

// Update V2Ray Status
async function updateV2RayStatus() {
    try {
        const response = await fetch('api.php?action=v2ray_status');
        const data = await response.json();

        statusData.v2ray = data;

        const v2rayBadge = document.getElementById('v2rayBadge');
        const v2rayStatus = document.getElementById('v2rayStatus');
        const v2rayServers = document.getElementById('v2rayServers');
        const v2rayGauge = document.getElementById('v2rayGauge');
        const v2rayCard = document.getElementById('v2rayCard');
        const v2rayChainStatus = document.getElementById('v2rayChainStatus');

        if (data.active) {
            v2rayBadge.textContent = 'Активен';
            v2rayBadge.className = 'service-badge';
            v2rayStatus.textContent = 'Запущен';
            v2rayServers.textContent = data.servers || '0';
            v2rayGauge.classList.add('active');
            v2rayCard.classList.add('active');
            v2rayChainStatus.textContent = 'Активен';
        } else {
            v2rayBadge.textContent = 'Остановлен';
            v2rayBadge.className = 'service-badge warning';
            v2rayStatus.textContent = 'Остановлен';
            v2rayServers.textContent = '-';
            v2rayGauge.classList.remove('active');
            v2rayCard.classList.remove('active');
            v2rayChainStatus.textContent = 'Отключен';
        }
    } catch (error) {
        console.error('V2Ray status error:', error);
    }
}

// Update Tor Status
async function updateTorStatus() {
    try {
        const response = await fetch('api.php?action=tor_status');
        const data = await response.json();

        statusData.tor = data;

        const torBadge = document.getElementById('torBadge');
        const torStatus = document.getElementById('torStatus');
        const torButtonText = document.getElementById('torButtonText');
        const torGauge = document.getElementById('torGauge');
        const torCard = document.getElementById('torCard');
        const torChainStatus = document.getElementById('torChainStatus');
        const chainTor = document.getElementById('chainTor');
        const arrowTor = document.getElementById('arrowTor');

        if (data.active) {
            torBadge.textContent = 'Активен';
            torBadge.className = 'service-badge';
            torStatus.textContent = 'Запущен';
            torButtonText.textContent = 'Остановить';
            torGauge.classList.add('active');
            torCard.classList.add('active');
            torChainStatus.textContent = 'Активен';
            chainTor.classList.add('active');
            chainTor.classList.remove('optional');
            arrowTor.classList.add('active');
            arrowTor.classList.remove('optional');
        } else {
            torBadge.textContent = 'Отключен';
            torBadge.className = 'service-badge secondary';
            torStatus.textContent = 'Остановлен';
            torButtonText.textContent = 'Включить';
            torGauge.classList.remove('active');
            torCard.classList.remove('active');
            torChainStatus.textContent = 'Опционально';
            chainTor.classList.remove('active');
            chainTor.classList.add('optional');
            arrowTor.classList.remove('active');
            arrowTor.classList.add('optional');
        }
    } catch (error) {
        console.error('Tor status error:', error);
    }
}

// Update WiFi Status
async function updateWiFiStatus() {
    try {
        const response = await fetch('api.php?action=wifi_status');
        const data = await response.json();

        statusData.wifi = data;

        const wifiBadge = document.getElementById('wifiBadge');
        const wifiSSID = document.getElementById('wifiSSID');
        const wifiClients = document.getElementById('wifiClients');
        const wifiGauge = document.getElementById('wifiGauge');
        const wifiCard = document.getElementById('wifiCard');

        if (data.active) {
            wifiBadge.textContent = 'Активен';
            wifiBadge.className = 'service-badge';
            wifiSSID.textContent = data.ssid || '-';
            wifiClients.textContent = data.clients || '0';
            wifiGauge.classList.add('active');
            wifiCard.classList.add('active');
        } else {
            wifiBadge.textContent = 'Остановлен';
            wifiBadge.className = 'service-badge warning';
            wifiSSID.textContent = '-';
            wifiClients.textContent = '-';
            wifiGauge.classList.remove('active');
            wifiCard.classList.remove('active');
        }
    } catch (error) {
        console.error('WiFi status error:', error);
    }
}

// Update WAN Status
async function updateWANStatus() {
    try {
        const response = await fetch('api.php?action=wan_status');
        const data = await response.json();

        statusData.wan = data;

        // Update current WAN display
        document.getElementById('wanCurrent').textContent = data.current || 'Нет';

        // Update WAN type badge
        const typeBadge = document.getElementById('wanTypeBadge');
        if (data.current === 'eth0') {
            typeBadge.textContent = 'Ethernet';
            typeBadge.className = 'wan-type-badge ethernet';
        } else if (data.current && data.current !== 'none') {
            typeBadge.textContent = 'USB Модем';
            typeBadge.className = 'wan-type-badge modem';
        } else {
            typeBadge.textContent = 'Нет';
            typeBadge.className = 'wan-type-badge';
        }

        // Update WAN IP
        let wanIP = '-';
        if (data.interfaces && data.interfaces[data.current]) {
            wanIP = data.interfaces[data.current].ip || '-';
        }
        document.getElementById('wanIP').textContent = wanIP;

        // Render interfaces
        renderWANInterfaces(data.interfaces, data.current);

        // Update modem info
        updateModemInfo();

    } catch (error) {
        console.error('WAN status error:', error);
    }
}

// Render WAN interfaces
function renderWANInterfaces(interfaces, current) {
    const container = document.getElementById('wanInterfaces');
    if (!container || !interfaces) return;

    let html = '';
    for (const [iface, info] of Object.entries(interfaces)) {
        const isActive = iface === current;
        const statusClass = info.status === 'up' ? 'up' : 'down';
        const icon = info.name.includes('Modem') ? '📡' : '🔗';

        html += `
            <div class="wan-interface ${isActive ? 'active' : ''}" onclick="switchWAN('${iface}')">
                <span class="wan-interface-icon">${icon}</span>
                <div class="wan-interface-info">
                    <div class="wan-interface-name">${info.name} (${iface})</div>
                    <div class="wan-interface-ip">${info.ip || 'Нет IP'}</div>
                </div>
                <div class="wan-interface-status ${statusClass}"></div>
            </div>
        `;
    }
    container.innerHTML = html;
}

// Update modem info
async function updateModemInfo() {
    try {
        const response = await fetch('api.php?action=modem_status');
        const data = await response.json();

        statusData.modem = data;

        const modemInfo = document.getElementById('modemInfo');

        if (data.detected) {
            modemInfo.style.display = 'block';
            document.getElementById('modemName').textContent = data.modem || 'USB Модем';
            document.getElementById('modemSignal').textContent = data.signal ? `📶 ${data.signal}%` : '-';
            document.getElementById('modemOperator').textContent = data.operator || '-';
            document.getElementById('modemState').textContent = data.state || data.status || '-';
        } else {
            modemInfo.style.display = 'none';
        }
    } catch (error) {
        console.error('Modem status error:', error);
    }
}

// Switch WAN interface
async function switchWAN(target) {
    showToast(`Переключение на ${target}...`, 'info');

    try {
        const response = await fetch('api.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-CSRF-Token': csrfToken
            },
            body: `action=wan_switch&target=${encodeURIComponent(target)}&csrf_token=${encodeURIComponent(csrfToken)}`
        });

        if (response.status === 401) {
            showToast('Сессия истекла', 'warning');
            setTimeout(() => window.location.href = 'login.html', 1500);
            return;
        }

        const data = await response.json();

        if (data.success) {
            showToast(data.message || 'WAN переключен', 'success');
        } else {
            showToast(data.message || 'Ошибка переключения', 'error');
        }

        // Update status
        updateWANStatus();

    } catch (error) {
        console.error('WAN switch error:', error);
        showToast('Ошибка переключения WAN', 'error');
    }
}

// Setup modem
async function setupModem() {
    const apn = prompt('Введите APN вашего оператора:', 'internet');
    if (!apn) return;

    showToast('Настройка модема...', 'info');

    try {
        const response = await fetch('api.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-CSRF-Token': csrfToken
            },
            body: `action=modem_setup&apn=${encodeURIComponent(apn)}&csrf_token=${encodeURIComponent(csrfToken)}`
        });

        const data = await response.json();

        if (data.success) {
            showToast('Модем настроен!', 'success');
        } else {
            showToast(data.message || 'Ошибка настройки модема', 'error');
        }

        // Update status
        updateWANStatus();

    } catch (error) {
        console.error('Modem setup error:', error);
        showToast('Ошибка настройки модема', 'error');
    }
}

// Update Public IP
async function updatePublicIP() {
    try {
        const response = await fetch('api.php?action=public_ip');
        const data = await response.json();

        statusData.ip = data;

        document.getElementById('publicIP').textContent = data.ip || 'Проверка...';
        document.getElementById('ipCountry').textContent = data.country || '-';
        document.getElementById('ipCity').textContent = data.city || '-';
        document.getElementById('ipOrg').textContent = data.org || '-';

        // Update location marker position based on coordinates (if available)
        updateLocationMarker(data);
    } catch (error) {
        console.error('Public IP error:', error);
        document.getElementById('publicIP').textContent = 'Ошибка';
    }
}

// Update location marker on map
function updateLocationMarker(data) {
    const marker = document.getElementById('locationMarker');
    if (data.lat && data.lon) {
        // Simple conversion of lat/lon to percentage position
        const x = ((parseFloat(data.lon) + 180) / 360) * 100;
        const y = ((90 - parseFloat(data.lat)) / 180) * 100;
        marker.style.left = `${x}%`;
        marker.style.top = `${y}%`;
    }
}

// Update System Stats
async function updateSystemStats() {
    try {
        const response = await fetch('api.php?action=system_stats');
        const data = await response.json();

        statusData.system = data;

        // CPU
        const cpuPercent = parseFloat(data.cpu) || 0;
        updateStatRing('cpuRing', cpuPercent, 'cpuValue', `${cpuPercent.toFixed(0)}%`);

        // Memory
        const memPercent = parseFloat(data.memory) || 0;
        updateStatRing('memRing', memPercent, 'memValue', `${memPercent.toFixed(0)}%`);

        // Temperature
        const temp = parseFloat(data.temperature) || 0;
        const tempPercent = Math.min((temp / 80) * 100, 100);
        updateStatRing('tempRing', tempPercent, 'tempValue', `${temp.toFixed(0)}°C`, temp);

        // Uptime
        if (data.uptime) {
            document.getElementById('uptimeValue').textContent = data.uptime;
        }
    } catch (error) {
        console.error('System stats error:', error);
    }
}

// Update circular stat ring
function updateStatRing(ringId, percent, valueId, valueText, temp = null) {
    const ring = document.getElementById(ringId);
    const circumference = 2 * Math.PI * 40; // radius = 40
    const offset = circumference - (percent / 100) * circumference;
    ring.style.strokeDashoffset = offset;

    document.getElementById(valueId).textContent = valueText;

    // Color based on value or temperature
    if (temp !== null) {
        if (temp > 70) {
            ring.style.stroke = 'var(--danger)';
        } else if (temp > 60) {
            ring.style.stroke = 'var(--warning)';
        } else {
            ring.style.stroke = 'var(--success)';
        }
    } else if (percent > 80) {
        ring.style.stroke = 'var(--danger)';
    } else if (percent > 60) {
        ring.style.stroke = 'var(--warning)';
    } else {
        ring.style.stroke = 'var(--accent-primary)';
    }
}

// Update Main Status Badge
function updateMainStatus() {
    const statusText = document.getElementById('statusText');
    const statusDot = document.querySelector('.status-dot');
    const statusRing = document.getElementById('statusRing');

    const vpnActive = statusData.vpn?.active || false;
    const v2rayActive = statusData.v2ray?.active || false;
    const torActive = statusData.tor?.active || false;

    let protectionLevel = 0;
    if (vpnActive) protectionLevel++;
    if (v2rayActive) protectionLevel++;
    if (torActive) protectionLevel++;

    // Calculate ring progress
    const maxLevel = 3;
    const circumference = 2 * Math.PI * 18;
    const offset = circumference - (protectionLevel / maxLevel) * circumference;
    statusRing.style.strokeDashoffset = offset;

    if (protectionLevel >= 2) {
        statusText.textContent = '🔒 Полная защита';
        statusDot.style.background = 'var(--success)';
        statusRing.style.stroke = 'var(--success)';
    } else if (protectionLevel === 1) {
        statusText.textContent = '⚠️ Частичная защита';
        statusDot.style.background = 'var(--warning)';
        statusRing.style.stroke = 'var(--warning)';
    } else {
        statusText.textContent = '❌ Не защищен';
        statusDot.style.background = 'var(--danger)';
        statusRing.style.stroke = 'var(--danger)';
    }
}

// Update Proxy Chain Visualization
function updateProxyChain() {
    const vpnActive = statusData.vpn?.active || false;
    const v2rayActive = statusData.v2ray?.active || false;
    const wifiActive = statusData.wifi?.active || false;

    // Update chain nodes
    const chainVpn = document.getElementById('chainVpn');
    const chainV2ray = document.getElementById('chainV2ray');
    const chainRouter = document.getElementById('chainRouter');

    // Update arrows
    const arrowWifi = document.getElementById('arrowWifi');
    const arrowVpn = document.getElementById('arrowVpn');
    const arrowV2ray = document.getElementById('arrowV2ray');
    const arrowInternet = document.getElementById('arrowInternet');

    // WiFi arrow (client to router)
    if (wifiActive) {
        arrowWifi.classList.add('active');
        chainRouter.classList.add('active');
    } else {
        arrowWifi.classList.remove('active');
    }

    // VPN
    if (vpnActive) {
        chainVpn.classList.add('active');
        chainVpn.classList.remove('inactive');
        arrowVpn.classList.add('active');
    } else {
        chainVpn.classList.remove('active');
        chainVpn.classList.add('inactive');
        arrowVpn.classList.remove('active');
    }

    // V2Ray
    if (v2rayActive) {
        chainV2ray.classList.add('active');
        chainV2ray.classList.remove('inactive');
        arrowV2ray.classList.add('active');
    } else {
        chainV2ray.classList.remove('active');
        chainV2ray.classList.add('inactive');
        arrowV2ray.classList.remove('active');
    }

    // Internet arrow (active if any protection is active)
    if (vpnActive || v2rayActive) {
        arrowInternet.classList.add('active');
    } else {
        arrowInternet.classList.remove('active');
    }
}

// Control Functions

async function toggleVPN() {
    const isActive = statusData.vpn?.active || false;
    const action = isActive ? 'vpn_stop' : 'vpn_start';

    await executeAction(action, isActive ? 'Остановка VPN...' : 'Запуск VPN...');
}

async function restartVPN() {
    await executeAction('vpn_restart', 'Перезапуск VPN...');
}

async function toggleTor() {
    const isActive = statusData.tor?.active || false;
    const action = isActive ? 'tor_stop' : 'tor_start';

    await executeAction(action, isActive ? 'Остановка Tor...' : 'Запуск Tor...');
}

async function toggleWiFi() {
    const isActive = statusData.wifi?.active || false;
    const action = isActive ? 'wifi_stop' : 'wifi_start';

    await executeAction(action, isActive ? 'Остановка WiFi...' : 'Запуск WiFi...');
}

async function startAll() {
    await executeAction('start_all', 'Запуск всех сервисов...');
}

async function stopAll() {
    if (confirm('Остановить все сервисы? Вы потеряете защиту!')) {
        await executeAction('stop_all', 'Остановка всех сервисов...');
    }
}

async function restartAll() {
    if (confirm('Перезапустить все сервисы?')) {
        await executeAction('restart_all', 'Перезапуск всех сервисов...');
    }
}

async function runTests() {
    await executeAction('run_tests', 'Запуск тестов безопасности...');

    // Open logs to show test results
    setTimeout(() => {
        refreshLogs();
    }, 2000);
}

function openV2rayUI() {
    window.open('http://' + window.location.hostname + ':2017', '_blank');
}

async function checkIP() {
    showToast('Проверка IP...', 'info');
    await updatePublicIP();
}

async function refreshLogs() {
    try {
        const response = await fetch('api.php?action=get_logs');
        const data = await response.json();

        const logsElement = document.getElementById('logs');
        logsElement.innerHTML = '<pre>' + (data.logs || 'Нет логов') + '</pre>';

        // Auto-scroll to bottom
        logsElement.scrollTop = logsElement.scrollHeight;
    } catch (error) {
        console.error('Logs error:', error);
    }
}

// Execute action with feedback
async function executeAction(action, message) {
    console.log('Executing:', action);

    showToast(message, 'info');

    try {
        const response = await fetch('api.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-CSRF-Token': csrfToken
            },
            body: 'action=' + action + '&csrf_token=' + encodeURIComponent(csrfToken)
        });

        // Check for auth error
        if (response.status === 401) {
            showToast('Сессия истекла. Перенаправление...', 'warning');
            setTimeout(() => window.location.href = 'login.html', 1500);
            return;
        }

        const data = await response.json();

        if (data.success) {
            showToast(data.message || 'Выполнено!', 'success');
        } else {
            showToast(data.message || data.error || 'Ошибка!', 'error');
        }

        // Update status immediately
        updateAll();

    } catch (error) {
        console.error('Action error:', error);
        showToast('Ошибка выполнения!', 'error');
    }
}

// Toast notification system
function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;

    const icons = {
        success: '✓',
        error: '✕',
        warning: '⚠',
        info: 'ℹ'
    };

    toast.innerHTML = `
        <span class="toast-icon">${icons[type] || icons.info}</span>
        <span class="toast-message">${message}</span>
    `;

    container.appendChild(toast);

    // Remove after 3 seconds
    setTimeout(() => {
        toast.style.animation = 'slideOut 0.3s ease forwards';
        setTimeout(() => {
            toast.remove();
        }, 300);
    }, 3000);
}

// Add slideOut animation dynamically
const style = document.createElement('style');
style.textContent = `
    @keyframes slideOut {
        from {
            transform: translateX(0);
            opacity: 1;
        }
        to {
            transform: translateX(100%);
            opacity: 0;
        }
    }
    .toast-icon {
        font-size: 1.2rem;
        font-weight: bold;
    }
    .toast.success .toast-icon { color: var(--success); }
    .toast.error .toast-icon { color: var(--danger); }
    .toast.warning .toast-icon { color: var(--warning); }
    .toast.info .toast-icon { color: var(--accent-primary); }
`;
document.head.appendChild(style);

// Cleanup on page unload
window.addEventListener('beforeunload', function () {
    if (updateInterval) {
        clearInterval(updateInterval);
    }
});
