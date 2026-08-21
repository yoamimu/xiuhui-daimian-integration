#!/usr/bin/env bash
#
# rebuild-inkstitch.sh
# 绣绘呆棉整合版 macOS build — incremental rebuild for Ink/Stitch-only changes.
#
# Use this when ONLY Ink/Stitch-side files changed (translations, overlays,
# extension code, *.inx, icons, etc.). It skips the expensive Inkscape C++
# rebuild (02-build-inkscape.sh) and reuses the existing raw Inkscape bundle.
#
# Pipeline: 01-apply-patches → 03-build-inkstitch → 04-bundle → 05-make-dmg
#
# Environment variables (all optional, same as the individual scripts):
#   MAC_ARCH        arm64 (default) | x86_64
#   VERSION         version stamp (default derived from repo short SHA)
#   PREVIEW_ROOT    source workspace root (default ~/xiuhui-build/inkscape-inkstitch-preview)
#   SIGNING_IDENTITY  Developer ID to sign with (default ad-hoc)
#   NOTARIZE=1      trigger notarization inside 05-make-dmg.sh
#   STOP_AFTER       optionally stop early: inkstitch | bundle | dmg

set -euo pipefail

_log()  { printf '\033[1;32m[rebuild-inkstitch]\033[0m %s\n' "$*"; }
_die()  { printf '\033[1;31m[rebuild-inkstitch]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- environment (passthrough) ----------
export MAC_ARCH="${MAC_ARCH:-arm64}"
case "${MAC_ARCH}" in
    arm64|x86_64) ;;
    *) _die "MAC_ARCH must be arm64 or x86_64 (got ${MAC_ARCH})" ;;
esac
# x86_64 must run under Rosetta: wrap the Ink/Stitch + bundle steps with `arch`.
ARCH_WRAP=""
[[ "${MAC_ARCH}" == "x86_64" ]] && ARCH_WRAP="arch -x86_64"

STOP_AFTER="${STOP_AFTER:-dmg}"
case "${STOP_AFTER}" in
    inkstitch|bundle|dmg) ;;
    *) _die "STOP_AFTER must be inkstitch | bundle | dmg (got ${STOP_AFTER})" ;;
esac

# ---------- 1. apply patches + overlays ----------
_log "Step 1/4: applying patches + overlays (01-apply-patches.sh)"
bash "${SCRIPT_DIR}/01-apply-patches.sh"

# ---------- 2. rebuild Ink/Stitch bundle ----------
_log "Step 2/4: rebuilding Ink/Stitch bundle (03-build-inkstitch.sh)"
bash "${SCRIPT_DIR}/03-build-inkstitch.sh"
[[ "${STOP_AFTER}" == "inkstitch" ]] && { _log "Stopped after Ink/Stitch build (STOP_AFTER=inkstitch)."; exit 0; }

# ---------- 3. re-bundle + re-sign ----------
_log "Step 3/4: re-bundling + re-signing (04-bundle.sh)"
${ARCH_WRAP} bash "${SCRIPT_DIR}/04-bundle.sh"
[[ "${STOP_AFTER}" == "bundle" ]] && { _log "Stopped after bundling (STOP_AFTER=bundle)."; exit 0; }

# ---------- 4. make dmg (optionally notarize) ----------
_log "Step 4/4: making dmg (05-make-dmg.sh)"
${ARCH_WRAP} bash "${SCRIPT_DIR}/05-make-dmg.sh"

_log "Done. Output dmg under ${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}/release/"
