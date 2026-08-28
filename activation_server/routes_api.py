import time

from flask import Blueprint, current_app, jsonify, request

from .db import get_db
from .licensing import LicenseError, process_activation


bp = Blueprint("api", __name__, url_prefix="/api/v1")


def _remote_ip() -> str:
    real_ip = request.headers.get("X-Real-IP", "").strip()
    return (real_ip or request.remote_addr or "unknown")[:64]


def _check_rate_limit() -> bool:
    connection = get_db()
    now = int(time.time())
    window = current_app.config["API_RATE_WINDOW_SECONDS"]
    cutoff = now - window
    connection.execute("DELETE FROM api_attempts WHERE occurred_at < ?", (now - 86400,))
    attempts = connection.execute(
        "SELECT COUNT(*) FROM api_attempts WHERE remote_ip = ? AND occurred_at >= ?",
        (_remote_ip(), cutoff),
    ).fetchone()[0]
    return attempts < current_app.config["API_RATE_LIMIT"]


def _record_attempt(succeeded: bool) -> None:
    get_db().execute(
        "INSERT INTO api_attempts (remote_ip, occurred_at, succeeded) VALUES (?, ?, ?)",
        (_remote_ip(), int(time.time()), 1 if succeeded else 0),
    )


def _handle(mode: str):
    if not request.is_json:
        return jsonify(ok=False, error="invalid_request", message="请求必须使用 JSON。"), 415
    if not _check_rate_limit():
        response = jsonify(ok=False, error="rate_limited", message="尝试次数过多，请稍后再试。")
        response.status_code = 429
        response.headers["Retry-After"] = str(current_app.config["API_RATE_WINDOW_SECONDS"])
        return response

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        _record_attempt(False)
        return jsonify(ok=False, error="invalid_request", message="请求内容不正确。"), 400
    try:
        result = process_activation(data, mode)
    except LicenseError as error:
        _record_attempt(False)
        return jsonify(ok=False, error=error.code, message=error.message), error.http_status
    _record_attempt(True)
    return jsonify(result)


@bp.post("/activate")
def activate():
    return _handle("activate")


@bp.post("/validate")
def validate():
    return _handle("validate")


@bp.get("/health")
def health():
    return jsonify(ok=True, service="xiuhui-activation")
