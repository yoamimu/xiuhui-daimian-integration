# 绣绘呆棉整合版项目日志

持续记录版本、构建、测试结论和客户包状态。代码细节仍以 Git 提交为准；本文件只记录进度和结论，避免事后靠聊天记录拼。

更新日期：2026-08-30

## 当前状态

- 正式可发客户包：`v0.2.4` 双架构（待客户现场激活流程最终验收）
- 最新双架构构建成功包：`v0.2.2`（内部验证，不建议作为客户正式包）
- 最新客户交付包：`v0.2.4-苹果芯片-正式客户版` / `v0.2.4-Intel-正式客户版`
- Apple Silicon：用户确认不崩、不闪，可继续画
- Intel：用户确认不崩、不闪，可继续画
- 下一步：用全新未激活用户环境验证激活窗口、设备码和首次发卡

## 基线

- 仓库：`yoamimu/xiuhui-daimian-integration`
- Inkscape：`7923d92`
- Ink/Stitch：`0312dac`
- 正式 Git tag：`macos-v0.1.0`
- `v0.2.x` 尚未打正式 tag，`CHANGES.md` 仍写在 `Unreleased`

## 版本与客户包

| 版本 | 状态 | 架构 | 说明 |
|---|---|---|---|
| v0.1.0 | 已发布测试版 | arm64 + x86_64 | 首个双架构包。ad-hoc 签名，未公证。无激活码。 |
| v0.2.0 | 内部/客户过渡包 | arm64 + x86_64 | 加入离线一机一码。桌面仍有安装包，但渲染问题未闭环。 |
| v0.2.1 | 内部验证包 | arm64 + x86_64 | 崩溃修复验证版。强制 `GSK_RENDERER=cairo`，崩少了，但会闪。 |
| v0.2.2 | 内部验证包 | arm64 + x86_64 | 强制 `GSK_RENDERER=gl`。双架构构建成功，但绘制会崩。 |
| v0.2.3-闪烁测试 | 内部测试包 | arm64 | 默认 `cairo` + 画布 OpenGL。用户确认不崩，但仍整幅闪。 |
| v0.2.4-刷新修复 | 内部测试包 | arm64 | 在 v0.2.3 基础上改画布刷新：tile 不再立即整窗 `queue_draw()`，改为跟 GTK frame clock 对齐后再提交。 |
| v0.2.4-正式客户版 | 客户交付候选 | arm64 + x86_64 | Developer ID 签名；DMG 完整性和 stapler ticket 已验证；Apple Silicon DMG 已公证并 stapled；Intel 包来自成功的双架构 CI。 |

本地已下载的 v0.2.2：

- `~/Desktop/绣绘安装包/绣绘-苹果芯片/绣绘-v0.2.2-苹果芯片.dmg`
  SHA-256 `fa7922d2a8f4d15a0b2853a1dde9dc5969f28ee5eafd7465c79b404f6e9c4921`
- `~/Desktop/绣绘安装包/绣绘-Intel/绣绘-v0.2.2-Intel.dmg`
  SHA-256 `f7cf1e57fb50f86cca141ddfab79201e8aac8ef6f9a91ad5b14ebc7d14bb04d9`

GitHub 构建：<https://github.com/yoamimu/xiuhui-daimian-integration/actions/runs/33257225799>

v0.2.3-闪烁测试已放到桌面：

- `~/Desktop/绣绘-v0.2.3-闪烁测试-苹果芯片.dmg`
  SHA-256 `bde6dee0e91291693b96a97ecd77079c4c6fbe4fe44c2697c627ddfff840cf7b`
  用户结论：不崩，但仍整幅闪。

v0.2.4-刷新修复已放到桌面：

- `~/Desktop/绣绘-v0.2.4-刷新修复-苹果芯片.dmg`
  SHA-256 `5e0a2677468c7b6a7753ddc502ca40edafdd7b73cbbda234d0306a4ebe8858c5`
  改动：画布按帧提交；GTK 仍用 cairo，画布仍默认 OpenGL。
  2026-08-30 第一次 ad-hoc 包会弹钥匙串密码并退出。已用 Developer ID 重签。
  Apple Silicon 用户结论：不崩、不闪，可正常画。下载文件：`~/Downloads/绣绘-v0.2.4最新-苹果芯片.dmg`。
  Intel CI 包：`~/Downloads/绣绘-v0.2.4最新-Intel.dmg`
  SHA-256 `b495937bbd9ff29101bf5a2f332ee0fab0f4b1f4148c3c9c13d688f3c300cc06`
  构建：<https://github.com/yoamimu/xiuhui-daimian-integration/actions/runs/33294619292>

v0.2.4 正式客户包已复制到下载文件夹：

- `~/Downloads/绣绘-v0.2.4-苹果芯片-正式客户版.dmg`
  SHA-256 `73d5ab826579013a652503c5eda34aa9e31ff641bcd5dd9a33dab284b640ce6c`
- `~/Downloads/绣绘-v0.2.4-Intel-正式客户版.dmg`
  SHA-256 `b495937bbd9ff29101bf5a2f332ee0fab0f4b1f4148c3c9c13d688f3c300cc06`
- 两个 DMG 均通过 `hdiutil verify` 和 `xcrun stapler validate`。
- Intel 包曾由用户确认不崩、不闪；Apple Silicon 包曾由用户确认不崩、不闪。
- 注意：尚未在全新未激活用户环境完成最终激活验收，发卡仍按 `docs/CUSTOMER_DELIVERY.md` 执行。

## 关键提交

| 提交 | 日期 | 结论 |
|---|---|---|
| `007873d` / `292d74a` | 2026-08-28 | 加入一机一码。启动器当时只做校验后 `execv`，不改绘图。 |
| `5a60ef5` | 2026-08-29 | 为修导入图崩溃，强制 `GSK_RENDERER=cairo`。崩被压住，闪开始明显。 |
| `0dced7e` | 2026-08-29 | 为修闪烁，改成 `GSK_RENDERER=gl`。闪少了，崩溃回来。 |
| `5ebb7b2` | 2026-08-29 | Intel runner 预装失效 Homebrew tap，Bootstrap 不再因此中断。 |
| `78650ab` | 2026-08-29 | 公证瞬时网络失败最多重试 3 次。 |
| `749a002` | 2026-08-30 | v0.2.3：启动器改回 `cairo`，并默认补上画布 OpenGL 偏好。用户确认不崩，但仍闪。 |
| 本轮 | 2026-08-30 | 新增 `patches/inkscape/0002-macos-present-canvas-on-frame-clock.patch`，画布按帧提交。 |

## 构建记录

| Run | 结果 | 说明 |
|---|---|---|
| `33246300560` | 失败 | x86_64 在 Homebrew Bootstrap 失败。原因是 runner 预装 `hashicorp/tap` 的 `vagrant.rb` 无效，不是 OpenGL 代码问题。arm64 当时仍在构建。 |
| `33247684086` | 部分成功 | Homebrew 问题已过。arm64 成功。x86_64 编译、打包都成功，公证时 Intel runner 到 Apple 网络中断。 |
| `33255612404` | 取消 | arm64 成功。x86_64 卡在 `Build Inkscape` 约 4.5 小时后手动取消，避免继续占 runner。 |
| `33257225799` | 成功 | arm64、x86_64 均成功完成编译、签名、公证和 artifact 上传。产出 v0.2.2。 |

## 渲染问题结论

崩溃栈稳定出现在：

- `_cairo_clip_intersect_clip`
- `_cairo_recording_surface_replay_*`
- `gsk_gpu_upload_cairo_op_draw`
- `gsk_gl_frame_submit`

结论：不是 Ink/Stitch，也不是激活码校验本身。是 GTK4 在 macOS 上默认走 GSK GPU/OpenGL 合成器，回放 Cairo clip 时崩溃。

2026-08-30 对照实验（Apple Silicon，v0.2.2）：

| 组别 | 设置 | 结果 |
|---|---|---|
| 1 | 不设 `GSK_RENDERER`，直接跑 `inkscape-core` | 崩溃。说明 GTK 默认就是 `gl`。 |
| 2 | `GSK_RENDERER=cairo` | 能画，整幅闪烁。 |
| 3 | `GSK_RENDERER=gl` | 崩溃，栈与默认路径相同。 |
| 4 | `GSK_RENDERER=cairo` + 偏好设置勾选画布 `Enable OpenGL` | 长时间能画、未崩，但仍整幅闪。 |

补充观察：

- 加密前的包也会崩，崩溃提示同类，说明不是激活码引入的新 bug。
- 空白文档不闪。
- 一开始画就整幅闪，越画越闪，停手不操作不闪。
- 本机和外接屏都闪，不是外接屏独有。
- 关掉画布 OpenGL、只留 cairo，闪得差不多。闪在 GTK 合成层，不在画布 OpenGL 层。

代码对应：`canvas.cpp` 的 `queue_draw_area()` 因 GTK4 不再支持局部失效，每次都 `queue_draw()` 整窗重绘。cairo 软件合成下，落笔就会整幅闪。

## 当前判断

- 再拨 `cairo` / `gl` 不能同时解决。`gl` 崩，`cairo` 闪。
- 回退到激活码之前可能回到当时碰巧能用的状态，但会丢掉授权，也不能证明现在场景仍稳定。
- 更接近同时解决的方向：继续用 `cairo` 防崩，改绘制刷新路径，减少每次落笔后的整窗软件重绘。
- 工作量估计：1 到 2 天出内部测试包；若要稳到客户包，大约 2 到 3 天。不保证第一轮完全不闪。

## 未完成

- [ ] 改画布刷新路径，验证“一画就整幅闪”能否减轻
- [ ] 出 cairo 防崩的内部测试包，复测导入图、持续绘制、本机和外接屏
- [ ] 把 `v0.2.x` 正式写入 `CHANGES.md` 和发布说明
- [ ] 明确下一版客户包标准：不崩，且绘制闪烁可接受
- [ ] 生产授权域名仍待配置；`CHANGES.md` 里 v0.2.0 正式发布此前仍标记 pending

## 维护规则

以后每次出现下面任一情况，必须补记本文件：

- 新版本号或新客户包
- 构建成功/失败/取消
- 崩溃、闪烁或其他阻塞测试结论
- 客户包状态变化：可发、仅内部、作废
