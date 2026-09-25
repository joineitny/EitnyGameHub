# EitnyGameHub contributor notes

- Native macOS / SwiftUI launcher. Current release: 0.4.1 (build 8).
- Read README.md for architecture, supported scenarios and known limitations.
- Build: `bash build.sh`. Verify: `bash test.sh`. Package: `bash package.sh`.
- Keep GWENT's Wine + DXMT environment separate from PoE's Wine + D3DMetal environment.
- Preserve user resolution, FSR, audio and key bindings when changing launch settings.
- PoE fullscreen is not supported by the current tested profile. Do not present it as fixed without a real test.
- Tests must use temporary fixtures, never an actual Steam account or installed game.
- Never commit accounts, Wine prefixes, games, runtime archives, logs, API keys, personal paths or local handoff notes.
- Keep the original Resources/App_Icon.png; use AppIconDisplay.png / AppIcon.icns for the current application icon.
- Releases contain only the launcher and instructions; users download third-party components and games separately.
- Do not claim general game compatibility or performance improvements without evidence.
