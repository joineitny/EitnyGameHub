#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
fail() { printf 'GB_ERROR|%s\n' "$*"; exit 1; }
event() { printf 'GB_STATUS|%s\n' "$*"; }
ACTION=${1:-doctor}
BASE=${EITNY_GAMEHUB_DATA:-${GWENT_BRIDGE_DATA:-"$HOME/Library/Application Support/EitnyGameHub"}}
[[ "$BASE" == /* && "$BASE" != / && "$BASE" != "$HOME" && "$BASE" != *'/../'* ]] || fail 'Некорректная папка данных.'
ROOT="$(cd "$(dirname "$0")" && pwd)"
DATA="$BASE/Profiles/PathOfExile"
PREFIX="$DATA/Bottle"
RUNTIME="$DATA/Runtime"
LOGS="$DATA/Logs"
STEAM_DIR="$PREFIX/drive_c/Program Files (x86)/Steam"
MANIFEST="$STEAM_DIR/steamapps/appmanifest_238960.acf"
DOCS="$PREFIX/drive_c/EitnyGameHub/Documents"
CONFIG="$DOCS/My Games/Path of Exile/production_Config.ini"
WINE="$RUNTIME/bin/wine"
source "$ROOT/poe-graphics.sh"
# Never copy a Steam account or the GWENT prefix into the experimental profile.
bridge() { EITNY_GAMEHUB_DATA="$DATA" /bin/bash "$ROOT/bridge.sh" "$@"; }
installed() {
  [[ -f "$MANIFEST" ]] || return 1
  local flags
  flags=$(/usr/bin/awk -F '"' '$2=="StateFlags" { print $4; exit }' "$MANIFEST")
  [[ "$flags" =~ ^[0-9]+$ ]] && (( (10#$flags & 4) != 0 ))
}
ready() { [[ -f "$DATA/.poe-ready" && -f "$RUNTIME/.ready-v1" && -f "$PREFIX/.configured-v1" && -f "$STEAM_DIR/steam.exe" ]]; }
wine_env() {
  export WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all WINEMSYNC=1
  export DYLD_FALLBACK_LIBRARY_PATH="$RUNTIME/lib:/usr/lib"
  export DYLD_FALLBACK_FRAMEWORK_PATH="$RUNTIME/lib:/Library/Frameworks:/System/Library/Frameworks"
  export WINEDLLPATH="$RUNTIME/lib/wine"
  export GST_PLUGIN_SYSTEM_PATH_1_0="$RUNTIME/lib/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0"
  export GST_PLUGIN_SCANNER_1_0="$RUNTIME/lib/GStreamer.framework/Versions/1.0/libexec/gstreamer-1.0/gst-plugin-scanner"
  export GST_REGISTRY_1_0="$DATA/gstreamer-registry.bin"
  unset WINEDLLOVERRIDES || true
}
isolate_folders() {
  mkdir -p "$DOCS/My Games/Path of Exile" "$PREFIX/drive_c/EitnyGameHub/Desktop"
  # PoE reads USERPROFILE\\Documents directly, ignoring Explorer's Personal value.
  # Retarget Wine-created symlinks only; never move or edit macOS Documents.
  local user folder target link backup
  for user in "$PREFIX"/drive_c/users/*; do
    [[ -d "$user" ]] || continue
    for folder in Documents Desktop; do
      link="$user/$folder"
      target="../../EitnyGameHub/$folder"
      [[ -L "$link" ]] || continue
      [[ "$(readlink "$link")" == "$target" ]] && continue
      backup="$user/$folder.before-Eitny-link"
      [[ ! -e "$backup" && ! -L "$backup" ]] || fail 'Резервная ссылка папки уже существует. Нужна проверка профиля PoE.'
      mv "$link" "$backup"
      ln -s "$target" "$link"
    done
  done
}
game_tasks() { "$WINE" tasklist /fo csv 2>>"$LOGS/settings.log"; }
require_game_closed() {
  local tasks
  tasks=$(game_tasks) || fail 'Не удалось проверить, закрыта ли PoE.'
  [[ "$tasks" != *PathOfExile* ]] || fail 'PoE уже запущена. Закрой её перед повторным запуском или изменением настроек.'
}
prepare_window() {
  isolate_folders
  "$ROOT/GameSettings" windowed "$CONFIG"
}
case "$ACTION" in
  doctor)
    if ready; then printf 'GB_CHECK|poe_environment|ready\n'; else printf 'GB_CHECK|poe_environment|missing\n'; fi
    if installed; then printf 'GB_CHECK|poe|present\n'; else printf 'GB_CHECK|poe|missing\n'; fi
    if graphics_ready; then printf 'GB_CHECK|poe_graphics|d3dmetal\n'; else printf 'GB_CHECK|poe_graphics|missing\n'; fi
    if [[ -f "$DATA/preset" ]]; then printf 'GB_CHECK|poe_preset|%s\n' "$(cat "$DATA/preset")"; fi
    exit 0;;
  setup|steam|install|launch|preset|recover|stop) ;;
  *) fail 'Неизвестное действие PoE.';;
esac
if [[ "$ACTION" == preset ]]; then
  case "${2:-}" in balanced|performance|quality) ;; *) fail 'Неизвестный профиль графики.';; esac
fi
mkdir -p "$DATA" "$LOGS"
chmod 700 "$DATA"
case "$ACTION" in
  setup)
    event 'Подготавливаю отдельное окружение Path of Exile…'
    if [[ ! -e "$RUNTIME" && -f "$BASE/Runtime/.ready-v1" && -x "$BASE/Runtime/bin/wine" ]]; then
      staging=$(mktemp -d "$DATA/runtime-clone.XXXXXX")
      /bin/cp -cR "$BASE/Runtime" "$staging/Runtime"
      /bin/mv "$staging/Runtime" "$RUNTIME"
      /bin/rmdir "$staging"
    fi
    bridge setup-environment
    wine_env
    install_graphics
    isolate_folders
    # Direct only this profile's Documents into its own prefix, not macOS Documents.
    for key in 'User Shell Folders' 'Shell Folders'; do
      "$WINE" reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\$key" /v Personal /t REG_SZ /d 'C:\EitnyGameHub\Documents' /f >>"$LOGS/setup.log" 2>&1
      "$WINE" reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\$key" /v Desktop /t REG_SZ /d 'C:\EitnyGameHub\Desktop' /f >>"$LOGS/setup.log" 2>&1
    done
    bridge setup
    "$ROOT/GameSettings" create "$CONFIG" balanced
    [[ -f "$DATA/preset" ]] || printf 'balanced\n' >"$DATA/preset"
    touch "$DATA/.poe-ready"
    event 'PoE подготовлена. Открой Steam для PoE и войди в свой аккаунт.';;
  steam) [[ -f "$DATA/.poe-ready" ]] || fail 'Сначала подготовь Path of Exile.'; bridge steam;;
  install) [[ -f "$DATA/.poe-ready" ]] || fail 'Сначала подготовь Path of Exile.'; bridge game-install 238960;;
  launch)
    [[ -f "$DATA/.poe-ready" ]] || fail 'Сначала подготовь Path of Exile.'
    installed || fail 'Сначала установи Path of Exile в Steam для PoE и дождись загрузки.'
    wine_env
    require_game_closed
    install_graphics
    prepare_window
    bridge game-launch 238960;;
  preset)
    [[ -f "$DATA/.poe-ready" ]] || fail 'Сначала подготовь Path of Exile.'
    wine_env
    require_game_closed
    isolate_folders
    "$ROOT/GameSettings" apply "$CONFIG" "$2"
    printf '%s\n' "$2" >"$DATA/preset"
    event 'Настройки PoE сохранены. Предыдущий файл оставлен рядом как резервная копия.';;
  recover)
    ready || fail 'Сначала подготовь Path of Exile.'
    wine_env
    tasks=$(game_tasks) || fail 'Не удалось проверить процессы PoE.'
    for exe in PathOfExileSteam.exe PathOfExile_x64Steam.exe; do
      if [[ "$tasks" == *"\"$exe\""* ]]; then
        "$WINE" taskkill /im "$exe" /f >>"$LOGS/recovery.log" 2>&1 || fail 'Не удалось закрыть PoE.'
      fi
    done
    require_game_closed
    prepare_window
    event 'PoE закрыта, оконный режим восстановлен. Разрешение и FSR сохранены. Можно снова нажать «Играть в PoE».';;
  stop) bridge stop;;
esac
