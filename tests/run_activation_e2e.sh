#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-${ROOT}/.venv/bin/python}"
GUNICORN_BIN="${GUNICORN_BIN:-${ROOT}/.venv/bin/gunicorn}"
PORT="${ACTIVATION_TEST_PORT:-18787}"
WORK="$(mktemp -d -t xiuhui-activation-e2e)"
SERVER_PID=""

cleanup() {
    if [[ -n "${SERVER_PID}" ]]; then
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
    rm -rf "${WORK}"
}
trap cleanup EXIT

[[ -x "${PYTHON_BIN}" ]] || { echo "missing Python: ${PYTHON_BIN}" >&2; exit 1; }
[[ -x "${GUNICORN_BIN}" ]] || { echo "missing Gunicorn: ${GUNICORN_BIN}" >&2; exit 1; }

"${PYTHON_BIN}" "${ROOT}/scripts/generate-activation-key.py" \
    --private-out "${WORK}/private.pem" \
    --public-out "${WORK}/public.b64"

export DATABASE_PATH="${WORK}/activation.db"
export FLASK_SECRET_KEY="e2e-session-secret"
export ADMIN_PASSWORD="e2e-admin-password"
export LICENSE_CODE_PEPPER="e2e-code-pepper"
export LICENSE_PRIVATE_KEY_PATH="${WORK}/private.pem"
export SESSION_COOKIE_SECURE="false"

cd "${ROOT}"
"${GUNICORN_BIN}" --workers 1 --bind "127.0.0.1:${PORT}" activation_server.wsgi:app \
    >"${WORK}/server.log" 2>&1 &
SERVER_PID=$!

for _attempt in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done
curl -fsS "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null

CODE="$("${PYTHON_BIN}" -c '
from datetime import date
from activation_server import create_app
from activation_server.licensing import add_years, create_license
app = create_app()
with app.app_context():
    print(create_license("E2E customer", "E2E-001", "", date.today(), add_years(date.today()), 1)[1])
')"

build_client() {
    local arch="$1"
    MAC_ARCH="${arch}" \
    ACTIVATION_SERVER_URL="http://127.0.0.1:${PORT}" \
    ALLOW_INSECURE_LOCAL_ACTIVATION=1 \
    ACTIVATION_CLIENT_TEST_BUILD=1 \
    LICENSE_PUBLIC_KEY_FILE="${WORK}/public.b64" \
        bash "${ROOT}/activation-client/macos/build-launcher.sh" "${WORK}/client-${arch}"
}

run_client() {
    local arch="$1"
    local device="$2"
    local endpoint="$3"
    XH_TEST_DEVICE_ID="${device}" "${WORK}/client-${arch}" \
        --xh-test-request "${endpoint}" "${CODE}"
}

HOST_ARCH="$(uname -m)"
if [[ "${HOST_ARCH}" == "arm64" ]]; then
    FIRST_ARCH="arm64"
    SECOND_ARCH="x86_64"
    build_client arm64
    build_client x86_64
else
    FIRST_ARCH="x86_64"
    SECOND_ARCH="x86_64"
    build_client x86_64
fi

DEVICE_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
DEVICE_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

run_client "${FIRST_ARCH}" "${DEVICE_A}" activate

set +e
REJECTION="$(run_client "${SECOND_ARCH}" "${DEVICE_B}" activate 2>&1)"
REJECTION_STATUS=$?
set -e
[[ ${REJECTION_STATUS} -eq 11 ]] || { echo "expected device-limit rejection, got ${REJECTION_STATUS}" >&2; exit 1; }
grep -F "已绑定其他 Mac" <<<"${REJECTION}" >/dev/null

"${PYTHON_BIN}" -c '
from activation_server import create_app
from activation_server.db import get_db
from activation_server.licensing import iso_utc
app = create_app()
with app.app_context():
    get_db().execute(
        "UPDATE activations SET unbound_at = ? WHERE device_id = ? AND unbound_at IS NULL",
        (iso_utc(), "a" * 64),
    )
'

set +e
OLD_DEVICE_REJECTION="$(run_client "${FIRST_ARCH}" "${DEVICE_A}" activate 2>&1)"
OLD_DEVICE_STATUS=$?
set -e
[[ ${OLD_DEVICE_STATUS} -eq 11 ]] || { echo "expected old-device rejection, got ${OLD_DEVICE_STATUS}" >&2; exit 1; }
grep -F "已被管理员解绑" <<<"${OLD_DEVICE_REJECTION}" >/dev/null

run_client "${SECOND_ARCH}" "${DEVICE_B}" activate
run_client "${SECOND_ARCH}" "${DEVICE_B}" validate

echo "activation E2E passed: ${FIRST_ARCH} -> ${SECOND_ARCH}"
