#!/usr/bin/env bash

set -euo pipefail

_log() { printf '[license-generator] %s\n' "$*"; }
_die() { printf '[license-generator] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCE="${SCRIPT_DIR}/XHOfflineLicenseGenerator.m"
OUTPUT="${1:-${ROOT}/build/绣绘授权生成器.app}"
ICON="${ROOT}/assets/branding/macos/绣绘.icns"
BUILD_DIR="$(mktemp -d -t xiuhui-license-generator)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

[[ -f "${SOURCE}" ]] || _die "missing source: ${SOURCE}"
rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}/Contents/MacOS" "${OUTPUT}/Contents/Resources"

for arch in arm64 x86_64; do
    xcrun --sdk macosx clang \
        -arch "${arch}" \
        -mmacosx-version-min=14.0 \
        -fobjc-arc \
        -Os \
        -Wall -Wextra -Werror \
        -framework Cocoa \
        "${SOURCE}" \
        -o "${BUILD_DIR}/generator-${arch}"
done
lipo -create "${BUILD_DIR}/generator-arm64" "${BUILD_DIR}/generator-x86_64" \
    -output "${OUTPUT}/Contents/MacOS/绣绘授权生成器"
chmod 755 "${OUTPUT}/Contents/MacOS/绣绘授权生成器"

/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.yoamimu.xiuhui.license-generator' \
    "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string 绣绘授权生成器' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string 绣绘授权生成器' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string 绣绘授权生成器' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "${OUTPUT}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "${OUTPUT}/Contents/Info.plist"

if [[ -f "${ICON}" ]]; then
    cp "${ICON}" "${OUTPUT}/Contents/Resources/绣绘.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string 绣绘.icns' "${OUTPUT}/Contents/Info.plist"
fi

codesign --force --sign - --timestamp=none "${OUTPUT}"
codesign --verify --deep --strict "${OUTPUT}"
_log "ready: ${OUTPUT} ($(lipo -archs "${OUTPUT}/Contents/MacOS/绣绘授权生成器"))"
