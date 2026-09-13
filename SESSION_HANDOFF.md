Контекст: проект Prism — чат-таб (QML) для шелла Caelestia (Hyprland/Quickshell/NixOS), с локальным FastAPI-демоном на бэкенде (Gemini/Claude API). Ниже — сводка сессии по нему.

# Расположение файлов
Один и тот же PrismTab.qml должен быть синхронизирован в 4 местах:
- ~/prism-chat-tab/PrismTab.qml (git-репо, origin github.com/skiffuff/prism-chat-tab)
- ~/dotfiles/.config/caelestia/PrismTab.qml (home-manager, но НЕ на реальном пути загрузки шелла)
- ~/.local/share/caelestia-shell/modules/dashboard/PrismTab.qml (реальный путь, который грузит запущенный quickshell)
- ~/nixos/patches/dashboard/PrismTab.qml (источник правды при следующем nixos/home-manager rebuild — home.nix копирует именно отсюда)
Все 4 сейчас идентичны (md5 совпадает). backend/prism_daemon.py живёт в ~/prism-chat-tab/backend/ и как рабочая копия в ~/.local/share/prism/prism_daemon.py.

# Как всё запускается
- Шелл: systemd user unit `caelestia.service` (override.conf → ExecStart=/home/skiffu/.local/bin/caelestia-shell-local, который вручную прокидывает NIXPKGS_QT6_QML_IMPORT_PATH/QT_PLUGIN_PATH для локального пути ~/.local/share/caelestia-shell вместо nix-стора). Перезапуск: `systemctl --user restart caelestia.service`.
- Демон: НЕ через systemd (юнит только для другого проекта, "prism-automods" — не путать), запускается вручную: `/home/skiffu/.venv/bin/python /home/skiffu/.local/share/prism/prism_daemon.py`, слушает 127.0.0.1:5000, healthcheck `/health`.

# Что было исправлено в этой сессии (визуальные баги в PrismTab.qml)
1. Пустое меню выбора провайдера (Gemini/Claude). Причина: использовался QtQuick.Controls `Menu`/`MenuItem` — в Quickshell-окружении (нет ApplicationWindow/Overlay) их дефолтные визуалы не резолвятся, попап рендерился пустым. Фикс: заменено на обычный `Popup` с полностью кастомным background/содержимым (как уже работающий в этом же файле `confirmModal` для подтверждения run_bash) — свой список провайдеров, галочка у активного, hover-подсветка.
2. Сайдбар с историей чатов "не помещался". Добавлен видимый ScrollBar.vertical (раньше список молча обрезался без индикатора прокрутки) + implicitWidth/Height таба уменьшены с 900x650 до 860x600 (ближе к соседним вкладкам дашборда: Weather ~840, Media height 320). ВАЖНО: это низкоуверенный фикс — не подтверждён визуально (шелл был упавшим на момент фикса, скриншот снять не успел). Стоит проверить глазами после перезапуска шелла и дать знать, если сайдбар всё ещё выглядит не так.

# Архитектурные заметки по backend/prism_daemon.py (FastAPI)
- Мультипровайдерный (Gemini/Claude), инструмент run_bash с whitelist разрешённых команд + `_is_dangerous()` вторым слоем защиты + подтверждение через модалку (pending/tool_confirm flow).
- Авторизация всех эндпоинтов через заголовок X-Prism-Token (файл ~/.local/share/prism/daemon.token), rate limit 10/мин на IP, ключи только в OS keyring.
- Известный архитектурный нюанс (не исправлялся, просто зафиксирован): PrismTab.qml ведёт историю чатов полностью client-side (chatsData/chatsModel в памяти QML), при этом бэкенд параллельно пишет свою собственную персистентность в sessions.json — это два независимых источника правды, между собой не синхронизированы. Бэкенд поддерживает полноценную мультисессионность (/sessions, /session/new и т.д.), но текущий PrismTab.qml эти эндпоинты не вызывает вовсе.
- Также существует полностью отдельная, более старая и глубоко интегрированная в шелл версия таба (~2700 строк, использует сервис-синглтон GeminiChat, Material3-тему, кастомные qs.components.controls.Menu) — она была вытеснена текущей более простой самодостаточной (Catppuccin, ~1100 строк) версией и теперь везде синхронизирована на новую.

# Текущее состояние на конец сессии
Оба процесса подняты и здоровы: демон отвечает {"status":"ok"} на /health, шелл активен через systemctl (active/running), конфиг QML грузится без ошибок. Следующий шаг — открыть дашборд Caelestia и глазами проверить вкладку Prism: (а) открывается ли меню выбора провайдера и видны ли в нём Gemini/Claude, (б) как выглядит сайдбар с историей чатов при разном количестве чатов.
