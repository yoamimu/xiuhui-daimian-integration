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
EXT_DEST="${FINAL_APP}/Contents/Resources/share/inkscape/extensions/inkstitch"
mkdir -p "$(dirname "${EXT_DEST}")"
rm -rf "${EXT_DEST}"

# Ink/Stitch's PyInstaller bundle is a standard .app:
#   dist/inkstitch.app/Contents/MacOS/        (the inkstitch binary)
#   dist/inkstitch.app/Contents/Resources/    (inx/, fonts/, palettes/, ... + symlinks)
#   dist/inkstitch.app/Contents/Frameworks/   (Python.framework, numpy, PIL, .dylibs, ...)
# Most of Resources/ is itself a forest of relative symlinks ("PIL -> ../Frameworks/PIL")
# that only resolve correctly if Frameworks/ is still a sibling of MacOS/ and Resources/.
#
# Layout decision:
#   - Flatten Resources/ into ${EXT_DEST} so Inkscape's extension scanner picks up
#     the inx/ directory (it scans one level deep by default).
#   - Copy Frameworks/ into ${EXT_DEST}/Frameworks/ so the Resources symlinks
#     (PIL -> ../Frameworks/PIL, etc.) keep resolving.
#   - Copy MacOS/ to ${EXT_PARENT}/MacOS/ — i.e. ONE level above ${EXT_DEST}.
#     Reason: Ink/Stitch's *.inx files hardcode
#         <command location="inx">../../MacOS/inkstitch</command>
#     which Inkscape resolves relative to the .inx file's own directory.
#     From extensions/inkstitch/inx/ that's extensions/inkstitch/../.. + MacOS/inkstitch
#     = extensions/MacOS/inkstitch. Putting it under ${EXT_DEST} would force
#     users to add a non-standard MacOS/ under inkstitch/, which breaks the
#     upstream inx paths without any obvious upside.
EXT_PARENT="$(dirname "${EXT_DEST}")"

_log "Embedding Ink/Stitch into ${EXT_DEST}"
rm -rf "${EXT_DEST}" "${EXT_PARENT}/MacOS"
mkdir -p "${EXT_DEST}" "${EXT_PARENT}/MacOS"

# Flatten Resources (inx/, fonts/, palettes/, icons/, locales/, ...) into the
# extension root. Most entries here are symlinks that point into Frameworks/.
cp -a "${INKSTITCH_DIST_APP}/Contents/Resources/." "${EXT_DEST}/"

# Copy Frameworks next to the symlinks so relative "../Frameworks/X" targets
# resolve inside the Inkscape .app.
if [[ -d "${INKSTITCH_DIST_APP}/Contents/Frameworks" ]]; then
    cp -a "${INKSTITCH_DIST_APP}/Contents/Frameworks/." "${EXT_DEST}/Frameworks/"
fi

# The actual inkstitch executable goes one level up at ${EXT_PARENT}/MacOS/, so
# that inx/../../MacOS/inkstitch resolves correctly.
cp -a "${INKSTITCH_DIST_APP}/Contents/MacOS/." "${EXT_PARENT}/MacOS/"

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
