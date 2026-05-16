param(
    [string]$PreviewRoot,
    [int]$Jobs = 1
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $PreviewRoot) {
    $driveRoot = ([System.IO.Path]::GetPathRoot($repoRoot)).TrimEnd("\")
    $PreviewRoot = Join-Path ($driveRoot + "\") ".BuildCache\inkscape-inkstitch-preview"
}

$buildRoot = Join-Path $PreviewRoot "build"
$tmpRoot = Join-Path $PreviewRoot ".tmp_system"
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$env:TEMP = $tmpRoot
$env:TMP = $tmpRoot
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH

& "C:\msys64\ucrt64\bin\ninja.exe" -C $buildRoot "-j$Jobs" install

Write-Host "Installed local preview to $(Join-Path $buildRoot 'install_dir')"

