#!/usr/bin/env bash
#
# 04-bundle.sh
# 绣绘呆棉整合版 macOS build — assemble the final, branded, ad-hoc-signed
# Inkscape.app that contains Ink/Stitch as an embedded extension.
#
# This script is cheap to re-run as long as 02-build-inkscape.sh and
# 03-build-inkstitch.sh have completed at least once.
#
# Output: ${PREVIEW_ROOT}/build/Inkscape-绣绘呆棉版.app
#
# Override PREVIEW_ROOT to use a non-default source workspace.

set -euo pipefail

_log()  { printf '\033[1;34m[04-bundle]\033[0m %s\n' "$*"; }
_die()  { printf '\033[1;31m[04-bundle]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEG_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"

RAW_APP="${PREVIEW_ROOT}/build/Inkscape.app"
FINAL_APP="${PREVIEW_ROOT}/build/Inkscape-绣绘呆棉版.app"
INKSTITCH_DIST_APP="${PREVIEW_ROOT}/src/inkstitch/dist/inkstitch.app"

[[ -d "${RAW_APP}" ]]           || _die "Raw Inkscape bundle not found at ${RAW_APP}. Run 02-build-inkscape.sh."
[[ -d "${INKSTITCH_DIST_APP}" ]] || _die "Ink/Stitch dist app not found at ${INKSTITCH_DIST_APP}. Run 03-build-inkstitch.sh."

# Version (mirrors logic in 03-build-inkstitch.sh).
VERSION="${VERSION:-xiuhui-$(git -C "${INTEG_REPO_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || date +%Y%m%d)-local}"
_log "VERSION=${VERSION}"

# ---------- 1. duplicate raw bundle ----------
_log "Cloning raw bundle → ${FINAL_APP}"
rm -rf "${FINAL_APP}"
cp -a "${RAW_APP}" "${FINAL_APP}"

# ---------- 2. embed Ink/Stitch ----------
# Inkscape looks up bundled extensions under
#   Inkscape.app/Contents/Resources/share/inkscape/extensions/
# Putting Ink/Stitch under a sub-folder there makes it visible to every
# user of the host machine without any post-install script.
EXT_DEST="${FINAL_APP}/Contents/Resources/share/inkscape/extensions/inkstitch"
mkdir -p "$(dirname "${EXT_DEST}")"
rm -rf "${EXT_DEST}"

# Ink/Stitch's PyInstaller bundle has the runnable tree at
#   dist/inkstitch.app/Contents/MacOS/  (binaries + python libs)
#   dist/inkstitch.app/Contents/Resources/  (inx, fonts, palettes, ...)
# Inkscape's extension loader expects the .inx files and Python entry
# point at the top level of the extension folder, so we flatten the
# Contents/MacOS + Contents/Resources content directly into ${EXT_DEST}.
_log "Embedding Ink/Stitch into ${EXT_DEST}"
mkdir -p "${EXT_DEST}"
# Resources come first; they include inx/, fonts/, palettes/ etc.
cp -a "${INKSTITCH_DIST_APP}/Contents/Resources/." "${EXT_DEST}/"
# Binaries + python libs from MacOS/. Inkstitch.py + the bundled python
# runtime end up here.
cp -a "${INKSTITCH_DIST_APP}/Contents/MacOS/." "${EXT_DEST}/"

# ---------- 3. rewrite Info.plist (branding) ----------
PLIST="${FINAL_APP}/Contents/Info.plist"
_log "Rewriting Info.plist branding..."
/usr/libexec/PlistBuddy -c "Set :CFBundleName 绣绘呆棉整合版" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleName string 绣绘呆棉整合版" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 绣绘呆棉整合版" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 绣绘呆棉整合版" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.yoamimu.xiuhui-daimian.inkscape" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION}" "${PLIST}"
# Optional but recommended: claim our own LSMinimumSystemVersion
DEPLOY_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion | cut -d. -f1).0}"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion ${DEPLOY_TARGET}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string ${DEPLOY_TARGET}" "${PLIST}"

# ---------- 4. ad-hoc codesign EVERYTHING ----------
# Ad-hoc signing (codesign -s -) does not need an Apple Developer account
# but DOES satisfy macOS's "all Mach-O binaries inside an .app bundle must
# be signed" rule for many GTK4 IPC paths. Without it, expect random
# subprocess crashes ("killed: 9") on launch.
_log "Ad-hoc signing all Mach-O files inside ${FINAL_APP} ..."
# Sign nested binaries first (deepest-first), then the bundle wrapper.
# Using --force --options=runtime here is intentional even for ad-hoc
# signatures; it makes verification predictable later.
find "${FINAL_APP}" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) -print0 \
    | xargs -0 -n 200 codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements,flags || true

# Top-level app bundle signature last.
codesign --force --deep --sign - --timestamp=none "${FINAL_APP}"

# Verify (informational; ad-hoc signatures cannot be notarized but should
# pass basic --verify).
codesign --verify --deep --verbose=2 "${FINAL_APP}" || _log "codesign --verify reported issues (this is often OK for ad-hoc)."

_log "Final bundle: ${FINAL_APP}"
_log "Next: bash 05-make-dmg.sh"
