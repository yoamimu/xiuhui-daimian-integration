# GitHub Account Switching

This project may need two GitHub accounts on the same Windows machine:

- `yoamimu`
- `lesenanimation`

Use different mechanisms for different jobs:

- For `gh` repository administration, use GitHub CLI multi-account login and `gh auth switch`.
- For normal `git push` / `git pull`, prefer SSH host aliases so each repository is pinned to the intended account and does not depend on the active HTTPS credential.

## Why Not Plain HTTPS

Plain HTTPS remotes such as `https://github.com/owner/repo.git` share a single Git credential target for `github.com` in Windows Credential Manager. This makes account switching easy to confuse, as seen when a push to `yoamimu/xiuhui-daimian-integration` was attempted with the stale `lesenanimation` credential.

## Recommended SSH Aliases

Configure two aliases in `%USERPROFILE%\.ssh\config`:

```sshconfig
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
```

Then set repository remotes explicitly:

```powershell
git remote set-url origin git@github.com-yoamimu:yoamimu/xiuhui-daimian-integration.git
```

or:

```powershell
git remote set-url origin git@github.com-lesenanimation:<owner>/<repo>.git
```

## GitHub CLI Switching

Login both accounts once:

```powershell
gh auth login --hostname github.com --git-protocol https --web --scopes repo
```

Then switch the active `gh` account as needed:

```powershell
gh auth switch --hostname github.com --user yoamimu
gh auth switch --hostname github.com --user lesenanimation
gh auth status
```

`gh auth switch` affects GitHub CLI API operations such as editing repository descriptions and topics. It does not make an HTTPS Git remote safe for account-specific pushes. Use SSH aliases for Git remotes.

