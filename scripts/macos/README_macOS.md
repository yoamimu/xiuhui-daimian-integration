# macOS 构建说明（绣绘呆棉整合版）

本目录提供在一台 Apple Silicon macOS 26+ 机器上从零构建 **整合 dmg** 的脚本。最终产物是一个未签名（仅 ad-hoc 签名）的 `.dmg`，里面装有：

- 应用了 4 个 UI 补丁的 Inkscape 主程序
- 内嵌在 `Inkscape.app/Contents/Resources/share/inkscape/extensions/inkstitch/` 的 Ink/Stitch
- 中文 "首次打开说明" 和 /Applications 拖拽快捷方式

## 目标 & 不做的事

- 目标架构：**arm64 单架构**（Apple Silicon）
- 目标系统：**macOS 26 (Tahoe) 及以后**
- **不做** Apple Developer 签名、不做 Apple 公证。dmg 第一次打开要走"右键 → 打开"流程，详见 `assets/首次打开说明.txt`
- **不构** Intel x86_64 dmg
- **不依赖** `inkscape-ci-macos` (jhb)；使用 Homebrew 上的 GTK4 栈

## 目录约定

脚本默认假定下面这套目录布局（可用 `PREVIEW_ROOT` 环境变量改）：

```
$HOME/xiuhui-build/
├── 绣绘呆棉整合版/                     ← 本整合仓库 (本目录所在仓库)
└── inkscape-inkstitch-preview/
    ├── src/inkscape/                  ← Inkscape 源码，固定基线 7923d92
    ├── src/inkstitch/                 ← Ink/Stitch 源码，固定基线 0312dac
    ├── build/                         ← cmake/ninja + 中间产物 (由脚本生成)
    └── release/                       ← 最终 dmg (由脚本生成)
```

## 端到端步骤

按顺序执行：

```bash
cd $HOME/xiuhui-build/绣绘呆棉整合版/scripts/macos

# 一次性环境（Xcode CLT、Homebrew、Brewfile 依赖、检查源码工作区）
bash 00-bootstrap.sh

# 应用补丁 + overlays（每次重置工作区后都要再跑一次）
bash 01-apply-patches.sh

# 编译 Inkscape，产出 build/Inkscape.app (raw 骨架)
bash 02-build-inkscape.sh

# 用 PyInstaller 打 Ink/Stitch，产出 src/inkstitch/dist/inkstitch.app
bash 03-build-inkstitch.sh

# 合并、改 Info.plist 品牌、ad-hoc 签名，产出 build/Inkscape-绣绘呆棉版.app
bash 04-bundle.sh

# 套 dmg 壳（带 /Applications 拖拽和首次打开说明），产出 release/*.dmg
bash 05-make-dmg.sh
```

完成后 `release/Inkscape-Inkstitch-绣绘呆棉版-<VERSION>-arm64.dmg` 即可上传 GitHub Release。

### 版本号

默认 `VERSION=xiuhui-<整合仓库 short SHA>-local`。手动指定例如：

```bash
VERSION=v0.1.0 bash 03-build-inkstitch.sh
VERSION=v0.1.0 bash 04-bundle.sh
VERSION=v0.1.0 bash 05-make-dmg.sh
```

## 估时

| 阶段 | 首次 | 增量 |
|---|---|---|
| 00-bootstrap | 30–60 分钟 | 0 |
| 01-apply-patches | <1 秒 | <1 秒 |
| 02-build-inkscape | 40–90 分钟 | 15–30 分钟（ccache 命中） |
| 03-build-inkstitch | 5–10 分钟 | 5–10 分钟 |
| 04-bundle | 2–4 分钟 | 2–4 分钟 |
| 05-make-dmg | 1–2 分钟 | 1–2 分钟 |
| **合计** | **~1.5–3 小时** | **25–50 分钟** |

## 如果构建失败

按出现频率从高到低：

1. **`02-build-inkscape.sh` 在 cmake 阶段报 GTK4 / poppler 找不到** → `brew update && brew upgrade gtk4 gtkmm4 poppler` 后重试。Inkscape `CMakeLists.txt` 对版本要求随时跟进上游，本仓库的补丁不动这些。
2. **某个 brew 公式在 macOS 26 上还没出 bottle** → `brew install --build-from-source <name>`，或临时 `brew install <name>@<旧版>` 并把 pin 加进 `Brewfile`。
3. **`03-build-inkstitch.sh` PyInstaller 报缺少 gi 子模块** → 编辑 `src/inkstitch/inkstitch.spec` 的 `hiddenimports`/`datas`，加入缺的项；或在 `requirements.txt` 后再 `pip install <missing>`。
4. **`04-bundle.sh` 之后启动 Inkscape 直接闪退**，控制台日志含 "Code Signature Invalid" → 重新跑 `bash 04-bundle.sh`（确保 ad-hoc 签名走过 deepest-first 顺序）。
5. **dmg 打开后双击 app 没反应** → 看 `Console.app`；多数情况是 fontconfig 缓存路径写不进。补救：临时 `xattr -dr com.apple.quarantine /Applications/Inkscape-绣绘呆棉版.app`。

## 与 Windows 整合包的差异

| 项 | Windows | macOS |
|---|---|---|
| Inkscape 主程序构建 | MSYS2 + UCRT64 + cmake | Homebrew + cmake |
| Ink/Stitch 整合形式 | NSIS 安装到 Inkscape 扩展目录 | 内嵌在 .app/Contents/Resources/.../extensions/inkstitch/ |
| 签名 | 无 | ad-hoc (`codesign -s -`) |
| 公证 | 不适用 | 跳过（无 Apple Developer 账号） |
| 分发格式 | `.exe` 安装器 | `.dmg`（拖拽到 /Applications） |
| 首次打开 | 直接双击 | 右键 → 打开（一次性） |

## 已知遗留事项 / 后续可做

- 没有自动化 CI；目前是纯手动跑脚本。后续可加 GitHub Actions self-hosted runner（私有 mac）来固化流程。
- 没有 background PNG。`assets/dmg-background-arm64.png` 当前未提供，`05-make-dmg.sh` 会优雅跳过样式。把图准备好放进去即可获得带说明的 dmg 背景。
- 没有验证 Inkscape Extensions Manager UI 是否能正确识别整合进 .app 的 Ink/Stitch（理论上识别为只读 system extension）。
- 没有 Intel x86_64 路径。若以后需要，复制 02/03/04/05 一份加 `-x86_64` 后缀，把 `CMAKE_OSX_ARCHITECTURES=x86_64` 改一下，在 Intel mac 上跑即可。
