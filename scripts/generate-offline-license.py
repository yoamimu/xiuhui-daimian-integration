#!/usr/bin/env python3
"""Generate a signed, device-bound offline license for Xiuhui."""

from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import uuid
from datetime import date, datetime, time, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


APP_ID = "com.yoamimu.xiuhui-daimian.inkscape"
LICENSE_VERSION = 2
LOCAL_TIMEZONE = ZoneInfo("Asia/Shanghai")
DEVICE_PATTERN = re.compile(r"^[a-f0-9]{64}$")


def add_years(day: date, years: int = 1) -> date:
    try:
        return day.replace(year=day.year + years)
    except ValueError:
        return day.replace(month=2, day=28, year=day.year + years)


def _base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _base64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def device_request_code(device_id: str) -> str:
    normalized = device_id.strip().lower()
    if not DEVICE_PATTERN.fullmatch(normalized):
        raise ValueError("设备码必须是 64 位十六进制字符串。")
    return "XHD-" + _base64url(bytes.fromhex(normalized))


def parse_device_code(raw_value: str) -> str:
    value = "".join((raw_value or "").split())
    if DEVICE_PATTERN.fullmatch(value.lower()):
        return value.lower()
    if value.upper().startswith("XHD-"):
        try:
            decoded = _base64url_decode(value[4:])
        except Exception as error:
            raise ValueError("设备码无法解码，请让客户重新复制。") from error
        if len(decoded) == 32:
            return decoded.hex()
    raise ValueError("设备码格式不正确，应以 XHD- 开头。")


def load_private_key(path: Path) -> ec.EllipticCurvePrivateKey:
    key = serialization.load_pem_private_key(path.read_bytes(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise ValueError("授权签名密钥必须是 ECDSA P-256 私钥。")
    return key


def create_offline_license(
    *,
    private_key: ec.EllipticCurvePrivateKey,
    device_code: str,
    starts_on: date,
    expires_on: date | None = None,
    customer_name: str = "",
    order_reference: str = "",
    issued_at: datetime | None = None,
) -> tuple[str, dict]:
    device_id = parse_device_code(device_code)
    expiry_day = expires_on or add_years(starts_on)
    if expiry_day <= starts_on:
        raise ValueError("到期日必须晚于付款日期。")

    issued = issued_at or datetime.now(timezone.utc)
    if issued.tzinfo is None:
        issued = issued.replace(tzinfo=timezone.utc)
    issued = issued.astimezone(timezone.utc)
    start_moment = datetime.combine(starts_on, time.min, tzinfo=LOCAL_TIMEZONE)
    expiry_moment = datetime.combine(expiry_day, time.min, tzinfo=LOCAL_TIMEZONE)
    if expiry_moment.astimezone(timezone.utc) <= issued:
        raise ValueError("该授权已经到期，无法生成。")

    payload = {
        "app_id": APP_ID,
        "customer": customer_name.strip()[:120],
        "device_id": device_id,
        "expires_at": int(expiry_moment.timestamp()),
        "expires_on": expiry_day.isoformat(),
        "issued_at": int(issued.timestamp()),
        "lease_until": int(expiry_moment.timestamp()),
        "license_id": str(uuid.uuid4()),
        "offline": True,
        "order_reference": order_reference.strip()[:120],
        "starts_at": int(start_moment.timestamp()),
        "starts_on": starts_on.isoformat(),
        "version": LICENSE_VERSION,
    }
    payload_bytes = json.dumps(
        payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    signature = private_key.sign(payload_bytes, ec.ECDSA(hashes.SHA256()))
    token = f"{_base64url(payload_bytes)}.{_base64url(signature)}"
    return token, payload


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="为指定 Mac 生成一年期绣绘离线授权码。"
    )
    parser.add_argument("--device-code", required=True, help="客户提供的 XHD- 设备码")
    parser.add_argument(
        "--starts-on",
        default=datetime.now(LOCAL_TIMEZONE).date().isoformat(),
        help="付款日期，格式 YYYY-MM-DD，默认今天",
    )
    parser.add_argument("--expires-on", help="可选的自定义到期日，格式 YYYY-MM-DD")
    parser.add_argument("--customer", default="", help="客户姓名或备注")
    parser.add_argument("--order-reference", default="", help="订单号")
    parser.add_argument(
        "--private-key",
        type=Path,
        required=True,
        help="授权签名私钥路径",
    )
    parser.add_argument("--output", type=Path, help="把授权码写入文件")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出签发结果")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        starts_on = date.fromisoformat(args.starts_on)
        expires_on = date.fromisoformat(args.expires_on) if args.expires_on else None
        private_key = load_private_key(args.private_key)
        token, payload = create_offline_license(
            private_key=private_key,
            device_code=args.device_code,
            starts_on=starts_on,
            expires_on=expires_on,
            customer_name=args.customer,
            order_reference=args.order_reference,
        )
    except (OSError, ValueError) as error:
        print(f"生成失败：{error}", file=sys.stderr)
        return 2

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(token + "\n", encoding="utf-8")
        args.output.chmod(0o600)

    result = {
        "customer": payload["customer"],
        "device_code": device_request_code(payload["device_id"]),
        "expires_on": payload["expires_on"],
        "license_code": token,
        "license_id": payload["license_id"],
        "order_reference": payload["order_reference"],
        "starts_on": payload["starts_on"],
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(token)
        print(
            f"已生成：{payload['starts_on']} 至 {payload['expires_on']}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
