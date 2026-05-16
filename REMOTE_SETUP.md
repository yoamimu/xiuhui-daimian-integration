# Remote Repository Setup

Canonical remote:

```text
https://github.com/yoamimu/xiuhui-daimian-integration.git
```

If GitHub CLI is not logged in, login first:

```powershell
gh auth login
```

Then push this local integration repository:

```powershell
cd "E:\.BuildCache\绣绘呆棉整合版"
git remote add origin https://github.com/yoamimu/xiuhui-daimian-integration.git
git push -u origin main
gh repo edit yoamimu/xiuhui-daimian-integration --description "非官方 Inkscape + Ink/Stitch 中文整合修改版" --add-topic inkscape --add-topic inkstitch --add-topic embroidery --add-topic gplv3 --add-topic chinese-localization
```

If Git reports `Permission to yoamimu/xiuhui-daimian-integration.git denied to <other-user>`, the local Windows Git credential is authenticated as an account without write access. Fix it by either:

- logging in as `yoamimu` with GitHub CLI, or
- adding the shown account as a collaborator with write access, or
- removing the stale GitHub credential from Windows Credential Manager and logging in again.

After pushing, verify:

- Visibility is public.
- Repository license is GPL-3.0-or-later.
- README includes the non-official disclaimer.
- Releases attach both binary and source archives.
- Repository topics include `inkscape`, `inkstitch`, `embroidery`, `gplv3`, `chinese-localization`.

If using GitLab instead, create a public project with the same name and push:

```powershell
git remote add origin <your-public-gitlab-repo-url>
git push -u origin main
```
