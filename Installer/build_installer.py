#!/usr/bin/env python3
"""Package an already-built launcher. Never reads or copies its game profiles."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


SOURCE = Path(__file__).resolve().parents[1]
OUTPUTS = SOURCE.parent
ALLOWED_FILES = {
    "Contents/Info.plist",
    "Contents/MacOS/EitnyGameHub",
    "Contents/_CodeSignature/CodeResources",
    "Contents/Resources/GameSettings",
    "Contents/Resources/bridge.sh",
    "Contents/Resources/poe.sh",
    "Contents/Resources/poe-graphics.sh",
    "Contents/Resources/App_Icon.png",
    "Contents/Resources/AppIconDisplay.png",
    "Contents/Resources/EitnyDockIcon.icns",
    "Contents/Resources/LICENSE.txt",
}


def run(*args, capture=False):
    result = subprocess.run([str(arg) for arg in args], check=True,
                            stdout=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None


def manifest(app):
    """An exact allowlist prevents accidental release of accounts or source trees."""
    hashes = {}
    for path in app.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Unexpected symlink in app: {path.relative_to(app)}")
        relative = path.relative_to(app).as_posix()
        if path.is_dir():
            if not any(name.startswith(relative + "/") for name in ALLOWED_FILES):
                raise ValueError(f"Unexpected directory in app: {relative}")
        else:
            if relative not in ALLOWED_FILES:
                raise ValueError(f"Unexpected file in app: {relative}")
            hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    if set(hashes) != ALLOWED_FILES:
        raise ValueError(f"Missing app files: {sorted(ALLOWED_FILES - set(hashes))}")
    return hashes


def page(title, content):
    return f'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><title>{title}</title>
<style>
body {{ font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 13px;
        line-height: 1.45; color: #252331; background: #fff; padding: 12px 18px; }}
h1 {{ font-size: 25px; line-height: 1.12; margin: 5px 0 8px; letter-spacing: -.5px; }}
h2 {{ font-size: 15px; margin: 19px 0 7px; }}
p {{ margin: 9px 0; }}
li {{ margin-bottom: 8px; }}
ol {{ padding-left: 20px; }}
.eyebrow {{ color: #7660bd; font-size: 10px; font-weight: 700; letter-spacing: 1.4px; }}
.muted {{ color: #686572; font-size: 11px; }}
.card {{ background: #f3f0fc; padding: 11px 14px; border-radius: 10px; }}
a {{ color: #6c54b5; }}
</style></head><body>{content}</body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=OUTPUTS / "EitnyGameHub.app")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    minimum = info["LSMinimumSystemVersion"]
    bundle_id = info["CFBundleIdentifier"]
    if not all(re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value)
               for value in (version, build, minimum)):
        raise ValueError("Version metadata must contain only dotted numbers")
    if bundle_id != "local.eitnygamehub.launcher" or app.name != "EitnyGameHub.app":
        raise ValueError("This packager only accepts EitnyGameHub.app")
    original = manifest(app)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    for executable in ("Contents/MacOS/EitnyGameHub", "Contents/Resources/GameSettings"):
        if run("/usr/bin/lipo", "-archs", app / executable, capture=True) != "arm64":
            raise ValueError("Unexpected executable architecture")
        if not os.access(app / executable, os.X_OK):
            raise ValueError(f"Missing execute permission: {executable}")

    destination = (args.output or OUTPUTS / f"Installer-{version}").resolve()
    destination.mkdir(parents=True, exist_ok=True)
    filename = f"EitnyGameHub-{version}-Installer.pkg"
    package = destination / filename
    identifier = "local.eitnygamehub.installer"
    package_version = f"{version}.{build}"

    with tempfile.TemporaryDirectory(prefix="eitny-installer-") as temporary:
        work = Path(temporary)
        root, resources = work / "root", work / "resources"
        root.mkdir()
        resources.mkdir()
        # Copies only the explicit bundle, never any of its adjacent data folders.
        run("/usr/bin/ditto", "--norsrc", "--noextattr", app, root / app.name)
        if manifest(root / app.name) != original:
            raise ValueError("App changed while being copied")
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", root / app.name)

        components = [{"RootRelativeBundlePath": app.name,
                       "BundleIsRelocatable": False,
                       "BundleIsVersionChecked": True,
                       "BundleHasStrictIdentifier": True,
                       "BundleOverwriteAction": "upgrade"}]
        component_plist = work / "components.plist"
        component_plist.write_bytes(plistlib.dumps(components))
        component = work / "EitnyGameHub-component.pkg"
        run("/usr/bin/pkgbuild", "--root", root, "--component-plist", component_plist,
            "--identifier", identifier, "--version", package_version,
            "--install-location", "/Applications", "--ownership", "recommended",
            "--compression", "legacy", "--min-os-version", minimum, component)

        shutil.copyfile(app / "Contents/Resources/AppIconDisplay.png", resources / "AppIcon.png")
        (resources / "Welcome.html").write_text(page("EitnyGameHub", f'''
<img src="AppIcon.png" width="64" height="64" alt="EitnyGameHub">
<p class="eyebrow">EITNYGAMEHUB / {version}</p>
<h1>Твои игры. Твой Mac.</h1>
<p>Библиотека Steam и запуск Windows-игр<br>на Mac с Apple Silicon.</p>
<div class="card">Установщик добавит EitnyGameHub<br>в папку <b>«Программы»</b>.</div>
<p class="muted">Apple Silicon · macOS 14 и новее<br>
Для Path of Exile требуется macOS 15 и новее.</p>
'''), encoding="utf-8")
        (resources / "ReadMe.html").write_text(page("Перед установкой", '''
<h1>Перед установкой</h1>
<p>Это ранняя версия EitnyGameHub. На компьютере автора проверены
<b>GWENT</b> и <b>Path of Exile</b> в оконном режиме.
Совместимость остальных игр пока не проверена.</p>
<h2>Что потребуется</h2>
<p>Mac с Apple Silicon, интернет, Rosetta 2 и место для выбранных игр.
Rosetta 2 устанавливается отдельно средствами macOS.</p>
<p>Компоненты запуска и Steam загружаются при первой подготовке внутри приложения.
Игры устанавливаются через твой аккаунт Steam.</p>
<h2>Обновление и первый запуск</h2>
<p>Перед установкой закрой EitnyGameHub. Игровые данные хранятся отдельно от приложения.
Этот пакет содержит только приложение — без исходного проекта, аккаунтов и игр.</p>
<p class="muted">Пакет не подписан сертификатом Developer ID и не заверен Apple.
Если macOS блокирует открытие, используй «Конфиденциальность и безопасность →
Открыть всё равно» только для полученного от автора EitnyGameHub.
<a href="https://support.apple.com/102445">Инструкция Apple</a>.</p>
'''), encoding="utf-8")
        (resources / "Conclusion.html").write_text(page("Первый запуск", '''
<h1>Теперь можно подключить Steam</h1>
<ol>
<li>Открой <b>EitnyGameHub</b> из папки <b>«Программы»</b>.</li>
<li>Нажми <b>«Подготовить Steam»</b> и дождись загрузки компонентов.</li>
<li>Нажми <b>«Открыть Steam»</b> и войди в свой аккаунт.</li>
<li>Установи GWENT в Steam, обнови библиотеку EitnyGameHub и нажми на карточку игры.</li>
</ol>
<div class="card"><b>Path of Exile</b><br>Открой раздел игры слева,
нажми «Подготовить PoE» и установи игру в отдельном Steam.</div>
<p class="muted">Для PoE используй оконный режим: Fullscreen пока нестабилен.
В случае зависания переключись в EitnyGameHub и выбери на странице PoE
«Восстановить оконный режим…».</p>
'''), encoding="utf-8")

        distribution = work / "Distribution.xml"
        distribution.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
  <title>EitnyGameHub {version}</title>
  <welcome file="Welcome.html" mime-type="text/html"/>
  <readme file="ReadMe.html" mime-type="text/html"/>
  <conclusion file="Conclusion.html" mime-type="text/html"/>
  <options customize="never" require-scripts="false" allow-external-scripts="false" hostArchitectures="arm64"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <volume-check><allowed-os-versions><os-version min="{minimum}"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="eitnygamehub"/></choices-outline>
  <choice id="eitnygamehub" title="EitnyGameHub" description="Приложение для библиотеки Steam и запуска игр" visible="false">
    <pkg-ref id="{identifier}"/>
  </choice>
  <pkg-ref id="{identifier}" version="{package_version}" onConclusion="None">EitnyGameHub-component.pkg</pkg-ref>
  <pkg-ref id="{identifier}"><must-close><app id="{bundle_id}"/></must-close></pkg-ref>
</installer-gui-script>
''', encoding="utf-8")
        run("/usr/bin/productbuild", "--distribution", distribution,
            "--resources", resources, "--package-path", work, work / filename)

        # Validate the actual distributable, including its payload and install destination.
        expanded = work / "expanded"
        run("/usr/sbin/pkgutil", "--expand-full", work / filename, expanded)
        payload = expanded / "EitnyGameHub-component.pkg/Payload"
        if sorted(path.name for path in payload.iterdir()) != [app.name]:
            raise ValueError("Unexpected files outside the application")
        if manifest(payload / app.name) != original:
            raise ValueError("Installer payload does not match the verified application")
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", payload / app.name)
        for executable in ("Contents/MacOS/EitnyGameHub", "Contents/Resources/GameSettings"):
            if not os.access(payload / app.name / executable, os.X_OK):
                raise ValueError(f"Package lost execute permission: {executable}")
        package_info = ET.parse(expanded / "EitnyGameHub-component.pkg/PackageInfo").getroot()
        if package_info.get("install-location") != "/Applications":
            raise ValueError("Unexpected installation location")
        if package_info.find("scripts") is not None:
            raise ValueError("Installer must not contain install scripts")
        relocation = package_info.find("relocate")
        if relocation is not None and (len(relocation) or relocation.attrib):
            raise ValueError("Installer must not relocate or overwrite the independent backup")
        run("/usr/sbin/installer", "-pkg", work / filename, "-target", "/", "-showChoicesXML", capture=True)
        shutil.copyfile(work / filename, package)

    readme = f'''EitnyGameHub {version} — установка на Mac

Передай другу файл {filename}. Исходный проект и личные данные не нужны.

1. Открой установщик, нажми «Продолжить», затем «Установить».
   macOS может запросить пароль администратора для установки в «Программы».
2. Открой EitnyGameHub из «Программ».
3. Нажми «Подготовить Steam». Дождись загрузки компонентов, затем открой Steam
   и войди в СВОЙ аккаунт. Для игр требуется Rosetta 2 и интернет.
4. Для GWENT: установи его в Steam, обнови библиотеку EitnyGameHub и нажми
   на карточку игры. При первом запуске войди в свой GOG.
5. Для первой Path of Exile: раздел «Path of Exile» → «Подготовить PoE».
   Затем войди в отдельный Steam и установи игру. Нужна macOS 15 или новее.

Требования: Apple Silicon (M1 и новее), macOS {minimum} и новее.
Rosetta 2, компоненты запуска, Steam и игры не входят в этот небольшой пакет.
Компоненты и Steam загружаются приложением при первой подготовке;
Rosetta устанавливается отдельно средствами macOS.

Пакет пока НЕ подписан сертификатом Developer ID и НЕ заверен Apple.
Если macOS блокирует установщик или приложение: после попытки открытия зайди
в «Системные настройки → Конфиденциальность и безопасность → Открыть всё равно»
именно для EitnyGameHub, полученного от автора. Не отключай защиту macOS целиком.
Официальная инструкция Apple: https://support.apple.com/102445
Если сообщение другое (например, «Не удаётся открыть программу»), пришли автору
точный текст ошибки и версию macOS — установщик не гарантирует исправление
любой ошибки запуска.

Проверены автором на M3 Pro: GWENT и PoE в обычном окне.
Остальные игры и другие модели Mac пока не проверены.
Fullscreen в PoE пока нестабилен. При зависании переключись через ⌘Tab
в EitnyGameHub → Path of Exile → «Восстановить оконный режим…».

Настройки, игры и аккаунты нового пользователя хранятся отдельно:
~/Library/Application Support/EitnyGameHub
Не передавай эту папку другим людям. Обновление приложения её не удаляет.
Удаление приложения: закрой его и перенеси EitnyGameHub из «Программ» в Корзину.
Игровые данные останутся на диске.

EitnyGameHub — независимый проект. Названия, игры и сторонние компоненты
принадлежат своим правообладателям; их лицензии сохраняются.
'''
    (destination / "Установка.txt").write_text(readme, encoding="utf-8")
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(f"{digest}  {filename}\n", encoding="ascii")
    print(f"Verified installer: {package}")
    print("PASS: exact app payload, signature, arm64, executable permissions, /Applications, no scripts or relocation")
    print("Signing: no Developer ID / no Apple notarization")


if __name__ == "__main__":
    main()
