$ErrorActionPreference = "Stop"

$sshDir = Join-Path $env:USERPROFILE ".ssh"
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null

$accounts = @(
    @{ User = "yoamimu"; Key = "id_ed25519_github_yoamimu" },
    @{ User = "lesenanimation"; Key = "id_ed25519_github_lesenanimation" }
)

foreach ($account in $accounts) {
    $keyPath = Join-Path $sshDir $account.Key
    if (-not (Test-Path -LiteralPath $keyPath)) {
        ssh-keygen -t ed25519 -C "$($account.User)@github" -f $keyPath -N ""
    }
}

$configPath = Join-Path $sshDir "config"
$existing = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { "" }
$managedStart = "# >>> xiuhui-daimian GitHub account aliases"
$managedEnd = "# <<< xiuhui-daimian GitHub account aliases"

$block = @"
$managedStart
Host github.com-yoamimu
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_yoamimu
  IdentitiesOnly yes

Host github.com-lesenanimation
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_lesenanimation
  IdentitiesOnly yes
$managedEnd
"@

if ($existing -match [regex]::Escape($managedStart)) {
    $pattern = "(?s)" + [regex]::Escape($managedStart) + ".*?" + [regex]::Escape($managedEnd)
    $updated = [regex]::Replace($existing, $pattern, $block)
} else {
    $updated = ($existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n").TrimStart()
}

Set-Content -LiteralPath $configPath -Value $updated -Encoding UTF8

Write-Host ""
Write-Host "SSH aliases are configured."
Write-Host ""
Write-Host "Add these public keys to the matching GitHub accounts:"
Write-Host ""
foreach ($account in $accounts) {
    $pubPath = Join-Path $sshDir ($account.Key + ".pub")
    Write-Host "[$($account.User)]"
    Get-Content -LiteralPath $pubPath
    Write-Host ""
}

Write-Host "After adding the keys on GitHub, test with:"
Write-Host "  ssh -T git@github.com-yoamimu"
Write-Host "  ssh -T git@github.com-lesenanimation"

