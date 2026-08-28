#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-${ROOT}/.venv/bin/python}"
WORK="$(mktemp -d -t xiuhui-offline-activation-e2e)"
trap 'rm -rf "${WORK}"' EXIT

if [[ "${PYTHON_BIN}" != */* ]]; then
    PYTHON_BIN="$(command -v "${PYTHON_BIN}" || true)"
fi
[[ -x "${PYTHON_BIN}" ]] || { echo "missing Python: ${PYTHON_BIN}" >&2; exit 1; }

"${PYTHON_BIN}" "${ROOT}/scripts/generate-activation-key.py" \
    --private-out "${WORK}/private.pem" \
    --public-out "${WORK}/public.b64"

DEVICE_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
DEVICE_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
STARTS_ON="$(TZ=Asia/Shanghai date +%F)"

TOKEN="$("${PYTHON_BIN}" "${ROOT}/scripts/generate-offline-license.py" \
    --private-key "${WORK}/private.pem" \
    --device-code "${DEVICE_A}" \
    --starts-on "${STARTS_ON}" \
    --customer "离线测试客户" \
    --order-reference "OFFLINE-E2E-001")"

build_client() {
    local arch="$1"
    MAC_ARCH="${arch}" \
    ACTIVATION_MODE=offline \
    ACTIVATION_CLIENT_TEST_BUILD=1 \
    LICENSE_PUBLIC_KEY_FILE="${WORK}/public.b64" \
        bash "${ROOT}/activation-client/macos/build-launcher.sh" "${WORK}/client-${arch}"
}

run_client() {
    local arch="$1"
    local device="$2"
    local token="$3"
    XH_TEST_DEVICE_ID="${device}" "${WORK}/client-${arch}" \
        --xh-test-offline-token "${token}"
}

HOST_ARCH="$(uname -m)"
if [[ "${HOST_ARCH}" == "arm64" ]]; then
    build_client arm64
    build_client x86_64
    run_client arm64 "${DEVICE_A}" "${TOKEN}"
    run_client x86_64 "${DEVICE_A}" "${TOKEN}"
    TEST_ARCH="arm64"
else
    build_client x86_64
    run_client x86_64 "${DEVICE_A}" "${TOKEN}"
    TEST_ARCH="x86_64"
fi

set +e
WRONG_DEVICE_OUTPUT="$(run_client "${TEST_ARCH}" "${DEVICE_B}" "${TOKEN}" 2>&1)"
WRONG_DEVICE_STATUS=$?
set -e
[[ ${WRONG_DEVICE_STATUS} -eq 11 ]] \
    || { echo "expected wrong-device rejection, got ${WRONG_DEVICE_STATUS}" >&2; exit 1; }
grep -F "offline license rejected" <<<"${WRONG_DEVICE_OUTPUT}" >/dev/null

TAMPERED_TOKEN="${TOKEN%?}A"
set +e
TAMPER_OUTPUT="$(run_client "${TEST_ARCH}" "${DEVICE_A}" "${TAMPERED_TOKEN}" 2>&1)"
TAMPER_STATUS=$?
set -e
[[ ${TAMPER_STATUS} -eq 11 ]] \
    || { echo "expected tampered-license rejection, got ${TAMPER_STATUS}" >&2; exit 1; }
grep -F "offline license rejected" <<<"${TAMPER_OUTPUT}" >/dev/null

echo "offline activation E2E passed on ${HOST_ARCH}: valid, wrong-device, and tamper checks"
