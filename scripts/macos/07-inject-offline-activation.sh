#!/usr/bin/env bash

set -euo pipefail

_log() { printf '[07-offline] %s\n' "$*"; }
_die() { printf '[07-offline] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_PATH="${1:-}"
MAC_ARCH="${2:-}"
VERSION="${VERSION:-0.2.0}"

[[ -d "${APP_PATH}" ]] || _die "usage: 07-inject-offline-activation.sh APP_PATH ARCH"
case "${MAC_ARCH}" in
    arm64|x86_64) ;;
    *) _die "ARCH must be arm64 or x86_64" ;;
esac

PLIST="${APP_PATH}/Contents/Info.plist"
LAUNCHER="${APP_PATH}/Contents/MacOS/inkscape"
CORE="${APP_PATH}/Contents/MacOS/inkscape-core"
[[ -f "${PLIST}" && -x "${LAUNCHER}" ]] || _die "invalid Xiuhui app bundle"

if [[ ! -x "${CORE}" ]]; then
    _log "preserving original Inkscape executable as inkscape-core"
    mv "${LAUNCHER}" "${CORE}"
else
    _log "existing inkscape-core found; replacing only the activation launcher"
    rm -f "${LAUNCHER}"
fi

CORE_ARCHS="$(lipo -archs "${CORE}")"
[[ " ${CORE_ARCHS} " == *" ${MAC_ARCH} "* ]] \
    || _die "core architecture mismatch: ${CORE_ARCHS}"

MAC_ARCH="${MAC_ARCH}" \
ACTIVATION_MODE=offline \
LICENSE_PUBLIC_KEY_FILE="${LICENSE_PUBLIC_KEY_FILE:-${ROOT}/activation-client/macos/license-public-key.b64}" \
    bash "${ROOT}/activation-client/macos/build-launcher.sh" "${LAUNCHER}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION}" "${PLIST}"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
ENTITLEMENTS="${ENTITLEMENTS:-${SCRIPT_DIR}/assets/entitlements.plist}"
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    SIGN_ARGS=(--force --options runtime --timestamp --sign "${SIGNING_IDENTITY}")
    [[ -n "${SIGNING_KEYCHAIN}" ]] && SIGN_ARGS+=(--keychain "${SIGNING_KEYCHAIN}")
    [[ -f "${ENTITLEMENTS}" ]] && SIGN_ARGS+=(--entitlements "${ENTITLEMENTS}")
    _log "Developer ID signing with ${SIGNING_IDENTITY}"
else
    SIGN_ARGS=(--force --sign - --timestamp=none)
    _log "ad-hoc signing for local validation"
fi

find "${APP_PATH}" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) -print0 \
    | xargs -0 -n 150 codesign "${SIGN_ARGS[@]}" --preserve-metadata=identifier,entitlements,flags || true
codesign --force --deep "${SIGN_ARGS[@]}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

_log "offline activation installed: ${APP_PATH} (${MAC_ARCH}, version ${VERSION})"
