**RU** · [UA](LAB.ua.md) · [EN](LAB.md)

# Тестовая лаборатория: запуск ShadowPi без Raspberry Pi

Лаборатория запускает **настоящий** `scripts/master-install.sh`, настоящую веб-панель и
настоящие скрипты firewall в Docker на Debian bookworm **arm64** — той же архитектуре, что
у Raspberry Pi. Затем она проверяет каждое утверждение проекта с точки зрения клиента.

```bash
cd lab
make lab-test     # собирает всё с нуля, дважды ставит систему, выполняет 42 проверки (~10 мин)
make lab-down     # удаляет лабораторию
```

Результаты пишутся в `lab/out/results.md`, логи — в `lab/out/`.

## Топология

```
 client 10.0.0.50 ── "Wi-Fi" (lan) ── wlan0 10.0.0.1 [router: real installer, systemd]
                                               eth0 172.30.0.10
                                                 │  (wan)
                         vpnserver 172.30.0.20 ──┤── whoami 198.51.100.7 = "a website on the internet"
                         (OpenVPN, stands in       (answers with the caller's IP; also the ISP gateway
                          for Windscribe)           and a "public DNS" that knows vpn.lab.test)
```

Сайт сообщает, какой IP он видит:

| Сайт видит | Что это значит |
|---|---|
| `172.30.0.20` | Трафик прошёл через VPN. Это правильно. |
| `172.30.0.10` | Настоящий WAN-адрес роутера. Это утечка. |
| `10.0.0.50` | Сам клиент. Это утечка. |
| `none` | Трафик заблокирован. |

## Что настоящее, а что эмулируется

| Часть | В лаборатории | Примечания |
|---|---|---|
| `master-install.sh` | **Настоящий**, запускается без изменений со сценарными ответами | Второй запуск намеренно ломает контрольную сумму v2rayA, см. «Обходные приёмы» ниже |
| Панель nginx + PHP, sudoers | **Настоящие** | Те же пути и права, что на Pi |
| `killswitch.sh`, `setup-v2ray-redirect.sh`, `start/stop/restart-all.sh` | **Настоящие** | |
| Клиент OpenVPN | **Настоящий**, настроен слово в слово по docs/03 | Вместо Windscribe — лабораторный сервер OpenVPN |
| Tor, Xray, dnsmasq | **Настоящие** пакеты | Tor подключается к настоящей сети Tor через лабораторный VPN (T3) |
| v2rayA | **Настоящий**, ставится из закреплённого релиза (проверка I4) | Остальные проверки идут на второй установке, где v2rayA намеренно отклонён (I2), и показывают, что роутер работает без него |
| Прозрачный прокси V2Ray | **Настоящее ядро Xray** (ставит установщик) с inbound `dokodemo-door` из docs/04 на :12345 | Outbound — `freedom` вместо VLESS-сервера; журнал доступа Xray показывает, какие соединения прошли через прокси |
| Wi-Fi хотспот (hostapd) | **Эмулируется** | Его заменяет Docker-сеть с именем `wlan0`, поэтому hostapd не запускается |
| Интерфейсы 4G-модема | **Эмулируются**, только для kill switch | Dummy-интерфейсы с именами `usb0`, `eth1`, `enx…` (`lab/router/lab-4g.sh`); их счётчик пакетов показывает, что выпускает firewall |
| 4G-модем, ModemManager, failover | **Не покрыто** | Нужно железо |
| Перезагрузка | **Эмулируется** | `docker compose restart router`: systemd загружается заново, все правила iptables исчезают |
| Производительность Pi, SD-карта, питание | **Не покрыто** | Нужно железо |

### Обходные приёмы лаборатории

Лаборатория делает несколько вещей, которых нет в реальной установке. Каждая видна в
`lab/router/*.sh` или прокомментирована в `lab/lab-test.sh`. Ни одна не меняет файлы проекта.

1. **Переименование интерфейсов.** Интерфейсы Docker переименовываются в `eth0` и `wlan0`.
2. **Из образа роутера удалён `policy-rc.d`.** Docker-образ debian запрещает apt запускать
   сервисы; настоящая система — нет. С этим файлом лаборатория сообщала «панель отвечает 502
   после установки», чего на реальной установке нет.
3. **Вторая установка с неверной контрольной суммой v2rayA.** В копии установщика внутри
   контейнера закреплённые значения SHA-256 заменяются нулями, чтобы проверить, что пакет
   отклоняется, а установка всё равно доходит до конца.
4. **Подставной Xray вместо настроенного v2rayA** (`lab/router/lab-xray-standin.sh`), описан
   в таблице выше.
5. **Сброс счётчика входов после P2.** Все запросы лаборатории идут с одного адреса, поэтому
   после теста блокировки файл счётчика удаляется. Это то же самое, что подождать 5 минут.
6. **Таймаут простоя через правку файла сессии** (P6): `last_activity` выставляется в 1970
   год вместо часа ожидания.
7. **Dummy-интерфейсы 4G** (`lab/router/lab-4g.sh`) и **DNS-сервер с одним именем** на
   контейнере сайта — для проверок kill switch K3a, K3b и K6.

8. **Исправление контрольных сумм TCP на лабораторном VPN-сервере.** Docker Desktop отдаёт
   пакеты из настоящего интернета с незаполненными контрольными суммами TCP. После пересылки в
   VPN-туннель роутер их отбрасывал. Сервер пересчитывает их (`tc … action csum`), поэтому
   роутер может достучаться до настоящей сети Tor.

Строки клиента OpenVPN читаются прямо из `docs/03_OPENVPN_SETUP.md`, поэтому изменение
документа тестируется автоматически.

## Второй раунд: hotfix (10–11.11.2026)

После каждого исправления лаборатория прогонялась целиком с нуля. «Было» — результат первого прогона.

| ID | Было | Стало | Что изменилось |
|---|---|---|---|
| D2 | FAIL | PASS | Из конфига dnsmasq убраны `log-queries` / `log-dhcp` (установщик и docs/06). |
| P4 | FAIL | PASS | Новый ID сессии при входе. Одна функция `start_secure_session()` для всех точек входа: strict mode, `HttpOnly`, `SameSite=Strict`, `Secure` только по HTTPS. |
| P5, P6 | новые | PASS | Флаги cookie; таймаут простоя (`SESSION_LIFETIME`) и общий срок жизни, потому что открытая панель опрашивает сервер каждые 5 секунд и никогда не простаивает. |
| P2 | FAIL | PASS | Неудачные входы считаются в `/var/lib/shadowpi/login-attempts.json` (flock) по адресу клиента, с удваивающейся блокировкой и общим счётчиком. Проверка идёт до пароля; если файл недоступен, вход закрывается. |
| P7 | новая | PASS | nginx basic auth перед панелью использовал тот же пароль и не имел блокировки, поэтому P2 можно было обойти через него. Сначала записано как FAIL, затем слой nginx убран: единственный вход — логин панели с серверной блокировкой. |
| B2 | FAIL | PASS | `start-all.sh`, `stop-all.sh`, `restart-all.sh` завершаются с ненулевым кодом, если обязательный шаг не удался; API возвращает этот код. `startWiFi` проверяет и dnsmasq. |
| B4 | новая | PASS | «Переключить WAN» сообщает об ошибке. Кроме того, панель вызывала `wan-switch.sh usb0`, что скрипт отклоняет; теперь вызывается `wan-switch.sh switch usb0`. |
| K3 | FAIL | заменена | Проверка считала правила, в которых названы `usb0`/`eth1`/`enx*`. Политика DROP и так блокировала эти интерфейсы, утечки не было; настоящая проблема была обратной (см. K3b). Заменена на K3a и K3b, которые проверяют поведение на dummy-интерфейсах. |
| K3a | новая | PASS | Пока VPN не работает, через 4G-интерфейс не уходит ничего ни от роутера, ни от клиента. |
| K3b | новая | PASS | VPN-handshake разрешён через 4G-интерфейс. До исправления он был разрешён только на `eth0`/`wwan0`, и failover не мог поднять VPN. Правила больше не называют WAN-интерфейсы. |
| K2 | FAIL | PASS | Роутеру разрешён только адрес, порт и протокол самого VPN-сервера, взятые из строк `remote`. |
| K6 | новая | PASS | С hostname в `remote` (так поставляют провайдеры) VPN вообще не мог переподключиться под kill switch: DNS роутера заблокирован. Теперь скрипт резолвит имя в момент запуска и закрепляет его в правилах и в `/etc/hosts`. Компромиссы: docs/08. |
| K5 | новая | PASS | Ничто не включало kill switch при загрузке. Показано так: новый юнит отключён, лабораторный роутер перезагружен — политик DROP нет, сайт видит самого клиента (`10.0.0.50`). Теперь установщик включает `shadowpi-killswitch.service` (`Before=network-pre.target`). |
| I3 | FAIL | PASS | В основном артефакт лаборатории: Docker-образ debian запрещает apt запускать сервисы (`policy-rc.d`). Файл удалён из лабораторного образа; установщик теперь ещё и запускает php-fpm явно. |
| D1 | PASS | PASS | **Сломалась, когда лабораторию сделали реалистичной, затем исправлена.** Когда сервисы запускает apt, systemd-resolved занимает `127.0.0.53:53` раньше dnsmasq, и dnsmasq (который слушает все адреса) не запускался: у клиентов не было ни DNS, ни DHCP. Старая лаборатория это скрывала. Исправлено через `bind-dynamic`. |
| I2 | FAIL | PASS | `rfkill` устанавливается, его сбой — предупреждение. Проверка теперь ещё намеренно ломает контрольную сумму v2rayA и ожидает, что установщик отклонит пакет и всё равно дойдёт до конца. |
| I1 | FAIL | PASS | v2rayA необязателен и больше не берётся из `apt.v2raya.org` (его цепочке сертификатов Debian не доверяет; проверки TLS не отключаются). Закреплённый релиз ставится, только если совпал SHA-256. |
| I4 | новая | PASS | v2rayA действительно ставится из закреплённого релиза и работает. |
| I5 | новая | PASS | Установщик не печатает пароли Wi-Fi и панели и не передаёт пароль панели аргументом процесса; файлы с паролями недоступны остальным пользователям. |
| T1 | FAIL | PASS | Режим Paranoid теперь маршрутизирует: TCP клиентов идёт на TransPort Tor, их DNS — на DNSPort (`setup-tor-redirect.sh`), а сам Tor выходит через VPN. Сначала режим только пометили экспериментальным, затем реализовали. Если Tor не работает, у клиентов нет интернета; на обычный VPN они не откатываются. |
| T3 | новая | PASS | Настоящий сайт (check.torproject.org) видит выходной узел Tor. Лабораторный роутер достаёт до настоящей сети Tor через лабораторный VPN-сервер. |
| T4 | новая | PASS | Трафик клиентов, который Tor не умеет переносить (ICMP, UDP), отбрасывается, а не уходит через VPN. |
| T5 | новая | PASS | Повторный запуск `killswitch.sh` (он сбрасывает все правила) возвращает редирект в Tor, поэтому клиенты не откатываются молча на обычный VPN. |
| T2 | новая | PASS | Выключение режима убирает правила и возвращает клиентов на VPN. (Пока маршрутизации через Tor не было, T2 проверяла пометки «экспериментальный».) |

Также исправлено без проверки в лаборатории: просмотр логов и список WAN в панели больше не
используют `innerHTML` (хранимая XSS через содержимое логов), а из `api.php` удалена мёртвая
проверка «локальной сети».

Две находки касались самой лаборатории, а не проекта: проверка K3 задавала не тот вопрос, а
`policy-rc.d` в Docker-образе одновременно выдумал I3 и скрывал D1. Обе исправлены в
лаборатории отдельными коммитами.

## Финальный прогон

`cd lab && ./lab-test.sh`, с нуля, на итоговом состоянии этой ветки. Доказательства по каждой
строке (что увидел сайт, что ответила панель) лежат в `lab/out/results.md`. Названия проверок
приведены так, как их печатает `lab-test.sh`, то есть на английском.

| ID | Result | Check |
|---|---|---|
| I1 | PASS | Installer finishes on Debian bookworm arm64 |
| I4 | PASS | v2rayA is installed from the pinned release (SHA-256 checked) and runs |
| I2 | PASS | Installer refuses v2rayA with a wrong SHA-256 and still finishes |
| I5 | PASS | Installer does not print the Wi-Fi or panel password, and keeps them in non-world-readable files |
| I3 | PASS | Panel API answers right after install (before reboot) |
| P1 | PASS | API refuses requests without login |
| P2 | PASS | 6 wrong passwords (new cookie each) lock the login |
| P7 | PASS | Panel password cannot be guessed without limit through nginx basic auth |
| P3 | PASS | Write action without CSRF token is refused |
| P4 | PASS | Session ID changes at login (no session fixation) |
| P5 | PASS | Session cookie is HttpOnly and SameSite=Strict |
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

PASS 42 · FAIL 0 · 2026-11-12 20:22 UTC

Ни одна проверка не падает. То, что лаборатория покрыть не может (железо, хоп V2Ray после Tor),
описано в [ROADMAP.ru.md](ROADMAP.ru.md).

Ход работ: первый прогон 8 PASS / 16 FAIL → исправление V1: 9 / 15 → исправление путей и
новая проверка X3: 12 / 13 (25 проверок) → исправление V2Ray, плюс X4 и X5: 19 / 10
(29 проверок) → hotfix-раунд, плюс 12 новых проверок и K3, разделённая на две:
37 / 2 (39 проверок) → убран nginx basic auth (P7): 38 / 1 (39 проверок) → реализована маршрутизация через Tor, плюс T3, T4 и T5: **42 PASS / 0 FAIL (42 проверки)**.

## История: находки первого прогона (10.11.2026)

Это состояние до hotfix-раунда, оставлено как запись. Текущее состояние — в двух разделах выше.

| ID | Результат | Находка |
|---|---|---|
| I1 | FAIL | apt-репозиторий v2rayA использует цепочку Let's Encrypt **YE2**, которой хранилище CA в bookworm не доверяет, поэтому установщик останавливается. |
| I2 | FAIL | На чистом Debian не установлен `rfkill`, и установщик падает на последнем шаге. В Raspberry Pi OS он обычно есть. |
| I3 | FAIL | Сразу после установки панель отвечает 502, потому что php-fpm не запущен. После перезагрузки работает. |
| P2 | FAIL | Блокировка логина хранится в PHP-сессии. Удаление cookie её сбрасывает, поэтому перебор пароля не ограничен. |
| P4 | FAIL | ID сессии не обновляется при входе (session fixation). |
| V1 | ✅ исправлено | С `pull-filter ignore "redirect-gateway"` из документации у клиентов **не было интернета**, пока VPN работал: маршрут по умолчанию оставался на `eth0`, и kill switch его отбрасывал. В docs/03 теперь `redirect-gateway def1`, K1 по-прежнему проходит. |
| V2 | ✅ исправлено | Скрипты up/down из docs/03 писали в `/opt/anon-router/status/`, а панель читает `/opt/shadowpi/status/`, поэтому IP VPN никогда не показывался. Все 71 путь `/opt/anon-router` и `/var/log/anon-router` в скриптах и документации теперь указывают на установленные пути. |
| D2 | FAIL | `dnsmasq` ставился с `log-queries`, то есть приватный роутер логировал каждый DNS-запрос клиентов. |
| B1, B3 | ✅ исправлено | `start-all.sh` и `restart-all.sh` вызывали несуществующий `/opt/anon-router/scripts/...`, поэтому «Перезапустить всё» ничего не делало. Исправлено вместе с V2. |
| B2 | FAIL | Панель отвечает `success: true`, даже когда скрипт завершился с ошибкой (нет v2raya, не запускается hostapd). |
| X3 | ✅ исправлено | «Запустить всё» включало редирект V2Ray, даже когда порт 12345 никто не слушал, и все TCP-соединения клиентов, кроме портов 80/443, обрывались (это было скрыто, пока не исправили B1). Теперь скрипт отказывается, и клиенты остаются на VPN. |
| T1 | FAIL | Режим Tor «Paranoid» запускает Tor, но ни одно правило не отправляет в него трафик клиентов, так что трафик не меняется. |
| X1 | ✅ исправлено | В `setup-v2ray-redirect.sh` была опечатка `-j RET URN`. Скрипт переписан и стал единственным источником; docs/04 ссылается на него, а не держит свою копию. |
| X2 | ✅ исправлено | Редирект пропускал **порты** назначения 80/443, то есть почти весь веб-трафик. Теперь он пропускает **адреса** назначения (сам роутер, частные диапазоны). Доказано журналом доступа Xray для портов 80, 443 и 8000. |
| X4 | ✅ новая, PASS | Скрипт идемпотентен: два запуска оставляют один набор правил. Старый при каждом запуске добавлял дубль перехода в PREROUTING. |
| X5 | ✅ новая, PASS | Панель на роутере остаётся доступной из Wi-Fi и не уходит в прокси. |
| — | ✅ исправлено | Даже с работающим V2Ray политика INPUT DROP в kill switch отбросила бы перенаправленные соединения на :12345. Теперь скрипт открывает этот порт на `wlan0`. |
| — | открыто | docs/08_FIREWALL.md описывает ещё два варианта firewall (`iptables-killswitch.sh`, nftables), которые расходятся с `scripts/killswitch.sh`. |
| K2 | FAIL | Когда VPN не работает, **сам роутер** всё ещё достаёт до любого хоста на tcp/443 со своим настоящим IP, потому что kill switch разрешает `-o eth0 --dport 443` для любого адреса. |
| K3 | FAIL | Kill switch покрывает только `eth0` и `wwan0`. Имена 4G-интерфейсов, которые реально использует `wan-switch.sh` (`usb0`, `eth1`, `enx*`), не покрыты. |
| — | FAIL | Документация предлагает пользователю создать 9 скриптов, которых нет в репозитории (`wan-failover.sh`, `route-through-tor.sh`, `connect-4g.sh`, …). Проверки в лаборатории для этого пока нет. |
| P1, P3, V3, D1, K1, K4 | PASS | Работает: обязательная авторизация, CSRF, маршрутизация через VPN (после исправления), DNS, kill switch для клиентов и блокировка IPv6. |

Kill switch для клиентов работает: при остановленном VPN из хотспота ничего не утекает (K1).

В конце первого раунда: 19 PASS / 10 FAIL (29 проверок).
