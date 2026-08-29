# Changes

## Unreleased

Activation and delivery:

- Added a one-code/one-Mac activation system for the official macOS packages without changing the Inkscape or Ink/Stitch drawing code paths.
- Added an authenticated web administration console for creating customer licenses, setting payment-date start and expiry dates, viewing bindings, revoking licenses, extending expiry dates, and unbinding old Macs.
- New licenses default to one device and one calendar year from the selected payment date, including leap-day handling.
- Activation codes contain 60 bits of cryptographic randomness and are stored only as server-peppered HMAC-SHA256 digests; the plaintext code is shown once when created.
- First activation atomically binds the code to the Mac device digest. Concurrent or later attempts from a second Mac are rejected, and an explicitly unbound old Mac cannot reclaim the released slot.
- Added ECDSA P-256 signed license tokens with a 72-hour offline grace period. The signing private key remains server-side; macOS packages contain only the public key.
- Added a native Cocoa activation launcher for both arm64 and x86_64. Successful validation hands control to the original `inkscape-core` executable with `execv`.
- Added a Docker/Gunicorn/SQLite deployment, Nginx HTTPS proxy configuration, API and admin-login rate limits, CSRF protection, secure sessions, audit logging, and backup instructions.
- Added an activation privacy notice covering the hashed hardware identifier, Mac model, OS version, architecture, app version, and validation timestamps.

Build and verification:

- macOS production builds now fail closed unless activation is enabled and an HTTPS `ACTIVATION_SERVER_URL` is supplied.
- Added GitHub Actions tests for the Python service and native arm64/x86_64 activation clients.
- Verified first-device activation, second-device rejection, administrator unbind, old-device reactivation rejection, replacement-device activation, expiry handling, signed token validation, and leap-day expiry calculation.
- Verified the protected arm64 launcher inside the real Xiuhui app bundle: activation succeeds, control passes to the original app, and the existing Ink/Stitch interface remains available.

Project log:

- Added `docs/PROJECT_LOG.md` to record version status, build results, rendering test conclusions, and whether a package is customer-ready.

Rendering:

- macOS launcher now defaults GTK composition to `GSK_RENDERER=cairo` to avoid the GPU clip-replay crash, and seeds Inkscape canvas `request_opengl=1` when that preference is absent. This is an internal flicker-test combination, not a claimed complete fix.

Deployment status:

- Production HTTPS deployment and protected v0.2.0 package publication remain pending until the final authorization domain is configured on the existing Ubuntu server.

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
