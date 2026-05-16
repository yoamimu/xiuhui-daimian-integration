param(
    [string]$PreviewRoot
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $PreviewRoot) {
    $driveRoot = ([System.IO.Path]::GetPathRoot($repoRoot)).TrimEnd("\")
    $PreviewRoot = Join-Path ($driveRoot + "\") ".BuildCache\inkscape-inkstitch-preview"
}

$inkscapeRoot = Join-Path $PreviewRoot "src\inkscape"
$inkstitchRoot = Join-Path $PreviewRoot "src\inkstitch"

git -C $inkscapeRoot apply (Join-Path $repoRoot "patches\inkscape\0001-xiuhui-daimian-ui-integration.patch")
git -C $inkstitchRoot apply (Join-Path $repoRoot "patches\inkstitch\0001-zh-cn-localization-and-preview-fixes.patch")

Copy-Item -LiteralPath (Join-Path $repoRoot "overlays\inkstitch\lib\i18n_zh_cn.py") -Destination (Join-Path $inkstitchRoot "lib\i18n_zh_cn.py") -Force
New-Item -ItemType Directory -Path (Join-Path $inkstitchRoot "docs") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot "overlays\inkstitch\docs\zh_CN_terminology.md") -Destination (Join-Path $inkstitchRoot "docs\zh_CN_terminology.md") -Force

Write-Host "Applied 绣绘呆棉整合版 patches to $PreviewRoot"

