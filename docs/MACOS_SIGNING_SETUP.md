# macOS 签名与公证配置指南

本文档说明如何为「绣绘呆棉整合版」配置 Apple Developer ID 签名与公证，让正式版 dmg 能通过 Gatekeeper、用户无需"右键 → 打开"即可直接双击安装。

> 前提：需要 **Apple Developer Program** 付费会员（$99/年）。ad-hoc 签名（默认）不需要任何账号。

## 一、准备证书

### 1. 在 Apple Developer 后台创建证书

1. 登录 <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**。
2. 选择 **Certificates** → 点 **+**。
3. 创建以下证书类型：
   - **Developer ID Application** — 用于签名 `.app` 和 `.dmg` 内的应用。
   - （可选）**Developer ID Installer** — 若未来做 `.pkg` 安装器才需要。
4. 按提示生成 CSR 并下载 `.cer` 文件，双击导入到「钥匙串访问」的 **login** 钥匙串。

> 证书主体形如 `Developer ID Application: 你的名字 (TEAMID)`，其中 `TEAMID` 是 10 位字符的团队标识。

### 2. 验证证书已就位

```bash
security find-identity -v -p codesigning
# 应看到类似：
#   1) 1234ABCDEF "Developer ID Application: 你的名字 (TEAMID)"
```

## 二、准备公证凭据

公证有两种方式，任选其一。

### 方式 A：App 专用密码（推荐个人开发者）

1. 登录 <https://appleid.apple.com> → **登录与安全** → **App 专用密码**。
2. 生成一个 App 专用密码（记下这串 `xxxx-xxxx-xxxx-xxxx`）。
3. 存储到钥匙串 profile：

```bash
xcrun notarytool store-credentials "xiuhui-notary-profile" \
    --apple-id "你的 Apple ID 邮箱" \
    --team-id "TEAMID" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

之后 `06-notarize.sh` 会自动使用 `xiuhui-notary-profile`。

### 方式 B：App Store Connect API Key（推荐团队/CI）

1. App Store Connect → **用户与访问** → **集成** → **App Store Connect API**。
2. 生成一个 API Key（`.p8` 文件），记下 **Issuer ID** 和 **Key ID**。
3. 在 CI 中用环境变量提供（见下方 GitHub Actions 章节）。

## 三、执行签名 + 公证

```bash
cd $HOME/xiuhui-build/xiuhui-daimian-integration/scripts/macos

# 1. 用 Developer ID 签名（04 检测到 SIGNING_IDENTITY 即走 Developer ID 路径）
SIGNING_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" bash 04-bundle.sh

# 2. 生成 dmg 并触发公证（NOTARIZE=1 会调用 06-notarize.sh）
NOTARIZE=1 bash 05-make-dmg.sh
```

或者分步手动公证已生成的 dmg：

```bash
bash 06-notarize.sh "$HOME/xiuhui-build/inkscape-inkstitch-preview/release/Inkscape-Inkstitch-绣绘呆棉版-<ver>-arm64.dmg"
```

## 四、硬性要求与常见问题

### 签名硬性要求

- **必须用 Developer ID Application 证书**签名，ad-hoc 或 Mac App 证书都会被公证拒绝。
- 签名顺序必须 **deepest-first**（先签嵌套的 `.dylib`/`.so`/二进制，最后签 `.app` 外壳），`04-bundle.sh` 已按此顺序处理。
- 本项目的 `assets/entitlements.plist` 已配置 `allow-jit` 和 `disable-library-validation`，这是内嵌 Python（PyInstaller）运行时通过公证所必需的两项。

### 常见问题

| 问题 | 原因 | 解决 |
|---|---|---|
| `notarytool submit` 报 `Profile not found` | 凭据未存储 | 执行 `store-credentials`，或导出 `APPLE_ID` / `APPLE_APP_SPECIFIC_PASSWORD` / `TEAM_ID` |
| 公证状态 `Invalid` | dmg 内某 Mach-O 未签名或签名顺序错误 | 重跑 `04-bundle.sh`，检查公证日志中的具体 issue |
| `stapler staple` 报错 | 公证未完成就 staple | 确认 submit 返回 `Accepted` 后再 staple |
| Gatekeeper 仍提示"无法验证" | 未公证，或公证后未 staple | 确认 `06-notarize.sh` 完整跑完（submit + staple） |

## 五、GitHub Actions 中的使用

在仓库 **Settings → Secrets and variables → Actions** 配置以下 Secrets：

| Secret 名 | 内容 |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application 证书的 `.p12` 文件（base64 编码） |
| `MACOS_CERTIFICATE_PWD` | `.p12` 的导出密码 |
| `APPLE_ID` | Apple ID 邮箱 |
| `APPLE_APP_SPECIFIC_PASSWORD` | App 专用密码 |
| `TEAM_ID` | 团队标识（10 位） |

CI 工作流 `macos-build.yml` 会在构建时导入证书、用 `SIGNING_IDENTITY` 签名，并用环境变量方式完成公证。

### 导出证书为 .p12（供 CI 使用）

```bash
# 在钥匙串访问中选中证书，右键 → 导出，格式选 p12，设置密码
# 然后 base64 编码：
base64 -i DeveloperID.p12 | pbcopy   # 粘贴到 GitHub Secret
```
