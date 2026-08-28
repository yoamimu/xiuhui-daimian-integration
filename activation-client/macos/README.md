# macOS 授权启动器

`XHActivationLauncher.m` 是放在绣绘主程序之前的原生 Cocoa 启动器。打包时，原有 `Contents/MacOS/inkscape` 会改名为 `inkscape-core`，授权启动器占用原来的 `inkscape` 路径。验证通过后启动器使用 `execv` 直接进入原主程序，因此不会修改 Inkscape 或 Ink/Stitch 的绘图行为。

安全边界：

- 设备密钥由 Mac 的 `IOPlatformUUID` 在本机单向 SHA-256 生成，服务器不会收到原始硬件 UUID。
- 激活码和短期许可保存在 macOS Keychain。
- 每次启动优先在线验证；服务器临时不可用时，只接受 ECDSA P-256 签名且仍在离线宽限期内的许可。
- 客户端只内置公钥，签名私钥仅保存在授权服务器。
- 生产地址必须使用 HTTPS；仅测试构建允许连接 `127.0.0.1` 的 HTTP 服务。

构建示例：

```bash
MAC_ARCH=arm64 \
ACTIVATION_SERVER_URL=https://license.example.com \
bash activation-client/macos/build-launcher.sh /tmp/xiuhui-activation-launcher
```
