# Help improve EitnyGameHub / Как помочь проекту

[English](#english) · [Русский](#русский)

## English

Thanks for your interest! The most useful contribution right now is testing on different Macs. Successful results are just as important as bug reports.

### Test a game

1. Install the [current release](https://github.com/joineitny/EitnyGameHub/releases/latest). Include the exact version, or the commit of your own build, in your report.
2. Check [existing reports](https://github.com/joineitny/EitnyGameHub/issues). You can add your hardware configuration and observations to a similar report.
3. Try launching and signing in, mouse or trackpad input, audio and an actual gameplay scene. Exit and launch again. Explain how far you got: loading screen, menu, town, match or another scene.
4. Record your Mac model, chip, memory, macOS, game, launch profile, resolution and graphics settings. For FPS, include the scene and test duration. If you did not measure FPS, say so.
5. Submit a [compatibility report](https://github.com/joineitny/EitnyGameHub/issues/new?template=compatibility.yml), including when everything works.

Use a normal window for PoE. Testing one scene does not establish compatibility for the entire game: note limitations and untested modes. Save your working configuration before experimenting with settings; do not add game data to Git.

### Report a bug or contribute a change

Use the [bug report form](https://github.com/joineitny/EitnyGameHub/issues/new?template=bug_report.yml) for installation, interface, library or launch problems. Include reproduction steps, expected behavior and the exact error. Remove tokens, account details and personal paths from logs; attach only the relevant excerpt.

Fixes, translations, documentation improvements and interface suggestions are welcome. Open an Issue before a large change to describe the problem and proposed approach. For code contributions, create a branch and Pull Request; explain the change and how it was verified. Preserve PoE/GWENT isolation and user settings. For launch-code changes, run `bash test.sh` and check the build with `bash build.sh` when relevant.

English and Russian are equally welcome in Issues and Pull Requests. Update both READMEs when changing shared documentation. Do not label untested games as confirmed compatible.

## Русский
Спасибо за интерес к проекту! Самая полезная помощь сейчас — реальные проверки на разных Mac. Успешные результаты нужны не меньше, чем сообщения об ошибках.

### Проверить игру

1. Установите [текущий релиз](https://github.com/joineitny/EitnyGameHub/releases/latest). Укажите в отчёте его точную версию или коммит своей сборки.
2. Откройте [существующие отчёты](https://github.com/joineitny/EitnyGameHub/issues): к похожему результату можно добавить свою конфигурацию и наблюдения.
3. Проверьте запуск и вход, мышь или трекпад, звук и реальную игровую сцену. После выхода попробуйте запустить игру снова. Укажите, насколько далеко удалось пройти: загрузка, меню, город, матч или другая сцена.
4. Запишите модель Mac, чип, память, macOS, игру, профиль запуска, разрешение и настройки графики. Для FPS укажите сцену и продолжительность проверки. Если FPS не измеряли, так и напишите.
5. Заполните [отчёт о совместимости](https://github.com/joineitny/EitnyGameHub/issues/new?template=compatibility.yml), даже если всё работает.

Для PoE используйте обычное окно. Проверка одной сцены не означает совместимость всей игры: отмечайте ограничения и неизученные режимы. Перед экспериментами с настройками сохраните свою рабочую конфигурацию; игровые данные не добавляйте в Git.

### Найти ошибку или улучшить проект

Для проблем установки, интерфейса, библиотеки или запуска используйте [форму ошибки](https://github.com/joineitny/EitnyGameHub/issues/new?template=bug_report.yml). Нужны шаги воспроизведения, ожидаемое поведение и точный текст ошибки. Удаляйте из журналов токены, аккаунты и личные пути; прикладывайте только нужный фрагмент.

Также полезны исправления, переводы, уточнения документации и предложения по интерфейсу. Перед крупным изменением откройте Issue с проблемой и предлагаемым подходом. Для кода создайте отдельную ветку и Pull Request; опишите, что поменялось и как это проверено. Сохраняйте изоляцию PoE/GWENT и пользовательские настройки. Для изменений кода запуска используйте `bash test.sh`; при необходимости проверьте сборку через `bash build.sh`.

Русский и английский одинаково подходят для Issues и Pull Requests. Связанные изменения документации обновляйте в обоих README. Не добавляйте непроверенные игры в список подтверждённой совместимости.
