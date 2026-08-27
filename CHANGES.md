# Changes

## Unreleased

No changes recorded yet.

## 0.1.0 - 2026-08-27

Release status:

- Published the first tested macOS dual-architecture release.
- Verified by the project owner on Apple Silicon and Intel Mac hardware.
- Apple Silicon package targets arm64 and was tested on macOS 14 or later.
- Intel package targets x86_64 and was tested on macOS 15.
- Both release images were verified with `hdiutil verify`; their embedded apps pass strict ad-hoc code-signature verification.
- The v0.1.0 packages are not Apple-notarized. First launch requires Control-click/right-click and **Open**.
- Both binaries report integration build `xiuhui-b1ad7aa-local`; release repackaging changed only the invalid outer app signature and first-launch instructions.

Base versions:

- Inkscape `7923d92`
- Ink/Stitch `0312dac`

Changes:

- Added floating Ink/Stitch action panel on the canvas.
- Added floating file operation panel with import and export buttons.
- Added collapsible/minimizable Ink/Stitch floating entry.
- Added user-customizable common-action area for Ink/Stitch operations.
- Localized Ink/Stitch operation labels, tooltips, menu entries and terminology into Simplified Chinese.
- Added Simplified Chinese terminology reference for embroidery-related UI.
- Prioritized DST export workflow for embroidery use.
- Added color parsing robustness for local Ink/Stitch parameter preview.
- Added the macOS Apple Silicon integrated DMG build pipeline under `scripts/macos/` (Homebrew-based, ad-hoc signed, unnotarized).
- Added dual-arch macOS build support (arm64 + x86_64), Developer ID signing + notarization (`06-notarize.sh`), and GitHub Actions CI workflow.
- Fixed macOS crash-on-launch: bundled GTK4's Adwaita icon theme into the `.app` (previously missing, causing SIGSEGV in `gtk_icon_theme_lookup_icon`).
- Fixed dmg naming bug: `create-dmg` icon layout now uses the arch-suffixed app name, and stale `rw.*.dmg` intermediates are cleaned up.
- Fixed Ink/Stitch extensions failing to load with "无法满足其中一个依赖项 ... 字符串: ../../MacOS/inkstitch": the Ink/Stitch bundle is now kept as a nested `extensions/inkstitch.app/Contents/{MacOS,Resources,Frameworks}` (the `.app` suffix and `Contents/` layer are required by the PyInstaller bootloader to locate its home and load `Python.framework`), with `inx/` hoisted to the extension root and its relative command path rewritten to `Contents/MacOS/inkstitch`.
