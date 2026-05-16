# xiuhui-daimian-integration

# 绣绘呆棉整合版

SPDX-License-Identifier: GPL-3.0-or-later

绣绘呆棉整合版是一个基于 Inkscape 与 Ink/Stitch 的非官方整合修改版发行仓库。

本仓库用于记录整合策略、源码对应关系、补丁、许可文件和打包发布流程。它不是 Inkscape Project 或 Ink/Stitch 官方项目，也未获得官方背书。

> 非官方声明：绣绘呆棉整合版是基于 Inkscape 与 Ink/Stitch 的非官方修改版。Inkscape、Ink/Stitch 及其相关标识归各自项目和权利人所有。本项目不得暗示获得 Inkscape Project 或 Ink/Stitch 维护者的官方认可、认证或背书。

当前仓库仅用于源码整合与发布准备，尚未发布正式二进制安装包。未来发布 Windows 安装包或其他平台包时，必须同步提供对应源码包或公开源码 tag。

## 当前基线

- Inkscape upstream: `https://gitlab.com/inkscape/inkscape.git`
- Inkscape base commit: `7923d92`
- Ink/Stitch upstream: `https://github.com/inkstitch/inkstitch.git`
- Ink/Stitch base commit: `0312dac`

## 当前修改范围

- 将 Ink/Stitch 高频功能外置为画布浮层按钮。
- 将导入、导出、刺绣参数等入口做成更易触达的浮层操作。
- 将 Ink/Stitch 菜单、参数界面、提示和术语做简体中文本地化补充。
- 导出格式中优先照顾 DST 使用场景。
- 修正本地预览构建中已发现的 Ink/Stitch 依赖、颜色解析和界面体验问题。

## 许可

本整合版按 GPL-3.0-or-later 策略发布。

- Inkscape 完整二进制目前按 GNU GPL version 3 or later 处理，见 `legal/INKSCAPE_COPYING`。
- Ink/Stitch 源码按 GNU GPL version 3.0 or later 处理，见 `legal/INKSTITCH_LICENSE`。
- 本仓库默认许可证为 GPL-3.0-or-later，见 `LICENSE`。

发布二进制时必须同步提供完整对应源码、补丁、构建说明和第三方许可说明。

不得对接收者附加“仅限非商业使用”“禁止再分发”“禁止修改”“禁止反编译”等与 GPL 权利冲突的额外限制。

## 非官方声明

绣绘呆棉整合版是非官方修改版。不得在名称、图标、发布页、安装器或关于窗口中暗示它是 Inkscape Project 或 Ink/Stitch 官方版本。

## 仓库结构

- `patches/inkscape/`: 对 Inkscape 源码的当前补丁。
- `patches/inkstitch/`: 对 Ink/Stitch 源码的当前补丁。
- `overlays/inkstitch/`: 当前补丁之外需要额外复制的新文件。
- `legal/`: 上游许可文件和本项目发布规则。
- `scripts/`: 本地构建和补丁应用脚本。
- `release/`: 发布说明模板；不提交大体积安装包。

## 开发与构建建议

本仓库主要保存整合说明、补丁、许可文件和发布脚本，不保存完整编译产物。

建议开发者在仓库外准备 Inkscape 与 Ink/Stitch 源码工作区，并将大型构建产物、临时文件和依赖缓存放在独立的本地构建目录中。具体目录可按自己的系统环境和构建工具习惯设置。

不要把 `build`、`dist`、`.venv`、`node_modules`、`__pycache__`、`.cache`、`.tmp_system` 等构建或缓存目录提交到本仓库。发布二进制时，应另行附带对应源码包或公开源码 tag。

## 远端仓库设置

建议远端仓库保持以下设置：

- Visibility: public
- Description: `非官方 Inkscape + Ink/Stitch 中文整合修改版`
- Topics: `inkscape`, `inkstitch`, `embroidery`, `gplv3`, `chinese-localization`
- License: GPL-3.0-or-later
- Releases: 发布二进制时必须同时附源码包或源码 tag 链接
