import base64
import importlib.util
import json
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec


SCRIPT_PATH = Path(__file__).parents[1] / "scripts" / "generate-offline-license.py"
SPEC = importlib.util.spec_from_file_location("generate_offline_license", SCRIPT_PATH)
offline = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(offline)


def base64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


class OfflineLicenseTest(unittest.TestCase):
    def setUp(self):
        self.private_key = ec.generate_private_key(ec.SECP256R1())
        self.device_id = "ab" * 32
        self.device_code = offline.device_request_code(self.device_id)

    def test_device_request_code_round_trip(self):
        self.assertTrue(self.device_code.startswith("XHD-"))
        self.assertEqual(offline.parse_device_code(self.device_code), self.device_id)
        self.assertEqual(offline.parse_device_code(self.device_id.upper()), self.device_id)

    def test_signed_license_contains_one_year_device_binding(self):
        issued_at = datetime(2026, 8, 28, 5, 0, tzinfo=timezone.utc)
        token, payload = offline.create_offline_license(
            private_key=self.private_key,
            device_code=self.device_code,
            starts_on=date(2026, 8, 28),
            customer_name="测试客户",
            order_reference="ORDER-001",
            issued_at=issued_at,
        )

        payload_part, signature_part = token.split(".")
        payload_bytes = base64url_decode(payload_part)
        signature = base64url_decode(signature_part)
        self.private_key.public_key().verify(
            signature, payload_bytes, ec.ECDSA(hashes.SHA256())
        )
        decoded = json.loads(payload_bytes)
        self.assertEqual(decoded, payload)
        self.assertEqual(payload["device_id"], self.device_id)
        self.assertEqual(payload["starts_on"], "2026-08-28")
        self.assertEqual(payload["expires_on"], "2027-08-28")
        self.assertTrue(payload["offline"])
        self.assertEqual(payload["version"], 2)

    def test_leap_day_expires_on_february_28(self):
        token, payload = offline.create_offline_license(
            private_key=self.private_key,
            device_code=self.device_code,
            starts_on=date(2024, 2, 29),
            issued_at=datetime(2024, 2, 29, tzinfo=timezone.utc),
        )
        self.assertTrue(token)
        self.assertEqual(payload["expires_on"], "2025-02-28")

    def test_invalid_device_code_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "设备码格式不正确"):
            offline.parse_device_code("XHD-not-a-device")


if __name__ == "__main__":
    unittest.main()
