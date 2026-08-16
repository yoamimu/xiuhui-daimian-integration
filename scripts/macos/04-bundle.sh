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

# ---------- target architecture ----------
export MAC_ARCH="${MAC_ARCH:-arm64}"
case "${MAC_ARCH}" in
    arm64|x86_64) ;;
    *) _die "MAC_ARCH must be arm64 or x86_64 (got ${MAC_ARCH})" ;;
esac

RAW_APP="${PREVIEW_ROOT}/build/Inkscape-${MAC_ARCH}.app"
FINAL_APP="${PREVIEW_ROOT}/build/Inkscape-绣绘呆棉版-${MAC_ARCH}.app"
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
#
# CRITICAL: the Ink/Stitch sub-folder MUST keep the `.app` suffix and the
# `Contents/` layer, because the PyInstaller bootloader locates its home
# directory by scanning upward for a `*.app/Contents/MacOS` path component.
# If we strip `.app` or flatten `Contents/`, the bootloader walks past the
# Ink/Stitch bundle and anchors onto the enclosing Inkscape.app instead, then
# fails with `Failed to load Python shared library .../MacOS/Python`.
#
# Final layout:
#   extensions/inkstitch.app/
#   ├── inx/                        ← hoisted copy so Inkscape's scanner finds it
#   │   └── *.inx  (rewritten to ../Contents/MacOS/inkstitch)
#   └── Contents/
#       ├── MacOS/inkstitch         ← the bootloader binary
#       ├── Resources/              ← full Resources (Python, PIL, fonts, ...)
#       └── Frameworks/             ← Python.framework + symlink targets
#
# The upstream *.inx files hardcode
#     <command location="inx">../../MacOS/inkstitch</command>
# which is only valid under the original Contents/Resources/inx/ location.
# After hoisting inx/ to the extension root, we rewrite it to
# `../Contents/MacOS/inkstitch` so Inkscape finds the binary relative to inx/.

EXT_DEST="${FINAL_APP}/Contents/Resources/share/inkscape/extensions/inkstitch.app"
mkdir -p "$(dirname "${EXT_DEST}")"

_log "Embedding Ink/Stitch into ${EXT_DEST}"
rm -rf "${EXT_DEST}"
mkdir -p "${EXT_DEST}"

# Keep the whole Contents/ subtree intact so MacOS/ + Resources/ + Frameworks/
# remain siblings exactly as the bootloader expects.
cp -a "${INKSTITCH_DIST_APP}/Contents/." "${EXT_DEST}/Contents/"

# Hoist the inx/ directory to the extension root and fix the relative path.
if [[ -d "${EXT_DEST}/Contents/Resources/inx" ]]; then
    cp -a "${EXT_DEST}/Contents/Resources/inx" "${EXT_DEST}/inx"
    # ../../MacOS/inkstitch  (upstream, assumes Resources/inx/ 2 levels deep)
    # → ../Contents/MacOS/inkstitch (relative to the hoisted extension-root inx/)
    sed -i '' 's|../../MacOS/inkstitch|../Contents/MacOS/inkstitch|g' "${EXT_DEST}/inx/"*.inx
fi

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

# ---------- 4. codesign EVERYTHING ----------
# Signing strategy is selectable:
#   SIGNING_IDENTITY set (e.g. "Developer ID Application: ...")
#       → Developer ID signing + hardened runtime (notarizable).
#   SIGNING_IDENTITY empty (default)
#       → ad-hoc signing (codesign -s -), no account needed.
#
# Ad-hoc signing still satisfies macOS's "all Mach-O binaries inside an
# .app bundle must be signed" rule for many GTK4 IPC paths. Without it,
# expect random subprocess crashes ("killed: 9") on launch.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-${SCRIPT_DIR}/assets/entitlements.plist}"

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    _log "Developer ID signing with identity: ${SIGNING_IDENTITY}"
    SIGN_ARGS=(--force --options runtime --timestamp --sign "${SIGNING_IDENTITY}")
    # Hardened runtime requires an entitlements plist; fall back to none if absent.
    if [[ -f "${ENTITLEMENTS}" ]]; then
        SIGN_ARGS+=(--entitlements "${ENTITLEMENTS}")
    else
        _warn "No entitlements plist at ${ENTITLEMENTS}; signing without entitlements."
    fi
else
    _log "Ad-hoc signing (no SIGNING_IDENTITY set; not notarizable)."
    SIGN_ARGS=(--force --sign - --timestamp=none)
fi

_log "Signing all Mach-O files inside ${FINAL_APP} ..."
# Sign nested binaries first (deepest-first), then the bundle wrapper.
find "${FINAL_APP}" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) -print0 \
    | xargs -0 -n 200 codesign "${SIGN_ARGS[@]}" --preserve-metadata=identifier,entitlements,flags || true

# Top-level app bundle signature last.
codesign --force --deep "${SIGN_ARGS[@]}" "${FINAL_APP}"

# Verify.
codesign --verify --deep --verbose=2 "${FINAL_APP}" || _log "codesign --verify reported issues (informational; notarization is the authoritative check)."

_log "Final bundle: ${FINAL_APP}"
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    _log "Next: bash 06-notarize.sh (after 05-make-dmg.sh), or set NOTARIZE=1 in 05-make-dmg.sh."
else
    _log "Next: bash 05-make-dmg.sh"
fi
