[RU](LAB.ru.md) · **UA** · [EN](LAB.md)

# Тестова лабораторія: запуск ShadowPi без Raspberry Pi

Лабораторія запускає **справжній** `scripts/master-install.sh`, справжню вебпанель і
справжні скрипти firewall у Docker на Debian bookworm **arm64** — тій самій архітектурі, що
в Raspberry Pi. Потім вона перевіряє кожне твердження проєкту з погляду клієнта.

```bash
cd lab
make lab-test     # збирає все з нуля, двічі встановлює систему, виконує 43 перевірки (~10 хв)
make lab-down     # видаляє лабораторію
```

Результати записуються в `lab/out/results.md`, логи — в `lab/out/`.

## Топологія

```
 client 10.0.0.50 ── "Wi-Fi" (lan) ── wlan0 10.0.0.1 [router: real installer, systemd]
                                               eth0 172.30.0.10
                                                 │  (wan)
                         vpnserver 172.30.0.20 ──┤── whoami 198.51.100.7 = "a website on the internet"
                         (OpenVPN, stands in       (answers with the caller's IP; also the ISP gateway
                          for Windscribe)           and a "public DNS" that knows vpn.lab.test)
```

Сайт повідомляє, який IP він бачить:

| Сайт бачить | Що це означає |
|---|---|
| `172.30.0.20` | Трафік пройшов через VPN. Це правильно. |
| `172.30.0.10` | Справжня WAN-адреса роутера. Це витік. |
| `10.0.0.50` | Сам клієнт. Це витік. |
| `none` | Трафік заблоковано. |

## Що справжнє, а що емулюється

| Частина | У лабораторії | Примітки |
|---|---|---|
| `master-install.sh` | **Справжній**, запускається без змін зі сценарними відповідями | Другий запуск навмисно ламає контрольну суму v2rayA, див. «Обхідні прийоми» нижче |
| Панель nginx + PHP, sudoers | **Справжні** | Ті самі шляхи й права, що на Pi |
| `killswitch.sh`, `setup-v2ray-redirect.sh`, `start/stop/restart-all.sh` | **Справжні** | |
| Клієнт OpenVPN | **Справжній**, налаштований слово в слово за docs/03 | Замість Windscribe — лабораторний сервер OpenVPN |
| Tor, Xray, dnsmasq | **Справжні** пакети | Tor підключається до справжньої мережі Tor через лабораторний VPN (T3) |
| v2rayA | **Справжній**, ставиться із закріпленого релізу (перевірка I4) | Решта перевірок іде на другому встановленні, де v2rayA навмисно відхилено (I2), і показує, що роутер працює без нього |
| Прозорий проксі V2Ray | **Справжнє ядро Xray** (ставить інсталятор) з inbound `dokodemo-door` із docs/04 на :12345 | Outbound — `freedom` замість VLESS-сервера; журнал доступу Xray показує, які з'єднання пройшли через проксі |
| Wi-Fi хотспот (hostapd) | **Емулюється** | Його замінює Docker-мережа з іменем `wlan0`, тому hostapd не запускається |
| Інтерфейси 4G-модема | **Емулюються**, лише для kill switch | Dummy-інтерфейси з іменами `usb0`, `eth1`, `enx…` (`lab/router/lab-4g.sh`); їхній лічильник пакетів показує, що випускає firewall |
| 4G-модем, ModemManager, failover | **Не покрито** | Потрібне залізо |
| Перезавантаження | **Емулюється** | `docker compose restart router`: systemd завантажується знову, усі правила iptables зникають |
| Продуктивність Pi, SD-картка, живлення | **Не покрито** | Потрібне залізо |

### Обхідні прийоми лабораторії

Лабораторія робить кілька речей, яких немає в реальному встановленні. Кожну видно в
`lab/router/*.sh` або прокоментовано в `lab/lab-test.sh`. Жодна не змінює файли проєкту.

1. **Перейменування інтерфейсів.** Інтерфейси Docker перейменовуються на `eth0` і `wlan0`.
2. **З образу роутера видалено `policy-rc.d`.** Docker-образ debian забороняє apt запускати
   сервіси; справжня система — ні. Із цим файлом лабораторія повідомляла «панель відповідає
   502 після встановлення», чого на реальному встановленні немає.
3. **Друге встановлення з хибною контрольною сумою v2rayA.** У копії інсталятора всередині
   контейнера закріплені значення SHA-256 замінюються нулями, щоб перевірити, що пакет
   відхиляється, а встановлення однаково доходить до кінця.
4. **Підставний Xray замість налаштованого v2rayA** (`lab/router/lab-xray-standin.sh`),
   описаний у таблиці вище.
5. **Скидання лічильника входів після P2.** Усі запити лабораторії йдуть з однієї адреси, тому
   після тесту блокування файл лічильника видаляється. Це те саме, що зачекати 5 хвилин.
6. **Тайм-аут бездіяльності через правку файлу сесії** (P6): `last_activity` виставляється на
   1970 рік замість години очікування.
7. **Dummy-інтерфейси 4G** (`lab/router/lab-4g.sh`) і **DNS-сервер з одним іменем** на
   контейнері сайту — для перевірок kill switch K3a, K3b і K6.

8. **Виправлення контрольних сум TCP на лабораторному VPN-сервері.** Docker Desktop віддає
   пакети зі справжнього інтернету з незаповненими контрольними сумами TCP. Після пересилання у
   VPN-тунель роутер їх відкидав. Сервер перераховує їх (`tc … action csum`), тому роутер може
   дістатися справжньої мережі Tor.

9. **Сертифікат панелі підтверджується один раз.** Він самопідписаний, тому лабораторія додає
   його до сховища довірених сертифікатів роутера — так само адміністратор підтверджує його в
   браузері. Після цього кожен запит до панелі перевіряє сертифікат по-справжньому.

Рядки клієнта OpenVPN читаються прямо з `docs/03_OPENVPN_SETUP.md`, тому зміна документа
тестується автоматично.

## Другий раунд: hotfix (10–11.11.2026)

Після кожного виправлення лабораторія проганялася повністю з нуля. «Було» — результат першого прогону.

| ID | Було | Стало | Що змінилося |
|---|---|---|---|
| D2 | FAIL | PASS | З конфігу dnsmasq прибрано `log-queries` / `log-dhcp` (інсталятор і docs/06). |
| P4 | FAIL | PASS | Новий ID сесії під час входу. Одна функція `start_secure_session()` для всіх точок входу: strict mode, `HttpOnly`, `SameSite=Strict`, `Secure` лише через HTTPS. |
| P5, P6 | нові | PASS | Прапорці cookie; тайм-аут бездіяльності (`SESSION_LIFETIME`) і загальний термін життя, бо відкрита панель опитує сервер кожні 5 секунд і ніколи не простоює. |
| H1 | нова | PASS | Панель працює через HTTPS із самопідписаним сертифікатом, дійсним для `10.0.0.1` і `anonrouter.local`; порт 8080 лише перенаправляє. Cookie сесії тепер ще й `Secure` (P5). |
| P2 | FAIL | PASS | Невдалі входи рахуються в `/var/lib/shadowpi/login-attempts.json` (flock) за адресою клієнта, з блокуванням, що подвоюється, і загальним лічильником. Перевірка йде до пароля; якщо файл недоступний, вхід закривається. |
| P7 | нова | PASS | nginx basic auth перед панеллю використовував той самий пароль і не мав блокування, тому P2 можна було обійти через нього. Спочатку записано як FAIL, потім шар nginx прибрано: єдиний вхід — логін панелі із серверним блокуванням. |
| B2 | FAIL | PASS | `start-all.sh`, `stop-all.sh`, `restart-all.sh` завершуються з ненульовим кодом, якщо обов'язковий крок не вдався; API повертає цей код. `startWiFi` перевіряє і dnsmasq. |
| B4 | нова | PASS | «Перемкнути WAN» повідомляє про помилку. Крім того, панель викликала `wan-switch.sh usb0`, що скрипт відхиляє; тепер викликається `wan-switch.sh switch usb0`. |
| K3 | FAIL | замінено | Перевірка рахувала правила, у яких названо `usb0`/`eth1`/`enx*`. Політика DROP і так блокувала ці інтерфейси, витоку не було; справжня проблема була протилежною (див. K3b). Замінено на K3a і K3b, які перевіряють поведінку на dummy-інтерфейсах. |
| K3a | нова | PASS | Поки VPN не працює, через 4G-інтерфейс не виходить нічого ні від роутера, ні від клієнта. |
| K3b | нова | PASS | VPN-handshake дозволено через 4G-інтерфейс. До виправлення його було дозволено лише на `eth0`/`wwan0`, і failover не міг підняти VPN. Правила більше не називають WAN-інтерфейси. |
| K2 | FAIL | PASS | Роутеру дозволено лише адресу, порт і протокол самого VPN-сервера, узяті з рядків `remote`. |
| K6 | нова | PASS | З hostname у `remote` (так постачають провайдери) VPN узагалі не міг перепідключитися під kill switch: DNS роутера заблоковано. Тепер скрипт резолвить ім'я в момент запуску й закріплює його в правилах і в `/etc/hosts`. Компроміси: docs/08. |
| K5 | нова | PASS | Ніщо не вмикало kill switch під час завантаження. Показано так: новий юніт вимкнено, лабораторний роутер перезавантажено — політик DROP немає, сайт бачить самого клієнта (`10.0.0.50`). Тепер інсталятор вмикає `shadowpi-killswitch.service` (`Before=network-pre.target`). |
| I3 | FAIL | PASS | Здебільшого артефакт лабораторії: Docker-образ debian забороняє apt запускати сервіси (`policy-rc.d`). Файл видалено з лабораторного образу; інсталятор тепер ще й запускає php-fpm явно. |
| D1 | PASS | PASS | **Зламалася, коли лабораторію зробили реалістичною, потім виправлена.** Коли сервіси запускає apt, systemd-resolved займає `127.0.0.53:53` раніше за dnsmasq, і dnsmasq (який слухає всі адреси) не запускався: у клієнтів не було ні DNS, ні DHCP. Стара лабораторія це приховувала. Виправлено через `bind-dynamic`. |
| I2 | FAIL | PASS | `rfkill` встановлюється, його збій — попередження. Перевірка тепер ще навмисно ламає контрольну суму v2rayA й очікує, що інсталятор відхилить пакет і однаково дійде до кінця. |
| I1 | FAIL | PASS | v2rayA необов'язковий і більше не береться з `apt.v2raya.org` (його ланцюжку сертифікатів Debian не довіряє; перевірки TLS не вимикаються). Закріплений реліз ставиться, лише якщо збігся SHA-256. |
| I4 | нова | PASS | v2rayA справді ставиться із закріпленого релізу й працює. |
| I5 | нова | PASS | Інсталятор не друкує паролі Wi-Fi та панелі й не передає пароль панелі аргументом процесу; файли з паролями недоступні іншим користувачам. |
| T1 | FAIL | PASS | Режим Paranoid тепер маршрутизує: TCP клієнтів іде на TransPort Tor, їхній DNS — на DNSPort (`setup-tor-redirect.sh`), а сам Tor виходить через VPN. Спочатку режим лише позначили експериментальним, потім реалізували. Якщо Tor не працює, клієнти не мають інтернету; на звичайний VPN вони не відкочуються. |
| T3 | нова | PASS | Справжній сайт (check.torproject.org) бачить вихідний вузол Tor. Лабораторний роутер дістається справжньої мережі Tor через лабораторний VPN-сервер. |
| T4 | нова | PASS | Трафік клієнтів, який Tor не вміє переносити (ICMP, UDP), відкидається, а не виходить через VPN. |
| T5 | нова | PASS | Повторний запуск `killswitch.sh` (він скидає всі правила) повертає редирект у Tor, тому клієнти не відкочуються мовчки на звичайний VPN. |
| T2 | нова | PASS | Вимкнення режиму прибирає правила й повертає клієнтів на VPN. (Поки маршрутизації через Tor не було, T2 перевіряла позначки «експериментальний».) |

Також виправлено без перевірки в лабораторії: перегляд логів і список WAN у панелі більше не
використовують `innerHTML` (збережена XSS через вміст логів), а з `api.php` видалено мертву
перевірку «локальної мережі».

Дві знахідки стосувалися самої лабораторії, а не проєкту: перевірка K3 ставила не те питання, а
`policy-rc.d` у Docker-образі водночас вигадав I3 і приховував D1. Обидві виправлено в
лабораторії окремими комітами.

## Фінальний прогін

`cd lab && ./lab-test.sh`, з нуля, на підсумковому стані цієї гілки. Докази для кожного рядка
(що побачив сайт, що відповіла панель) лежать у `lab/out/results.md`. Назви перевірок наведено
так, як їх друкує `lab-test.sh`, тобто англійською.

| ID | Result | Check |
|---|---|---|
| I1 | PASS | Installer finishes on Debian bookworm arm64 |
| I4 | PASS | v2rayA is installed from the pinned release (SHA-256 checked) and runs |
| I2 | PASS | Installer refuses v2rayA with a wrong SHA-256 and still finishes |
| I5 | PASS | Installer does not print the Wi-Fi or panel password, and keeps them in non-world-readable files |
| H1 | PASS | Panel is served over HTTPS with a certificate valid for its address; plain HTTP only redirects |
| I3 | PASS | Panel API answers right after install (before reboot) |
| P1 | PASS | API refuses requests without login |
| P2 | PASS | 6 wrong passwords (new cookie each) lock the login |
| P7 | PASS | Panel password cannot be guessed without limit through nginx basic auth |
| P3 | PASS | Write action without CSRF token is refused |
| P4 | PASS | Session ID changes at login (no session fixation) |
| P5 | PASS | Session cookie is Secure, HttpOnly and SameSite=Strict |
| P6 | PASS | Idle session expires (SESSION_LIFETIME) |
| V1 | PASS | Client reaches the internet through the VPN (docs config) |
| V2 | PASS | Panel shows the VPN IP |
| V3.80 | PASS | Client → site:80 goes through the VPN |
| V3.8000 | PASS | Client → site:8000 goes through the VPN |
| B1 | PASS | 'Start all' runs the whole start script |
| B2 | PASS | 'Start all' reports failure when steps fail |
| B4 | PASS | 'Switch WAN' to a missing interface reports failure |
| X3 | PASS | 'Start all' does not cut clients off when the proxy is not running |
| D1 | PASS | Client DNS works through the router |
| D2 | PASS | Router does not log clients' DNS queries |
| B3 | PASS | 'Restart all' restarts services |
| T1 | PASS | Tor 'Paranoid' mode sends client traffic into Tor |
| T3 | PASS | In Paranoid mode a real website sees a Tor exit (needs the real Tor network) |
| T4 | PASS | In Paranoid mode client traffic Tor cannot carry (ICMP, UDP) is dropped, not sent through the VPN |
| T5 | PASS | Re-running the kill switch keeps Paranoid mode on (no silent fall back to the plain VPN) |
| T2 | PASS | Turning Paranoid mode off puts clients back on the VPN |
| X1 | PASS | V2Ray redirect script applies cleanly when the proxy listens |
| X4 | PASS | Running the script twice leaves one rule set |
| X2.80 | PASS | Client → site:80 goes through V2Ray, then the VPN |
| X2.443 | PASS | Client → site:443 goes through V2Ray, then the VPN |
| X2.8000 | PASS | Client → site:8000 goes through V2Ray, then the VPN |
| X5 | PASS | Panel on the router stays reachable (not sent to the proxy) |
| K1.80 | PASS | VPN down: client cannot reach site:80 |
| K1.8000 | PASS | VPN down: client cannot reach site:8000 |
| K2 | PASS | VPN down: router itself cannot reach the internet on tcp/443 |
| K3a | PASS | VPN down: nothing leaves through a 4G interface (usb0, eth1, enx*) |
| K3b | PASS | VPN handshake is allowed through a 4G interface (so failover can bring the VPN up) |
| K4 | PASS | IPv6 disabled and blocked |
| K6 | PASS | VPN reconnects under the kill switch when 'remote' is a hostname |
| K5 | PASS | After a reboot the kill switch is on before anything else starts |

PASS 43 · FAIL 0 · SKIP 0 · 2026-11-12 20:51 UTC

Жодна перевірка не падає. Те, що лабораторія покрити не може (залізо, хоп V2Ray після Tor),
описано в [ROADMAP.ua.md](ROADMAP.ua.md).

Перебіг робіт: перший прогін 8 PASS / 16 FAIL → виправлення V1: 9 / 15 → виправлення шляхів і
нова перевірка X3: 12 / 13 (25 перевірок) → виправлення V2Ray, плюс X4 і X5: 19 / 10
(29 перевірок) → hotfix-раунд, плюс 12 нових перевірок і K3, розділена на дві:
37 / 2 (39 перевірок) → прибрано nginx basic auth (P7): 38 / 1 (39 перевірок) → реалізовано маршрутизацію через Tor, плюс T3, T4 і T5: 42 / 0 (42 перевірки) → HTTPS для панелі (H1): **43 PASS / 0 FAIL (43 перевірки)**.

## Історія: знахідки першого прогону (10.11.2026)

Це стан до hotfix-раунду, залишений як запис. Поточний стан — у двох розділах вище.

| ID | Результат | Знахідка |
|---|---|---|
| I1 | FAIL | apt-репозиторій v2rayA використовує ланцюжок Let's Encrypt **YE2**, якому сховище CA в bookworm не довіряє, тому інсталятор зупиняється. |
| I2 | FAIL | На чистому Debian не встановлено `rfkill`, і інсталятор падає на останньому кроці. У Raspberry Pi OS він зазвичай є. |
| I3 | FAIL | Одразу після встановлення панель відповідає 502, бо php-fpm не запущено. Після перезавантаження працює. |
| P2 | FAIL | Блокування логіну зберігається в PHP-сесії. Видалення cookie його скидає, тому перебір пароля не обмежено. |
| P4 | FAIL | ID сесії не оновлюється під час входу (session fixation). |
| V1 | ✅ виправлено | З `pull-filter ignore "redirect-gateway"` з документації клієнти **не мали інтернету**, поки VPN працював: типовий маршрут залишався на `eth0`, і kill switch його відкидав. У docs/03 тепер `redirect-gateway def1`, K1 і далі проходить. |
| V2 | ✅ виправлено | Скрипти up/down із docs/03 писали в `/opt/anon-router/status/`, а панель читає `/opt/shadowpi/status/`, тому IP VPN ніколи не показувався. Усі 71 шлях `/opt/anon-router` і `/var/log/anon-router` у скриптах і документації тепер вказують на встановлені шляхи. |
| D2 | FAIL | `dnsmasq` ставився з `log-queries`, тобто приватний роутер логував кожен DNS-запит клієнтів. |
| B1, B3 | ✅ виправлено | `start-all.sh` і `restart-all.sh` викликали неіснуючий `/opt/anon-router/scripts/...`, тому «Перезапустити все» нічого не робило. Виправлено разом із V2. |
| B2 | FAIL | Панель відповідає `success: true`, навіть коли скрипт завершився з помилкою (немає v2raya, не запускається hostapd). |
| X3 | ✅ виправлено | «Запустити все» вмикало редирект V2Ray, навіть коли порт 12345 ніхто не слухав, і всі TCP-з'єднання клієнтів, крім портів 80/443, обривалися (це було приховано, доки не виправили B1). Тепер скрипт відмовляється, і клієнти залишаються на VPN. |
| T1 | FAIL | Режим Tor «Paranoid» запускає Tor, але жодне правило не спрямовує в нього трафік клієнтів, тож трафік не змінюється. |
| X1 | ✅ виправлено | У `setup-v2ray-redirect.sh` була одруківка `-j RET URN`. Скрипт переписано, він став єдиним джерелом; docs/04 посилається на нього, а не тримає власну копію. |
| X2 | ✅ виправлено | Редирект пропускав **порти** призначення 80/443, тобто майже весь вебтрафік. Тепер він пропускає **адреси** призначення (сам роутер, приватні діапазони). Доведено журналом доступу Xray для портів 80, 443 і 8000. |
| X4 | ✅ нова, PASS | Скрипт ідемпотентний: два запуски залишають один набір правил. Старий під час кожного запуску додавав дубль переходу в PREROUTING. |
| X5 | ✅ нова, PASS | Панель на роутері залишається доступною з Wi-Fi і не потрапляє в проксі. |
| — | ✅ виправлено | Навіть із працюючим V2Ray політика INPUT DROP у kill switch відкинула б перенаправлені з'єднання на :12345. Тепер скрипт відкриває цей порт на `wlan0`. |
| — | відкрито | docs/08_FIREWALL.md описує ще два варіанти firewall (`iptables-killswitch.sh`, nftables), які розходяться зі `scripts/killswitch.sh`. |
| K2 | FAIL | Коли VPN не працює, **сам роутер** усе ще дістається до будь-якого хоста на tcp/443 зі своїм справжнім IP, бо kill switch дозволяє `-o eth0 --dport 443` для будь-якої адреси. |
| K3 | FAIL | Kill switch покриває лише `eth0` і `wwan0`. Імена 4G-інтерфейсів, які реально використовує `wan-switch.sh` (`usb0`, `eth1`, `enx*`), не покрито. |
| — | FAIL | Документація пропонує користувачеві створити 9 скриптів, яких немає в репозиторії (`wan-failover.sh`, `route-through-tor.sh`, `connect-4g.sh`, …). Перевірки в лабораторії для цього поки немає. |
| P1, P3, V3, D1, K1, K4 | PASS | Працює: обов'язкова авторизація, CSRF, маршрутизація через VPN (після виправлення), DNS, kill switch для клієнтів і блокування IPv6. |

Kill switch для клієнтів працює: коли VPN зупинено, з хотспоту нічого не витікає (K1).

Наприкінці першого раунду: 19 PASS / 10 FAIL (29 перевірок).
