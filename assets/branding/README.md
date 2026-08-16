# Branding Assets

These files are the confirmed branding assets used by the Windows package work for 绣绘呆棉整合版.

## Confirmed Source

- Source image in this repository: `assets/branding/source/xiuhui-daimian-icon-source.png`
- Source filename recorded during the Windows package work: `绣_v2-tou.png`
- Source dimensions: 1024 x 1024, RGBA
- Source SHA256: `28C74804395B5C1180515294992D252864AD6E8BCBC2D127B9198946323A898A`

## Generated Windows Assets

- `assets/branding/windows/xiuhui-daimian.ico`
  - Used for Inkscape branding icon replacement: `src/inkscape/share/branding/inkscape.ico`
  - Also matches Ink/Stitch Windows icon replacement: `src/inkstitch/images/inkstitch/win/inkstitch.ico`
  - SHA256: `C1B1D926022620CB3A2E846CFF853391A3A60ABABA2B1BF7F092403CFEE66B95`
- `assets/branding/windows/nsis-header.bmp`
  - Used for NSIS header image replacement: `src/inkscape/packaging/nsis/header.bmp`
  - Size: 150 x 57
  - SHA256: `9D21C8DACD38ABBCE0706C12B0ACE6FD2615AA6155E9B83760AA393B1A9C040B`
- `assets/branding/windows/nsis-welcomefinish.bmp`
  - Used for NSIS welcome/finish page image replacement: `src/inkscape/packaging/nsis/welcomefinish.bmp`
  - Size: 164 x 314
  - SHA256: `BB721AB5805CE4A304BE0F49B260EE56AAE12730E7E76424DB350AA37A32BCCB`

## Evidence Checked

Local build records checked on 2026-08-16 show:

- `MODIFICATIONS.md` lines 9-28: records `绣_v2-tou.png` as the 1024 x 1024 RGBA source and lists the generated ICO/BMP replacements.
- `MODIFICATIONS.md` lines 320-322: records relinking `inkscape.exe` and verifying the embedded icon with `[System.Drawing.Icon]::ExtractAssociatedIcon` as the 绣字 logo rather than the upstream Inkscape diamond logo.
- `HANDOFF.md` lines 249-255: records the same source image and generated replacement files.
- `THIRD_PARTY_NOTICES.md` lines 171-175: records that the main icon and NSIS wizard bitmap use the locally generated independent 绣字 logo, not the Inkscape trademark logo.

## Non-Used Candidate

The repository-root file `1779423940804_d.png` is not tracked here because it does not match the recorded source image hash and visually represents a different calligraphy-style candidate, not the confirmed Windows package icon source.
