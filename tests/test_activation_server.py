import base64
import json
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from activation_server import create_app
from activation_server.db import get_db
from activation_server.licensing import add_years, create_license


class ActivationServerTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.private_key = ec.generate_private_key(ec.SECP256R1())
        private_pem = self.private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        self.app = create_app(
            {
                "TESTING": True,
                "DATABASE_PATH": str(Path(self.temp_dir.name) / "activation.db"),
                "SECRET_KEY": "test-session-secret",
                "ADMIN_PASSWORD": "test-admin-password",
                "LICENSE_CODE_PEPPER": "test-code-pepper",
                "LICENSE_PRIVATE_KEY_PEM": private_pem,
                "SESSION_COOKIE_SECURE": False,
                "API_RATE_LIMIT": 1000,
            }
        )
        self.client = self.app.test_client()

    def tearDown(self):
        self.temp_dir.cleanup()

    def create_year_license(self):
        today = date.today()
        with self.app.app_context():
            return create_license(
                "测试客户", "ORDER-001", "", today, add_years(today), 1
            )

    @staticmethod
    def request_body(code: str, device: str):
        return {
            "activation_code": code,
            "device_id": device,
            "device_label": "MacBook Pro",
            "app_version": "v0.2.0",
            "macos_version": "macOS 15.6",
            "architecture": "arm64",
        }

    def verify_token(self, token: str, expected_device: str):
        encoded_payload, encoded_signature = token.split(".", 1)

        def decode(value: str) -> bytes:
            return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))

        payload_bytes = decode(encoded_payload)
        signature = decode(encoded_signature)
        self.private_key.public_key().verify(
            signature, payload_bytes, ec.ECDSA(hashes.SHA256())
        )
        payload = json.loads(payload_bytes)
        self.assertEqual(payload["device_id"], expected_device)
        self.assertEqual(payload["app_id"], "com.yoamimu.xiuhui-daimian.inkscape")
        self.assertGreater(payload["lease_until"], payload["issued_at"])
        return payload

    def test_one_device_binding_unbind_and_rebind(self):
        public_id, code = self.create_year_license()
        device_a = "a" * 64
        device_b = "b" * 64

        first = self.client.post(
            "/api/v1/activate", json=self.request_body(code, device_a)
        )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.json["activation"], "new")
        self.verify_token(first.json["license_token"], device_a)

        validation = self.client.post(
            "/api/v1/validate", json=self.request_body(code, device_a)
        )
        self.assertEqual(validation.status_code, 200)
        self.assertEqual(validation.json["activation"], "existing")

        rejected = self.client.post(
            "/api/v1/activate", json=self.request_body(code, device_b)
        )
        self.assertEqual(rejected.status_code, 409)
        self.assertEqual(rejected.json["error"], "device_limit")

        with self.app.app_context():
            activation_id = get_db().execute(
                "SELECT id FROM activations WHERE device_id = ? AND unbound_at IS NULL",
                (device_a,),
            ).fetchone()[0]
        with self.client.session_transaction() as session:
            session["admin_authenticated"] = True
            session["csrf_token"] = "test-csrf"
        unbind = self.client.post(
            f"/admin/licenses/{public_id}/unbind/{activation_id}",
            data={"csrf_token": "test-csrf"},
        )
        self.assertEqual(unbind.status_code, 302)

        old_reactivation = self.client.post(
            "/api/v1/activate", json=self.request_body(code, device_a)
        )
        self.assertEqual(old_reactivation.status_code, 409)
        self.assertEqual(old_reactivation.json["error"], "device_unbound")

        replacement = self.client.post(
            "/api/v1/activate", json=self.request_body(code, device_b)
        )
        self.assertEqual(replacement.status_code, 200)
        self.assertEqual(replacement.json["activation"], "new")

        old_device = self.client.post(
            "/api/v1/validate", json=self.request_body(code, device_a)
        )
        self.assertEqual(old_device.status_code, 409)
        self.assertEqual(old_device.json["error"], "device_unbound")

    def test_expired_license_is_rejected(self):
        with self.app.app_context():
            _public_id, code = create_license(
                "过期客户",
                "ORDER-OLD",
                "",
                date.today() - timedelta(days=400),
                date.today(),
                1,
            )
        response = self.client.post(
            "/api/v1/activate", json=self.request_body(code, "c" * 64)
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json["error"], "expired")

    def test_admin_creates_one_year_license_from_payment_date(self):
        with self.client.session_transaction() as session:
            session["admin_authenticated"] = True
            session["csrf_token"] = "test-csrf"
        response = self.client.post(
            "/admin/licenses/new",
            data={
                "csrf_token": "test-csrf",
                "customer_name": "付款客户",
                "order_reference": "ORDER-2026-08-20",
                "starts_on": "2026-08-20",
                "expires_on": "2027-08-20",
                "max_devices": "1",
                "notes": "微信付款",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"XH-", response.data)
        with self.app.app_context():
            row = get_db().execute(
                "SELECT * FROM licenses WHERE order_reference = ?",
                ("ORDER-2026-08-20",),
            ).fetchone()
            self.assertEqual(row["starts_on"], "2026-08-20")
            self.assertEqual(row["expires_on"], "2027-08-20")
            self.assertEqual(row["max_devices"], 1)
            self.assertNotIn("XH-", row["code_digest"])

        listing = self.client.get("/admin/licenses")
        self.assertEqual(listing.status_code, 200)
        self.assertIn("0/1", listing.get_data(as_text=True))

    def test_invalid_code_format_is_rejected(self):
        response = self.client.post(
            "/api/v1/activate",
            json=self.request_body("XH-INVALID", "d" * 64),
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json["error"], "invalid_code")

    def test_leap_day_year_calculation(self):
        self.assertEqual(add_years(date(2028, 2, 29)), date(2029, 2, 28))


if __name__ == "__main__":
    unittest.main()
