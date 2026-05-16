# Remote Repository Setup

GitHub CLI on this machine is currently not logged in. After login, create the remote repository with:

```powershell
gh auth login
gh repo create "绣绘呆棉整合版" --public --source "E:\.BuildCache\绣绘呆棉整合版" --remote origin --push --description "非官方 Inkscape + Ink/Stitch 中文整合修改版"
```

After the repository is created, verify:

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

