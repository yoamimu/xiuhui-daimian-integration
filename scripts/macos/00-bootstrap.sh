#!/usr/bin/env bash
#
# 00-bootstrap.sh
# 绣绘呆棉整合版 macOS build — environment bootstrap.
#
# Run this once on a fresh macOS machine before the rest of the
# scripts in scripts/macos/. Safe to re-run; existing tools are
# left alone.
#
# Assumptions / decisions baked in:
#   - Target machine: Apple Silicon (arm64)
#   - Target OS:      macOS 26 (Tahoe) or later
#   - We do NOT use Apple Developer signing (ad-hoc codesign only)
#   - We do NOT use jhb / inkscape-ci-macos; we use plain Homebrew.
#
# After this script finishes, the following layout is expected on disk:
#
#   $HOME/xiuhui-build/
#   ├── 绣绘呆棉整合版/      (this repo, can also live elsewhere — see PREVIEW_ROOT)
#   └── inkscape-inkstitch-preview/
#       ├── src/inkscape/    (clone of Inkscape, will be patched)
#       └── src/inkstitch/   (clone of Ink/Stitch, will be patched)
#
# PREVIEW_ROOT can be overridden to use a different layout (see other
# scripts in this dir which all accept the same env var).

set -euo pipefail

# ---------- pretty logging ----------
_log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
_warn() { printf '\033[1;33m[bootstrap]\033[0m %s\n' "$*" >&2; }
_die()  { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- sanity checks ----------
[[ "$(uname -s)" == "Darwin" ]] || _die "This script must run on macOS."
[[ "$(uname -m)" == "arm64" ]]  || _die "Only Apple Silicon is supported by the current pipeline (got $(uname -m))."

MAC_VERSION="$(sw_vers -productVersion)"
MAC_MAJOR="${MAC_VERSION%%.*}"
if (( MAC_MAJOR < 26 )); then
    _warn "Detected macOS ${MAC_VERSION}. The pipeline targets macOS 26+ (Tahoe). Older versions may work but are not tested."
fi

# ---------- Xcode Command Line Tools ----------
if ! xcode-select -p >/dev/null 2>&1; then
    _log "Installing Xcode Command Line Tools (interactive popup will appear)..."
    xcode-select --install || true
    _die "Re-run this script after the Xcode Command Line Tools installation completes."
else
    _log "Xcode Command Line Tools: $(xcode-select -p)"
fi

# ---------- Homebrew ----------
if ! command -v brew >/dev/null 2>&1; then
    _log "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Make brew available in this shell (Apple Silicon default prefix).
eval "$(/opt/homebrew/bin/brew shellenv)"
_log "Homebrew: $(brew --version | head -1)"

# ---------- Brewfile ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${SCRIPT_DIR}/Brewfile"
[[ -f "${BREWFILE}" ]] || _die "Brewfile not found at ${BREWFILE}"

_log "Updating Homebrew formulae index..."
brew update

_log "Installing build dependencies from ${BREWFILE}..."
brew bundle install --file="${BREWFILE}" --no-lock

# ---------- workspace check ----------
PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"
INKSCAPE_SRC="${PREVIEW_ROOT}/src/inkscape"
INKSTITCH_SRC="${PREVIEW_ROOT}/src/inkstitch"

if [[ ! -d "${INKSCAPE_SRC}/.git" ]] || [[ ! -d "${INKSTITCH_SRC}/.git" ]]; then
    cat >&2 <<EOF

[bootstrap] Inkscape / Ink/Stitch source clones not found at:
    ${INKSCAPE_SRC}
    ${INKSTITCH_SRC}

Clone them now with (matching this repo's pinned base commits):

  mkdir -p "${PREVIEW_ROOT}/src" && cd "${PREVIEW_ROOT}/src"

  # Inkscape (base: 7923d92)
  git clone --recurse-submodules https://gitlab.com/inkscape/inkscape.git
  cd inkscape && git checkout 7923d92 && git submodule update --init --recursive && cd ..

  # Ink/Stitch (base: 0312dac)
  git clone --recurse-submodules https://github.com/inkstitch/inkstitch.git
  cd inkstitch && git checkout 0312dac && git submodule update --init --recursive && cd ..

Then re-run this script.

EOF
    exit 2
fi

_log "Source workspace OK: ${PREVIEW_ROOT}"
_log "Bootstrap done. Next: bash 01-apply-patches.sh"
