#!/usr/bin/env bash
#
# 05-make-dmg.sh
# 绣绘 macOS build — wrap the final .app into a user-friendly
# .dmg with an /Applications drag target, a localized README and (if
# available) a background image showing the "first launch" workaround.
#
# Output:
#   ${PREVIEW_ROOT}/release/绣绘-<VERSION>-arm64.dmg
#
# Uses Homebrew `create-dmg` (installed via Brewfile). If create-dmg is
# missing we fall back to a plain `hdiutil create` that still contains
# the README and the Applications symlink, just without the styled
# background.
#
# Override PREVIEW_ROOT / RELEASE_DIR to redirect outputs.

set -euo pipefail

_log()  { printf '\033[1;34m[05-dmg]\033[0m %s\n' "$*"; }
_die()  { printf '\033[1;31m[05-dmg]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEG_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"
RELEASE_DIR="${RELEASE_DIR:-${PREVIEW_ROOT}/release}"

# ---------- target architecture ----------
export MAC_ARCH="${MAC_ARCH:-arm64}"
case "${MAC_ARCH}" in
    arm64|x86_64) ;;
    *) _die "MAC_ARCH must be arm64 or x86_64 (got ${MAC_ARCH})" ;;
esac

APP_NAME="绣绘-${MAC_ARCH}.app"
FINAL_APP="${PREVIEW_ROOT}/build/${APP_NAME}"
[[ -d "${FINAL_APP}" ]] || _die "Final app not found at ${FINAL_APP}. Run 04-bundle.sh first."

VERSION="${VERSION:-xiuhui-$(git -C "${INTEG_REPO_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || date +%Y%m%d)-local}"
DMG_NAME="绣绘-${VERSION}-${MAC_ARCH}.dmg"
DMG_OUT="${RELEASE_DIR}/${DMG_NAME}"

mkdir -p "${RELEASE_DIR}"
rm -f "${DMG_OUT}"
# 清理 create-dmg 可能残留的中间文件（rw.<pid>.<name>），
# 避免并发或上次中断时 hdiutil convert 报"文件已存在"。
rm -f "${RELEASE_DIR}"/rw.*."${DMG_NAME}"

# Stage dir: contents of the mounted dmg.
STAGE="$(mktemp -d -t xiuhui-dmg)"
trap 'rm -rf "${STAGE}"' EXIT
_log "Staging dmg contents at ${STAGE}"

cp -a "${FINAL_APP}" "${STAGE}/"
cp -f "${SCRIPT_DIR}/assets/首次打开说明.txt" "${STAGE}/首次打开说明.txt"

# Background image (optional). Generated separately and checked into
# scripts/macos/assets/. If missing the dmg is plain.
BG_IMG="${SCRIPT_DIR}/assets/dmg-background-${MAC_ARCH}.png"

if command -v create-dmg >/dev/null 2>&1; then
    _log "Building styled dmg with create-dmg ..."
    EXTRA_BG=()
    if [[ -f "${BG_IMG}" ]]; then
        EXTRA_BG=(--background "${BG_IMG}")
    fi
    create-dmg \
        --volname "绣绘 ${VERSION}" \
        --window-pos 200 120 \
        --window-size 720 480 \
        --icon-size 110 \
        --icon "${APP_NAME}" 180 240 \
        --app-drop-link 540 240 \
        --icon "首次打开说明.txt" 360 380 \
        --hide-extension "${APP_NAME}" \
        ${EXTRA_BG[@]+"${EXTRA_BG[@]}"} \
        "${DMG_OUT}" \
        "${STAGE}/" || true

    # macOS 26: create-dmg 常因 AppleScript 美化窗口超时退出非 0，但 dmg
    # 已写出，只是名字带 rw.<pid>. 临时前缀。检测并重命名。
    if [ ! -f "${DMG_OUT}" ]; then
        RW=$(ls -t "$(dirname "${DMG_OUT}")"/rw.*."$(basename "${DMG_OUT}")" 2>/dev/null | head -1)
        if [ -n "${RW}" ] && [ -f "${RW}" ]; then
            _log "Detected create-dmg AppleScript timeout; renaming ${RW} -> ${DMG_OUT}"
            mv -f "${RW}" "${DMG_OUT}"
        fi
    fi
    [ -f "${DMG_OUT}" ] || _die "dmg 未生成: ${DMG_OUT}"
else
    _log "create-dmg not installed; falling back to plain hdiutil dmg."
    ln -s /Applications "${STAGE}/Applications"
    hdiutil create -volname "绣绘 ${VERSION}" \
                   -srcfolder "${STAGE}" \
                   -ov -format UDZO \
                   "${DMG_OUT}"
fi

_log "DMG written to: ${DMG_OUT}"
ls -lh "${DMG_OUT}"
shasum -a 256 "${DMG_OUT}"

# ---------- notarization (optional) ----------
# If NOTARIZE=1, submit the freshly-built dmg to Apple's notary service.
# Requires an App Store Connect API key or App-specific password — see
# docs/MACOS_SIGNING_SETUP.md. Signing must have been done with a
# Developer ID identity in 04-bundle.sh for notarization to succeed.
if [[ "${NOTARIZE:-0}" == "1" ]]; then
    _log "Notarization requested; delegating to 06-notarize.sh ..."
    bash "${SCRIPT_DIR}/06-notarize.sh" "${DMG_OUT}"
fi
