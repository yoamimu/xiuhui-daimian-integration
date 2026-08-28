# 绣绘授权服务器

这是绣绘 macOS 版的一机一码授权服务。它适合运行在现有的 Ubuntu 2 核、2 GB 内存服务器上，使用 Flask、Gunicorn 和 SQLite，不需要单独购买数据库服务器。

## 授权规则

- 所有客户下载相同的 Apple 芯片版或 Intel 版安装包。
- 后台创建授权时默认从付款当天开始，次年同日到期。
- 每个激活码默认只能绑定一台 Mac。
- 客户换机时，在授权详情中解绑旧设备，新设备即可用原激活码重新绑定；已解绑的旧设备不能抢回名额。
- 应用每次启动都会联系服务器验证。网络临时不可用时，只接受服务器签名且不超过 72 小时的本地缓存。
- 数据库只保存激活码的 HMAC-SHA256 摘要，不保存完整激活码。

## 服务器资源

典型的小规模销售场景下，容器常驻内存通常远低于 512 MB。现有 2 核、2 GB、50 GB Ubuntu 服务器足够同时承载原来的静态页面和授权服务。

## 首次部署

1. 为授权服务准备一个域名，例如 `license.example.com`，将 A 记录指向服务器 IP。
2. 把仓库上传到服务器，并进入 `activation-server/`。
3. 创建签名密钥和环境配置。必须在制作第一批受保护安装包之前完成一次；安装包发布后不得重新生成，否则现有客户端将无法验证服务器签名：

   ```bash
   mkdir -p secrets
   python3 ../scripts/generate-activation-key.py \
     --private-out secrets/license_private_key.pem \
     --public-out ../activation-client/macos/license-public-key.b64
   cp .env.example .env
   ```

   如果安装包已经内置 `activation-client/macos/license-public-key.b64`，服务器必须使用与它配对的现有私钥。当前项目的生产私钥保存在发布机外部的安全目录中，不在 Git 仓库内。

4. 生成后台密码哈希及随机配置值：

   ```bash
   python3 -c 'from werkzeug.security import generate_password_hash; print(generate_password_hash("换成你的管理密码"))'
   openssl rand -hex 32
   openssl rand -hex 32
   ```

   将密码哈希写入 `ADMIN_PASSWORD_HASH`，两个随机值分别写入 `FLASK_SECRET_KEY` 和 `LICENSE_CODE_PEPPER`。

5. 启动容器：

   ```bash
   cp docker-compose.example.yml docker-compose.yml
   docker compose up -d --build
   curl http://127.0.0.1:8787/api/v1/health
   ```

6. 安装 Certbot、签发 HTTPS 证书，然后把 `nginx/xiuhui-activation.conf` 中的域名替换为真实域名并启用配置。激活码和设备密钥不得通过明文 HTTP 传输。

## 日常操作

打开 `https://你的授权域名/admin/`：

1. 客户付款后点击“新建授权”。
2. 开始日期默认是当天，到期日期自动设置为次年同日。
3. 填写客户名称或订单号，点击“生成激活码”。
4. 复制唯一激活码发给客户。
5. 换机时进入该授权详情，点击当前设备右侧的“解绑”。

## 备份

SQLite 数据库存放在 Docker 卷 `activation-data`。每天备份一次即可：

```bash
docker compose exec activation-server \
  python -c 'import sqlite3; src=sqlite3.connect("/data/activation.db"); dst=sqlite3.connect("/data/activation-backup.db"); src.backup(dst); dst.close(); src.close()'
```

随后把 `/data/activation-backup.db` 复制到服务器外部存储。签名私钥、`.env` 和数据库必须分别备份；签名私钥不得提交到 Git。
