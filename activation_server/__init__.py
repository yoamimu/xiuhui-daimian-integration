import os
import secrets
from pathlib import Path

from flask import Flask, session

from . import db
from .routes_admin import bp as admin_bp
from .routes_api import bp as api_bp


def _env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.config.from_mapping(
        DATABASE_PATH=os.environ.get("DATABASE_PATH", "/data/activation.db"),
        SECRET_KEY=os.environ.get("FLASK_SECRET_KEY", ""),
        ADMIN_PASSWORD=os.environ.get("ADMIN_PASSWORD", ""),
        ADMIN_PASSWORD_HASH=os.environ.get("ADMIN_PASSWORD_HASH", ""),
        LICENSE_CODE_PEPPER=os.environ.get("LICENSE_CODE_PEPPER", ""),
        LICENSE_PRIVATE_KEY_PATH=os.environ.get(
            "LICENSE_PRIVATE_KEY_PATH", "/run/secrets/license_private_key.pem"
        ),
        LICENSE_PRIVATE_KEY_PEM=None,
        LICENSE_TIMEZONE=os.environ.get("LICENSE_TIMEZONE", "Asia/Shanghai"),
        OFFLINE_GRACE_HOURS=int(os.environ.get("OFFLINE_GRACE_HOURS", "72")),
        API_RATE_LIMIT=int(os.environ.get("API_RATE_LIMIT", "30")),
        API_RATE_WINDOW_SECONDS=int(os.environ.get("API_RATE_WINDOW_SECONDS", "600")),
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
        SESSION_COOKIE_SECURE=_env_bool("SESSION_COOKIE_SECURE", True),
        MAX_CONTENT_LENGTH=16 * 1024,
    )
    if test_config:
        app.config.update(test_config)

    if not app.config.get("TESTING"):
        required = {
            "FLASK_SECRET_KEY": app.config["SECRET_KEY"],
            "LICENSE_CODE_PEPPER": app.config["LICENSE_CODE_PEPPER"],
        }
        if not app.config["ADMIN_PASSWORD"] and not app.config["ADMIN_PASSWORD_HASH"]:
            required["ADMIN_PASSWORD or ADMIN_PASSWORD_HASH"] = ""
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError(f"Missing required activation-server settings: {', '.join(missing)}")

    database_path = Path(app.config["DATABASE_PATH"])
    database_path.parent.mkdir(parents=True, exist_ok=True)

    db.init_app(app)
    app.register_blueprint(api_bp)
    app.register_blueprint(admin_bp)

    @app.context_processor
    def inject_csrf_token():
        def csrf_token() -> str:
            token = session.get("csrf_token")
            if not token:
                token = secrets.token_urlsafe(32)
                session["csrf_token"] = token
            return token

        return {"csrf_token": csrf_token}

    @app.after_request
    def security_headers(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "same-origin")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self'; script-src 'self'; "
            "img-src 'self' data:; form-action 'self'; frame-ancestors 'none'",
        )
        if response.content_type and response.content_type.startswith("application/json"):
            response.headers["Cache-Control"] = "no-store"
        return response

    return app
