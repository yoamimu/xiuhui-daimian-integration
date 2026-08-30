# 绣绘 v0.2.4 客户交付与发卡清单

适用于当前离线一机一码包。客户电脑没有激活过时，打开软件会提示“激活绣绘”。

## 交付给客户的文件

客户只需要对应芯片的安装包：

- Apple 芯片：`绣绘-v0.2.4最新-苹果芯片.dmg`
- Intel 芯片：`绣绘-v0.2.4最新-Intel.dmg`

不要把授权私钥、授权生成器或本仓库源码发给客户。

## 客户安装

1. 按芯片选择安装包，双击打开 DMG。
2. 把 `绣绘-苹果芯片` 或 `绣绘-Intel` 拖到“应用程序”。
3. 从“应用程序”打开绣绘。
4. 若系统提示无法验证开发者：按住 Control 点击应用，选“打开”，再确认打开。公证完成后应可直接双击。
5. 未激活的 Mac 会弹出“激活绣绘”窗口，显示本机设备码。

## 发卡流程（销售方）

这是离线授权，不经过网上激活服务器。

1. 客户打开软件，复制窗口里的设备码。设备码以 `XHD-` 开头。
2. 客户把设备码发给销售方。
3. 销售方在本机用授权生成器，或用下面的命令生成一年期授权码：

```bash
python3 ~/xiuhui-build/xiuhui-daimian-integration/scripts/generate-offline-license.py \
  --device-code '客户发来的XHD-设备码' \
  --customer '客户名' \
  --order-reference '订单号' \
  --starts-on "$(date +%F)" \
  --private-key ~/xiuhui-build/signing/activation/license_private_key.pem
```

也可编译图形工具：

```bash
SIGNING_IDENTITY="Developer ID Application: jinyun mu (2JMZH352X8)" \
bash ~/xiuhui-build/xiuhui-daimian-integration/activation-client/macos/build-license-generator.sh
```

默认会读取 `~/xiuhui-build/signing/activation/license_private_key.pem`。

4. 把生成的整段授权码发给客户。必须完整复制，不要截断。
5. 客户粘贴到“离线授权码”，点“激活并打开”。
6. 成功后提示授权仅限这台 Mac，并显示到期日。授权保存在系统钥匙串。

## 换机

旧 Mac 上的授权不能直接拿到新 Mac 用。新机器会生成新的设备码，销售方按新设备码再发一张授权。

## 销售方注意

- 私钥只留在销售方电脑，不要放进安装包，也不要发给客户。
- 授权生成器只给内部使用。
- 记录客户名、订单号、设备码、付款日期、到期日，方便以后核对。
- 已激活过的测试机不会再弹激活窗，这是正常的。
