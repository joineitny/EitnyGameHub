# Sourced only by poe.sh, after DATA has been restricted to Profiles/PathOfExile.
graphics_ready() {
  [[ -f "$RUNTIME/.poe-d3dmetal-v3" && -f "$RUNTIME/lib/D3DMetal.framework/D3DMetal" && -f "$RUNTIME/lib/wine/x86_64-unix/d3d12.so" ]]
}
install_graphics() (
  graphics_ready && exit 0
  [[ "$DATA" == "$BASE/Profiles/PathOfExile" ]] || fail 'Неверный путь окружения PoE.'
  local major
  major=$(/usr/bin/sw_vers -productVersion); major=${major%%.*}
  (( major >= 15 )) || fail 'Для Path of Exile с DirectX 12 нужна macOS 15 или новее.'
  wine_env
  local tasks
  tasks=$("$WINE" tasklist /fo csv 2>>"$LOGS/graphics.log") || fail 'Не удалось проверить процессы PoE.'
  [[ "$tasks" != *PathOfExile* && "$tasks" != *'"steam.exe"'* && "$tasks" != *'"Steam.exe"'* ]] || fail 'Перед обновлением графики закрой игру и нажми «Закрыть Steam для PoE», затем повтори запуск.'
  local lock="$DATA/.graphics-setup-lock" stage=""
  mkdir "$lock" 2>/dev/null || fail 'Подготовка графики PoE уже выполняется.'
  trap '[[ -z "$stage" ]] || rm -rf "$stage"; rmdir "$lock" 2>/dev/null || true' EXIT
  stage=$(mktemp -d "$DATA/graphics-prepare.XXXXXX")
  local checksum=9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a
  local archive="$BASE/Downloads/wrapper.tar.xz"
  verify_graphics_archive() { [[ -f "$1" && "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" == "$checksum" ]]; }
  if ! verify_graphics_archive "$archive"; then
    archive="$DATA/Downloads/wrapper.tar.xz"
    if ! verify_graphics_archive "$archive"; then
      event 'Загружаю компонент DirectX 12 для PoE…'
      mkdir -p "$DATA/Downloads"
      /usr/bin/curl --fail --location --retry 2 --connect-timeout 20 --max-time 900 --proto '=https' --proto-redir '=https' --silent --show-error 'https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.11.tar.xz' -o "$stage/wrapper.tar.xz"
      verify_graphics_archive "$stage/wrapper.tar.xz" || fail 'Компонент графики не прошёл проверку целостности.'
      mv "$stage/wrapper.tar.xz" "$archive"
    fi
  fi
  event 'Подключаю DirectX 12 в отдельном окружении PoE…'
  /usr/bin/tar -xf "$archive" -C "$stage" 'Template-1.0.11.app/Contents/Frameworks/renderer/d3dmetal'
  local source="$stage/Template-1.0.11.app/Contents/Frameworks/renderer/d3dmetal"
  [[ -f "$source/wine/x86_64-windows/d3d12.dll" && -f "$source/external/D3DMetal.framework/D3DMetal" ]] || fail 'В архиве отсутствует графика DirectX 12.'
  if ! /bin/cp -cR "$RUNTIME" "$stage/Runtime"; then
    rm -rf "$stage/Runtime"
    /bin/cp -R "$RUNTIME" "$stage/Runtime"
  fi
  local next="$stage/Runtime" dll name
  /bin/cp -R "$source/external/D3DMetal.framework" "$next/lib/"
  /bin/cp "$source/external/libd3dshared.dylib" "$next/lib/"
  mkdir -p "$next/D3DMetal-Notices"
  /bin/cp "$source/License.rtf" "$source/Acknowledgements.rtf" "$source/Read Me.rtf" "$next/D3DMetal-Notices/"
  for dll in "$source"/wine/x86_64-windows/*.dll; do
    name=$(basename "$dll" .dll)
    /bin/cp "$dll" "$next/lib/wine/x86_64-windows/"
    ln -sf ../../libd3dshared.dylib "$next/lib/wine/x86_64-unix/$name.so"
  done
  local backup="$DATA/Runtime.before-D3DMetal.$(/bin/date +%s).$$"
  /bin/mv "$RUNTIME" "$backup"
  if ! /bin/mv "$next" "$RUNTIME"; then /bin/mv "$backup" "$RUNTIME"; fail 'Не удалось установить графику PoE.'; fi
  for dll in "$source"/wine/x86_64-windows/*.dll; do
    name=$(basename "$dll")
    if [[ -f "$PREFIX/drive_c/windows/system32/$name" && ! -e "$PREFIX/drive_c/windows/system32/$name.before-D3DMetal" ]]; then
      /bin/cp "$PREFIX/drive_c/windows/system32/$name" "$PREFIX/drive_c/windows/system32/$name.before-D3DMetal"
    fi
    /bin/cp "$dll" "$PREFIX/drive_c/windows/system32/"
  done
  touch "$RUNTIME/.poe-d3dmetal-v3"
)
