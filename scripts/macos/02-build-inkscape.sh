#!/usr/bin/env bash
#
# 02-build-inkscape.sh
# 绣绘呆棉整合版 macOS build — compile patched Inkscape and produce a
# raw Inkscape.app skeleton in $PREVIEW_ROOT/build/Inkscape.app.
#
# This script does NOT yet copy Ink/Stitch into the bundle, nor does it
# rewrite Info.plist or codesign anything. Those happen in 04-bundle.sh
# so they can be re-run cheaply without rebuilding Inkscape.
#
# Override PREVIEW_ROOT to use a non-default source workspace.

set -euo pipefail

_log()  { printf '\033[1;34m[02-inkscape]\033[0m %s\n' "$*"; }
_die()  { printf '\033[1;31m[02-inkscape]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"
INKSCAPE_SRC="${PREVIEW_ROOT}/src/inkscape"
BUILD_DIR="${PREVIEW_ROOT}/build/inkscape-macos"
INSTALL_PREFIX="${BUILD_DIR}/install"

[[ -d "${INKSCAPE_SRC}/.git" ]] || _die "Inkscape clone not found at ${INKSCAPE_SRC}."

# Pull Homebrew prefixes for paths and pkg-config.
eval "$(/opt/homebrew/bin/brew shellenv)"
export PKG_CONFIG_PATH="$(brew --prefix)/Library/Homebrew/os/mac/pkgconfig/26:$(brew --prefix icu4c@77)/lib/pkgconfig:$(brew --prefix libffi)/lib/pkgconfig:$(brew --prefix gettext)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$(brew --prefix gettext)/bin:${PATH}"

# Deployment target: match the build host major version. macOS 26+ users
# are the only audience by design.
DEPLOY_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion | cut -d. -f1).0}"
export MACOSX_DEPLOYMENT_TARGET="${DEPLOY_TARGET}"
_log "MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}"

# Number of parallel jobs — keep some headroom on laptops.
JOBS="${JOBS:-$(($(sysctl -n hw.ncpu) > 4 ? $(sysctl -n hw.ncpu) - 2 : $(sysctl -n hw.ncpu)))}"
_log "Parallel jobs: ${JOBS}"

mkdir -p "${BUILD_DIR}"

# Re-run cmake every time so option changes in the patch are picked up;
# CMakeCache.txt is reused as a build cache via ccache.
_log "Configuring Inkscape with cmake..."
cmake -S "${INKSCAPE_SRC}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOY_TARGET}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_FIND_FRAMEWORK=LAST \
    -DWITH_NLS=ON \
    -DWITH_CAPYPDF=OFF

_log "Building Inkscape (this is the longest step)..."
ninja -C "${BUILD_DIR}" -j"${JOBS}"

_log "Installing into ${INSTALL_PREFIX} ..."
rm -rf "${INSTALL_PREFIX}"
ninja -C "${BUILD_DIR}" install

# ---- assemble a minimal Inkscape.app skeleton ----
# Inkscape's CMake on macOS installs into a Unix-style ${prefix}/{bin,share,lib}
# tree but does NOT itself synthesise an .app bundle. We build the bundle
# ourselves the same way jhb does:
#   Contents/MacOS/      runnable binaries
#   Contents/Resources/  share/, etc/, lib/, plus Info.plist + icons
#
# The resulting .app is "raw": no rewritten Info.plist branding (done in
# 04-bundle.sh) and no Ink/Stitch yet (also 04-bundle.sh).

APP_OUT="${PREVIEW_ROOT}/build/Inkscape.app"
_log "Assembling raw bundle skeleton at ${APP_OUT} ..."
rm -rf "${APP_OUT}"
mkdir -p "${APP_OUT}/Contents/MacOS" \
         "${APP_OUT}/Contents/Resources" \
         "${APP_OUT}/Contents/Frameworks"

# binaries
cp -a "${INSTALL_PREFIX}/bin/." "${APP_OUT}/Contents/MacOS/"

# share, lib, etc go into Resources (Inkscape resolves them relative to bin
# via binreloc / hard-coded relative paths).
for d in share lib etc; do
    if [[ -d "${INSTALL_PREFIX}/${d}" ]]; then
        cp -a "${INSTALL_PREFIX}/${d}" "${APP_OUT}/Contents/Resources/"
    fi
done

# Inkscape's rpath on macOS also looks for libs at Contents/lib/ (not just
# Contents/Resources/lib/). Duplicate lib there so the binary can find
# libinkscape_base at runtime.
if [[ -d "${INSTALL_PREFIX}/lib" ]]; then
    cp -a "${INSTALL_PREFIX}/lib" "${APP_OUT}/Contents/"
fi

# Drop in upstream Info.plist verbatim; 04-bundle.sh will rewrite the
# branding-related keys (bundle id, name, version) afterwards.
cp -f "${INKSCAPE_SRC}/packaging/macos/res/inkscape.plist" \
      "${APP_OUT}/Contents/Info.plist"

# Document type icons.
cp -a "${INKSCAPE_SRC}/packaging/macos/res/." \
      "${APP_OUT}/Contents/Resources/"

# fonts.conf for fontconfig
cp -f "${INKSCAPE_SRC}/packaging/macos/res/fonts.conf" \
      "${APP_OUT}/Contents/Resources/" 2>/dev/null || true

_log "Done. Raw bundle at: ${APP_OUT}"
_log "Next: bash 03-build-inkstitch.sh"
