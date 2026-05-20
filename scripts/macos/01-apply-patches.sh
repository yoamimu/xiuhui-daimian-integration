#!/usr/bin/env bash
#
# 01-apply-patches.sh
# 绣绘呆棉整合版 macOS build — apply patches + overlays.
#
# sh-equivalent of scripts/apply-current-patches.ps1.
# Idempotent-ish: if the patch is already applied it will fail with a
# clear message instead of half-applying.
#
# Override PREVIEW_ROOT to use a non-default source workspace.

set -euo pipefail

_log()  { printf '\033[1;34m[01-apply]\033[0m %s\n' "$*"; }
_die()  { printf '\033[1;31m[01-apply]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"

INKSCAPE_SRC="${PREVIEW_ROOT}/src/inkscape"
INKSTITCH_SRC="${PREVIEW_ROOT}/src/inkstitch"

INKSCAPE_PATCH="${REPO_ROOT}/patches/inkscape/0001-xiuhui-daimian-ui-integration.patch"
INKSTITCH_PATCH="${REPO_ROOT}/patches/inkstitch/0001-zh-cn-localization-and-preview-fixes.patch"

[[ -d "${INKSCAPE_SRC}/.git" ]]  || _die "Inkscape clone not found at ${INKSCAPE_SRC}. Run 00-bootstrap.sh first."
[[ -d "${INKSTITCH_SRC}/.git" ]] || _die "Ink/Stitch clone not found at ${INKSTITCH_SRC}. Run 00-bootstrap.sh first."
[[ -f "${INKSCAPE_PATCH}" ]]  || _die "Missing patch: ${INKSCAPE_PATCH}"
[[ -f "${INKSTITCH_PATCH}" ]] || _die "Missing patch: ${INKSTITCH_PATCH}"

# Verify we are on the pinned base commits (warn, don't fail — devs may
# have rebased locally for testing).
_check_base() {
    local dir="$1" want="$2" label="$3"
    local have
    have="$(git -C "${dir}" rev-parse --short=7 HEAD)"
    if [[ "${have}" != "${want}" ]]; then
        printf '\033[1;33m[01-apply]\033[0m %s HEAD is %s, expected base %s. Continuing — patches may fail.\n' \
            "${label}" "${have}" "${want}" >&2
    else
        _log "${label} base commit OK (${have})"
    fi
}
_check_base "${INKSCAPE_SRC}"  "7923d92" "Inkscape"
_check_base "${INKSTITCH_SRC}" "0312dac" "Ink/Stitch"

# Check that the patches haven't already been applied.
_pre_check() {
    local dir="$1" patch="$2" label="$3"
    if ! git -C "${dir}" apply --check "${patch}" 2>/dev/null; then
        # Maybe already applied?
        if git -C "${dir}" apply --reverse --check "${patch}" 2>/dev/null; then
            _die "${label} patch appears to be already applied. Reset the working tree first: cd ${dir} && git reset --hard ${4}"
        fi
        _die "${label} patch does not apply cleanly. Run: git -C ${dir} apply --check --verbose ${patch}"
    fi
}
_pre_check "${INKSCAPE_SRC}"  "${INKSCAPE_PATCH}"  "Inkscape"  "7923d92"
_pre_check "${INKSTITCH_SRC}" "${INKSTITCH_PATCH}" "Ink/Stitch" "0312dac"

_log "Applying Inkscape patch..."
git -C "${INKSCAPE_SRC}" apply "${INKSCAPE_PATCH}"

_log "Applying Ink/Stitch patch..."
git -C "${INKSTITCH_SRC}" apply "${INKSTITCH_PATCH}"

_log "Copying overlays..."
mkdir -p "${INKSTITCH_SRC}/lib" "${INKSTITCH_SRC}/docs"
cp -f "${REPO_ROOT}/overlays/inkstitch/lib/i18n_zh_cn.py"      "${INKSTITCH_SRC}/lib/i18n_zh_cn.py"
cp -f "${REPO_ROOT}/overlays/inkstitch/docs/zh_CN_terminology.md" "${INKSTITCH_SRC}/docs/zh_CN_terminology.md"

_log "Done. Next: bash 02-build-inkscape.sh"
