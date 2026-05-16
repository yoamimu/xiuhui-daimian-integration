$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
git -C $repoRoot remote set-url origin "git@github.com-yoamimu:yoamimu/xiuhui-daimian-integration.git"
git -C $repoRoot config user.name "yoamimu"

Write-Host "origin is now pinned to yoamimu via SSH alias:"
git -C $repoRoot remote -v

