#!/usr/bin/env bash

set -euo pipefail

_log() { printf '[activation-client] %s\n' "$*"; }
_die() { printf '[activation-client] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/XHActivationLauncher.m"
MAC_ARCH="${MAC_ARCH:-arm64}"
OUTPUT="${1:-}"
ACTIVATION_SERVER_URL="${ACTIVATION_SERVER_URL:-}"
PUBLIC_KEY_FILE="${LICENSE_PUBLIC_KEY_FILE:-${SCRIPT_DIR}/license-public-key.b64}"

[[ -n "${OUTPUT}" ]] || _die "usage: build-launcher.sh OUTPUT_PATH"
case "${MAC_ARCH}" in
    arm64|x86_64) ;;
    *) _die "MAC_ARCH must be arm64 or x86_64" ;;
esac
[[ -f "${SOURCE}" ]] || _die "missing launcher source: ${SOURCE}"
[[ -n "${ACTIVATION_SERVER_URL}" ]] || _die "ACTIVATION_SERVER_URL is required"
[[ "${ACTIVATION_SERVER_URL}" == https://* ]] \
    || [[ "${ALLOW_INSECURE_LOCAL_ACTIVATION:-0}" == "1" && "${ACTIVATION_SERVER_URL}" == http://127.0.0.1:* ]] \
    || _die "ACTIVATION_SERVER_URL must use HTTPS"
[[ -f "${PUBLIC_KEY_FILE}" ]] || _die "missing license public key: ${PUBLIC_KEY_FILE}"

PUBLIC_KEY_B64="$(tr -d '\r\n[:space:]' < "${PUBLIC_KEY_FILE}")"
[[ "${#PUBLIC_KEY_B64}" -ge 80 ]] || _die "license public key is invalid"

DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-}"
if [[ -z "${DEPLOYMENT_TARGET}" ]]; then
    [[ "${MAC_ARCH}" == "arm64" ]] && DEPLOYMENT_TARGET="14.0" || DEPLOYMENT_TARGET="15.0"
fi

mkdir -p "$(dirname "${OUTPUT}")"
DEFINES=(
    "-DXH_ACTIVATION_SERVER_URL=@\"${ACTIVATION_SERVER_URL}\""
    "-DXH_LICENSE_PUBLIC_KEY_B64=@\"${PUBLIC_KEY_B64}\""
)
if [[ "${ALLOW_INSECURE_LOCAL_ACTIVATION:-0}" == "1" ]]; then
    DEFINES+=("-DXH_ALLOW_INSECURE_HTTP=1")
fi
if [[ "${ACTIVATION_CLIENT_TEST_BUILD:-0}" == "1" ]]; then
    DEFINES+=("-DXH_TEST_BUILD=1")
fi

_log "building ${MAC_ARCH} launcher for ${ACTIVATION_SERVER_URL}"
xcrun --sdk macosx clang \
    -arch "${MAC_ARCH}" \
    -mmacosx-version-min="${DEPLOYMENT_TARGET}" \
    -fobjc-arc \
    -fblocks \
    -Os \
    -Wall -Wextra -Werror \
    "${DEFINES[@]}" \
    -framework Cocoa \
    -framework Security \
    -framework IOKit \
    "${SOURCE}" \
    -o "${OUTPUT}"

ACTUAL_ARCHS="$(lipo -archs "${OUTPUT}")"
[[ " ${ACTUAL_ARCHS} " == *" ${MAC_ARCH} "* ]] \
    || _die "launcher architecture mismatch: ${ACTUAL_ARCHS}"
chmod 755 "${OUTPUT}"
_log "launcher ready: ${OUTPUT} (${ACTUAL_ARCHS})"
