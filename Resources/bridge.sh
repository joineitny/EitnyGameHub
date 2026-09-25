#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

fail() { printf 'GB_ERROR|%s\n' "$*"; exit 1; }
event() { printf 'GB_STATUS|%s\n' "$*"; }
verify() { [[ -f "$1" && "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" == "$2" ]]; }

ACTION=${1:-doctor}
if [[ "$ACTION" == verify ]]; then
  [[ $# == 3 ]] || fail 'verify требует путь и SHA-256'
  verify "$2" "$3" || fail 'Контрольная сумма не совпала.'
  exit 0
fi

# Keep existing Steam accounts and games when upgrading from Gwent Bridge.
DEFAULT_DATA="$HOME/Library/Application Support/EitnyGameHub"
if [[ ! -d "$DEFAULT_DATA" && -d "$HOME/Library/Application Support/GwentBridge" ]]; then
  DEFAULT_DATA="$HOME/Library/Application Support/GwentBridge"
fi
DATA=${EITNY_GAMEHUB_DATA:-${GWENT_BRIDGE_DATA:-"$DEFAULT_DATA"}}
[[ "$DATA" == /* && "$DATA" != / && "$DATA" != "$HOME" && "$DATA" != *'/../'* ]] || fail 'Нужна отдельная папка данных с абсолютным путём.'
RUNTIME="$DATA/Runtime"
PREFIX="$DATA/Bottle"
STEAM_DIR="$PREFIX/drive_c/Program Files (x86)/Steam"
STEAM="$STEAM_DIR/steam.exe"
GAME_DIR="$STEAM_DIR/steamapps/common/GWENT The Witcher Card Game"
MANIFEST="$STEAM_DIR/steamapps/appmanifest_1284410.acf"
LOGS="$DATA/Logs"
CACHE="$DATA/Downloads"
WINE="$RUNTIME/bin/wine"
SERVER="$RUNTIME/bin/wineserver"

configure_environment() {
  export WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all WINEMSYNC=1
  export DYLD_FALLBACK_LIBRARY_PATH="$RUNTIME/lib:/usr/lib"
  export DYLD_FALLBACK_FRAMEWORK_PATH="$RUNTIME/lib:/Library/Frameworks:/System/Library/Frameworks"
  export WINEDLLPATH="$RUNTIME/lib/wine"
  export GST_PLUGIN_SYSTEM_PATH_1_0="$RUNTIME/lib/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0"
  export GST_PLUGIN_SCANNER_1_0="$RUNTIME/lib/GStreamer.framework/Versions/1.0/libexec/gstreamer-1.0/gst-plugin-scanner"
  export GST_REGISTRY_1_0="$DATA/gstreamer-registry.bin"
  unset WINEDLLOVERRIDES || true
}

doctor() {
  printf 'GB_CHECK|system|%s\n' "$(/usr/bin/sw_vers -productVersion)"
  if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then printf 'GB_CHECK|rosetta|ready\n'; else printf 'GB_CHECK|rosetta|missing\n'; fi
  if [[ -x "$WINE" && -f "$RUNTIME/.ready-v1" ]]; then printf 'GB_CHECK|runtime|ready\n'; else printf 'GB_CHECK|runtime|missing\n'; fi
  if [[ -f "$PREFIX/.configured-v1" ]]; then printf 'GB_CHECK|bottle|ready\n'; else printf 'GB_CHECK|bottle|missing\n'; fi
  if [[ -f "$STEAM" ]]; then printf 'GB_CHECK|steam|ready\n'; else printf 'GB_CHECK|steam|missing\n'; fi
  if [[ -f "$GAME_DIR/Gwent.exe" && -f "$MANIFEST" ]]; then printf 'GB_CHECK|gwent|present\n'; else printf 'GB_CHECK|gwent|missing\n'; fi
  printf 'GB_CHECK|data|%s\n' "$DATA"
}

download() {
  local name="$1" url="$2" checksum="$3"
  if verify "$CACHE/$name" "$checksum"; then return; fi
  event "Загружаю $name…"
  /usr/bin/curl --fail --location --retry 2 --connect-timeout 20 --max-time 900 --proto '=https' --proto-redir '=https' --silent --show-error "$url" -o "$CACHE/$name.part"
  verify "$CACHE/$name.part" "$checksum" || fail "Файл $name не прошёл проверку целостности. Запуск отменён."
  /bin/mv "$CACHE/$name.part" "$CACHE/$name"
}

setup_runtime() {
  if [[ -x "$WINE" && -f "$RUNTIME/.ready-v1" ]]; then return; fi
  download wine.tar.xz 'https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz' '9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2'
  download wrapper.tar.xz 'https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.11.tar.xz' '9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a'
  download dxmt.tar.gz 'https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz' '8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d'
  event 'Подготавливаю Wine и графику Metal…'
  local stage
  stage=$(/usr/bin/mktemp -d "$DATA/prepare.XXXXXX")
  /bin/mkdir -p "$stage/engine" "$stage/wrapper" "$stage/dxmt"
  /usr/bin/tar -xf "$CACHE/wine.tar.xz" -C "$stage/engine"
  /usr/bin/tar -xf "$CACHE/wrapper.tar.xz" -C "$stage/wrapper"
  /usr/bin/tar -xf "$CACHE/dxmt.tar.gz" -C "$stage/dxmt"
  local root="$stage/engine/wswine.bundle" framework="$stage/wrapper/Template-1.0.11.app/Contents/Frameworks"
  /bin/cp -R "$framework/"*.dylib "$root/lib/"
  /bin/cp -R "$framework/GStreamer.framework" "$root/lib/"
  /bin/cp -R "$stage/dxmt/v0.80/." "$root/lib/wine/"
  DYLD_FALLBACK_LIBRARY_PATH="$root/lib:/usr/lib" "$root/bin/wine" --version
  if [[ -e "$RUNTIME" ]]; then /bin/mv "$RUNTIME" "$DATA/Runtime.previous.$(/bin/date +%s)"; fi
  /bin/mv "$root" "$RUNTIME"
  /usr/bin/touch "$RUNTIME/.ready-v1"
  /bin/rm -rf "$stage"
}

setup_bottle() {
  if [[ -f "$PREFIX/.configured-v1" ]]; then return; fi
  event 'Создаю отдельное окружение Windows…'
  /bin/mkdir -p "$PREFIX"
  WINEDLLOVERRIDES='mscoree,mshtml=' "$WINE" wineboot -u >>"$LOGS/setup.log" 2>&1
  "$WINE" reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win10 /f >>"$LOGS/setup.log" 2>&1
  "$WINE" reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d coreaudio /f >>"$LOGS/setup.log" 2>&1
  "$WINE" reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d y /f >>"$LOGS/setup.log" 2>&1
  /bin/cp "$RUNTIME/lib/wine/x86_64-windows/winemetal.dll" "$PREFIX/drive_c/windows/system32/"
  /bin/cp "$RUNTIME/lib/wine/i386-windows/winemetal.dll" "$PREFIX/drive_c/windows/syswow64/"
  /usr/bin/touch "$PREFIX/.configured-v1"
}

setup_steam() {
  if [[ -f "$STEAM" ]]; then return; fi
  event 'Устанавливаю официальный Steam для Windows…'
  /usr/bin/curl --fail --location --retry 2 --connect-timeout 20 --max-time 180 --proto '=https' --proto-redir '=https' --silent --show-error 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe' -o "$CACHE/SteamSetup.exe.part"
  [[ "$(/usr/bin/head -c 2 "$CACHE/SteamSetup.exe.part")" == MZ ]] || fail 'Сервер не вернул установщик Steam.'
  /bin/mv "$CACHE/SteamSetup.exe.part" "$CACHE/SteamSetup.exe"
  "$WINE" "$CACHE/SteamSetup.exe" /S >>"$LOGS/setup.log" 2>&1
  [[ -f "$STEAM" ]] || fail 'Steam не установлен. Подробности находятся в журнале установки.'
}

require_ready() {
  [[ -f "$RUNTIME/.ready-v1" && -f "$PREFIX/.configured-v1" && -f "$STEAM" ]] || fail 'Сначала нажмите «Подготовить Steam».'
}

launch_steam() {
  require_ready
  local log="$LOGS/steam-$ACTION-$(/bin/date +%Y%m%d-%H%M%S).log"
  local flags=()
  # Scoped to the Chromium helper inside Wine; no macOS security settings change.
  # Current Steam's CEF sandbox is incompatible with this Wine runtime.
  flags+=(-no-cef-sandbox)
  case "$ACTION" in
    # REDlauncher fails to create its OpenGL context on this runtime.
    gwent|gwent-direct)
      # GWENT restores its own FULLSCREEN preference after Unity processes CLI flags.
      # Preserve the user's resolution; only select the confirmed working window mode.
      "$WINE" reg add 'HKCU\Software\CDProjektRED\Gwent' /v FULLSCREEN_h742858458 /t REG_BINARY /d 66616c736500 /f >>"$log" 2>&1
      "$WINE" reg add 'HKCU\Software\CDProjektRED\Gwent' /v 'Screenmanager Fullscreen mode_h3630240806' /t REG_DWORD /d 3 /f >>"$log" 2>&1
      flags+=(-applaunch 1284410 --launcher-skip -screen-fullscreen 0);;
    library) flags+=('steam://nav/games/details/1284410');;
    game-library)
      [[ ${2:-} =~ ^[1-9][0-9]{0,9}$ ]] || fail 'Некорректный номер игры.'
      flags+=("steam://nav/games/details/$2");;
    game-launch|game-install)
      [[ ${2:-} == 238960 ]] || fail 'Для этой игры ещё нет профиля запуска.'
      if [[ "$ACTION" == game-launch ]]; then flags+=(-applaunch "$2")
      else flags+=("steam://install/$2"); fi;;
  esac
  event 'Открываю Steam… Первый запуск может включать обновление клиента.'
  /usr/bin/nohup "$WINE" "$STEAM" "${flags[@]}" >>"$log" 2>&1 </dev/null &
  local pid=$!
  printf '%s\n' "$pid" >"$DATA/last-launch.pid"
  /bin/sleep 3
  if ! /bin/kill -0 "$pid" 2>/dev/null; then
    local status=0
    wait "$pid" || status=$?
    [[ "$status" == 0 ]] || fail "Steam завершился с кодом $status. Откройте журнал запуска."
  fi
  if [[ "$ACTION" == gwent || "$ACTION" == gwent-direct ]]; then
    event 'Запуск GWENT передан Steam. Ожидаем окно игры…'
  else
    event 'Команда передана Steam.'
  fi
}

import_game() {
  require_ready
  local source=${2:-"$HOME/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps"}
  [[ -f "$source/common/GWENT The Witcher Card Game/Gwent.exe" && -f "$source/appmanifest_1284410.acf" ]] || fail 'Готовая установка GWENT не найдена. Установите игру через Steam.'
  [[ ! -e "$GAME_DIR" && ! -e "$MANIFEST" ]] || fail 'Файлы GWENT уже есть. Используйте проверку файлов в Steam.'
  event 'Переношу GWENT в отдельную библиотеку…'
  /bin/mkdir -p "$STEAM_DIR/steamapps/common"
  local staging="$STEAM_DIR/steamapps/common/.gwent-import-$$"
  # APFS clone avoids re-downloading and keeps future writes independent.
  /bin/cp -cR "$source/common/GWENT The Witcher Card Game" "$staging"
  /bin/mv "$staging" "$GAME_DIR"
  /bin/cp "$source/appmanifest_1284410.acf" "$MANIFEST"
  # No login state or account IDs are imported from the previous client.
  /usr/bin/sed -i '' '/"LastOwner"/d' "$MANIFEST"
  event 'Файлы GWENT перенесены. Steam проверит их при установке или запуске.'
}

case "$ACTION" in
  doctor) doctor; exit 0;;
  setup|setup-environment|steam|gwent|gwent-direct|library|game-library|game-launch|game-install|import|stop) ;;
  *) fail "Неизвестное действие: $ACTION";;
esac
/bin/mkdir -p "$DATA" "$LOGS" "$CACHE"
/bin/chmod 700 "$DATA"
configure_environment
case "$ACTION" in
  setup|setup-environment)
    /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || fail 'Установите Rosetta 2 средствами macOS, затем повторите.'
    lock="$DATA/setup.lock"
    if ! /bin/mkdir "$lock" 2>/dev/null; then
      old_pid=$(/bin/cat "$lock/pid" 2>/dev/null || true)
      if [[ "$old_pid" =~ ^[0-9]+$ ]] && ! /bin/kill -0 "$old_pid" 2>/dev/null; then
        /bin/rm -f "$lock/pid"
        /bin/rmdir "$lock" || fail 'Не удалось освободить папку подготовки.'
        /bin/mkdir "$lock" || fail 'Подготовка уже запущена.'
      else
        fail 'Подготовка уже запущена. Дождитесь её завершения.'
      fi
    fi
    printf '%s\n' "$$" >"$lock/pid"
    trap '/bin/rm -f "$lock/pid"; /bin/rmdir "$lock" 2>/dev/null || true' EXIT
    setup_runtime
    setup_bottle
    if [[ "$ACTION" == setup ]]; then
      setup_steam
      event 'Steam подготовлен. Можно запускать.'
    else
      event 'Окружение Windows подготовлено.'
    fi
    ;;
  steam|gwent|gwent-direct|library|game-library|game-launch|game-install) launch_steam "$@";;
  import) import_game "$@";;
  stop)
    require_ready
    "$WINE" "$STEAM" -shutdown >>"$LOGS/shutdown.log" 2>&1
    event 'Steam получил команду завершения.'
    ;;
esac
