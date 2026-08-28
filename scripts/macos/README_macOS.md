# macOS 构建说明（绣绘呆棉整合版）

本目录提供在 macOS 26+ 机器上从零构建 **整合 dmg** 的脚本。最终产物是 `.dmg`，里面装有：

- 应用了 UI 补丁的 Inkscape 主程序
- 内嵌在 `Inkscape.app/Contents/Resources/share/inkscape/extensions/inkstitch/` 的 Ink/Stitch
- 中文 "首次打开说明" 和 /Applications 拖拽快捷方式

## 目标 & 不做的事

- 目标架构：**arm64（Apple Silicon）** 与 **x86_64（Intel）**，分别产出独立 dmg（不做 Universal Binary）
- 目标系统：**macOS 26 (Tahoe) 及以后**
- 签名策略可切换：
  - 默认 **ad-hoc 签名**（无需开发者账号），dmg 首次打开要走"右键 → 打开"
  - 可选 **Developer ID 签名 + 公证**（需付费开发者账号，见 `docs/MACOS_SIGNING_SETUP.md`）
- **不依赖** `inkscape-ci-macos` (jhb)；使用 Homebrew 上的 GTK4 栈
- 正式构建默认安装原生授权启动器；必须设置生产 HTTPS 地址 `ACTIVATION_SERVER_URL`

## 架构说明

每个脚本通过环境变量 `MAC_ARCH` 选择目标架构，默认 `arm64`（向后兼容）：

| `MAC_ARCH` | Homebrew 前缀 | 说明 |
|---|---|---|
| `arm64`（默认） | `/opt/homebrew` | 原生 Apple Silicon |
| `x86_64` | `/usr/local` | Intel Mac 原生，或 Apple Silicon 上用 Rosetta 2 |

- 在 Apple Silicon 上构建 x86_64：需先安装 Rosetta 2 的 Homebrew 到 `/usr/local`：
  ```bash
  arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
  然后在每个脚本前加 `MAC_ARCH=x86_64`，并用 `arch -x86_64` 包裹执行。
- 构建目录按架构隔离（`build/inkscape-macos-arm64` / `build/inkscape-macos-x86_64`），互不干扰。

## 目录约定

脚本默认假定下面这套目录布局（可用 `PREVIEW_ROOT` 环境变量改）：

```
$HOME/xiuhui-build/
├── xiuhui-daimian-integration/       ← 本整合仓库
└── inkscape-inkstitch-preview/
    ├── src/inkscape/                  ← Inkscape 源码，固定基线 7923d92
    ├── src/inkstitch/                 ← Ink/Stitch 源码，固定基线 0312dac
    ├── build/                         ← cmake/ninja + 中间产物 (由脚本生成)
    └── release/                       ← 最终 dmg (由脚本生成)
```

## 端到端步骤

按顺序执行（以 arm64 为例，x86_64 加 `MAC_ARCH=x86_64` 即可）：

```bash
cd $HOME/xiuhui-build/xiuhui-daimian-integration/scripts/macos

# 一次性环境（Xcode CLT、Homebrew、Brewfile 依赖、检查源码工作区）
bash 00-bootstrap.sh

# 应用补丁 + overlays（每次重置工作区后都要再跑一次）
bash 01-apply-patches.sh

# 编译 Inkscape，产出 build/Inkscape-arm64.app (raw 骨架)
bash 02-build-inkscape.sh

# 用 PyInstaller 打 Ink/Stitch，产出 src/inkstitch/dist/inkstitch.app
bash 03-build-inkstitch.sh

# 合并、改 Info.plist 品牌、安装授权启动器并签名
ACTIVATION_SERVER_URL=https://你的授权域名 bash 04-bundle.sh

# 套 dmg 壳（带 /Applications 拖拽和首次打开说明），产出 release/*.dmg
bash 05-make-dmg.sh
```

完成后 `release/Inkscape-Inkstitch-绣绘呆棉版-<VERSION>-arm64.dmg` 即可上传 GitHub Release。

### x86_64 构建

```bash
# 在 Apple Silicon 上（Rosetta 2）或 Intel Mac 上：
MAC_ARCH=x86_64 bash 00-bootstrap.sh
MAC_ARCH=x86_64 bash 01-apply-patches.sh
MAC_ARCH=x86_64 arch -x86_64 bash 02-build-inkscape.sh
MAC_ARCH=x86_64 arch -x86_64 bash 03-build-inkstitch.sh
MAC_ARCH=x86_64 ACTIVATION_SERVER_URL=https://你的授权域名 bash 04-bundle.sh
MAC_ARCH=x86_64 bash 05-make-dmg.sh
```

### 版本号

默认 `VERSION=xiuhui-<整合仓库 short SHA>-local`。手动指定例如：

```bash
VERSION=v0.1.0 bash 03-build-inkstitch.sh
VERSION=v0.1.0 bash 04-bundle.sh
VERSION=v0.1.0 bash 05-make-dmg.sh
```

## 签名与公证

默认走 ad-hoc 签名，无需任何账号。要发布可公证的正式版，配置 Developer ID 后：

```bash
# 1. 用 Developer ID Application 证书签名（04 会检测 SIGNING_IDENTITY）
SIGNING_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" bash 04-bundle.sh

# 2. 生成 dmg 并公证（05 会检测 NOTARIZE=1 并调用 06-notarize.sh）
NOTARIZE=1 bash 05-make-dmg.sh
```

公证凭据通过钥匙串 profile `xiuhui-notary-profile` 或环境变量 `APPLE_ID` / `APPLE_APP_SPECIFIC_PASSWORD` / `TEAM_ID` 提供。完整配置步骤见 `docs/MACOS_SIGNING_SETUP.md`。

## 授权启动器

正式包默认启用一机一码授权。`04-bundle.sh` 会把原来的 `Contents/MacOS/inkscape` 移为 `inkscape-core` 并随应用重新签名，再把对应架构的原生授权启动器写入原入口。授权成功后启动器使用 `execv` 进入原主程序，不修改 Inkscape 或 Ink/Stitch 的功能代码。

生产构建必须设置：

```bash
ENABLE_ACTIVATION=1 \
ACTIVATION_SERVER_URL=https://license.example.com \
bash 04-bundle.sh
```

只在开发机调试不需要授权的本地包时，才允许显式设置 `ENABLE_ACTIVATION=0`。GitHub Actions 固定启用授权；仓库 Secret `ACTIVATION_SERVER_URL` 缺失时构建会终止，不会产生未保护的发布包。

## 估时

| 阶段 | 首次 | 增量 |
|---|---|---|
| 00-bootstrap | 30–60 分钟 | 0 |
| 01-apply-patches | <1 秒 | <1 秒 |
| 02-build-inkscape | 40–90 分钟 | 15–30 分钟（ccache 命中） |
| 03-build-inkstitch | 5–10 分钟 | 5–10 分钟 |
| 04-bundle | 2–4 分钟 | 2–4 分钟 |
| 05-make-dmg | 1–2 分钟 | 1–2 分钟 |
| 06-notarize（可选） | 3–10 分钟 | 3–10 分钟 |
| **合计** | **~1.5–3 小时** | **25–50 分钟** |

## 如果构建失败

按出现频率从高到低：

1. **`02-build-inkscape.sh` 在 cmake 阶段报 GTK4 / poppler 找不到** → `brew update && brew upgrade gtk4 gtkmm4 poppler` 后重试。Inkscape `CMakeLists.txt` 对版本要求随时跟进上游，本仓库的补丁不动这些。
2. **某个 brew 公式在 macOS 26 上还没出 bottle** → `brew install --build-from-source <name>`，或临时 `brew install <name>@<旧版>` 并把 pin 加进 `Brewfile`。
3. **`03-build-inkstitch.sh` PyInstaller 报缺少 gi 子模块** → 编辑 `src/inkstitch/inkstitch.spec` 的 `hiddenimports`/`datas`，加入缺的项；或在 `requirements.txt` 后再 `pip install <missing>`。
4. **`04-bundle.sh` 之后启动 Inkscape 直接闪退**，控制台日志含 "Code Signature Invalid" → 重新跑 `bash 04-bundle.sh`（确保签名走过 deepest-first 顺序）。
5. **`03-build-inkstitch.sh` 报架构不匹配** → 检查当前 shell 是否在正确的 Rosetta/Homebrew 环境下（`uname -m` 应与 `MAC_ARCH` 一致，或已用 `arch -x86_64` 包裹）。
6. **dmg 打开后双击 app 没反应** → 看 `Console.app`；多数情况是 fontconfig 缓存路径写不进。补救：临时 `xattr -dr com.apple.quarantine /Applications/Inkscape-绣绘呆棉版.app`。
7. **`06-notarize.sh` 公证失败** → 确认 dmg 是用 Developer ID 签名的（ad-hoc 签名会被 Apple 拒绝），并检查公证日志里的具体 issue。

## 与 Windows 整合包的差异

| 项 | Windows | macOS |
|---|---|---|
| Inkscape 主程序构建 | MSYS2 + UCRT64 + cmake | Homebrew + cmake |
| Ink/Stitch 整合形式 | NSIS 安装到 Inkscape 扩展目录 | 内嵌在 .app/Contents/Resources/.../extensions/inkstitch/ |
| 签名 | 无 | ad-hoc（默认）/ Developer ID（可选） |
| 公证 | 不适用 | 可选（需开发者账号） |
| 分发格式 | `.exe` 安装器 | `.dmg`（拖拽到 /Applications） |
| 首次打开 | 直接双击 | ad-hoc 版右键 → 打开（一次性）；已公证版直接双击 |

## 已知遗留事项 / 后续可做

- CI 自动化：`../.github/workflows/macos-build.yml` 提供双架构矩阵构建；公证流程需在仓库 Secrets 里配置证书/凭据。
- 没有验证 Inkscape Extensions Manager UI 是否能正确识别整合进 .app 的 Ink/Stitch（理论上识别为只读 system extension）。
- `assets/dmg-background-arm64.png` / `assets/dmg-background-x86_64.png` 已提供，`05-make-dmg.sh` 会自动使用；若缺失会优雅跳过样式。
