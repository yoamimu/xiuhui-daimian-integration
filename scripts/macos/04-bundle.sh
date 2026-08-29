#!/usr/bin/env bash
#
# 04-bundle.sh
# 绣绘呆棉整合版 macOS build — assemble the final, branded, ad-hoc-signed
# Inkscape.app that contains Ink/Stitch as an embedded extension.
#
# This script is cheap to re-run as long as 02-build-inkscape.sh and
# 03-build-inkstitch.sh have completed at least once.
#
# Output: ${PREVIEW_ROOT}/build/绣绘-苹果芯片.app or 绣绘-Intel.app
#
# Override PREVIEW_ROOT to use a non-default source workspace.

set -euo pipefail

_log()  { printf '\033[1;34m[04-bundle]\033[0m %s\n' "$*"; }
_warn() { printf '\033[1;33m[04-bundle]\033[0m %s\n' "$*" >&2; }
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

if [[ "${MAC_ARCH}" == "arm64" ]]; then
    ARCH_LABEL="苹果芯片"
else
    ARCH_LABEL="Intel"
fi
RAW_APP="${PREVIEW_ROOT}/build/Inkscape-${MAC_ARCH}.app"
FINAL_APP="${PREVIEW_ROOT}/build/绣绘-${ARCH_LABEL}.app"
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

# Keep a second copy of the inx/ directory inside Contents/ so Inkscape's
# recursive extension scanner finds it, and fix the relative paths.
#
# NOTE: the copy MUST NOT live at the bundle root (inkstitch.app/inx/).
# Files directly in an .app bundle root make codesign fail with
# "unsealed contents present in the bundle root", which breaks Developer ID
# signing / notarization. Contents/inx/ is inside the bundle and signs fine.
#
# Upstream *.inx files reference "../icons/<...>", which assumes inx/ sits two
# levels deep (Contents/Resources/inx/). From Contents/inx/ we rewrite:
#   ../../MacOS/inkstitch            → ../MacOS/inkstitch
#   ../icons/<...>                   → ../Resources/icons/<...>
if [[ -d "${EXT_DEST}/Contents/Resources/inx" ]]; then
    cp -a "${EXT_DEST}/Contents/Resources/inx" "${EXT_DEST}/Contents/inx"
    sed -i '' 's|../../MacOS/inkstitch|../MacOS/inkstitch|g' "${EXT_DEST}/Contents/inx/"*.inx
    sed -i '' 's|\.\./icons/|../Resources/icons/|g' "${EXT_DEST}/Contents/inx/"*.inx

    # ---------- 2b. override fragile SVG icons ----------
    # Two upstream Ink/Stitch icons fail to render in Inkscape's extension
    # gallery (showing a broken-image X placeholder):
    #   lettering.svg           uses font-family="Barlow" (not installed;
    #                            only Barlow_Condensed is available on macOS,
    #                            and Pango/Cairo treat the names as distinct).
    #   stitch_plan_preview.svg uses an inkstitch-namespaced attribute that
    #                            trips the strict SVG loader.
    # Rather than debug upstream, we ship our own raster-friendly versions
    # from assets/macos-icons/ and overwrite the upstream copies in the
    # installed PyInstaller bundle.
    MAC_ICONS="${INTEG_REPO_ROOT}/assets/macos-icons"
    if [[ -d "${MAC_ICONS}" ]]; then
        _log "Overriding fragile Ink/Stitch SVG icons from ${MAC_ICONS} ..."
        for svg in lettering stitch_plan_preview; do
            if [[ -f "${MAC_ICONS}/${svg}.svg" ]]; then
                cp -f "${MAC_ICONS}/${svg}.svg" \
                      "${EXT_DEST}/Contents/Resources/icons/inx/${svg}.svg"
            fi
        done
    else
        _warn "${MAC_ICONS} not found; lettering/stitch_plan_preview will likely render as X."
    fi
fi

# ---------- 3. rewrite Info.plist (branding) ----------
PLIST="${FINAL_APP}/Contents/Info.plist"
_log "Rewriting Info.plist branding..."
/usr/libexec/PlistBuddy -c "Set :CFBundleName 绣绘" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleName string 绣绘" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 绣绘" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 绣绘" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.yoamimu.xiuhui-daimian.inkscape" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION}" "${PLIST}"
# Optional but recommended: claim our own LSMinimumSystemVersion
DEPLOY_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion | cut -d. -f1).0}"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion ${DEPLOY_TARGET}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string ${DEPLOY_TARGET}" "${PLIST}"

# ---------- 3b. brand the app icon (绣绘 logo) ----------
# Use the 绣绘 icon (generated from assets/branding/source) as the app icon.
BRAND_ICNS="${INTEG_REPO_ROOT}/assets/branding/macos/绣绘.icns"
if [[ -f "${BRAND_ICNS}" ]]; then
    _log "Applying 绣绘 app icon ..."
    cp -f "${BRAND_ICNS}" "${FINAL_APP}/Contents/Resources/绣绘.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile 绣绘.icns" "${PLIST}" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string 绣绘.icns" "${PLIST}"
else
    _warn "Brand icon not found at ${BRAND_ICNS}; keeping default icon."
fi

# ---------- 3c. install icon aliases used by older prebuilt UI code ----------
# The Ink/Stitch floating panel originally used a few freedesktop icon names
# that are not shipped in Inkscape's bundled icon theme on macOS.  Keep aliases
# in the app bundle so re-running this bundling step fixes existing binaries
# even before the Inkscape source is rebuilt with the newer icon names.
ICON_ROOT="${FINAL_APP}/Contents/Resources/share/inkscape/icons"
install_icon_alias() {
    local old="$1"
    local new="$2"
    local dir dst src

    for dir in \
        "hicolor/scalable/actions" \
        "hicolor/symbolic/actions" \
        "multicolor/symbolic/actions" \
        "Dash/symbolic/actions"; do
        mkdir -p "${ICON_ROOT}/${dir}"
        case "${dir}" in
            */scalable/actions)
                dst="${ICON_ROOT}/${dir}/${old}.svg"
                [[ -f "${ICON_ROOT}/${dir}/${new}.svg" ]] && src="${ICON_ROOT}/${dir}/${new}.svg" || src=""
                ;;
            *)
                dst="${ICON_ROOT}/${dir}/${old}-symbolic.svg"
                [[ -f "${ICON_ROOT}/${dir}/${new}-symbolic.svg" ]] && src="${ICON_ROOT}/${dir}/${new}-symbolic.svg" || src=""
                ;;
        esac
        [[ -z "${src}" && -f "${ICON_ROOT}/hicolor/scalable/actions/${new}.svg" ]] && src="${ICON_ROOT}/hicolor/scalable/actions/${new}.svg"
        [[ -z "${src}" && -f "${ICON_ROOT}/hicolor/symbolic/actions/${new}-symbolic.svg" ]] && src="${ICON_ROOT}/hicolor/symbolic/actions/${new}-symbolic.svg"
        [[ -z "${src}" && -f "${ICON_ROOT}/multicolor/symbolic/actions/${new}-symbolic.svg" ]] && src="${ICON_ROOT}/multicolor/symbolic/actions/${new}-symbolic.svg"
        [[ -z "${src}" && -f "${ICON_ROOT}/Dash/symbolic/actions/${new}-symbolic.svg" ]] && src="${ICON_ROOT}/Dash/symbolic/actions/${new}-symbolic.svg"

        if [[ -n "${src}" ]]; then
            cp -f "${src}" "${dst}"
        else
            _warn "Cannot create icon alias ${old} -> ${new}; source icon not found."
        fi
    done
}

_log "Installing Ink/Stitch floating-panel icon aliases ..."
install_icon_alias "insert-text" "draw-text"
install_icon_alias "document-print-preview" "preview-mode"
install_icon_alias "help-about" "dialog-information"
install_icon_alias "preferences-color" "color-palette"
install_icon_alias "insert-object" "list-add"
install_icon_alias "font-select" "dialog-text-and-font"
install_icon_alias "document-edit" "edit"
install_icon_alias "view-list" "layout-list"
install_icon_alias "media-playback-start" "play"

# ---------- 3d. install activation launcher ----------
# Keep licensing outside the Inkscape/Ink-Stitch code paths.  The original
# executable is moved to inkscape-core and re-signed with the surrounding app;
# a small native launcher performs activation and then execs that process.
ENABLE_ACTIVATION="${ENABLE_ACTIVATION:-1}"
case "${ENABLE_ACTIVATION}" in
    1|true|yes)
        ACTIVATION_MODE="${ACTIVATION_MODE:-offline}"
        ACTIVATION_CLIENT_DIR="${INTEG_REPO_ROOT}/activation-client/macos"
        INKSCAPE_EXECUTABLE="${FINAL_APP}/Contents/MacOS/inkscape"
        INKSCAPE_CORE="${FINAL_APP}/Contents/MacOS/inkscape-core"
        [[ -x "${INKSCAPE_EXECUTABLE}" ]] \
            || _die "Inkscape executable not found at ${INKSCAPE_EXECUTABLE}"
        case "${ACTIVATION_MODE}" in
            offline) ;;
            online)
                [[ -n "${ACTIVATION_SERVER_URL:-}" ]] \
                    || _die "ACTIVATION_SERVER_URL is required when ACTIVATION_MODE=online."
                ;;
            *) _die "ACTIVATION_MODE must be offline or online (got ${ACTIVATION_MODE})" ;;
        esac

        _log "Installing native ${MAC_ARCH} ${ACTIVATION_MODE} activation launcher ..."
        mv "${INKSCAPE_EXECUTABLE}" "${INKSCAPE_CORE}"
        MAC_ARCH="${MAC_ARCH}" \
        ACTIVATION_MODE="${ACTIVATION_MODE}" \
        ACTIVATION_SERVER_URL="${ACTIVATION_SERVER_URL:-}" \
        LICENSE_PUBLIC_KEY_FILE="${LICENSE_PUBLIC_KEY_FILE:-${ACTIVATION_CLIENT_DIR}/license-public-key.b64}" \
        ALLOW_INSECURE_LOCAL_ACTIVATION="${ALLOW_INSECURE_LOCAL_ACTIVATION:-0}" \
            bash "${ACTIVATION_CLIENT_DIR}/build-launcher.sh" "${INKSCAPE_EXECUTABLE}"
        ;;
    0|false|no)
        _warn "Activation launcher disabled for this local development build."
        ;;
    *)
        _die "ENABLE_ACTIVATION must be 1 or 0 (got ${ENABLE_ACTIVATION})"
        ;;
esac

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
