import hmac
import json
import secrets
from datetime import date
from functools import wraps
from zoneinfo import ZoneInfo

from flask import (
    Blueprint,
    abort,
    current_app,
    flash,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from werkzeug.security import check_password_hash

from .db import get_db, immediate_transaction
from .licensing import add_years, create_license, iso_utc, utc_now


bp = Blueprint("admin", __name__, url_prefix="/admin")


def _remote_ip() -> str:
    real_ip = request.headers.get("X-Real-IP", "").strip()
    return (real_ip or request.remote_addr or "unknown")[:64]


def _password_matches(candidate: str) -> bool:
    password_hash = current_app.config.get("ADMIN_PASSWORD_HASH", "")
    if password_hash:
        return check_password_hash(password_hash, candidate)
    return hmac.compare_digest(current_app.config.get("ADMIN_PASSWORD", ""), candidate)


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("admin_authenticated"):
            return redirect(url_for("admin.login", next=request.path))
        return view(*args, **kwargs)

    return wrapped


def csrf_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        expected = session.get("csrf_token", "")
        supplied = request.form.get("csrf_token", "")
        if not expected or not hmac.compare_digest(expected, supplied):
            abort(400, "CSRF validation failed")
        return view(*args, **kwargs)

    return wrapped


def _audit(connection, action: str, license_id: int | None, details: dict | None = None):
    connection.execute(
        """
        INSERT INTO admin_audit (license_id, action, details, remote_ip, created_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            license_id,
            action,
            json.dumps(details or {}, ensure_ascii=False, sort_keys=True),
            _remote_ip(),
            iso_utc(),
        ),
    )


def _license_or_404(public_id: str):
    row = get_db().execute(
        "SELECT * FROM licenses WHERE public_id = ?", (public_id,)
    ).fetchone()
    if row is None:
        abort(404)
    return row


@bp.route("/login", methods=("GET", "POST"))
def login():
    if request.method == "POST":
        if _password_matches(request.form.get("password", "")):
            session.clear()
            session["admin_authenticated"] = True
            session["csrf_token"] = secrets.token_urlsafe(32)
            destination = request.args.get("next", "")
            if not destination.startswith("/admin"):
                destination = url_for("admin.licenses")
            return redirect(destination)
        flash("管理密码不正确。", "error")
    return render_template("login.html")


@bp.post("/logout")
@login_required
@csrf_required
def logout():
    session.clear()
    return redirect(url_for("admin.login"))


@bp.get("/")
@login_required
def index():
    return redirect(url_for("admin.licenses"))


@bp.get("/licenses")
@login_required
def licenses():
    query = request.args.get("q", "").strip()[:120]
    params = []
    where = ""
    if query:
        where = "WHERE l.customer_name LIKE ? OR l.order_reference LIKE ? OR l.code_hint LIKE ?"
        needle = f"%{query}%"
        params = [needle, needle, needle]
    rows = get_db().execute(
        f"""
        SELECT l.*,
               SUM(CASE WHEN a.id IS NOT NULL AND a.unbound_at IS NULL THEN 1 ELSE 0 END)
                   AS active_devices
        FROM licenses l
        LEFT JOIN activations a ON a.license_id = l.id
        {where}
        GROUP BY l.id
        ORDER BY l.created_at DESC
        LIMIT 500
        """,
        params,
    ).fetchall()
    today = utc_now().astimezone(ZoneInfo(current_app.config["LICENSE_TIMEZONE"])).date()
    return render_template("licenses.html", licenses=rows, query=query, today=today.isoformat())


@bp.route("/licenses/new", methods=("GET", "POST"))
@login_required
def new_license():
    local_today = utc_now().astimezone(
        ZoneInfo(current_app.config["LICENSE_TIMEZONE"])
    ).date()
    default_expiry = add_years(local_today)
    if request.method == "POST":
        expected = session.get("csrf_token", "")
        supplied = request.form.get("csrf_token", "")
        if not expected or not hmac.compare_digest(expected, supplied):
            abort(400, "CSRF validation failed")
        try:
            starts_on = date.fromisoformat(request.form.get("starts_on", ""))
            expires_on = date.fromisoformat(request.form.get("expires_on", ""))
            max_devices = int(request.form.get("max_devices", "1"))
            public_id, activation_code = create_license(
                request.form.get("customer_name", "").strip(),
                request.form.get("order_reference", "").strip(),
                request.form.get("notes", "").strip(),
                starts_on,
                expires_on,
                max_devices,
            )
            license_row = _license_or_404(public_id)
            with immediate_transaction() as connection:
                _audit(
                    connection,
                    "license_created",
                    license_row["id"],
                    {"starts_on": starts_on.isoformat(), "expires_on": expires_on.isoformat()},
                )
            return render_template(
                "license_created.html",
                license=license_row,
                activation_code=activation_code,
            )
        except (TypeError, ValueError) as error:
            flash(str(error) or "请检查授权日期和设备数量。", "error")
    return render_template(
        "license_new.html",
        starts_on=request.form.get("starts_on", local_today.isoformat()),
        expires_on=request.form.get("expires_on", default_expiry.isoformat()),
    )


@bp.get("/licenses/<public_id>")
@login_required
def license_detail(public_id: str):
    license_row = _license_or_404(public_id)
    activations = get_db().execute(
        "SELECT * FROM activations WHERE license_id = ? ORDER BY bound_at DESC",
        (license_row["id"],),
    ).fetchall()
    audits = get_db().execute(
        "SELECT * FROM admin_audit WHERE license_id = ? ORDER BY created_at DESC LIMIT 50",
        (license_row["id"],),
    ).fetchall()
    return render_template(
        "license_detail.html", license=license_row, activations=activations, audits=audits
    )


@bp.post("/licenses/<public_id>/unbind/<int:activation_id>")
@login_required
@csrf_required
def unbind(public_id: str, activation_id: int):
    license_row = _license_or_404(public_id)
    now = iso_utc()
    with immediate_transaction() as connection:
        cursor = connection.execute(
            """
            UPDATE activations SET unbound_at = ?
            WHERE id = ? AND license_id = ? AND unbound_at IS NULL
            """,
            (now, activation_id, license_row["id"]),
        )
        if cursor.rowcount:
            _audit(connection, "device_unbound", license_row["id"], {"activation_id": activation_id})
            flash("旧设备已解绑，可以在新 Mac 上使用同一激活码。", "success")
        else:
            flash("该设备已经解绑。", "error")
    return redirect(url_for("admin.license_detail", public_id=public_id))


@bp.post("/licenses/<public_id>/status")
@login_required
@csrf_required
def update_status(public_id: str):
    license_row = _license_or_404(public_id)
    status = request.form.get("status", "")
    if status not in {"active", "revoked"}:
        abort(400)
    with immediate_transaction() as connection:
        connection.execute(
            "UPDATE licenses SET status = ?, updated_at = ? WHERE id = ?",
            (status, iso_utc(), license_row["id"]),
        )
        _audit(connection, "status_changed", license_row["id"], {"status": status})
    flash("授权状态已更新。", "success")
    return redirect(url_for("admin.license_detail", public_id=public_id))


@bp.post("/licenses/<public_id>/expiry")
@login_required
@csrf_required
def update_expiry(public_id: str):
    license_row = _license_or_404(public_id)
    try:
        expires_on = date.fromisoformat(request.form.get("expires_on", ""))
        starts_on = date.fromisoformat(license_row["starts_on"])
        if expires_on <= starts_on:
            raise ValueError
    except ValueError:
        flash("到期日必须晚于开始日期。", "error")
        return redirect(url_for("admin.license_detail", public_id=public_id))
    with immediate_transaction() as connection:
        connection.execute(
            "UPDATE licenses SET expires_on = ?, updated_at = ? WHERE id = ?",
            (expires_on.isoformat(), iso_utc(), license_row["id"]),
        )
        _audit(
            connection,
            "expiry_changed",
            license_row["id"],
            {"expires_on": expires_on.isoformat()},
        )
    flash("授权到期日已更新。", "success")
    return redirect(url_for("admin.license_detail", public_id=public_id))
