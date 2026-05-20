# Release Checklist

Before publishing a release:

- [ ] Confirm product name and about dialog clearly say `绣绘呆棉整合版` and `非官方修改版`.
- [ ] Confirm source tag exists for the exact binary.
- [ ] Confirm binary archive and source archive are both attached.
- [ ] Confirm `LICENSE`, `NOTICE.md`, `CHANGES.md`, `SOURCE_CODE.md` and third-party license inventory are included.
- [ ] Confirm installer does not impose non-commercial-only or no-redistribution restrictions.
- [ ] Confirm Inkscape and Ink/Stitch upstream attribution is present.
- [ ] Confirm release notes describe the major modifications.
- [ ] Smoke test import, export, Ink/Stitch params, DST export and floating panels.

## macOS (Apple Silicon) dmg build

For the integrated macOS dmg specifically:

- [ ] Build host is Apple Silicon, macOS 26+, with Xcode CLT installed.
- [ ] `scripts/macos/00-bootstrap.sh` finished without errors and `brew bundle install` reported no missing formulae.
- [ ] `scripts/macos/01-apply-patches.sh` reported "base commit OK" for both Inkscape and Ink/Stitch.
- [ ] `02-build-inkscape.sh` produced `build/Inkscape.app` and the binary launches standalone (test: `open build/Inkscape.app`).
- [ ] `03-build-inkstitch.sh` produced `src/inkstitch/dist/inkstitch.app`.
- [ ] `04-bundle.sh` produced `build/Inkscape-绣绘呆棉版.app`; `codesign --verify --deep` reports no fatal errors.
- [ ] `05-make-dmg.sh` produced `release/Inkscape-Inkstitch-绣绘呆棉版-<ver>-arm64.dmg`.
- [ ] dmg first-launch tested on a clean user account: right-click → 打开 succeeds without crash.
- [ ] Ink/Stitch menu appears inside Inkscape after launch; "刺绣参数" dialog opens.
- [ ] DST export round-trip works.
- [ ] `assets/首次打开说明.txt` is present inside the mounted dmg.
- [ ] GitHub Release description quotes the same "首次打开说明" workaround in Chinese.

