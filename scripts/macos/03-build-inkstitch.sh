#!/usr/bin/env bash
#
# 03-build-inkstitch.sh
# 绣绘呆棉整合版 macOS build — build Ink/Stitch as a PyInstaller bundle.
#
# We use Ink/Stitch's own `make dist BUILD=osx` pipeline (which calls
# bin/build-python + bin/build-distribution-archives). It produces:
#   dist/inkstitch.app/            (PyInstaller .app bundle, self-contained)
#
# 04-bundle.sh then strips the outer .app shell and copies the runnable
# tree into the Inkscape.app/Contents/Resources/share/inkscape/extensions/inkstitch/
# location, which is where Inkscape looks for bundled extensions.
#
# Override PREVIEW_ROOT to use a non-default source workspace.

set -euo pipefail

_log()  { printf '\033[1;34m[03-inkstitch]\033[0m %s\n' "$*"; }
_die()  { printf '\033[1;31m[03-inkstitch]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"
INKSTITCH_SRC="${PREVIEW_ROOT}/src/inkstitch"

# ---------- target architecture ----------
# PyInstaller builds for the arch of the running interpreter, so MAC_ARCH
# selects the Homebrew prefix (and thus the Python) used. x86_64 builds must
# run under Rosetta 2 (arch -x86_64) with an /usr/local Homebrew.
export MAC_ARCH="${MAC_ARCH:-arm64}"
case "${MAC_ARCH}" in
    arm64)  BREW_PREFIX="/opt/homebrew" ;;
    x86_64) BREW_PREFIX="/usr/local" ;;
    *)      _die "MAC_ARCH must be arm64 or x86_64 (got ${MAC_ARCH})" ;;
esac

[[ -d "${INKSTITCH_SRC}/.git" ]] || _die "Ink/Stitch clone not found at ${INKSTITCH_SRC}."

eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
export PKG_CONFIG_PATH="$(brew --prefix)/Library/Homebrew/os/mac/pkgconfig/26:$(brew --prefix libffi)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$(brew --prefix gnu-getopt)/bin:${PATH}"

# Ink/Stitch's build scripts expect a `python` on PATH. Pin to the brew
# python 3.13 we installed in 00-bootstrap.sh.
PY_BIN="$(brew --prefix python@3.13)/bin/python3.13"
[[ -x "${PY_BIN}" ]] || _die "python@3.13 not found at ${PY_BIN}; re-run 00-bootstrap.sh"

# Create / refresh a venv inside the source dir to keep PyInstaller and
# Ink/Stitch's pinned deps isolated from the system Python. Per-arch venv so
# arm64 and x86_64 don't clobber each other's PyInstaller artifacts.
VENV_DIR="${INKSTITCH_SRC}/.venv-macos-${MAC_ARCH}"
if [[ ! -d "${VENV_DIR}" ]]; then
    _log "Creating venv at ${VENV_DIR} (python @ ${PY_BIN}) ..."
    "${PY_BIN}" -m venv --system-site-packages "${VENV_DIR}"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
python -m pip install --upgrade pip wheel
python -m pip install -r "${INKSTITCH_SRC}/requirements.txt"
python -m pip install pyinstaller

# Version stamp for the dist artefacts. CHANGES.md "Unreleased" → use
# the integration repo's short SHA + timestamp so re-builds are unique.
INTEG_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="${VERSION:-xiuhui-$(git -C "${INTEG_REPO_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || date +%Y%m%d)-local}"
export VERSION
export BUILD=osx
_log "VERSION=${VERSION}  BUILD=${BUILD}  MAC_ARCH=${MAC_ARCH}"

# Ink/Stitch's Makefile `dist` target = generate-version-file + locales + inx + build-python + build-distribution-archives
_log "Running make distclean + make dist (Ink/Stitch) ..."
( cd "${INKSTITCH_SRC}" && make distclean && make dist )

DIST_APP="${INKSTITCH_SRC}/dist/inkstitch.app"
[[ -d "${DIST_APP}" ]] || _die "Expected ${DIST_APP} after make dist, but it is missing."

# Verify the built bundle matches the requested architecture.
DIST_ARCH="$(file -b "${DIST_APP}/Contents/MacOS/inkstitch" | grep -o 'arm64\|x86_64' | head -1 || true)"
if [[ -n "${DIST_ARCH}" && "${DIST_ARCH}" != "${MAC_ARCH}" ]]; then
    _die "Ink/Stitch built as ${DIST_ARCH} but MAC_ARCH=${MAC_ARCH}. Rebuild under the matching Homebrew/Rosetta environment."
fi

_log "Ink/Stitch built at ${DIST_APP}"
_log "Next: bash 04-bundle.sh"
