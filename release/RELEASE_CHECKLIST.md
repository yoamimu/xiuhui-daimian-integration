# Release Checklist

Before publishing a release:

- [ ] Confirm product name and about dialog clearly say `绣绘呆棉整合版` and `非官方修改版`.
- [ ] Confirm source tag exists for the exact binary.
- [ ] Confirm binary archive and source archive are both attached.
- [ ] Confirm `LICENSE`, `NOTICE.md`, `CHANGES.md`, `SOURCE_CODE.md` and third-party license inventory are included.
- [ ] Confirm installer does not impose non-commercial-only or no-redistribution restrictions.
- [ ] Confirm Inkscape and Ink/Stitch upstream attribution is present.
- [ ] Confirm release notes describe the major modifications.
- [ ] Update `docs/PROJECT_LOG.md` with version status, build result, test conclusions, and whether the package is customer-ready.
- [ ] Smoke test import, export, Ink/Stitch params, DST export and floating panels.

## macOS dmg build (arm64 + x86_64)

For each architecture (`MAC_ARCH=arm64` and `MAC_ARCH=x86_64`) built separately:

- [ ] Build host is the matching arch (Apple Silicon for arm64; Intel or Rosetta 2 for x86_64), macOS 26+, with Xcode CLT installed.
- [ ] `scripts/macos/00-bootstrap.sh` finished without errors and `brew bundle install` reported no missing formulae.
- [ ] `scripts/macos/01-apply-patches.sh` reported "base commit OK" for both Inkscape and Ink/Stitch.
- [ ] `02-build-inkscape.sh` produced `build/Inkscape-${MAC_ARCH}.app` and the binary launches standalone.
- [ ] `03-build-inkstitch.sh` produced `src/inkstitch/dist/inkstitch.app` and its arch matches `MAC_ARCH`.
- [ ] `04-bundle.sh` produced `build/Inkscape-绣绘呆棉版-${MAC_ARCH}.app`; `codesign --verify --deep` reports no fatal errors.
- [ ] `05-make-dmg.sh` produced `release/Inkscape-Inkstitch-绣绘呆棉版-<ver>-${MAC_ARCH}.dmg`.
- [ ] dmg first-launch tested on a clean user account (right-click → 打开 for ad-hoc; direct double-click for notarized).
- [ ] Ink/Stitch menu appears inside Inkscape after launch; "刺绣参数" dialog opens.
- [ ] DST export round-trip works.
- [ ] `assets/首次打开说明.txt` is present inside the mounted dmg.
- [ ] GitHub Release description quotes the same "首次打开说明" workaround in Chinese (ad-hoc builds).

## Signing & notarization (optional, for official release)

When publishing a Developer-ID-signed + notarized build:

- [ ] Developer ID Application certificate installed in keychain and `SIGNING_IDENTITY` set in `04-bundle.sh`.
- [ ] Notary credentials stored (`xiuhui-notary-profile`) or `APPLE_ID` / `APPLE_APP_SPECIFIC_PASSWORD` / `TEAM_ID` exported.
- [ ] `04-bundle.sh` signed with Developer ID (verify: `codesign -dv` shows `Authority=Developer ID Application`).
- [ ] `06-notarize.sh` reported `status: Accepted` and `stapler validate` passed.
- [ ] The notarized dmg opens without Gatekeeper warning on a clean machine.

## Customer delivery sign-off

- [x] v0.2.4 arm64 and x86_64 customer DMGs are copied to the local Downloads folder.
- [x] Both DMGs pass `hdiutil verify` and `xcrun stapler validate`.
- [x] Both app bundles contain the native activation launcher and `inkscape-core`.
- [x] Test on a clean, never-activated Apple Silicon Mac: app opens and enters the activation flow after clearing the transfer quarantine attribute.
- [x] User confirmed Intel and Apple Silicon drawing is stable without crashes or flicker.
- [ ] Record the customer order, device code, start date, expiry date and issued license ID.
- [ ] Do not deliver a license private key or the internal license generator to customers.
