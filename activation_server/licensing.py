import base64
import hashlib
import hmac
import json
import re
import secrets
import string
import time
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from flask import current_app

from .db import immediate_transaction


APP_ID = "com.yoamimu.xiuhui-daimian.inkscape"
CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
CODE_PATTERN = re.compile(r"^XH(?:-[%s]{4}){3}$" % CODE_ALPHABET)
DEVICE_PATTERN = re.compile(r"^[a-f0-9]{64}$")


@dataclass
class LicenseError(Exception):
    code: str
    message: str
    http_status: int = 403

    def __str__(self) -> str:
        return self.message


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_utc(moment: datetime | None = None) -> str:
    value = moment or utc_now()
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def add_years(day: date, years: int = 1) -> date:
    try:
        return day.replace(year=day.year + years)
    except ValueError:
        return day.replace(month=2, day=28, year=day.year + years)


def normalize_code(raw_code: str) -> str:
    compact = re.sub(r"[^A-Za-z0-9]", "", raw_code or "").upper()
    if compact.startswith("XH") and len(compact) == 14:
        compact = f"XH-{compact[2:6]}-{compact[6:10]}-{compact[10:14]}"
    if not CODE_PATTERN.fullmatch(compact):
        raise LicenseError("invalid_code", "激活码格式不正确。", 400)
    return compact


def generate_code() -> str:
    groups = ["".join(secrets.choice(CODE_ALPHABET) for _ in range(4)) for _ in range(3)]
    return "XH-" + "-".join(groups)


def code_digest(code: str) -> str:
    pepper = current_app.config["LICENSE_CODE_PEPPER"].encode("utf-8")
    return hmac.new(pepper, code.encode("ascii"), hashlib.sha256).hexdigest()


def code_hint(code: str) -> str:
    return f"XH-****-****-{code[-4:]}"


def validate_device_id(device_id: str) -> str:
    normalized = (device_id or "").strip().lower()
    if not DEVICE_PATTERN.fullmatch(normalized):
        raise LicenseError("invalid_device", "设备密钥格式不正确。", 400)
    return normalized


def create_license(
    customer_name: str,
    order_reference: str,
    notes: str,
    starts_on: date,
    expires_on: date,
    max_devices: int,
) -> tuple[str, str]:
    if expires_on <= starts_on:
        raise ValueError("到期日必须晚于开始日期。")
    if not 1 <= max_devices <= 10:
        raise ValueError("设备数量必须在 1 到 10 之间。")

    now = iso_utc()
    public_id = str(uuid.uuid4())
    with immediate_transaction() as connection:
        for _attempt in range(10):
            code = generate_code()
            try:
                connection.execute(
                    """
                    INSERT INTO licenses (
                        public_id, code_digest, code_hint, customer_name,
                        order_reference, notes, starts_on, expires_on,
                        max_devices, status, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
                    """,
                    (
                        public_id,
                        code_digest(code),
                        code_hint(code),
                        customer_name[:120],
                        order_reference[:120],
                        notes[:1000],
                        starts_on.isoformat(),
                        expires_on.isoformat(),
                        max_devices,
                        now,
                        now,
                    ),
                )
                return public_id, code
            except Exception as error:
                if "UNIQUE constraint failed: licenses.code_digest" not in str(error):
                    raise
        raise RuntimeError("Unable to generate a unique activation code")


def _private_key():
    cached = current_app.extensions.get("license_private_key")
    if cached is not None:
        return cached

    pem = current_app.config.get("LICENSE_PRIVATE_KEY_PEM")
    if pem is None:
        pem = Path(current_app.config["LICENSE_PRIVATE_KEY_PATH"]).read_bytes()
    elif isinstance(pem, str):
        pem = pem.encode("utf-8")
    key = serialization.load_pem_private_key(pem, password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise RuntimeError("License signing key must be an ECDSA P-256 private key")
    current_app.extensions["license_private_key"] = key
    return key


def _base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _signed_token(payload: dict) -> str:
    payload_bytes = json.dumps(
        payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    signature = _private_key().sign(payload_bytes, ec.ECDSA(hashes.SHA256()))
    return f"{_base64url(payload_bytes)}.{_base64url(signature)}"


def _field(value, limit: int) -> str:
    return str(value or "").strip()[:limit]


def process_activation(request_data: dict, mode: str) -> dict:
    if mode not in {"activate", "validate"}:
        raise ValueError("invalid activation mode")

    code = normalize_code(request_data.get("activation_code", ""))
    device_id = validate_device_id(request_data.get("device_id", ""))
    device_label = _field(request_data.get("device_label"), 120)
    app_version = _field(request_data.get("app_version"), 80)
    macos_version = _field(request_data.get("macos_version"), 40)
    architecture = _field(request_data.get("architecture"), 20)
    now = utc_now()
    now_iso = iso_utc(now)
    local_zone = ZoneInfo(current_app.config["LICENSE_TIMEZONE"])
    today = now.astimezone(local_zone).date()

    with immediate_transaction() as connection:
        license_row = connection.execute(
            "SELECT * FROM licenses WHERE code_digest = ?", (code_digest(code),)
        ).fetchone()
        if license_row is None:
            raise LicenseError("invalid_code", "激活码无效。")
        if license_row["status"] != "active":
            raise LicenseError("revoked", "该授权已被停用，请联系销售方。")

        starts_on = date.fromisoformat(license_row["starts_on"])
        expires_on = date.fromisoformat(license_row["expires_on"])
        if today < starts_on:
            raise LicenseError("not_started", f"该授权将于 {starts_on.isoformat()} 生效。")
        if today >= expires_on:
            raise LicenseError("expired", f"该授权已于 {expires_on.isoformat()} 到期。")

        activation = connection.execute(
            """
            SELECT * FROM activations
            WHERE license_id = ? AND device_id = ? AND unbound_at IS NULL
            """,
            (license_row["id"], device_id),
        ).fetchone()

        newly_bound = False
        if activation is None:
            if mode == "validate":
                raise LicenseError("device_unbound", "这台 Mac 尚未激活，或已被管理员解绑。", 409)
            previously_unbound = connection.execute(
                """
                SELECT 1 FROM activations
                WHERE license_id = ? AND device_id = ? AND unbound_at IS NOT NULL
                LIMIT 1
                """,
                (license_row["id"], device_id),
            ).fetchone()
            if previously_unbound is not None:
                raise LicenseError(
                    "device_unbound",
                    "这台 Mac 已被管理员解绑，不能再次占用该激活码。",
                    409,
                )
            active_count = connection.execute(
                """
                SELECT COUNT(*) FROM activations
                WHERE license_id = ? AND unbound_at IS NULL
                """,
                (license_row["id"],),
            ).fetchone()[0]
            if active_count >= license_row["max_devices"]:
                raise LicenseError(
                    "device_limit",
                    "该激活码已绑定其他 Mac。如需换机，请先联系销售方解绑旧设备。",
                    409,
                )
            cursor = connection.execute(
                """
                INSERT INTO activations (
                    license_id, device_id, device_label, app_version,
                    macos_version, architecture, bound_at, last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    license_row["id"],
                    device_id,
                    device_label,
                    app_version,
                    macos_version,
                    architecture,
                    now_iso,
                    now_iso,
                ),
            )
            activation_id = cursor.lastrowid
            newly_bound = True
        else:
            activation_id = activation["id"]
            connection.execute(
                """
                UPDATE activations
                SET device_label = ?, app_version = ?, macos_version = ?,
                    architecture = ?, last_seen_at = ?
                WHERE id = ?
                """,
                (
                    device_label,
                    app_version,
                    macos_version,
                    architecture,
                    now_iso,
                    activation_id,
                ),
            )

    expiry_local = datetime.combine(expires_on, datetime.min.time(), tzinfo=local_zone)
    expiry_utc = expiry_local.astimezone(timezone.utc)
    grace_until = min(
        expiry_utc,
        now + timedelta(hours=current_app.config["OFFLINE_GRACE_HOURS"]),
    )
    payload = {
        "app_id": APP_ID,
        "device_id": device_id,
        "expires_at": int(expiry_utc.timestamp()),
        "issued_at": int(now.timestamp()),
        "lease_until": int(grace_until.timestamp()),
        "license_id": license_row["public_id"],
        "starts_on": starts_on.isoformat(),
        "version": 1,
    }
    return {
        "ok": True,
        "activation": "new" if newly_bound else "existing",
        "expires_on": expires_on.isoformat(),
        "lease_until": iso_utc(grace_until),
        "server_time": now_iso,
        "license_token": _signed_token(payload),
    }
