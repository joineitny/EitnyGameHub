#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
RESOURCES="$ROOT/Resources"
SOURCES="$ROOT/Sources"
TESTS="$ROOT/Tests"
[[ -d "$RESOURCES" ]] || RESOURCES="$ROOT"
[[ -d "$SOURCES" ]] || SOURCES="$ROOT"
[[ -d "$TESTS" ]] || TESTS="$ROOT"
BACKEND="$RESOURCES/bridge.sh"
TMP=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$TMP"' EXIT
export GWENT_BRIDGE_DATA="$TMP/данные с пробелами"
unset EITNY_GAMEHUB_DATA
/bin/bash -n "$BACKEND"
result=$(/bin/bash "$BACKEND" doctor)
[[ "$result" == *'GB_CHECK|steam|missing'* ]]
[[ ! -e "$GWENT_BRIDGE_DATA" ]] || { echo 'Diagnostics must not create data.'; exit 1; }
if /bin/bash "$BACKEND" steam >"$TMP/error" 2>&1; then echo 'Launch without installed runtime must fail.'; exit 1; fi
/usr/bin/grep -q 'Сначала' "$TMP/error"
if GWENT_BRIDGE_DATA=/ /bin/bash "$BACKEND" setup >"$TMP/error" 2>&1; then echo 'Unsafe data path accepted.'; exit 1; fi
if GWENT_BRIDGE_DATA=relative /bin/bash "$BACKEND" doctor >"$TMP/error" 2>&1; then echo 'Relative data path accepted.'; exit 1; fi
printf abc >"$TMP/asset"
/bin/bash "$BACKEND" verify "$TMP/asset" ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
if /bin/bash "$BACKEND" verify "$TMP/asset" 000000 >"$TMP/error" 2>&1; then echo 'Bad digest accepted.'; exit 1; fi
printf altered >"$TMP/asset"
if /bin/bash "$BACKEND" verify "$TMP/asset" ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad >"$TMP/error" 2>&1; then echo 'Changed asset accepted.'; exit 1; fi
if /bin/bash "$BACKEND" unknown >"$TMP/error" 2>&1; then echo 'Unknown action accepted.'; exit 1; fi

# Exercise the launch boundary without opening Steam or touching a real account.
# Check the Steam launch and REDlauncher skip with paths containing spaces.
export CAPTURE="$TMP/captured"
mkdir -p "$GWENT_BRIDGE_DATA/Runtime/bin" "$GWENT_BRIDGE_DATA/Bottle/drive_c/Program Files (x86)/Steam"
touch "$GWENT_BRIDGE_DATA/Runtime/.ready-v1" "$GWENT_BRIDGE_DATA/Bottle/.configured-v1"
touch "$GWENT_BRIDGE_DATA/Bottle/drive_c/Program Files (x86)/Steam/steam.exe"
cat >"$GWENT_BRIDGE_DATA/Runtime/bin/wine" <<'FAKE'
#!/bin/bash
printf '%s\n' "$WINEPREFIX" "$@" >>"$CAPTURE"
FAKE
chmod +x "$GWENT_BRIDGE_DATA/Runtime/bin/wine"
/bin/bash "$BACKEND" gwent >"$TMP/launch"
printf '%s\n' "$GWENT_BRIDGE_DATA/Bottle" reg add 'HKCU\Software\CDProjektRED\Gwent' /v FULLSCREEN_h742858458 /t REG_BINARY /d 66616c736500 /f "$GWENT_BRIDGE_DATA/Bottle" reg add 'HKCU\Software\CDProjektRED\Gwent' /v 'Screenmanager Fullscreen mode_h3630240806' /t REG_DWORD /d 3 /f "$GWENT_BRIDGE_DATA/Bottle" "$GWENT_BRIDGE_DATA/Bottle/drive_c/Program Files (x86)/Steam/steam.exe" -no-cef-sandbox -applaunch 1284410 --launcher-skip -screen-fullscreen 0 >"$TMP/expected"
cmp "$TMP/expected" "$CAPTURE"
# New variable takes precedence, while the legacy variable above remains supported.
result=$(EITNY_GAMEHUB_DATA="$TMP/new data" /bin/bash "$BACKEND" doctor)
[[ "$result" == *"GB_CHECK|data|$TMP/new data"* && "$result" == *'GB_CHECK|steam|missing'* ]]
if /bin/bash "$BACKEND" game-library '1284410;bad' >"$TMP/error" 2>&1; then echo 'Invalid app ID accepted.'; exit 1; fi
echo 'PASS: diagnostics, migration paths, runtime refusal, checksums, Steam launch, REDlauncher skip, persisted windowed mode, app IDs.'
mkdir -p "$TMP/module-cache"
swiftc -swift-version 5 -module-cache-path "$TMP/module-cache" -parse-as-library "$SOURCES/SteamLibrary.swift" "$TESTS/LibraryTests.swift" -o "$TMP/library-tests"
"$TMP/library-tests"

swiftc -swift-version 5 -module-cache-path "$TMP/module-cache" -parse-as-library "$SOURCES/GameSettings.swift" "$TESTS/GameSettingsTests.swift" -o "$TMP/settings-tests"
"$TMP/settings-tests"
# A separate PoE prefix must never route its Steam calls into the working GWENT prefix.
POE="$GWENT_BRIDGE_DATA/Profiles/PathOfExile"
/bin/bash -n "$RESOURCES/poe.sh"
result=$(/bin/bash "$RESOURCES/poe.sh" doctor)
[[ "$result" == *'GB_CHECK|poe_environment|missing'* ]]
[[ ! -e "$POE" ]] || { echo 'PoE diagnostics must be read-only'; exit 1; }
mkdir -p "$POE/Runtime/bin" "$POE/Bottle/drive_c/Program Files (x86)/Steam/steamapps"
cat >"$POE/Runtime/bin/wine" <<'FAKEPOE'
#!/bin/bash
if [[ "${1:-}" == tasklist ]]; then
  if [[ -n "${POE_FAKE_TASK_FILE:-}" && -f "$POE_FAKE_TASK_FILE" ]]; then cat "$POE_FAKE_TASK_FILE"; fi
  [[ -z "${POE_FAKE_RUNNING:-}" ]] || printf '\"PathOfExileSteam.exe\",\"123\"\n'
  exit 0
fi
if [[ "${1:-}" == taskkill && "${3:-}" == PathOfExileSteam.exe && -n "${POE_FAKE_TASK_FILE:-}" ]]; then
  printf '\"steam.exe\",\"20\"\n\"Gwent.exe\",\"30\"\n' >"$POE_FAKE_TASK_FILE"
fi
printf '%s\n' "$WINEPREFIX" "$@" >>"$CAPTURE"
FAKEPOE
chmod +x "$POE/Runtime/bin/wine"
mkdir -p "$POE/Runtime/lib/D3DMetal.framework" "$POE/Runtime/lib/wine/x86_64-unix"
touch "$POE/Runtime/.poe-d3dmetal-v3" "$POE/Runtime/lib/D3DMetal.framework/D3DMetal" "$POE/Runtime/lib/wine/x86_64-unix/d3d12.so"
# Stage the real compiled settings helper with the production shell resources.
mkdir -p "$TMP/resources"
cp "$RESOURCES/"*.sh "$TMP/resources/"
swiftc -swift-version 5 -module-cache-path "$TMP/module-cache" -parse-as-library "$SOURCES/GameSettings.swift" "$SOURCES/GameSettingsMain.swift" -o "$TMP/resources/GameSettings"
POE_BACKEND="$TMP/resources/poe.sh"
touch "$POE/Runtime/.ready-v1" "$POE/Bottle/.configured-v1" "$POE/.poe-ready" "$POE/Bottle/drive_c/Program Files (x86)/Steam/steam.exe"
if /bin/bash "$POE_BACKEND" launch >"$TMP/error" 2>&1; then echo 'PoE launch before download accepted'; exit 1; fi
printf '"AppState"\n{\n"StateFlags" "4"\n}\n' >"$POE/Bottle/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_238960.acf"
mkdir -p "$TMP/mac-documents" "$POE/Bottle/drive_c/users/test-player"
printf 'Do not modify native game settings\n' >"$TMP/mac-documents/sentinel"
ln -s "$TMP/mac-documents" "$POE/Bottle/drive_c/users/test-player/Documents"
: >"$CAPTURE"
/bin/bash "$POE_BACKEND" launch >"$TMP/poe-launch"
[[ "$(readlink "$POE/Bottle/drive_c/users/test-player/Documents")" == '../../EitnyGameHub/Documents' ]]
[[ "$(readlink "$POE/Bottle/drive_c/users/test-player/Documents.before-Eitny-link")" == "$TMP/mac-documents" ]]
[[ "$(cat "$TMP/mac-documents/sentinel")" == 'Do not modify native game settings' ]]
printf '%s\n' "$POE/Bottle" "$POE/Bottle/drive_c/Program Files (x86)/Steam/steam.exe" -no-cef-sandbox -applaunch 238960 >"$TMP/poe-expected"
cmp "$TMP/poe-expected" "$CAPTURE"
: >"$CAPTURE"
/bin/bash "$POE_BACKEND" install >"$TMP/poe-install"
printf '%s\n' "$POE/Bottle" "$POE/Bottle/drive_c/Program Files (x86)/Steam/steam.exe" -no-cef-sandbox 'steam://install/238960' >"$TMP/poe-expected"
cmp "$TMP/poe-expected" "$CAPTURE"
if /bin/bash "$BACKEND" game-launch '1284410' >"$TMP/error" 2>&1; then echo 'Generic launch bypassed GWENT window profile'; exit 1; fi
if /bin/bash "$POE_BACKEND" preset invalid >"$TMP/error" 2>&1; then echo 'Invalid PoE preset accepted'; exit 1; fi
echo 'PASS: PoE launches and installs only in its isolated profile; incomplete install refused; GWENT cannot bypass its dedicated launch.'

# Recovery and launch must preserve player-chosen FSR/resolution and never act on GWENT.
CONFIG="$POE/Bottle/drive_c/EitnyGameHub/Documents/My Games/Path of Exile/production_Config.ini"
printf '[DISPLAY]\nfullscreen=true\nresolution_width=2704\nupscale=FSR\nupscale_quality=Performance\n' >"$CONFIG"
: >"$CAPTURE"
/bin/bash "$POE_BACKEND" recover >"$TMP/recovery"
/usr/bin/grep -q '^fullscreen=false$' "$CONFIG"
/usr/bin/grep -q '^resolution_width=2704$' "$CONFIG"
/usr/bin/grep -q '^upscale=FSR$' "$CONFIG"
[[ ! -s "$CAPTURE" ]]
if POE_FAKE_RUNNING=1 /bin/bash "$POE_BACKEND" launch >"$TMP/error" 2>&1; then echo 'Already-running PoE was launched twice'; exit 1; fi
[[ ! -s "$CAPTURE" ]]
echo 'PASS: PoE window recovery preserves player graphics; running game is protected from config edits.'

# A hung-game recovery may kill only the PoE executable in the PoE prefix.
printf '\"PathOfExileSteam.exe\",\"123\"\n\"steam.exe\",\"20\"\n\"Gwent.exe\",\"30\"\n' >"$TMP/task-list"
: >"$CAPTURE"
POE_FAKE_TASK_FILE="$TMP/task-list" /bin/bash "$POE_BACKEND" recover >"$TMP/recovery"
printf '%s\n' "$POE/Bottle" taskkill /im PathOfExileSteam.exe /f >"$TMP/kill-expected"
cmp "$TMP/kill-expected" "$CAPTURE"
/usr/bin/grep -q 'Gwent.exe' "$TMP/task-list"
/usr/bin/grep -q 'steam.exe' "$TMP/task-list"
echo 'PASS: hung-game recovery kills only PoE, never Steam or GWENT.'
