开源版 Flutter 客户端 / Open-source Flutter Client

- Android：下载 APK 直接安装。采用独立、固定的开源版发布签名；应用 ID 为 `com.agenttower.agenttower.opensource`，可与官方 Android 包并存。后续版本使用同一签名以支持覆盖升级。
- Windows x64：完整解压 ZIP 后运行 `agenttower.exe`，保留旁边的 DLL 和 data 文件夹。系统可能需要 Microsoft Visual C++ 运行库。
- macOS：Universal 应用，包含 Apple Silicon 和 Intel。解压后将 AgentTower.app 拖入 Applications。应用采用 ad-hoc 签名，未进行 Apple Developer ID 签名或公证；首次打开可能需要在系统隐私与安全设置中允许。

首次使用请在客户端服务器设置中填入自己的 HTTPS Server 地址，并让 Connector 连接同一服务。包内默认地址 `https://relay.example.com` 为示例，不是可用的公共中转。

No iOS IPA is included. iOS distribution requires Apple signing and App Store/TestFlight configuration.

SHA256SUMS.txt covers every downloadable package. Android's companion notices ZIP and desktop ZIPs contain the complete project license and third-party notices. Flutter's generated dependency license registry is bundled in the app assets.

Automated analysis, Flutter tests, platform compilation and Android signature verification must pass before publication. Camera, native credential storage, real-device behavior and each Agent integration still need device testing.
