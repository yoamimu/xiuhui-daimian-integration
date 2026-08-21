#!/usr/bin/env bash
#
# 06-notarize.sh
# 绣绘呆棉整合版 macOS build — notarize + staple a signed .dmg.
#
# Submits a Developer-ID-signed dmg to Apple's notary service using the
# notarytool credentials stored in the keychain profile
# "xiuhui-notary-profile", then staples the resulting ticket.
#
# Usage:
#   bash 06-notarize.sh /path/to/Inkscape-...-arm64.dmg
#
# Credentials are expected to be pre-stored via notarytool store-credentials
# (see docs/MACOS_SIGNING_SETUP.md). Environment overrides are also honoured
# for CI use (APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + TEAM_ID):
#
#   xcrun notarytool store-credentials "xiuhui-notary-profile" \
#       --apple-id "$APPLE_ID" \
#       --team-id "$TEAM_ID" \
#       --password "$APPLE_APP_SPECIFIC_PASSWORD"
#
# The dmg MUST have been signed with a Developer ID Application identity
# (SIGNING_IDENTITY set in 04-bundle.sh) for notarization to succeed.
# Ad-hoc-signed artifacts will be rejected by Apple.

set -euo pipefail

_log()  { printf '\033[1;34m[06-notarize]\033[0m %s\n' "$*"; }
_warn() { printf '\033[1;33m[06-notarize]\033[0m %s\n' "$*" >&2; }
_die()  { printf '\033[1;31m[06-notarize]\033[0m %s\n' "$*" >&2; exit 1; }

KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-xiuhui-notary-profile}"

DMG_PATH="${1:-}"
[[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]] || _die "Usage: bash 06-notarize.sh <path-to-signed.dmg>"

# ---------- credential resolution ----------
# Prefer explicit env vars (CI) over the keychain profile (local).
if [[ -n "${APPLE_API_KEY_FILE:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" && -n "${TEAM_ID:-}" ]]; then
    _log "Using App Store Connect API key from environment."
    AUTH_ARGS=(--key "${APPLE_API_KEY_FILE}" --key-id "${APPLE_API_KEY_ID}" --issuer "${APPLE_API_ISSUER}" --team-id "${TEAM_ID}")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
    _log "Using APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / TEAM_ID from environment."
    AUTH_ARGS=(--apple-id "${APPLE_ID}" --password "${APPLE_APP_SPECIFIC_PASSWORD}" --team-id "${TEAM_ID}")
else
    _log "Using keychain profile: ${KEYCHAIN_PROFILE}"
    AUTH_ARGS=(--keychain-profile "${KEYCHAIN_PROFILE}")
    if ! xcrun notarytool history "${AUTH_ARGS[@]}" >/dev/null 2>&1; then
        _warn "Keychain profile '${KEYCHAIN_PROFILE}' not found or invalid."
        _die "Store credentials first (see docs/MACOS_SIGNING_SETUP.md) or export APPLE_ID/APPLE_APP_SPECIFIC_PASSWORD/TEAM_ID."
    fi
fi

# ---------- submit ----------
_log "Submitting ${DMG_PATH} for notarization (this can take a few minutes)..."
SUBMIT_OUT="$(mktemp -t xiuhui-notary)"
trap 'rm -f "${SUBMIT_OUT}"' EXIT

if ! xcrun notarytool submit "${DMG_PATH}" "${AUTH_ARGS[@]}" --wait --output-format json > "${SUBMIT_OUT}" 2>&1; then
    _warn "notarytool submit returned non-zero. Output follows."
    cat "${SUBMIT_OUT}" >&2
fi

STATUS="$(jq -r '.status // "Unknown"' "${SUBMIT_OUT}" 2>/dev/null || echo "Unknown")"
SUBMIT_ID="$(jq -r '.id // empty' "${SUBMIT_OUT}" 2>/dev/null || true)"

_log "Notarization status: ${STATUS}"

if [[ "${STATUS}" != "Accepted" ]]; then
    _warn "Notarization was NOT accepted."
    if [[ -n "${SUBMIT_ID}" ]]; then
        _log "Fetching notarization log for id ${SUBMIT_ID} ..."
        xcrun notarytool log "${SUBMIT_ID}" "${AUTH_ARGS[@]}" >&2 || true
    fi
    _die "Notarization failed. Fix the reported issues and re-submit."
fi

# ---------- staple ----------
_log "Stapling ticket to ${DMG_PATH} ..."
xcrun stapler staple "${DMG_PATH}"

_log "Verifying staple..."
xcrun stapler validate "${DMG_PATH}" && _log "Staple verified OK." || _warn "stapler validate reported an issue."

_log "Done. Notarized + stapled dmg: ${DMG_PATH}"
