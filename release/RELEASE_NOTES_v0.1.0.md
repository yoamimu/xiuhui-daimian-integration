# 绣绘 macOS v0.1.0

绣绘呆棉整合版的首个 macOS 双架构测试版本。项目基于 Inkscape 与 Ink/Stitch，提供中文界面、画布浮动功能面板、DST 优先导出以及完整的本地 Ink/Stitch 运行环境。

## 下载选择

- Apple 芯片（M1/M2/M3/M4 等）：`xiuhui-v0.1.0-macOS-Apple-Silicon-arm64.dmg`
- Intel 芯片：`xiuhui-v0.1.0-macOS-Intel-x86_64.dmg`

两个版本均为原生架构应用，不需要安装 Homebrew 或额外的 Ink/Stitch 依赖。

## 测试记录

- Apple Silicon `arm64`：项目所有者确认可以正常安装和使用，测试范围为 macOS 14 或更高版本。
- Intel `x86_64`：项目所有者确认可以正常安装和使用，测试系统为 macOS 15。
- 两个 DMG 均通过 `hdiutil verify` 完整性校验。
- 两个应用均通过 `codesign --verify --deep --strict` ad-hoc 签名校验。
- 构建源码版本：`b1ad7aa`。

## 首次启动

本版本采用 ad-hoc 签名，尚未经过 Apple 公证。首次启动时：

1. 将 DMG 内的“绣绘”拖到“应用程序”。
2. 在“应用程序”中按住 Control 点击或右键点击“绣绘”。
3. 选择“打开”，再在系统弹窗中确认“打开”。

以后可直接双击启动。如果没有“打开”按钮，请进入“系统设置 -> 隐私与安全性”，选择“仍要打开”。

## SHA-256

```text
8bea9f85014a81953ec1a6498f538ad6a4f80c4ae9e6daeedf79cbf5969cc408  xiuhui-v0.1.0-macOS-Apple-Silicon-arm64.dmg
99576fec5a24de5ae23eadcf6e7eda9924c1ea6f522384e6d3f931a46eadb4d0  xiuhui-v0.1.0-macOS-Intel-x86_64.dmg
```

## 许可与来源

绣绘呆棉整合版是基于 Inkscape 与 Ink/Stitch 的非官方修改版，不代表或暗示获得上游项目的官方认可。本整合版按 GPL-3.0-or-later 发布；对应源码、补丁、构建脚本和许可材料包含在本 Release 的 Source code 归档及项目仓库中。

- [macOS v0.1.0 第三方许可清单](https://github.com/yoamimu/xiuhui-daimian-integration/blob/macos-v0.1.0/release/THIRD_PARTY_LICENSES_v0.1.0.md)
- [固定上游源码包](https://github.com/yoamimu/xiuhui-daimian-integration/releases/download/upstream-sources-r1/xiuhui-upstream-sources.tar.gz)，SHA-256：`b4525c08299e4f8b9fedbe38424f60cdd2bf19c96c8fdd30f61fddf012d6d40f`
