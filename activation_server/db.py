import sqlite3
from contextlib import contextmanager

from flask import current_app, g


SCHEMA = """
CREATE TABLE IF NOT EXISTS licenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    public_id TEXT NOT NULL UNIQUE,
    code_digest TEXT NOT NULL UNIQUE,
    code_hint TEXT NOT NULL,
    customer_name TEXT NOT NULL DEFAULT '',
    order_reference TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    starts_on TEXT NOT NULL,
    expires_on TEXT NOT NULL,
    max_devices INTEGER NOT NULL DEFAULT 1 CHECK (max_devices BETWEEN 1 AND 10),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS activations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    license_id INTEGER NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    device_label TEXT NOT NULL DEFAULT '',
    app_version TEXT NOT NULL DEFAULT '',
    macos_version TEXT NOT NULL DEFAULT '',
    architecture TEXT NOT NULL DEFAULT '',
    bound_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    unbound_at TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_activations_active_device
    ON activations(license_id, device_id)
    WHERE unbound_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_activations_license
    ON activations(license_id, unbound_at);

CREATE TABLE IF NOT EXISTS admin_audit (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    license_id INTEGER REFERENCES licenses(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details TEXT NOT NULL DEFAULT '',
    remote_ip TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS api_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    remote_ip TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    succeeded INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_api_attempts_ip_time
    ON api_attempts(remote_ip, occurred_at);

PRAGMA user_version = 1;
"""


def get_db() -> sqlite3.Connection:
    if "db" not in g:
        connection = sqlite3.connect(
            current_app.config["DATABASE_PATH"], timeout=15, isolation_level=None
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = NORMAL")
        connection.execute("PRAGMA busy_timeout = 15000")
        g.db = connection
    return g.db


def close_db(_error=None) -> None:
    connection = g.pop("db", None)
    if connection is not None:
        connection.close()


def initialize_database() -> None:
    connection = get_db()
    connection.executescript(SCHEMA)


@contextmanager
def immediate_transaction():
    connection = get_db()
    connection.execute("BEGIN IMMEDIATE")
    try:
        yield connection
    except Exception:
        connection.rollback()
        raise
    else:
        connection.commit()


def init_app(app) -> None:
    app.teardown_appcontext(close_db)
    with app.app_context():
        initialize_database()
