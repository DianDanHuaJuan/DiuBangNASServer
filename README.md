# DiuBangFileS (NASServer)

面向 **Windows 桌面** 的 NAS 服务端（Flutter）：围绕用户选定的单个共享目录提供 WebDAV、控制面 API、Relay，以及共享目录内图片/视频的预览与缩略图能力。

**许可证：** [MIT](LICENSE) · **版本：** 1.0.0

**配套客户端：** [DiuBangNASClient](https://github.com/DianDanHuaJuan/DiuBangNASClient)

## 功能特性

- 用户选定单个共享目录，不提供媒体库或全盘扫描
- WebDAV 文件访问（`/dav/fs`）
- 控制面 REST API 与 WebSocket 实时通道
- 共享目录内图片/视频预览与缩略图
- Relay：以 NAS 服务端为中转的设备间文件互传
- Windows 托盘运行、开机自启（可选）

## 环境要求

- Flutter SDK，兼容 **Dart ^3.10.7**（见 `pubspec.yaml`）
- **Windows 10 / 11，x64**（本仓库当前主要支持 Windows 桌面）
- 配套 [DiuBangNASClient](https://github.com/DianDanHuaJuan/DiuBangNASClient)（Android 客户端）

> `android/` 目录为历史遗留平台代码，开源版本以 Windows 桌面为主；Android 构建未作为当前维护目标。

## 快速开始

1. 从 GitHub 克隆仓库：

   ```powershell
   git clone https://github.com/DianDanHuaJuan/DiuBangNASServer.git
   cd DiuBangNASServer
   ```

2. 安装依赖：

   ```powershell
   flutter pub get
   ```

3. **配置加密密钥：**

   仓库仅提供 `Encryption_key.example` 作为参考示例（位于项目根目录），不包含可直接用于生产的密钥。构建前必须在项目根目录创建 `Encryption_key`（与客户端使用相同的密钥文件）。

   生成随机密钥（推荐）：

   ```powershell
   openssl rand -hex 16 | Out-File -Encoding ascii -NoNewline Encryption_key
   ```

   或者复制公开兼容示例密钥（仅限本地测试，须与客户端 example 密钥一致）：

   ```powershell
   Copy-Item Encryption_key.example Encryption_key
   ```

4. 运行（Windows 桌面）：

   ```powershell
   flutter run -d windows
   ```

5. 开发检查：

   ```powershell
   flutter analyze
   flutter test
   ```

## Windows 构建

```powershell
flutter build windows --release `
  --dart-define=NAS_APP_VERSION=1.0.0+1 `
  --dart-define=NAS_BUILD_SHA=<git-sha> `
  --dart-define=NAS_BUILD_TIME=<utc-iso8601>
```

构建产物位于 `build\windows\x64\runner\Release\`（便携目录，约 200MB+）。

## Windows 安装包（Inno Setup）

详细步骤见 [`packaging\windows\README.md`](packaging/windows/README.md)。

```powershell
# 构建前确保 assets\ffmpeg.exe 已就位（见 packaging\windows\README.md）
.\packaging\windows\build_installer.ps1
```

安装包输出：`packaging\windows\output\DiuBangFileS-Setup-<version>.exe`

### 部署须知

| 项目 | 说明 |
|------|------|
| 操作系统 | **Windows 10 / 11，x64** |
| 默认管理员 | 首次启动为 `admin` / `admin`，**必须在本地 UI 修改后**才允许远程客户端配对 |
| Encryption_key | 须与客户端使用相同密钥；自托管请自行生成，勿在生产环境使用 example 密钥 |
| 运行库 | 安装包可附带 VC++ 运行库；需 Windows 10/11 系统 UCRT |
| 网络 | 局域网互通；防火墙放行应用与 HTTP/HTTPS 端口 |
| 窗口行为 | 关闭窗口缩到托盘而非退出 |

## 贡献

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。提交 Pull Request 前请确保 `flutter analyze` 和 `flutter test` 通过。

## 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## 第三方组件

- [Noto Sans CJK SC](assets/fonts/OFL.txt) — UI 字体（SIL Open Font License 1.1）
- [FFmpeg](https://ffmpeg.org/) — 可选，用于 Windows 安装包中的 HLS/转码（需自行放置 `assets\ffmpeg.exe`，许可取决于你的构建配置）

## 安全

详见 [SECURITY.md](SECURITY.md)。切勿提交生产凭据、`Encryption_key` 或私有调试日志。
