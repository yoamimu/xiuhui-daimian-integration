#!/usr/bin/env bash
#
# 04b-bundle-dylibs.sh
# 绣绘呆棉整合版 macOS build — make the Inkscape.app self-contained.
#
# Inkscape is built against Homebrew (GTK4 stack etc.) and its binaries
# reference dylibs under the brew prefix by absolute path. This script:
#   1. replaces dangling Homebrew-symlinked icons (Adwaita) with real files,
#   2. copies the full dylib dependency closure into Contents/Frameworks,
#   3. rewrites install names to @executable_path/../Frameworks/...,
#   4. fixes @loader_path / @rpath gaps (icu, rsvg, sharpyuv, ...),
#   5. writes gdk-pixbuf loaders.cache and bundles GIR typelibs / glib
#      schemas / fontconfig config / xdg dirs so Inkscape's set_xdg_env()
#      finds everything inside the bundle,
#   6. reports any remaining absolute brew references.
#
# Works for arm64 (/opt/homebrew) and x86_64 (/usr/local) — auto-detected
# from MAC_ARCH (defaults to the host architecture).
#
# Output: modifies ${PREVIEW_ROOT}/build/绣绘-${MAC_ARCH}.app in place.
# Run AFTER 04-bundle.sh and BEFORE 05-make-dmg.sh.

set -euo pipefail

_log()  { printf '\033[1;34m[04b-dylibs]\033[0m %s\n' "$*"; }
_warn() { printf '\033[1;33m[04b-dylibs]\033[0m %s\n' "$*" >&2; }
_die()  { printf '\033[1;31m[04b-dylibs]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREVIEW_ROOT="${PREVIEW_ROOT:-${HOME}/xiuhui-build/inkscape-inkstitch-preview}"

export MAC_ARCH="${MAC_ARCH:-$(uname -m)}"
case "${MAC_ARCH}" in
    arm64)  BREW_PREFIX="/opt/homebrew" ;;
    x86_64) BREW_PREFIX="/usr/local" ;;
    *)      _die "MAC_ARCH must be arm64 or x86_64 (got ${MAC_ARCH})" ;;
esac

APP="${PREVIEW_ROOT}/build/绣绘-${MAC_ARCH}.app"
[[ -d "${APP}/Contents" ]] || _die "App not found at ${APP}. Run 04-bundle.sh first."

FW="${APP}/Contents/Frameworks"
MACOS_DIR="${APP}/Contents/MacOS"
ETC="${APP}/Contents/Resources/etc"
mkdir -p "${FW}" "${ETC}/fonts" "${ETC}/xdg"

MAPFILE="$(mktemp -t xiuhui-map)"
STAMPDIR="$(mktemp -d -t xiuhui-stamp)"
trap 'rm -f "$MAPFILE"; rm -rf "$STAMPDIR"' EXIT
WORKLIST=()

enqueue() {
    local f="$1" key
    key="$(printf '%s' "$f" | shasum | cut -c1-16)"
    [ -e "$STAMPDIR/$key" ] && return
    : > "$STAMPDIR/$key"
    WORKLIST+=("$f")
}

resolve_real() {
    local p="$1" t n=0
    while [ -L "$p" ]; do
        t="$(readlink "$p")"
        case "$t" in
            /*) p="$t" ;;
            *) p="$(dirname "$p")/$t" ;;
        esac
        n=$((n+1)); [ $n -gt 8 ] && break
    done
    printf '%s\n' "$p"
}

deps_of() {
    otool -L "$1" 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//' | awk '{print $1}'
}

is_external() {
    case "$1" in
        /System/*|/usr/lib/*|/usr/libexec/*|@rpath/*|@executable_path/*|@loader_path/*) return 1 ;;
        /opt/homebrew/*|/usr/local/*) return 0 ;;
        *) return 1 ;;
    esac
}

enqueue_deps() {
    local f="$1" p real base alias stem
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        is_external "$p" || continue
        real="$(resolve_real "$p")"
        if [ ! -f "$real" ]; then _warn "missing dep $p for $f"; continue; fi
        base="$(basename "$real")"
        if [ ! -e "$FW/$base" ]; then
            cp -p "$real" "$FW/$base"
            chmod u+w "$FW/$base"
            _log "  + $base"
        fi
        enqueue "$FW/$base"
        alias="$(basename "$p")"
        if [ "$alias" != "$base" ] && [ ! -e "$FW/$alias" ]; then
            ln -sf "$base" "$FW/$alias"
        fi
        stem="${alias%-[0-9]*}"
        if [ "$stem" != "$alias" ] && [[ "$alias" == *.dylib ]] && [ ! -e "$FW/${stem}.dylib" ]; then
            ln -sf "$base" "$FW/${stem}.dylib" 2>/dev/null || true
        fi
        if ! grep -qF "$p|" "$MAPFILE"; then echo "$p|$base" >> "$MAPFILE"; fi
    done < <(deps_of "$f")
}

find_in_cellar() {
    local name="$1"
    find "${BREW_PREFIX}/Cellar" -name "$name" \( -type f -o -type l \) 2>/dev/null | head -1
}

copy_from_cellar() {
    local name="$1" found real base
    found="$(find_in_cellar "$name")"
    if [ -z "$found" ]; then return 1; fi
    real="$(resolve_real "$found")"
    base="$(basename "$real")"
    if [ ! -e "$FW/$base" ]; then
        cp -p "$real" "$FW/$base"
        chmod u+w "$FW/$base"
        _log "  + $base (cellar)"
    fi
    # Replace any stale/broken alias with a fresh link to the real file.
    if [ "$base" != "$name" ]; then
        if [ -e "$FW/$name" ] || [ -L "$FW/$name" ]; then
            [ "$(readlink "$FW/$name" 2>/dev/null)" != "$base" ] && rm -f "$FW/$name"
        fi
        [ ! -e "$FW/$name" ] && ln -sf "$base" "$FW/$name"
    fi
    enqueue "$FW/$base"
    return 0
}

# ---------- 1. Adwaita icons: dereference dangling Homebrew symlinks ----------
ADWAITA_APP="${APP}/Contents/Resources/share/icons/Adwaita"
ADWAITA_CELLAR="$(ls -d "${BREW_PREFIX}"/Cellar/adwaita-icon-theme/*/share/icons/Adwaita 2>/dev/null | head -1)"
if [[ -n "${ADWAITA_CELLAR}" && -d "${ADWAITA_CELLAR}" ]]; then
    _log "Replacing Adwaita symlinks with real files from ${ADWAITA_CELLAR} ..."
    rm -rf "${ADWAITA_APP}"
    cp -RL "${ADWAITA_CELLAR}" "${ADWAITA_APP}"
fi
DANGLING="$(find "${APP}" -type l | while read -r l; do [ -e "$l" ] || echo "$l"; done | wc -l | tr -d ' ')"
[[ "${DANGLING}" != "0" ]] && _warn "${DANGLING} dangling symlinks remain inside the app (they will be removed by signing-preflight or cause verify issues)" || _log "No dangling symlinks."

# ---------- 2. gdk-pixbuf loaders (runtime dlopen'd) ----------
LOADER_SRC="${BREW_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders"
if [ -d "${LOADER_SRC}" ]; then
    for ld in "${LOADER_SRC}"/libpixbufloader*; do
        [ -f "$ld" ] || continue
        real="$(resolve_real "$ld")"
        base="$(basename "$real")"
        cp -p "$real" "$FW/$base"
        chmod u+w "$FW/$base"
        enqueue "$FW/$base"
    done
fi

# ---------- 3. roots + BFS over absolute deps ----------
for bin in "${MACOS_DIR}"/* "${APP}/Contents/lib/"*.dylib "${APP}/Contents/lib/inkscape/"*.dylib \
           "${APP}/Contents/Resources/lib/"*.dylib "${APP}/Contents/Resources/lib/inkscape/"*.dylib; do
    [ -f "$bin" ] || continue
    file -b "$bin" | grep -q "Mach-O" || continue
    enqueue "$bin"
done

i=0
while [ $i -lt ${#WORKLIST[@]} ]; do
    enqueue_deps "${WORKLIST[$i]}"
    i=$((i+1))
done

# ---------- 4. fill @loader_path / @rpath gaps from the Cellar ----------
for round in 1 2 3 4 5 6; do
    gap=""
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        [ -e "$FW/$name" ] && continue
        # Inkscape's own libs (lib2geom, libinkscape_base) resolve via the
        # main binary's LC_RPATH into Contents/lib — not real gaps.
        if [ -e "${APP}/Contents/lib/$name" ] || [ -e "${APP}/Contents/Resources/lib/$name" ] \
           || [ -e "${APP}/Contents/lib/inkscape/$name" ] || [ -e "${APP}/Contents/Resources/lib/inkscape/$name" ]; then
            continue
        fi
        _log "filling gap: $name"
        if ! copy_from_cellar "$name"; then
            _warn "cannot find $name in Cellar; runtime loading may fail"
        else
            gap="1"
        fi
    done < <(for f in "${WORKLIST[@]}" "${MACOS_DIR}"/* "${APP}/Contents/lib/"*.dylib \
                    "${APP}/Contents/lib/inkscape/"*.dylib "${APP}/Contents/Resources/lib/"*.dylib \
                    "${APP}/Contents/Resources/lib/inkscape/"*.dylib; do
                 [ -f "$f" ] || continue
                 deps_of "$f" | sed -n 's|^@loader_path/||p; s|^@rpath/||p'
             done | sort -u)
    [ -z "$gap" ] && break
    # BFS again for anything newly added
    j=${#WORKLIST[@]}
    k=0
    while [ $k -lt $j ]; do
        enqueue_deps "${WORKLIST[$k]}"
        k=$((k+1))
    done
done

# ---------- 5. rewrite absolute brew refs → @executable_path/../Frameworks ----------
for f in "${WORKLIST[@]}"; do
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if grep -qF "$p|" "$MAPFILE"; then
            base="$(grep -F "$p|" "$MAPFILE" | head -1 | cut -d'|' -f2)"
            install_name_tool -change "$p" "@executable_path/../Frameworks/$base" "$f" || true
        fi
    done < <(deps_of "$f")
done

for f in "${WORKLIST[@]}"; do
    if [[ "$f" == "$FW/"*.dylib ]]; then
        install_name_tool -id "@executable_path/../Frameworks/$(basename "$f")" "$f" 2>/dev/null || true
    fi
done

# ---------- 6. rpath hygiene ----------
for f in "${WORKLIST[@]}"; do
    [ -f "$f" ] || continue
    if ! otool -l "$f" | grep -q "path @executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$f" || true
    fi
    while otool -l "$f" | grep -qE "path /(opt/homebrew|usr/local)"; do
        rp="$(otool -l "$f" | grep -E "path /(opt/homebrew|usr/local)" | head -1 | awk '{print $2}')"
        install_name_tool -delete_rpath "$rp" "$f" || break
    done
done

# ---------- 8. GIR typelibs, glib schemas, fontconfig, xdg ----------
GIR_CELLAR="$(ls -d "${BREW_PREFIX}"/Cellar/gobject-introspection/*/lib/girepository-1.0 2>/dev/null | head -1)"
if [ -n "${GIR_CELLAR}" ]; then
    rm -rf "${APP}/Contents/Resources/lib/girepository-1.0"
    mkdir -p "${APP}/Contents/Resources/lib/girepository-1.0"
    cp -RL "${GIR_CELLAR}/." "${APP}/Contents/Resources/lib/girepository-1.0/"
    _log "GIR typelibs bundled (standalone-bundle indicator present)."
else
    _warn "girepository-1.0 not found; set_xdg_env() will not activate."
fi

SCHEMAS="${APP}/Contents/Resources/share/glib-2.0/schemas"
mkdir -p "${SCHEMAS}"
if [ -f "${BREW_PREFIX}/share/glib-2.0/schemas/gschemas.compiled" ]; then
    cp -f "${BREW_PREFIX}/share/glib-2.0/schemas/gschemas.compiled" "${SCHEMAS}/"
fi

FONTS_CONF="${PREVIEW_ROOT}/src/inkscape/packaging/macos/res/fonts.conf"
if [ -f "${FONTS_CONF}" ]; then
    cp -f "${FONTS_CONF}" "${ETC}/fonts/fonts.conf"
else
    _warn "fonts.conf template not found; fontconfig will fall back to defaults."
fi

# ---------- 9. report leftovers ----------
_log "Scanning for remaining absolute brew references ..."
LEFTOVERS="$(find "${APP}" -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) 2>/dev/null \
    | while read -r f; do
        file -b "$f" 2>/dev/null | grep -q "Mach-O" || continue
        deps_of "$f" | grep -E "^/(opt/homebrew|usr/local)/" || true
      done | sort -u | head -20)"
if [ -n "${LEFTOVERS}" ]; then
    _warn "Some brew references remain:"
    printf '%s\n' "${LEFTOVERS}" >&2
else
    _log "Clean: no /opt/homebrew or /usr/local references remain."
fi

# ---------- 10. re-sign everything ----------
# install_name_tool edits above invalidate all code signatures, so the whole
# bundle MUST be re-signed after bundling. Same policy as 04-bundle.sh:
# SIGNING_IDENTITY set → Developer ID + hardened runtime + entitlements
# (notarizable); empty → ad-hoc.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-${SCRIPT_DIR}/assets/entitlements.plist}"

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    _log "Developer ID signing with identity: ${SIGNING_IDENTITY}"
    SIGN_ARGS=(--force --options runtime --timestamp --sign "${SIGNING_IDENTITY}")
    if [[ -f "${ENTITLEMENTS}" ]]; then
        SIGN_ARGS+=(--entitlements "${ENTITLEMENTS}")
    else
        _warn "No entitlements plist at ${ENTITLEMENTS}; signing without entitlements."
    fi
else
    _log "Ad-hoc signing (no SIGNING_IDENTITY set; not notarizable)."
    SIGN_ARGS=(--force --sign - --timestamp=none)
fi

EXT_APP="${APP}/Contents/Resources/share/inkscape/extensions/inkstitch.app"
_log "Signing all Mach-O files inside ${APP} ..."
# Sign one file per codesign invocation (multi-file invocations abort the
# whole batch on the first failure), in parallel, then serially retry any
# Mach-O that still lacks a valid signature (timestamp hiccups etc.).
find "${APP}" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) -print0 \
    | xargs -0 -n 1 -P 6 codesign "${SIGN_ARGS[@]}" --preserve-metadata=identifier,entitlements,flags 2>/dev/null || true

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    while IFS= read -r f; do
        if codesign -dv "$f" 2>/dev/null | grep -q "TeamIdentifier="; then
            continue
        fi
        codesign "${SIGN_ARGS[@]}" --preserve-metadata=identifier,entitlements,flags "$f" 2>/dev/null || true
    done < <(find "${APP}" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -111 \) -print)
fi

if [[ -d "${EXT_APP}" ]]; then
    codesign "${SIGN_ARGS[@]}" "${EXT_APP}/Contents/Frameworks/Python.framework" 2>/dev/null || true
    codesign "${SIGN_ARGS[@]}" "${EXT_APP}" || _warn "inkstitch.app signing failed"
fi
codesign "${SIGN_ARGS[@]}" "${APP}"

codesign --verify --deep --strict --verbose=2 "${APP}" \
    || _die "Code-signature verification failed before cache generation."
# ---------- 7. gdk-pixbuf loaders.cache (relative, relocatable) ----------
# Run AFTER signing: gdk-pixbuf-query-loaders dlopens each loader, and on
# modern macOS an unsigned loader gets the query tool SIGKILLed. With valid
# signatures the official tool output is correct; the hand fallback emits
# entries with zero type lines, which the parser accepts cleanly.
QUERY_TOOL="${BREW_PREFIX}/bin/gdk-pixbuf-query-loaders"
CACHE_GENERATED=0
if [ -x "$QUERY_TOOL" ]; then
    _log "Generating loaders.cache ..."
    ( cd "${ETC}" && DYLD_LIBRARY_PATH="${FW}" "$QUERY_TOOL" \
        ../../Frameworks/libpixbufloader-*.so ../../Frameworks/libpixbufloader_svg.dylib \
        > loaders.cache 2>/dev/null || true )
    # Rewrite canonicalized absolute paths to bundle-relative ones.
    # Note: the tool escapes non-ASCII path bytes as \ooo, so build the
    # needle the same way (e.g. 绣绘 → \347\273\243...).
    python3 - "${ETC}/loaders.cache" "${APP}" <<'PYEOF'
import sys
cache, app = sys.argv[1], sys.argv[2].rstrip('/')
with open(cache) as f:
    data = f.read()
raw = (app + '/Contents/Resources/etc/../../Frameworks/').encode('utf-8')
needle = ''.join(chr(b) if 32 <= b < 127 else '\\%03o' % b for b in raw)
data = data.replace(needle, '../../Frameworks/')
with open(cache, 'w') as f:
    f.write(data)
PYEOF
    if grep -q '^"\.\./\.\./Frameworks/' "${ETC}/loaders.cache"; then
        CACHE_GENERATED=1
    fi
fi

if [ "${CACHE_GENERATED}" != "1" ]; then
    _warn "query tool unavailable; generating a conservative loaders.cache by hand."
    python3 - "${FW}" "${ETC}/loaders.cache" <<'PYEOF'
import glob, os, sys
fw, out = sys.argv[1], sys.argv[2]
lines = ["# GdkPixbuf Image Loader Modules file",
         "# Automatically generated file, do not edit",
         "# Created by xiuhui bundling (04b-bundle-dylibs.sh)",
         "# LoaderDir = ../../Frameworks"]
files = sorted(glob.glob(os.path.join(fw, 'libpixbufloader*.so')) +
               glob.glob(os.path.join(fw, 'libpixbufloader*.dylib')))
for f in files:
    base = os.path.basename(f)
    name = base[len('libpixbufloader-'):].rsplit('.', 1)[0].replace('_', '-')
    lines += ['"../../Frameworks/%s"' % base,
              '"%s" 0 "gdk-pixbuf" "%s" "LGPL"' % (name, name),
              '']
open(out, 'w').write('\n'.join(lines) + '\n')
PYEOF
fi

# loaders.cache changed after the bundle seal was written -> re-seal the top app.
codesign "${SIGN_ARGS[@]}" "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}" \
    || _die "Final code-signature verification failed; refusing to package the app."

_log "Signed bundle: ${APP}"
_log "Self-contained bundling done. Next: bash 05-make-dmg.sh"
