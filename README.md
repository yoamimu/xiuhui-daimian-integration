# 绣绘呆棉整合版

绣绘呆棉整合版是一个基于 Inkscape 与 Ink/Stitch 的非官方整合修改版发行仓库。

本仓库用于记录整合策略、源码对应关系、补丁、许可文件和打包发布流程。它不是 Inkscape Project 或 Ink/Stitch 官方项目，也未获得官方背书。

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

## 非官方声明

绣绘呆棉整合版是非官方修改版。不得在名称、图标、发布页、安装器或关于窗口中暗示它是 Inkscape Project 或 Ink/Stitch 官方版本。

## 仓库结构

- `patches/inkscape/`: 对 Inkscape 源码的当前补丁。
- `patches/inkstitch/`: 对 Ink/Stitch 源码的当前补丁。
- `overlays/inkstitch/`: 当前补丁之外需要额外复制的新文件。
- `legal/`: 上游许可文件和本项目发布规则。
- `scripts/`: 本地构建和补丁应用脚本。
- `release/`: 发布说明模板；不提交大体积安装包。

## 本地源码位置

当前开发源码位于构建产物区：

- `E:\.BuildCache\inkscape-inkstitch-preview\src\inkscape`
- `E:\.BuildCache\inkscape-inkstitch-preview\src\inkstitch`

构建和临时目录仍应放在 `E:\.BuildCache\inkscape-inkstitch-preview\build`、`E:\.BuildCache\inkscape-inkstitch-preview\.tmp_system` 等 BuildCache 路径下，不放进云同步工作区。

